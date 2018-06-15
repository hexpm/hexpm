defmodule Hexpm.Web.UserController do
  use Hexpm.Web, :controller

  def show(conn, %{"username" => username}) do
    if user = Users.get_by_username(username, [:emails, owned_packages: :organization]) do
      organizations = Users.all_organizations(conn.assigns.current_user)
      organization_ids = Enum.map(organizations, & &1.id)

      packages =
        user.owned_packages
        |> Enum.filter(&(&1.organization_id in organization_ids))
        |> Packages.attach_versions()
        |> Enum.sort_by(&[organization_sort(&1.organization), &1.name])

      public_email = User.email(user, :public)
      gravatar_email = User.email(user, :gravatar)

      render(
        conn,
        "show.html",
        title: user.username,
        container: "container page user",
        user: user,
        packages: packages,
        public_email: public_email,
        gravatar_email: gravatar_email
      )
    else
      not_found(conn)
    end
  end

  # TODO: DRY up
  # Atoms sort before strings
  defp organization_sort(%Organization{id: 1}), do: :first
  defp organization_sort(%Organization{name: name}), do: name
end
