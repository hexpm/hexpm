defmodule HexWeb do
  use Application

  def start(_type, _args) do
    opts  = [port: 4000]

    if port = System.get_env("PORT") do
      opts = Keyword.put(opts, :port, binary_to_integer(port))
    end

    start_lager()

    File.mkdir_p!("tmp")
    HexWeb.Config.init(opts)
    Plug.Adapters.Cowboy.http(HexWeb.Router, [], opts ++ [compress: true])
    HexWeb.Supervisor.start_link
  end

  @lager_level Mix.Project.config[:lager_level]

  defp start_lager do
    :application.set_env(:lager, :handlers, [lager_console_backend:
        [@lager_level, { :lager_default_formatter, [:time, ' [', :severity, '] ', :message, '\n']}]
    ], persistent: true)
    :application.set_env(:lager, :crash_log, :undefined, persistent: true)
    :application.set_env(:lager, :error_logger_hwm, 150, persistent: true)

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
