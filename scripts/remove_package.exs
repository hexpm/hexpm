[name] = System.argv

package = HexWeb.Repo.get_by!(HexWeb.Package, name: name)

unless package do
  IO.puts "No package: #{name}"
  System.halt(1)
end

releases = HexWeb.Release.all(package)
           |> HexWeb.Repo.all
owners   = Ecto.assoc(package, :owners)
           |> HexWeb.Repo.all
           |> HexWeb.Repo.preload(:emails)

IO.puts name

IO.puts ""
IO.puts "Owners:"
Enum.each(owners, fn owner ->
  IO.puts("#{owner.username} #{HexWeb.User.email(owner, :primary)}")
end)

IO.puts ""
IO.puts "Releases:"
Enum.each(releases, &IO.puts(&1.version))

answer = IO.gets "Remove? [Yn] "

if answer =~ ~r/^(Y(es)?)?$/i do
  Enum.each(owners, &(HexWeb.Package.owner(package, &1) |> HexWeb.Repo.delete_all))
  Enum.each(releases, &(HexWeb.Release.delete(&1, force: true) |> HexWeb.Repo.delete!))
  HexWeb.Repo.delete!(package)
  HexWeb.RegistryBuilder.partial_build({:revert, name})
  IO.puts "Removed"
else
  IO.puts "Not removed"
end

# TODO: Remove tarballs!
