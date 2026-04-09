defmodule HexpmWeb.Plugs.ReadmeContentSecurityPolicy do
  @moduledoc """
  Sets Content-Security-Policy headers for the readme iframe page.

  Wraps PlugContentSecurityPolicy with runtime configuration for
  img-src and frame-ancestors directives.
  """

  @behaviour Plug

  @impl Plug
  def init(_opts), do: []

  @impl Plug
  def call(conn, _opts) do
    img_url = Application.fetch_env!(:hexpm, :img_url)
    host = Application.get_env(:hexpm, :host)

    # TODO: Remove new.hex.pm when new.hex.pm replaces hex.pm
    frame_ancestors =
      if host do
        ["https://#{host}", "https://new.#{host}"]
      else
        ["http://localhost:*"]
      end

    opts = [
      nonces_for: [:script_src, :style_src],
      directives: %{
        default_src: ~w('none'),
        script_src: [],
        style_src: [],
        img_src: [img_url],
        frame_ancestors: frame_ancestors,
        base_uri: ~w('none'),
        form_action: ~w('none')
      }
    ]

    PlugContentSecurityPolicy.call(conn, PlugContentSecurityPolicy.init(opts))
  end
end
