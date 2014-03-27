defmodule HexWeb do
  use Application.Behaviour

  def start(_type, _args) do
    { opts, _, _ } = OptionParser.parse(System.argv, aliases: [p: :port])

    if opts[:port] do
     opts = Keyword.update!(opts, :port, &binary_to_integer(&1))
    end

    start_lager()

    File.mkdir_p!("tmp")
    HexWeb.Config.init(opts)
    Plug.Adapters.Cowboy.http(HexWeb.Router, [], opts ++ [compress: true])
    HexWeb.Supervisor.start_link
  end

  @lager_level Mix.project[:lager_level]

  defp start_lager do
    :application.set_env(:lager, :handlers, [lager_console_backend:
        [@lager_level, { :lager_default_formatter, [:time, ' [', :severity, '] ', :message, '\n']}]
    ], persistent: true)
    :application.set_env(:lager, :crash_log, :undefined, persistent: true)

    :application.ensure_all_started(:exlager)
  end

  defprotocol Render do
    @moduledoc """
    Render entities to something that can be showed publicly.
    Used, for example, when converting entities to JSON responses.
    """

    @spec render(term) :: Dict.t
    def render(entity)
  end
end
