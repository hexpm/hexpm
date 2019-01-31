defmodule HexpmWeb.VersionController do
  use HexpmWeb, :controller

  def index(conn, params) do
    %{"repository" => repository, "name" => name} = params
    organizations = Users.all_organizations(conn.assigns.current_user)
    repositories = Enum.map(organizations, & &1.repository)

    if repository in Enum.map(repositories, & &1.name) do
      repository = Repositories.get(repository)
      package = repository && Packages.get(repository, name)

      # Should have access even though repository does not have active billing
      if package do
        releases = Releases.all(package)

        if releases do
          render(
            conn,
            "index.html",
            title: "#{name} versions",
            container: "container",
            releases: releases,
            package: package
          )
        end
      end
    end || not_found(conn)
  end
end
