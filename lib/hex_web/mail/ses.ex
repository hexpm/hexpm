defmodule HexWeb.Mail.SES do
  @behaviour HexWeb.Mail
  require Logger

  def send(to, subject, body) do
    ses_rate = Application.get_env(:hex_web, :ses_rate) |> String.to_integer

    Enum.each(recipient_chunks(to, ses_rate), fn recipients ->
      HexWeb.Throttle.wait(HexWeb.SESThrottle, length(recipients))
      do_send(recipients, subject, body)
    end)
  end

  defp recipient_chunks(recipients, limit) do
    Enum.chunk(recipients, limit, limit, [])
  end

  defp do_send(to, subject, body) do
    source   = Application.get_env(:hex_web, :email_host)
    endpoint = Application.get_env(:hex_web, :ses_endpoint)
    username = Application.get_env(:hex_web, :ses_user)
    password = Application.get_env(:hex_web, :ses_pass)
    port     = Application.get_env(:hex_web, :ses_port) |> String.to_integer
    body     = Phoenix.HTML.safe_to_string(body)
    source   = "noreply@" <> source

    send(source, to, subject, body, endpoint, username, password, port)
  end

  defp send(from, to, subject, body, server, login, password, port) do
    headers = [
      {"Subject", subject},
      {"From", "Hex.pm <#{from}>"},
      {"To", Enum.join(to, ",")},
      {"Return-Path", from}
    ]

    email = :mimemail.encode({"text", "html", headers, [{"charset", "utf-8"}], body})

    opts = [
      relay: server,
      username: login,
      password: password,
      port: port,
      tls: :always ]

    result = :gen_smtp_client.send_blocking({from, to, email}, opts)

    unless is_binary(result) do
      Logger.error(["Failed to send email to ", inspect(to), " with subject ", inspect(subject)])
      raise "Failed to send email"
    end
    result
  end
end
