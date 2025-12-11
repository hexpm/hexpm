destructure [username_or_email], System.argv()

alias Hexpm.Accounts.{AuditLogs, User, Users}

if !username_or_email do
  IO.puts("Usage: mix run priv/scripts/reset_tfa.exs <username_or_email>")
  System.halt(1)
end

user = Users.get(username_or_email, [:emails])

cond do
  !user ->
    IO.puts("No user found with username or email: #{username_or_email}")
    System.halt(1)

  !User.tfa_enabled?(user) ->
    IO.puts("User #{user.username} does not have 2FA enabled")
    System.halt(0)

  true ->
    Users.tfa_disable(user, audit: AuditLogs.admin())

    IO.puts("Successfully disabled 2FA for user: #{user.username}")
    IO.puts("The user can now log in without 2FA and re-enable it in their security settings")
end
