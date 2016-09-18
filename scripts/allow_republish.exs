[name, version] = System.argv

package = HexWeb.Repo.get_by!(HexWeb.Package, name: name)

unless package do
  IO.puts "No package: #{name}"
  System.halt(1)
end

release = HexWeb.Repo.get_by!(assoc(package, :releases), version: version)

unless release do
  IO.puts "No release: #{name} #{version}"
  System.halt(1)
end

Ecto.Changeset.change(release, release | inserted_at: HexWeb.Utils.utc_now)
|> HexWeb.Repo.update!(release)
