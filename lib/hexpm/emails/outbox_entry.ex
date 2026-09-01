defmodule Hexpm.Emails.OutboxEntry do
  use Hexpm.Schema

  schema "email_outbox_entries" do
    field :category, :string
    field :group_key, :string
    field :scope_key, :string
    field :recipients, {:array, :string}, redact: true
    field :subject, :string
    field :email, :map, redact: true
    field :expires_at, :utc_datetime_usec
    field :priority, :integer, default: 0
    field :delivered_at, :utc_datetime_usec
    field :provider_message_id, :string

    timestamps(updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :category,
      :group_key,
      :scope_key,
      :recipients,
      :subject,
      :email,
      :expires_at,
      :priority
    ])
    |> validate_required([:category, :email])
    |> validate_inclusion(:priority, 0..9)
    |> validate_format(:category, ~r/\A[a-z][a-z0-9_.-]*\z/)
    |> validate_length(:category, max: 100)
    |> validate_length(:group_key, max: 255)
    |> validate_length(:scope_key, max: 255)
  end

  # A delivered entry stays as the record of what was sent until the purge job
  # archives it, so everything that means "waiting to be sent" starts here.
  def undelivered(query \\ __MODULE__) do
    from(entry in query, where: is_nil(entry.delivered_at))
  end
end
