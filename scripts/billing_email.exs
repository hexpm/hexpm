# TODO: Filter organizations that already entered billing details

Hexpm.Repo.all(Hexpm.Repository.Repository)
|> Hexpm.Repo.preload([repository_users: [user: :emails]])
|> Enum.reject(fn repository ->
  Hexpm.Billing.dashboard(repository.name)["subscription"]
end)
|> Enum.flat_map(fn repository ->
  Enum.flat_map(repository.repository_users, fn ru ->
    if ru.role == "admin" do
      [ru.user]
    else
      []
    end
  end)
end)
|> Enum.uniq_by(& &1.id)
|> Enum.each(fn user ->
  user
  # |> Hexpm.Emails.organizations_live()
  |> Hexpm.Emails.billing_reminder()
  |> Hexpm.Emails.Mailer.deliver_now_throttled()

  IO.puts(user.username)
end)
