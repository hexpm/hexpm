[name, username] = System.argv

package = HexWeb.Package.get(name)
user    = HexWeb.User.get(username: username)

unless package do
  IO.puts "No package: #{name}"
  System.halt(1)
end

unless user do
  IO.puts "No user: #{usernname}"
  System.halt(1)
end

HexWeb.Package.add_owner(package, user)
