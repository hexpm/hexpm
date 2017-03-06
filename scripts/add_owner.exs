[name, username] = System.argv

package = Hexpm.Repo.get_by!(Hexpm.Repository.Package, name: name)
user    = Hexpm.Repo.get_by!(Hexpm.Accounts.User, username: username)

unless package do
  IO.puts "No package: #{name}"
  System.halt(1)
end

unless user do
  IO.puts "No user: #{username}"
  System.halt(1)
end

Hexpm.Repository.Package.build_owner(package, user) |> Hexpm.Repo.insert!
