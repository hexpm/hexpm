case System.argv do
  ["username", username, password] ->
    if user = HexWeb.Repo.get_by(HexWeb.Accounts.User, username: username) do
      HexWeb.Accounts.User.update_password_no_check(user, password: password)
      |> HexWeb.Repo.update!
    else
      IO.puts "No user with username: #{username}"
      System.halt(1)
    end


  ["email", email, password] ->
    if user = HexWeb.Repo.get_by(HexWeb.Accounts.User, email: email) do
      HexWeb.Accounts.User.update_password_no_check(user, password: password)
      |> HexWeb.Repo.update!
    else
      IO.puts "No user with email: #{email}"
      System.halt(1)
    end

end
