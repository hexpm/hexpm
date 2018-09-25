destructure([version, name, repo], Enum.reverse(System.argv()))

organization =
  if repo do
    Hexpm.Repo.get_by!(Hexpm.Accounts.Organization, name: repo)
  else
    Hexpm.Repo.get!(Hexpm.Accounts.Organization, 1)
  end

unless organization do
  IO.puts("No package: #{repo}")
  System.halt(1)
end

package =
  Hexpm.Repo.get_by!(Hexpm.Repository.Package, name: name, organization_id: organization.id)

unless package do
  IO.puts("No package: #{name}")
  System.halt(1)
end

release = Hexpm.Repo.get_by!(Ecto.assoc(package, :releases), version: version)

unless release do
  IO.puts("No release: #{name} #{version}")
  System.halt(1)
end

Ecto.Changeset.change(release, %{inserted_at: DateTime.utc_now()})
|> Hexpm.Repo.update!()
