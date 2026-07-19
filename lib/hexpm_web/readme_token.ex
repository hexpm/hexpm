defmodule HexpmWeb.ReadmeToken do
  @moduledoc """
  Signed tokens authorizing readme access for a single private package version.

  The readme host never receives the hex.pm session cookie, so the package
  page mints a token after its own authorization check and embeds it in the
  iframe URL.
  """

  @salt "private readme"
  @max_age 30 * 60

  def sign(repository, package, version) do
    Phoenix.Token.sign(
      HexpmWeb.Endpoint,
      @salt,
      {repository, package, to_string(version)}
    )
  end

  def verify(token, repository, package, version) when is_binary(token) do
    case Phoenix.Token.verify(HexpmWeb.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, {^repository, ^package, ^version}} -> :ok
      _other -> :error
    end
  end

  def verify(_token, _repository, _package, _version), do: :error
end
