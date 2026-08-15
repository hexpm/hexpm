defmodule Hexpm.Emails.OutboxEntry do
  use Hexpm.Schema

  schema "email_outbox_entries" do
    field :category, :string
    field :group_key, :string
    field :scope_key, :string
    field :email, :map, redact: true
    field :expires_at, :utc_datetime_usec

    timestamps(updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:category, :group_key, :scope_key, :email, :expires_at])
    |> validate_required([:category, :email])
    |> validate_format(:category, ~r/\A[a-z][a-z0-9_.-]*\z/)
    |> validate_length(:category, max: 100)
    |> validate_length(:group_key, max: 255)
    |> validate_length(:scope_key, max: 255)
  end
end
