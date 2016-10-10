defmodule HexWeb.DashboardView do
  use HexWeb.Web, :view

  defp pages do
    [profile: "Profile",
     password: "Password",
     email: "Email"]
  end

  defp selected(conn, id) do
    if List.last(conn.path_info) == Atom.to_string(id) do
      "selected"
    end
  end
end
