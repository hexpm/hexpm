defmodule Hexpm.Accounts.UserHandles do
  use Hexpm.Schema

  @derive HexpmWeb.Stale

  embedded_schema do
    field :twitter, :string
    field :github, :string
    field :elixirforum, :string
    field :freenode, :string
    field :slack, :string
  end

  def changeset(handles, params) do
    cast(handles, params, ~w(twitter github elixirforum freenode slack)a)
  end

  def services() do
    [
      {:twitter, "Twitter", "https://twitter.com/{handle}"},
      {:github, "GitHub", "https://github.com/{handle}"},
      {:elixirforum, "Elixir Forum", "https://elixirforum.com/u/{handle}"},
      {:freenode, "Libera", "irc://irc.libera.chat/elixir"},
      {:slack, "Slack", "https://elixir-slackin.herokuapp.com/"}
    ]
  end

  def render(%{handles: nil}) do
    []
  end

  def render(user) do
    Enum.flat_map(services(), fn {field, service, url} ->
      handle = Map.get(user.handles, field)

      if handle = handle && handle(field, handle) do
        full_url = String.replace(url, "{handle}", handle)
        [{service, handle, full_url}]
      else
        []
      end
    end)
  end

  def handle(:twitter, handle), do: unuri(handle, "twitter.com", "/")
  def handle(:github, handle), do: unuri(handle, "github.com", "/")
  def handle(:elixirforum, handle), do: unuri(handle, "elixirforum.com", "/u/")
  def handle(_service, handle), do: handle

  defp unuri(handle, host, path) do
    uri = URI.parse(handle)
    http? = uri.scheme in ["http", "https"]
    host? = String.contains?(uri.host || "", host)
    path? = String.starts_with?(uri.path || "", path)

    cond do
      http? and host? and path? ->
        {_, handle} = String.split_at(uri.path, String.length(path))
        handle

      uri.path ->
        String.replace(uri.path, host <> path, "")

      true ->
        nil
    end
  end
end
