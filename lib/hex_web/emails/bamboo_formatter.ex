defimpl Bamboo.Formatter, for: HexWeb.Accounts.User do
  def format_email_address(user, _opts) do
    {user.username, HexWeb.Accounts.User.email(user, :primary)}
  end
end

defimpl Bamboo.Formatter, for: HexWeb.Accounts.Email do
  def format_email_address(email, _opts) do
    {email.user.username, email.email}
  end
end
