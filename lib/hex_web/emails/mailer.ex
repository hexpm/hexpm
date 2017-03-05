defmodule HexWeb.Mailer do
  use Bamboo.Mailer, otp_app: :hex_web

  def deliver_now_throttled(email) do
    ses_rate = Application.get_env(:hex_web, :ses_rate) |> String.to_integer

    email
    |> recipients
    |> recipient_chunks(ses_rate)
    |> Enum.each(fn chunk ->
      HexWeb.Throttle.wait(HexWeb.SESThrottle, length(chunk))
      email
      |> Bamboo.Email.to(chunk)
      |> HexWeb.Mailer.deliver_now
    end)
  end

  defp recipient_chunks(recipients, limit),
    do: Enum.chunk(recipients, limit, limit, [])

  defp recipients(email) do
    email
    |> Bamboo.Mailer.normalize_addresses
    |> Bamboo.Email.all_recipients
  end
end
