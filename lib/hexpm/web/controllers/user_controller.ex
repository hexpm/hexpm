defmodule Hexpm.Web.UserController do
  use Hexpm.Web, :controller

  def show(conn, %{"username" => username}) do
    if user = Users.get_by_username(username, [:emails, owned_packages: :repository]) do
      repositories = Users.all_repositories(conn.assigns.current_user)
      repository_ids = Enum.map(repositories, & &1.id)
      packages =
        user.owned_packages
        |> Enum.filter(& &1.repository_id in repository_ids)
        |> Packages.attach_versions()
        |> Enum.sort_by(&[repository_sort(&1.repository), &1.name])
      public_email = User.email(user, :public)
      gravatar_email = User.email(user, :gravatar)

      render(conn, "show.html", [
        title: user.username,
        container: "container page user",
        user: user,
        packages: packages,
        public_email: public_email,
        gravatar_email: gravatar_email
      ])
    else
      not_found(conn)
    end
  end

  # TODO: DRY up
  # Atoms sort before strings
  defp repository_sort(%Repository{id: 1}), do: :first
  defp repository_sort(%Repository{name: name}), do: name
end
