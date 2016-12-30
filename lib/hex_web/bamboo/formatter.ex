defimpl Bamboo.Formatter, for: HexWeb.User do
  def format_email_address(user, _opts) do
    Enum.map(user.emails, fn(email) -> { user.username, email.email } end)
  end
end
