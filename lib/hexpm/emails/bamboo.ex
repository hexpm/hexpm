defmodule Hexpm.Emails.Bamboo.SESAdapter do
  @behaviour Bamboo.Adapter

  def deliver(email, _config) do
    if email.headers != %{} do
      raise "headers not supported for Hexpm.Emails.Bamboo.SESAdapter"
    end

    destination = %{
      to: emails(email.to),
      cc: emails(email.cc),
      bcc: emails(email.bcc)
    }

    message = ExAws.SES.build_message(email.html_body, email.text_body, email.subject)

    ExAws.SES.send_email(destination, message, email(email.from), [])
    |> ExAws.request!()
  end

  def handle_config(config) do
    config
  end

  defp emails(emails), do: emails |> List.wrap() |> Enum.map(&email/1)

  defp email({name, email}), do: "#{name} <#{email}>"
  defp email(email), do: email
end

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
