defmodule HexpmWeb.Plugs.ReadmeContentSecurityPolicy do
  @moduledoc """
  Sets Content-Security-Policy headers for the readme iframe page.

  Separate from the main CSP plug because the readme page has different
  requirements: it must allow being framed by hex.pm, load images only
  from the proxy, and run only nonced scripts.
  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    nonce = generate_nonce()
    img_url = Application.fetch_env!(:hexpm, :img_url)
    host = Application.get_env(:hexpm, :host)

    # TODO: Remove new.hex.pm when new.hex.pm replaces hex.pm
    frame_ancestors =
      if host do
        "https://#{host} https://new.#{host}"
      else
        "http://localhost:*"
      end

    csp =
      [
        "default-src 'none'",
        "script-src 'nonce-#{nonce}'",
        "style-src 'nonce-#{nonce}'",
        "img-src #{img_url}",
        "frame-ancestors #{frame_ancestors}",
        "base-uri 'none'",
        "form-action 'none'"
      ]
      |> Enum.join("; ")

    conn
    |> assign(:readme_csp_nonce, nonce)
    |> put_resp_header("content-security-policy", csp)
    |> delete_resp_header("x-frame-options")
  end

  defp generate_nonce do
    :crypto.strong_rand_bytes(16) |> Base.encode64()
  end
end
