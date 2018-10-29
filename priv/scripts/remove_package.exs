destructure [name, org], Enum.reverse(System.argv())

organization =
  if org do
    Hexpm.Repo.get_by!(Hexpm.Accounts.Organization, name: org)
  else
    Hexpm.Repo.get!(Hexpm.Accounts.Organization, 1)
  end

unless organization do
  IO.puts("No organzation: #{org}")
  System.halt(1)
end

package =
  Hexpm.Repository.Package
  |> Hexpm.Repo.get_by!(name: name, organization_id: organization.id)
  |> Hexpm.Repo.preload(:organization)

unless package do
  IO.puts("No package: #{name}")
  System.halt(1)
end

releases =
  Hexpm.Repository.Release.all(package)
  |> Hexpm.Repo.all()
  |> Hexpm.Repo.preload(package: :organization)

package_owners =
  Ecto.assoc(package, :package_owners)
  |> Hexpm.Repo.all()

owners =
  Ecto.assoc(package, :owners)
  |> Hexpm.Repo.all()
  |> Hexpm.Repo.preload(:emails)

IO.puts(name)

IO.puts("")
IO.puts("Owners:")

Enum.each(owners, fn owner ->
  IO.puts("#{owner.username} #{Hexpm.Accounts.User.email(owner, :primary)}")
end)

IO.puts("")
IO.puts("Releases:")
Enum.each(releases, &IO.puts(&1.version))

answer = IO.gets("Remove? [Yn] ")

if answer =~ ~r/^(Y(es)?)?$/i do
  Enum.each(package_owners, &Hexpm.Repo.delete!/1)
  Enum.each(releases, &(Hexpm.Repository.Release.delete(&1, force: true) |> Hexpm.Repo.delete!()))
  Hexpm.Repo.delete!(package)
  Enum.each(releases, &Hexpm.Repository.Assets.revert_release/1)
  Hexpm.Repository.RegistryBuilder.partial_build({:publish, package})
  IO.puts("Removed")
else
  IO.puts("Not removed")
end
