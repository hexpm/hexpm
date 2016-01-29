[name] = System.argv

package = HexWeb.Package.get(name)

unless package do
  IO.puts "No package: #{name}"
  System.halt(1)
end

releases = HexWeb.Release.all(package)
owners   = HexWeb.Package.owners(package)

IO.puts name

IO.puts ""
IO.puts "Owners:"
Enum.each(owners, &IO.puts("#{&1.username} #{&1.email}"))

IO.puts ""
IO.puts "Releases:"
Enum.each(releases, &IO.puts(&1.version))

answer = IO.gets "Remove? [Yn] "

if answer =~ ~r/^(Y(es)?)?$/i do
  Enum.each(owners, &HexWeb.Package.delete_owner(package, &1))
  Enum.each(releases, &HexWeb.Release.delete(&1, force: true))
  HexWeb.Package.delete(package)
  IO.puts "Removed"
else
  IO.puts "Not removed"
end

# TODO: Remove tarballs!
