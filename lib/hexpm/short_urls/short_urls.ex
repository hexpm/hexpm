defmodule Hexpm.ShortURLs do
  use Hexpm.Context
  alias Hexpm.ShortURLs.{ShortURL, Target}

  @doc """
  Returns the short URL for the canonical form of the submitted diff link,
  creating it when no short URL points there yet.

  `:before_insert` is called only when a new row would be written; any value
  other than `:ok` is returned as `{:error, value}` without writing.
  """
  def add(params, opts \\ []) do
    changeset =
      params
      |> ShortURL.diff_changeset()
      |> validate_packages_exist()

    with {:ok, %{url: url}} <- apply_action(changeset, :insert) do
      hash = Target.url_hash(url)

      case get_by_url_hash(hash) do
        %ShortURL{} = short_url ->
          {:ok, short_url}

        nil ->
          before_insert = Keyword.get(opts, :before_insert, fn -> :ok end)

          case before_insert.() do
            :ok -> insert(url, hash)
            error -> {:error, error}
          end
      end
    end
  end

  def get(short_code) do
    from(s in ShortURL, where: s.short_code == ^short_code, preload: :target)
    |> Repo.one()
    |> put_url()
  end

  defp put_url(%ShortURL{target_id: nil} = short_url) do
    url = from(s in "short_urls", where: s.id == ^short_url.id, select: s.url) |> Repo.one()
    %{short_url | url: url}
  end

  defp put_url(short_url), do: short_url

  defp validate_packages_exist(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp validate_packages_exist(changeset) do
    names = get_change(changeset, :packages)

    existing =
      from(p in Package, where: p.repository_id == 1 and p.name in ^names, select: p.name)
      |> Repo.all()

    case names -- existing do
      [] -> changeset
      missing -> add_error(changeset, :url, "unknown packages: #{Enum.join(missing, ", ")}")
    end
  end

  defp get_by_url_hash(hash) do
    from(s in ShortURL,
      join: t in assoc(s, :target),
      where: t.url_hash == ^hash,
      order_by: s.id,
      limit: 1
    )
    |> Repo.one()
  end

  defp insert(url, hash) do
    Repo.transaction(fn ->
      Repo.insert_all(
        Target,
        [%{url: url, url_hash: hash, inserted_at: DateTime.utc_now()}],
        on_conflict: :nothing,
        conflict_target: [:url_hash]
      )

      target = Repo.get_by!(Target, url_hash: hash)

      case get_by_url_hash(hash) do
        %ShortURL{} = short_url ->
          short_url

        nil ->
          case Repo.insert(ShortURL.changeset(target)) do
            {:ok, short_url} -> short_url
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
  end
end
