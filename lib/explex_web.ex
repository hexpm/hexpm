defmodule ExplexWeb do
  use Application.Behaviour

  def start(_type, _args) do
    Plug.Adapters.Cowboy.http(ExplexWeb.Router, [])

    ExplexWeb.Supervisor.start_link
  end

  defprotocol Render do
    @moduledoc """
    Render entities to something that can be showed publically.
    Used, for example, when converting entities to JSON responses.
    """

    @spec render(term) :: Dict.t
    def render(entity)
  end
end
