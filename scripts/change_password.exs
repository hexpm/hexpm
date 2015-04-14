case System.argv do
  ["username", username, password] ->
    user = HexWeb.User.get(username: username)

    unless user do
      IO.puts "No user with username: #{username}"
      System.halt(1)
    end

  ["email", email, password] ->
    user = HexWeb.User.get(email: email)

    unless user do
      IO.puts "No user with email: #{email}"
      System.halt(1)
    end
end

{:ok, _user} = HexWeb.User.update(%{username: user, password: password})

IO.puts "Password changed for user: #{user.username} (#{user.email})"
