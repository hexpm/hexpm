defmodule HexWeb do
  use Application

  def start(_type, _args) do
    opts  = [port: 4000]

    if port = System.get_env("PORT") do
      opts = Keyword.put(opts, :port, binary_to_integer(port))
    end

    File.mkdir_p!("tmp")
    HexWeb.Config.init(opts)
    Plug.Adapters.Cowboy.http(HexWeb.Router, [], opts ++ [compress: true])
    HexWeb.Supervisor.start_link
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
