defmodule HexpmWeb.VersionsController do
  use HexpmWeb, :controller

  def index(conn, params) do
    %{"repository" => repository, "name" => name} = params
    organizations = Users.all_organizations(conn.assigns.current_user)

    if repository in Enum.map(organizations, & &1.name) do
      organization = Organizations.get(repository)
      package = organization && Packages.get(organization, name)
      # Should have access even though organization does not have active billing
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
