defmodule Hexpm.Accounts.UserHandles do
  use Hexpm.Web, :schema

  @derive Hexpm.Web.Stale

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

  def services() do
    [{:twitter, "Twitter", "https://twitter.com/{handle}"},
     {:github, "GitHub", "https://github.com/{handle}"},
     {:elixirforum, "Elixir Forum", "https://elixirforum.com/users/{handle}"},
     {:freenode, "Freenode", "irc://chat.freenode.net/elixir-lang"},
     {:slack, "Slack", "https://elixir-slackin.herokuapp.com/"}]
  end

  def render(%{handles: nil}) do
    []
  end
  def render(user) do
    Enum.flat_map(services(), fn {field, service, url} ->
      if handle = Map.get(user.handles, field) do
        handle = UserHandles.handle(service, handle)
        full_url = String.replace(url, "{handle}", handle)
        [{service, handle, full_url}]
      else
        []
      end
    end)
  end

  def handle(:twitter, handle), do: unuri(handle, "twitter.com", "/")
  def handle(:github, handle), do: unuri(handle, "github.com", "/")
  def handle(:elixirforum, handle), do: unuri(handle, "elixirforum.com", "/users/")
  def handle(_service, handle), do: handle

  defp unuri(handle, host, path) do
    uri = URI.parse(handle)
    http? = uri.scheme in ["http", "https"]
    host? = String.contains?(uri.host, host)
    path? = String.starts_with?(uri.path, path)

    if http? and host? and path? do
      {_, handle} = String.split_at(uri.path, String.length(path))
      handle
    else
      uri.path
    end
  end
end
