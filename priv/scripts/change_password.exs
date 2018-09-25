case System.argv() do
  ["username", username, password] ->
    if user = Hexpm.Repo.get_by(Hexpm.Accounts.User, username: username) do
      Hexpm.Accounts.User.update_password_no_check(user, password: password)
      |> Hexpm.Repo.update!()
    else
      IO.puts("No user with username: #{username}")
      System.halt(1)
    end

  ["email", email, password] ->
    if user = Hexpm.Repo.get_by(Hexpm.Accounts.User, email: email) do
      Hexpm.Accounts.User.update_password_no_check(user, password: password)
      |> Hexpm.Repo.update!()
    else
      IO.puts("No user with email: #{email}")
      System.halt(1)
    end
end
