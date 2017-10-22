desctructure([version, name, repo], Enum.reverse(System.argv()))

repository =
  if repo do
    Hexpm.Repo.get_by!(Hexpm.Repository.Repository, name: repo)
  else
    Hexpm.Repo.get!(Hexpm.Repository.Repository, 1)
  end

unless repository do
  IO.puts("No package: #{repo}")
  System.halt(1)
end

package = Hexpm.Repo.get_by!(Hexpm.Repository.Package, name: name, repository_id: repository.id)

unless package do
  IO.puts("No package: #{name}")
  System.halt(1)
end

release = Hexpm.Repo.get_by!(Ecto.assoc(package, :releases), version: version)

unless release do
  IO.puts("No release: #{name} #{version}")
  System.halt(1)
end

Ecto.Changeset.change(release, %{inserted_at: NaiveDateTime.utc_now()})
|> Hexpm.Repo.update!()
