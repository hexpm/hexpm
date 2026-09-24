defmodule Hexpm.Emails.OutboxEnvelope do
  alias Swoosh.Email

  @rendering_private_keys [:phoenix_layout, :phoenix_template, :phoenix_view]
  @persisted_private_keys [:type]

  def dump!(%Email{} = email) do
    ensure_deliverable!(email)
    ensure_supported!(email)

    %{
      "version" => 1,
      "subject" => email.subject,
      "from" => dump_recipient(email.from),
      "to" => dump_recipients(email.to),
      "cc" => dump_recipients(email.cc),
      "bcc" => dump_recipients(email.bcc),
      "reply_to" => dump_reply_to(email.reply_to),
      "text_body" => email.text_body,
      "html_body" => email.html_body,
      "headers" => email.headers,
      "provider_options" => dump_provider_options!(email.provider_options),
      "type" => email.private[:type]
    }
  end

  def load!(%{"version" => 1} = email) do
    persisted_email =
      Email.new(
        subject: Map.fetch!(email, "subject"),
        from: load_recipient(Map.fetch!(email, "from")),
        to: load_recipients(Map.fetch!(email, "to")),
        cc: load_recipients(Map.fetch!(email, "cc")),
        bcc: load_recipients(Map.fetch!(email, "bcc")),
        text_body: email["text_body"],
        html_body: email["html_body"],
        headers: Map.fetch!(email, "headers"),
        provider_options: load_provider_options!(Map.fetch!(email, "provider_options"))
      )

    persisted_email =
      case load_reply_to(Map.fetch!(email, "reply_to")) do
        nil -> persisted_email
        reply_to -> Email.reply_to(persisted_email, reply_to)
      end

    case email["type"] do
      nil -> persisted_email
      type -> Email.put_private(persisted_email, :type, type)
    end
  end

  defp ensure_deliverable!(%Email{} = email) do
    unless match?({_name, address} when is_binary(address) and address != "", email.from) do
      raise ArgumentError, "email outbox requires a sender"
    end

    unless is_list(email.to) and is_list(email.cc) and is_list(email.bcc) and
             email.to ++ email.cc ++ email.bcc != [] do
      raise ArgumentError, "email outbox requires a recipient"
    end

    unless valid_body?(email.text_body) and valid_body?(email.html_body) and
             (is_binary(email.text_body) or is_binary(email.html_body)) do
      raise ArgumentError, "email outbox requires a rendered body"
    end
  end

  defp valid_body?(body), do: is_nil(body) or is_binary(body)

  defp ensure_supported!(%Email{attachments: []} = email) do
    ensure_supported_private!(email.private)
  end

  defp ensure_supported!(%Email{}) do
    raise ArgumentError, "email outbox does not support attachments"
  end

  defp ensure_supported_private!(private) do
    if map_size(Map.drop(private, @rendering_private_keys ++ @persisted_private_keys)) != 0 do
      raise ArgumentError, "email outbox does not support private delivery options"
    end
  end

  defp dump_recipient({name, address}), do: %{"name" => name, "address" => address}
  defp dump_recipient(nil), do: nil

  defp dump_recipients(recipients), do: Enum.map(recipients, &dump_recipient/1)

  defp dump_reply_to(reply_to) when is_list(reply_to), do: dump_recipients(reply_to)
  defp dump_reply_to(reply_to), do: dump_recipient(reply_to)

  defp dump_provider_options!(%{} = options) when map_size(options) == 0, do: %{}

  defp dump_provider_options!(%{click_tracking: %{enable: enabled} = click_tracking} = options)
       when is_boolean(enabled) and map_size(click_tracking) == 1 and map_size(options) == 1 do
    %{"click_tracking" => %{"enable" => enabled}}
  end

  defp dump_provider_options!(_options) do
    raise ArgumentError, "email outbox does not support these provider options"
  end

  defp load_recipient(%{"name" => name, "address" => address}), do: {name, address}
  defp load_recipient(nil), do: nil

  defp load_recipients(recipients), do: Enum.map(recipients, &load_recipient/1)

  defp load_reply_to(reply_to) when is_list(reply_to), do: load_recipients(reply_to)
  defp load_reply_to(reply_to), do: load_recipient(reply_to)

  defp load_provider_options!(%{} = options) when map_size(options) == 0, do: %{}

  defp load_provider_options!(
         %{"click_tracking" => %{"enable" => enabled} = click_tracking} = options
       )
       when is_boolean(enabled) and map_size(click_tracking) == 1 and map_size(options) == 1 do
    %{click_tracking: %{enable: enabled}}
  end
end
