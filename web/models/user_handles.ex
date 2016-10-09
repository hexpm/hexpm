defmodule HexWeb.UserHandles do
  use HexWeb.Web, :model

  embedded_schema do
    field :twitter, :string
    field :github, :string
    field :freenode, :string
  end

  def changeset(handles, params) do
    cast(handles, params, ~w(twitter github freenode))
  end

  def services do
    [{:twitter, "Twitter", "https://twitter.com/{handle}"},
     {:github, "GitHub", "https://github.com/{handle}"},
     {:freenode, "Freenode", "irc://chat.freenode.net/elixir-lang"}]
  end
end
