defimpl Bamboo.Formatter, for: HexWeb.User do
  def format_email_address(user, _opts) do
    {user.username, HexWeb.User.email(user, :primary)}
  end
end
