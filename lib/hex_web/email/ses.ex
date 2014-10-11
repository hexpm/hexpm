defmodule HexWeb.Email.SES do
  @behaviour HexWeb.Email

  def send(to, subject, body) do
    source   = Application.get_env(:hex_web, :email_host)
    endpoint = Application.get_env(:hex_web, :ses_endpoint)
    username = Application.get_env(:hex_web, :ses_user)
    password = Application.get_env(:hex_web, :ses_pass)
    port     = Application.get_env(:hex_web, :ses_port) |> String.to_integer
    source   = "noreply@" <> source

    send(source, to, subject, body, endpoint, username, password, port)
  end

  defp send(from, to, subject, body, server, login, password, port) do
    headers = headers(from, to, subject)
    email = {to, [from], headers <> "\r\n\r\n" <> body}
    opts = [
      relay: server,
      username: login,
      password: password,
      port: port,
      tls: :always ]

    :gen_smtp_client.send_blocking(email, opts)
  end

  defp headers(subject, from, to) do
    [ "MIME-Version: 1.0",
      "Content-Type: text/html; charset=utf-8",
      "From: #{from}",
      "To: #{to}",
      "Subject: #{subject}" ]
    |> Enum.join("\r\n")
  end
end
