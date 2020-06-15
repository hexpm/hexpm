defmodule Hexpm.Repository.PackageReport do
  use Hexpm.Schema
  import Ecto.Query, only: [from: 2]

  schema "package_reports" do
    field :state, :string, default: "to_accept"
    field :description, :string

    belongs_to :author, Hexpm.Accounts.User
    belongs_to :package, Package
    #field :requirement, :string
    has_many :affected_releases, AffectedRelease
    has_many :releases, through: [:affected_releases, :release]

    timestamps()
  end

  @valid_states ["to_accept","accepted","rejected","solved"]

  def build(releases, user, package, params) do
    %PackageReport{}
    |> cast(params, ~w(state description)a)
    |> validate_required(:state)
    |> validate_inclusion(:state, @valid_states)
    |> validate_length(:description, min: 2, max: 500)
    |> put_assoc(:affected_releases, get_list_of_affected(releases))
    |> put_assoc(:author, user)
    |> put_assoc(:package, package)   
  end

  def change_state(package_report,params) do
    cast(package_report, params, ~w(state)a)
    |> validate_required(:state)
    |> validate_inclusion(:state, @valid_states)
  end

  def get(id) do
    from(
      r in PackageReport,
      preload: :author,
      preload: :package,
      preload: :releases,
      preload: :affected_releases,
      where: r.id == ^id,
      select: r
    )
  end

  def all(count, page, search) do
    from(
      p in PackageReport,
      preload: :affected_releases,
      preload: :author,
      preload: :releases,
      preload: :package,
    )
    |>Hexpm.Utils.paginate(page, count)
    |>search(search)
    |>fields()
    
  end

  def count() do
    from(r in PackageReport, select: count(r.id))
  end

  defp get_list_of_affected(releases) do
    Enum.map(releases, fn r -> %AffectedRelease{release_id: r.id} end)
  end

  defp fields(query) do
    from(p in query, select: p)
  end

  ############################
  # Search functionality block
  ############################
  defp search(query, search) when is_binary(search) do
    IO.puts("search/2" <> search)
    case parse_search(search) do
      {:ok, params} ->
        Enum.reduce(params, query, fn {k, v}, q -> search_param(k, v, q) end)

      :error ->
        IO.puts("error")
        basic_search(query)
    end
  end
  
  defp search(query, nil) do
    query
  end

  defp basic_search(query) do
    IO.puts("basic_search/1")
    from(
          p in query,
          where: p.state != "to_accept"
        )
  end

  defp parse_search(search) do
    IO.puts("parse_search/1" <> search)
    search
    |> String.trim_leading()
    |> parse_params([])
  end

  defp parse_params("", params), do: {:ok, Enum.reverse(params)}

  defp parse_params(tail, params) do
    IO.puts("parse_params/2")
    with {:ok, key, tail} <- parse_key(tail),
         {:ok, value, tail} <- parse_value(tail) do
      parse_params(tail, [{key, value} | params])
    else
      _ -> :error
    end
  end

  defp parse_key(string) do
    IO.puts("parse_key/1" <> string)
    with [k, tail] when k != "" <- String.split(string, ":", parts: 2) do
      {:ok, k, String.trim_leading(tail)}
    end
  end

  defp parse_value(string) do
    IO.puts("parse_value/1" <> string)
    case string do
      "\"" <> rest ->
        with [v, tail] <- String.split(rest, "\"", parts: 2) do
          {:ok, v, String.trim_leading(tail)}
        end

      _ ->
        case String.split(string, " ", parts: 2) do
          [value] -> {:ok, value, ""}
          [value, tail] -> {:ok, value, String.trim_leading(tail)}
        end
    end
  end

  defp search_param("state", search, query) do
    IO.puts("search_param/3" <> search)
    case String.split(search, ":", parts: 2) do
      ["not_equal", state] ->
        from(
          p in query,
          where: p.state != ^state
        )

      _ ->
        basic_search(query)
    end
  end

  defp search_param(_, _, query) do
    query
  end

 

  ###################################
  # End of search functionality block
  ###################################

end
