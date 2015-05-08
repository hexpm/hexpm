[name] = System.argv

package = HexWeb.Package.get(name)

unless package do
  IO.puts "No package: #{name}"
  System.halt(1)
end

releases = HexWeb.Release.all(package)

IO.puts name
IO.puts ""
IO.puts "Releases:"
Enum.each(releases, &IO.puts(&1.version))

answer = IO.gets "Remove? [Yn] "

if answer =~ ~r/^(Y(es)?)?$/i do
  Enum.each(releases, &HexWeb.Release.delete(&1, force: true))
  HexWeb.Package.delete(package)
  IO.puts "Removed"
else
  IO.puts "Not removed"
end

# TODO: Remove tarballs!
