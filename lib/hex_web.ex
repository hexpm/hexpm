defmodule HexWeb do
  use Application.Behaviour

  def start(_type, _args) do
    # { opts, _, _ } = OptionParser.parse(System.argv, aliases: [p: :port])

    # if opts[:port] do
    #  opts = Keyword.update!(opts, :port, &binary_to_integer(&1))
    # end

    # Workaround for elixir bug fixed in 0.12.5 and 0.13.0
    opts =
      Enum.find_value(System.argv, fn arg ->
        case Integer.parse(arg) do
          { port, "" } -> [port: port]
          :error -> nil
        end
      end) || [port: 4000]

    File.mkdir_p!("tmp")
    HexWeb.Config.init(opts)
    Plug.Adapters.Cowboy.http(HexWeb.Router, [], opts)
    HexWeb.Supervisor.start_link
  end

  def store do
    HexWeb.Config.store
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
