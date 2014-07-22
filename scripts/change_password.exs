[username, password] = System.argv

user = HexWeb.User.get(username: username)

unless user do
  IO.puts "No user with username: #{username}"
  System.halt(1)
end

{:ok, user} = HexWeb.User.update(user, nil, password)

IO.puts "Password changed for user: #{username}"
IO.inspect user
