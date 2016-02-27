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

IO.puts name

IO.puts ""
IO.puts "Owners:"
Enum.each(owners, &IO.puts("#{&1.username} #{&1.email}"))

IO.puts ""
IO.puts "Releases:"
Enum.each(releases, &IO.puts(&1.version))

answer = IO.gets "Remove? [Yn] "

if answer =~ ~r/^(Y(es)?)?$/i do
  Enum.each(owners, &(HexWeb.Package.owner(package, &1) |> HexWeb.Repo.delete_all))
  Enum.each(releases, &(HexWeb.Release.delete(&1, force: true) |> HexWeb.Repo.delete!))
  HexWeb.Repo.delete!(package)
  IO.puts "Removed"
else
  IO.puts "Not removed"
end

# TODO: Remove tarballs!
