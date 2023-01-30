defmodule Hexpm do
  def setup do
    Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDependant, concurrently: false)
    Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDownload, concurrently: false)
    Hexpm.Repo.refresh_view(Hexpm.Repository.ReleaseDownload, concurrently: false)

    unless Hexpm.Repo.get(Hexpm.Accounts.Organization, 1) do
      %{id: 1} =
        %Hexpm.Accounts.Organization{name: "hexpm", trial_end: DateTime.utc_now()}
        |> Hexpm.Repo.insert!()
    end

    unless Hexpm.Repo.get(Hexpm.Repository.Repository, 1) do
      %{id: 1} =
        %Hexpm.Repository.Repository{name: "hexpm", organization_id: 1}
        |> Hexpm.Repo.insert!()
    end

    unless Hexpm.Repo.get(Hexpm.Accounts.User, 1) do
      %{id: 1} =
        %Hexpm.Accounts.User{username: "hexdocs", service: true}
        |> Hexpm.Repo.insert!()
    end
  end
end
