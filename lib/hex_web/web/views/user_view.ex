defmodule HexWeb.UserView do
  use HexWeb.Web, :view

  def handles(user) do
    Enum.flat_map(UserHandles.services, fn {field, service, url} ->
      if handle = Map.get(user.handles, field) do
        handle = UserHandles.handle(service, handle)
        full_url = String.replace(url, "{handle}", handle)
        [{service, handle, full_url}]
      else
        []
      end
    end)
  end
end
