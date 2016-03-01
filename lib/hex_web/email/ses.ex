defmodule HexWeb.Email.SES do
  @behaviour HexWeb.Email

  def send(to, subject, body) do
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
      {"To", to},
      {"Return-Path", from}
    ]

    email = :mimemail.encode({"text", "html", headers, [{"charset", "utf-8"}], body})

    opts = [
      relay: server,
      username: login,
      password: password,
      port: port,
      tls: :always ]

    :gen_smtp_client.send({from, to, email}, opts, fn result ->
      {:ok, _receipt} = result
    end)
  end
end
