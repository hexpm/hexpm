defmodule ExplexWeb do
  use Application.Behaviour

  def start(_type, _args) do
    Plug.Adapters.Cowboy.http(ExplexWeb.Router, [])

    ExplexWeb.Supervisor.start_link
  end
end
