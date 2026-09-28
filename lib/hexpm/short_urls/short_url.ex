defmodule Hexpm.ShortURLs.ShortURL do
  use Hexpm.Schema

  alias Hexpm.ShortURLs.{ShortURL, Target}
  alias Hexpm.Repo
  alias HexpmWeb.DiffController

  @derive {Phoenix.Param, key: :short_code}

  # A subset of the host code points the WHATWG URL Standard permits
  # (https://url.spec.whatwg.org/#forbidden-host-code-point). Every character a
  # browser reads as the end of the authority is outside it, so a host matching
  # this is the same host in `URI.parse/1` and in a browser.
  @host ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/

  @diff_locations [
    {"hex.pm", "/diffs"},
    {"diff.hex.pm", nil},
    {"diff.hex.pm", "/"},
    {"diff.hex.pm", "/diffs"}
  ]
  @max_comparisons 150
  @max_comparison_bytes 512
  # Bandit refuses request lines over 10,000 bytes, so a longer link would
  # shorten fine and then fail with 414 when followed.
  @max_url_bytes 8192
  @package_name ~r/^[a-z][a-z0-9_]*$/
  @max_package_name_bytes 255

  schema "short_urls" do
    field :short_code, :string
    belongs_to :target, Target

    timestamps(updated_at: false)
  end

  def changeset(%Target{} = target) do
    %ShortURL{}
    |> change(target_id: target.id, short_code: generate_random(5))
    |> validate_required(:short_code, message: "could not generate a unique short code")
    |> unique_constraint(:short_code)
  end

  @doc """
  Validates a submitted diff link and puts its canonical form in `:url` and
  the package names it compares in `:packages`.
  """
  def diff_changeset(params) do
    {%{}, %{url: :string, packages: {:array, :string}}}
    |> cast(params, [:url])
    |> validate_required([:url])
    |> put_canonical_diff_url()
  end

  @doc """
  The canonical form of a hex.pm diff link: its comparisons sorted and
  deduplicated under `https://hex.pm/diffs`, whichever accepted diff host and
  query key the link used.
  """
  def canonical_diff_url(url) when is_binary(url) do
    uri = URI.parse(url)

    with :ok <- check_diff_uri(url, uri),
         {:ok, comparisons} <- diff_comparisons(uri.query) do
      comparisons = comparisons |> Enum.uniq() |> Enum.sort()

      query =
        Enum.map_join(comparisons, "&", fn {package, from, to} ->
          "diffs[]=" <> URI.encode("#{package}:#{from}:#{to}", &comparison_char?/1)
        end)

      packages = comparisons |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
      url = "https://hex.pm/diffs?" <> query

      if byte_size(url) <= @max_url_bytes do
        {:ok, url, packages}
      else
        {:error, "must be at most #{@max_url_bytes} bytes"}
      end
    end
  end

  def canonical_diff_url(_url), do: {:error, "must be a hex.pm diff link"}

  @doc """
  The URL a short code redirects to, or `nil` when the stored value does not
  pass validation.

  Rebuilt from the parsed host and path rather than returned as stored, so the
  host redirected to is the one that was checked.
  """
  def redirect_url(%ShortURL{target: %Target{url: url}}) do
    case canonical_uri(url) do
      {:ok, uri} -> URI.to_string(uri)
      {:error, _reason} -> nil
    end
  end

  defp put_canonical_diff_url(changeset) do
    case get_change(changeset, :url) do
      nil ->
        changeset

      url ->
        case canonical_diff_url(url) do
          {:ok, canonical, packages} ->
            changeset
            |> put_change(:url, canonical)
            |> put_change(:packages, packages)

          {:error, reason} ->
            add_error(changeset, :url, reason)
        end
    end
  end

  defp check_diff_uri(url, uri) do
    cond do
      String.contains?(url, ["\t", "\r", "\n"]) -> {:error, "must not contain tabs or newlines"}
      uri.scheme not in ["http", "https"] -> {:error, "must use http or https scheme"}
      uri.userinfo != nil -> {:error, "must not have userinfo"}
      uri.port != URI.default_port(uri.scheme) -> {:error, "must use the default port"}
      {uri.host, uri.path} not in @diff_locations -> {:error, "must be a hex.pm diff link"}
      true -> :ok
    end
  end

  defp diff_comparisons(nil), do: {:error, "must contain at least one comparison"}

  defp diff_comparisons(query) do
    params = Plug.Conn.Query.decode(query)
    raw = params |> Map.get("diffs", Map.get(params, "diff", [])) |> List.wrap()

    cond do
      raw == [] ->
        {:error, "must contain at least one comparison"}

      length(raw) > @max_comparisons ->
        {:error, "must contain at most #{@max_comparisons} comparisons"}

      not Enum.all?(raw, &(is_binary(&1) and byte_size(&1) <= @max_comparison_bytes)) ->
        {:error, "has an invalid comparison"}

      true ->
        comparisons = DiffController.comparisons(%{"diffs" => raw})

        if length(comparisons) == length(raw) and Enum.all?(comparisons, &valid_comparison?/1) do
          {:ok, Enum.map(comparisons, fn {nil, package, from, to} -> {package, from, to} end)}
        else
          {:error, "has an invalid comparison"}
        end
    end
  rescue
    Plug.Conn.InvalidQueryError -> {:error, "has an invalid query"}
  end

  defp valid_comparison?({nil, package, from, to}) do
    byte_size(package) <= @max_package_name_bytes and Regex.match?(@package_name, package) and
      match?({:ok, _}, Version.parse(from)) and match?({:ok, _}, Version.parse(to))
  end

  defp valid_comparison?({_repository, _package, _from, _to}), do: false

  defp comparison_char?(char), do: URI.char_unreserved?(char) or char == ?:

  defp canonical_uri(url) when is_binary(url) do
    uri = URI.parse(url)

    cond do
      # WHATWG strips these before it parses and `URI.parse/1` does not, so a
      # URL holding one parses to a different authority in a browser.
      String.contains?(url, ["\t", "\r", "\n"]) ->
        {:error, "must not contain tabs or newlines"}

      uri.scheme not in ["http", "https"] ->
        {:error, "must use http or https scheme"}

      uri.userinfo != nil ->
        {:error, "must not have userinfo"}

      uri.port != URI.default_port(uri.scheme) ->
        {:error, "must use the default port"}

      not is_binary(uri.host) or not Regex.match?(@host, uri.host) ->
        {:error, "must include a host"}

      not allowed_host?(uri.host, uri.path) ->
        {:error, "domain must match hex.pm, *.hex.pm, hexdocs.pm, *.hexdocs.pm, or *.hexorgs.pm"}

      true ->
        {:ok,
         %URI{
           scheme: uri.scheme,
           host: uri.host,
           path: uri.path,
           query: uri.query,
           fragment: uri.fragment
         }}
    end
  end

  defp allowed_host?(host, path) do
    cond do
      host == "hex.pm" or String.ends_with?(host, ".hex.pm") -> true
      String.ends_with?(host, [".hexdocs.pm", ".hexorgs.pm"]) -> true
      host in ["hexdocs.pm", "staging.hex.pm"] and path in [nil, "/"] -> true
      true -> false
    end
  end

  defp charset do
    capitals = Enum.map(?A..?Z, fn ch -> <<ch>> end)
    lowers = Enum.map(?a..?z, fn ch -> <<ch>> end)
    numbers = Enum.map(?0..?9, fn ch -> <<ch>> end)
    ambiguous = ["I", "0", "O", "l"]
    (capitals ++ lowers ++ numbers) -- ambiguous
  end

  defp generate_random(length, retries \\ 5)
  defp generate_random(_length, 0), do: nil

  defp generate_random(length, retries) do
    short_code = IO.iodata_to_binary(Enum.map(1..length, fn _ -> Enum.random(charset()) end))
    # Make sure this short_code is unique before continuing
    if short_code_unique?(short_code), do: short_code, else: generate_random(length, retries - 1)
  end

  defp short_code_unique?(short_code) do
    Repo.get_by(ShortURL, short_code: short_code) |> is_nil()
  end
end
