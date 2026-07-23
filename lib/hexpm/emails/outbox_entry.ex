defmodule Hexpm.Emails.OutboxEntry do
  use Hexpm.Schema

  alias Swoosh.Email

  @max_recipients 1_000
  @max_subject_bytes 1_000
  @max_body_bytes 1_000_000
  @max_headers 50
  @max_header_name_bytes 255
  @max_header_value_bytes 8_192

  schema "email_outbox_entries" do
    field :category, :string
    field :ordering_key, :string
    field :scope_key, :string
    field :email, :map, redact: true
    field :expires_at, :utc_datetime_usec

    timestamps(updated_at: false)
  end

  def changeset(entry, %Email{} = email, attrs) do
    entry
    |> cast(attrs, [:category, :ordering_key, :scope_key, :expires_at])
    |> validate_required([:category])
    |> validate_format(:category, ~r/\A[a-z][a-z0-9_.-]*\z/)
    |> validate_length(:category, max: 100)
    |> validate_length(:ordering_key, max: 255)
    |> validate_length(:scope_key, max: 255)
    |> put_email(email)
  end

  def to_email(%__MODULE__{email: %{"version" => 1} = email}) do
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
        provider_options: load_provider_options(Map.fetch!(email, "provider_options"))
      )

    case load_reply_to(Map.fetch!(email, "reply_to")) do
      nil -> persisted_email
      reply_to -> Email.reply_to(persisted_email, reply_to)
    end
  end

  defp put_email(changeset, %Email{} = email) do
    with :ok <- validate_delivery_fields(email),
         :ok <- validate_attachments(email.attachments),
         :ok <- validate_private(email.private),
         :ok <- validate_provider_options(email.provider_options) do
      put_change(changeset, :email, dump_email(email))
    else
      {:error, message} -> add_error(changeset, :email, message)
    end
  end

  defp validate_delivery_fields(%Email{to: to, cc: cc, bcc: bcc} = email)
       when is_list(to) and is_list(cc) and is_list(bcc) do
    recipients = email.to ++ email.cc ++ email.bcc

    cond do
      not is_binary(email.subject) or byte_size(email.subject) > @max_subject_bytes ->
        {:error, "requires a valid subject"}

      not valid_recipient?(email.from) ->
        {:error, "requires a valid sender"}

      recipients == [] or not Enum.all?(recipients, &valid_recipient?/1) ->
        {:error, "requires at least one valid recipient"}

      length(recipients) > @max_recipients ->
        {:error, "contains too many recipients"}

      not valid_reply_to?(email.reply_to) ->
        {:error, "contains an invalid reply-to address"}

      not is_map(email.headers) or
        map_size(email.headers) > @max_headers or
          not Enum.all?(email.headers, fn {name, value} ->
            is_binary(name) and byte_size(name) <= @max_header_name_bytes and
              is_binary(value) and byte_size(value) <= @max_header_value_bytes
          end) ->
        {:error, "contains invalid headers"}

      not valid_body?(email.text_body) or not valid_body?(email.html_body) ->
        {:error, "contains an invalid body"}

      is_nil(email.text_body) and is_nil(email.html_body) ->
        {:error, "requires a text or HTML body"}

      body_size(email.text_body) + body_size(email.html_body) > @max_body_bytes ->
        {:error, "body is too large"}

      true ->
        :ok
    end
  end

  defp validate_delivery_fields(_email), do: {:error, "contains invalid recipients"}

  defp valid_body?(nil), do: true
  defp valid_body?(body), do: is_binary(body)

  defp body_size(nil), do: 0
  defp body_size(body), do: byte_size(body)

  defp valid_recipient?({name, address}),
    do:
      is_binary(name) and byte_size(name) <= 320 and is_binary(address) and address != "" and
        byte_size(address) <= 320

  defp valid_recipient?(_recipient), do: false

  defp valid_reply_to?(nil), do: true

  defp valid_reply_to?(reply_to) when is_list(reply_to),
    do: length(reply_to) <= @max_recipients and Enum.all?(reply_to, &valid_recipient?/1)

  defp valid_reply_to?(reply_to), do: valid_recipient?(reply_to)

  defp validate_attachments([]), do: :ok
  defp validate_attachments(_attachments), do: {:error, "attachments are not supported"}

  defp validate_private(private) when is_map(private) do
    private =
      Map.drop(private, [
        :phoenix_layout,
        :phoenix_template,
        :phoenix_view
      ])

    if map_size(private) == 0,
      do: :ok,
      else: {:error, "contains unsupported private delivery options"}
  end

  defp validate_private(_private), do: {:error, "contains invalid private delivery options"}

  defp validate_provider_options(options)
       when options in [
              %{},
              %{click_tracking: %{enable: false}},
              %{click_tracking: %{enable: true}}
            ],
       do: :ok

  defp validate_provider_options(_options),
    do: {:error, "contains unsupported provider options"}

  defp dump_email(email) do
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
      "provider_options" => dump_provider_options(email.provider_options)
    }
  end

  defp dump_recipient({name, address}), do: %{"name" => name, "address" => address}
  defp dump_recipient(nil), do: nil

  defp dump_recipients(recipients), do: Enum.map(recipients, &dump_recipient/1)

  defp dump_reply_to(reply_to) when is_list(reply_to), do: dump_recipients(reply_to)
  defp dump_reply_to(reply_to), do: dump_recipient(reply_to)

  defp dump_provider_options(%{} = options) when map_size(options) == 0, do: %{}

  defp dump_provider_options(%{click_tracking: %{enable: enabled}}) do
    %{"click_tracking" => %{"enable" => enabled}}
  end

  defp load_recipient(%{"name" => name, "address" => address}), do: {name, address}
  defp load_recipient(nil), do: nil

  defp load_recipients(recipients), do: Enum.map(recipients, &load_recipient/1)

  defp load_reply_to(reply_to) when is_list(reply_to), do: load_recipients(reply_to)
  defp load_reply_to(reply_to), do: load_recipient(reply_to)

  defp load_provider_options(%{} = options) when map_size(options) == 0, do: %{}

  defp load_provider_options(%{"click_tracking" => %{"enable" => enabled}}) do
    %{click_tracking: %{enable: enabled}}
  end
end
