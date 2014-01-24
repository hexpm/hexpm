defmodule ExplexWeb do
  use Application.Behaviour

  # See http://elixir-lang.org/docs/stable/Application.Behaviour.html
  # for more information on OTP Applications
  def start(_type, _args) do
    Plug.Adapters.Cowboy.http(ExplexWeb.Router, [])

    ExplexWeb.Supervisor.start_link
  end
end
