defimpl Bamboo.Formatter, for: Hexpm.Accounts.User do
  def format_email_address(user, _opts) do
    {user.username, Hexpm.Accounts.User.email(user, :primary)}
  end
end

defimpl Bamboo.Formatter, for: Hexpm.Accounts.Email do
  def format_email_address(email, _opts) do
    {email.user.username, email.email}
  end
end
