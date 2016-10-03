defimpl Bamboo.Formatter, for: HexWeb.User do
  def format_email_address(user, _opts) do
    email = hd(user.emails).email

    {user.username, email}
  end
end
