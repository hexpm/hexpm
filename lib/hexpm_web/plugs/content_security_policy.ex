defmodule HexpmWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Wrapper around PlugContentSecurityPolicy.
  """

  import Plug.Conn

  @behaviour Plug

  @doc """
  Extends the form-action CSP directive to allow a redirect URI's origin.

  Chrome applies form-action to redirects after form submission, so OAuth
  consent pages need to allow the client's callback origin.
  """
  def allow_form_action(conn, redirect_uri) do
    origin = uri_origin(redirect_uri)

    case get_resp_header(conn, "content-security-policy") do
      [csp] ->
        updated = String.replace(csp, "form-action 'self'", "form-action 'self' #{origin}")
        put_resp_header(conn, "content-security-policy", updated)

      _ ->
        conn
    end
  end

  defp uri_origin(url) do
    uri = URI.parse(url)

    if uri.port && uri.port != URI.default_port(uri.scheme) do
      "#{uri.scheme}://#{uri.host}:#{uri.port}"
    else
      "#{uri.scheme}://#{uri.host}"
    end
  end

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    directives =
      opts[:directives]
      |> maybe_add_plausible_host()
      |> maybe_add_readme_host()

    opts = Keyword.put(opts, :directives, directives)
    PlugContentSecurityPolicy.call(conn, PlugContentSecurityPolicy.init(opts))
  end

  # Allow Plausible analytics to send events to s.<host>
  defp maybe_add_plausible_host(directives) do
    case Application.get_env(:hexpm, :host) do
      nil -> directives
      host -> Map.update(directives, :connect_src, [], &(&1 ++ ["https://s.#{host}"]))
    end
  end

  defp maybe_add_readme_host(directives) do
    readme_url = Application.get_env(:hexpm, :readme_url)

    if readme_url do
      Map.update(directives, :frame_src, [], &(&1 ++ [readme_url]))
    else
      directives
    end
  end
end
