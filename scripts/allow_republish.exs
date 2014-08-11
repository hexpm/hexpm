[name, version] = System.argv

package = HexWeb.Package.get(name)

unless package do
  IO.puts "No package: #{name}"
  System.halt(1)
end

release = HexWeb.Release.get(package, version)

unless release do
  IO.puts "No release: #{name} #{version}"
  System.halt(1)
end

release = %{release | created_at: HexWeb.Util.ecto_now}
:ok = HexWeb.Repo.update(release)
