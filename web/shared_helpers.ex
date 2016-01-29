defmodule HexWeb.SharedHelpers do
   def api_url(path) do
    HexWeb.Endpoint.url <> "/api/" <> Path.join(List.wrap(path))
  end
end
