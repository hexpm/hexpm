defmodule HexWeb.UserHandles do
  use HexWeb.Web, :model

  embedded_schema do
    field :twitter, :string
    field :github, :string
    field :elixirforum, :string
    field :freenode, :string
    field :slack, :string
  end

  def changeset(handles, params) do
    cast(handles, params, ~w(twitter github elixirforum freenode slack))
  end

  def services do
    [{:twitter, "Twitter", "https://twitter.com/{handle}"},
     {:github, "GitHub", "https://github.com/{handle}"},
     {:elixirforum, "Elixir Forum", "https://elixirforum.com/users/{handle}"},
     {:freenode, "Freenode", "irc://chat.freenode.net/elixir-lang"},
     {:slack, "Slack", "https://elixir-slackin.herokuapp.com/"}]
  end
end
