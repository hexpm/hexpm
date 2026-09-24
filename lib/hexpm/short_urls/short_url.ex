defmodule Hexpm.ShortURLs.ShortURL do
  use Hexpm.Schema

  alias Hexpm.ShortURLs.ShortURL
  alias Hexpm.Repo

  @derive {Phoenix.Param, key: :short_code}

  # A subset of the host code points the WHATWG URL Standard permits
  # (https://url.spec.whatwg.org/#forbidden-host-code-point). Every character a
  # browser reads as the end of the authority is outside it, so a host matching
  # this is the same host in `URI.parse/1` and in a browser.
  @host ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/

  schema "short_urls" do
    field :url, :string
    field :short_code, :string

    timestamps(updated_at: false)
  end

  def changeset(params) do
    %ShortURL{}
    |> cast(params, [:url])
    |> validate_required([:url])
    |> validate_length(:url, count: :bytes, max: 8192)
    |> put_canonical_url()
    |> put_change(:short_code, generate_random(5))
    |> validate_required(:short_code, message: "could not generate a unique short code")
    |> unique_constraint(:short_code)
  end

  @doc """
  The URL a short code redirects to, or `nil` when the stored value does not
  pass validation.

  Rebuilt from the parsed host and path rather than returned as stored, so the
  host redirected to is the one that was checked.
  """
  def redirect_url(%ShortURL{url: url}) do
    case canonical_uri(url) do
      {:ok, uri} -> URI.to_string(uri)
      {:error, _reason} -> nil
    end
  end

  defp put_canonical_url(changeset) do
    case get_change(changeset, :url) do
      nil ->
        changeset

      url ->
        case canonical_uri(url) do
          {:ok, uri} -> put_change(changeset, :url, URI.to_string(uri))
          {:error, reason} -> add_error(changeset, :url, reason)
        end
    end
  end

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

  defp canonical_uri(_url), do: {:error, "must include a host"}

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
