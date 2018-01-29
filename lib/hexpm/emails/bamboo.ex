defmodule Hexpm.Emails.Bamboo.SESAdapter do
  require Logger

  @behaviour Bamboo.Adapter
  @backoff 100
  @backoff_times 5

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

    request = ExAws.SES.send_email(destination, message, email(email.from), [])
    send_email(request, email, 0)
  end

  def handle_config(config) do
    config
  end

  defp send_email(request, email, times) do
    request
    |> ExAws.request()
    |> maybe_retry(request, email, times)
  end

  defp maybe_retry({:error, {:http_error, 454, _body}} = error, request, email, times) do
    if times > @backoff_times do
      Logger.warn("AWS SES throttled ##{times}")
      raise "failed to send email\n\n#{inspect(email)}\n\n#{inspect(error)}"
    else
      Process.sleep(@backoff * trunc(:math.pow(2, times)))
      send_email(request, email, times + 1)
    end
  end

  defp maybe_retry({:error, _} = error, _request, email, _times) do
    raise "failed to send email\n\n#{inspect(email)}\n\n#{inspect(error)}"
  end

  defp maybe_retry({:ok, result}, _request, _email, _times) do
    result
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
