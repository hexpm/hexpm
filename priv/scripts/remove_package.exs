destructure [repo, name, version], System.argv()

repository = Hexpm.Repo.get_by!(Hexpm.Repository.Repository, name: repo)

unless repository do
  IO.puts("No repository: #{repo}")
  System.halt(1)
end

package =
  Hexpm.Repository.Package
  |> Hexpm.Repo.get_by!(name: name, repository_id: repository.id)
  |> Hexpm.Repo.preload(:repository)

unless package do
  IO.puts("No package: #{name}")
  System.halt(1)
end

owners =
  Ecto.assoc(package, :owners)
  |> Hexpm.Repo.all()
  |> Hexpm.Repo.preload(:emails)

IO.puts("")
IO.puts("Owners:")

Enum.each(owners, fn owner ->
  IO.puts("#{owner.username} #{Hexpm.Accounts.User.email(owner, :primary)}")
end)

if version do
  release =
    Hexpm.Repository.Releases.get(package, version)
    |> Hexpm.Repo.preload(package: :repository)

    answer = IO.gets("Remove? [Yn] ")

    if answer =~ ~r/^(Y(es)?)?$/i do
      Hexpm.Repository.Release.delete(release, force: true)
      |> Hexpm.Repo.delete!()

      Hexpm.Repository.Assets.revert_release(release)
      Hexpm.Repository.RegistryBuilder.package(package)
      Hexpm.Repository.RegistryBuilder.repository(package.repository)
      IO.puts("Removed")
    else
      IO.puts("Not removed")
    end
else
  package_owners =
    Ecto.assoc(package, :package_owners)
    |> Hexpm.Repo.all()

  releases =
    Hexpm.Repository.Release.all(package)
    |> Hexpm.Repo.all()
    |> Hexpm.Repo.preload(package: :repository)

  IO.puts("")
  IO.puts("Releases:")
  Enum.each(releases, &IO.puts(&1.version))

  answer = IO.gets("Remove? [Yn] ")

  if answer =~ ~r/^(Y(es)?)?$/i do
    Enum.each(package_owners, &Hexpm.Repo.delete!/1)
    Enum.each(releases, &(Hexpm.Repository.Release.delete(&1, force: true) |> Hexpm.Repo.delete!()))
    Hexpm.Repo.delete!(package)
    Enum.each(releases, &Hexpm.Repository.Assets.revert_release/1)
    Hexpm.Repository.RegistryBuilder.package_delete(package)
    Hexpm.Repository.RegistryBuilder.repository(package.repository)
    IO.puts("Removed")
  else
    IO.puts("Not removed")
  end
end
