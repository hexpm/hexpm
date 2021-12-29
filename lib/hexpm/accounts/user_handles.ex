defmodule Hexpm.Accounts.UserHandles do
  use Hexpm.Schema
  use Phoenix.HTML

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
    Enum.flat_map(services(), fn {field, _service, url} ->
      handle = Map.get(user.handles, field)

      if handle = handle && handle(field, handle) do
        full_url = String.replace(url, "{handle}", handle)
        [{handle_icon(field), full_url}]
      else
        []
      end
    end)
  end

  def handle(:twitter, handle), do: unuri(handle, "twitter.com", "/")
  def handle(:github, handle), do: unuri(handle, "github.com", "/")
  def handle(:elixirforum, handle), do: unuri(handle, "elixirforum.com", "/u/")
  def handle(_service, handle), do: handle

  def handle_icon(:twitter), do: "twitter-fill"
  def handle_icon(:github), do: "github-fill"
  def handle_icon(:slack), do: "slack-fill"
  def handle_icon(field), do: field

  def handle_svg_icon(:elixirforum) do
    ~E"""
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
      <g clip-path="url(#clip0_280_334)">
        <path d="M13.1954 11.0494C13.1954 13.5507 11.244 16.0001 8.03335 16.0001C4.53402 16.0001 2.80469 13.5267 2.80469 10.4734C2.80469 7.00006 5.39935 1.83873 8.13802 0.0420585C8.17977 0.0152102 8.22823 0.000643208 8.27786 2.0814e-05C8.32749 -0.000601579 8.3763 0.0127458 8.41871 0.0385387C8.46112 0.0643316 8.49542 0.101531 8.51769 0.145888C8.53997 0.190245 8.54932 0.239972 8.54469 0.289392C8.39105 1.82615 8.79157 3.36724 9.67402 4.63473C10.022 5.16473 10.402 5.62006 10.8494 6.20273C11.476 7.02073 11.9407 7.47339 12.612 8.76406L12.622 8.78273C12.9995 9.47852 13.1966 10.2578 13.1954 11.0494Z" fill="#304254"/>
      </g>
      <defs>
        <clipPath id="clip0_280_334">
          <rect width="16" height="16" fill="white"/>
        </clipPath>
      </defs>
    </svg>
    """
  end

  def handle_svg_icon(:freenode) do
    ~E"""
    <div class="mix-blend-luminosity">
      <svg width="16" height="16" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96.89 78.87">
        <path d="M40.86 9.3h-.01a32.2 32.2 0 00-.65.14l-.22.04a39.48 39.48 0 00-.43.1l-.21.05a39.35 39.35 0 00-5.68 1.8l-.12.06L44.8 48.82l.47-.55 1.26-1.48zm14.98-.04l-4.1 31.45 3.32-3.88.66 1.05 7.36-26.51-.18-.07a37.97 37.97 0 00-6.55-1.94 39.84 39.84 0 00-.43-.09zm-35.33 10.9a34.93 34.93 0 00-3.03 3.42 41.1 41.1 0 00-1.8 2.48v.02L37.2 49.59l1.62-2.12.08.04zm55.45-.44l-15.91 25.1 1.81 2.9 19.26-21.8a35.29 35.29 0 00-2.9-3.82 38.85 38.85 0 00-2.26-2.38zM9.98 39.94a38.23 38.23 0 00-.72 7.54L32.2 56.1l1.79-2.33zm77.07.67L65.2 53.1l1.72 2.75 20.7-7.55v-.1a22.66 22.66 0 00.01-.66v-.44-.22-.14-.22l-.01-.21v-.22l-.01-.22-.01-.22-.01-.22-.01-.22-.02-.21-.01-.22-.02-.22-.01-.22-.02-.21-.02-.22-.02-.22-.02-.22-.02-.21a31.66 31.66 0 00-.37-2.6v-.04zM12.42 62.57a39.78 39.78 0 003.96 7.03h.01l6.73-1.48.14-.18h-.16l4.18-5.44zm58.83.21l3.24 5.39 6.05 1.36.05-.06a36.02 36.02 0 002.53-4.1A37.2 37.2 0 0084.27 63z" paint-order="markers fill stroke"/>
        <g fill="rgba(48, 66, 84, 1)">
          <path d="M55.53 35.83L44.12 48.86l-5.22-2.3-16.98 21.82h1.48l15.88-20.32 5.17 2.29 10.9-12.45c6.04 10.27 12.55 20.15 18.47 30.49h1.48z" />
          <path d="M55.32 39.73l-10.6 12.15-5.17-2.15-14.64 18.64h1.62l13.4-17.15 5.14 2.13L55.14 41.8l15.84 26.62 1.56-.03z" />
          <path d="M28.1 68.36l12.23-15.59 5.24 2.13 9.51-10.92 14.28 24.4z"/>
        </g>
      </svg>
    </div>
    """
  end

  def handle_svg_icon(_field), do: ""

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
