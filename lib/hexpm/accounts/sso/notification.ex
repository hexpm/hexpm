defmodule Hexpm.Accounts.SSO.Notification do
  use Hexpm.Schema

  schema "organization_sso_notifications" do
    field :kind, :string
    field :organization_name, :string
    field :username, :string
    field :recipients, :map, redact: true
    field :provider_email, :string, redact: true

    belongs_to :connection, Hexpm.Accounts.SSO.Connection
    belongs_to :user, User

    timestamps(updated_at: false)
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :connection_id,
      :user_id,
      :kind,
      :organization_name,
      :username,
      :recipients,
      :provider_email
    ])
    |> validate_required([
      :connection_id,
      :user_id,
      :kind,
      :organization_name,
      :username,
      :recipients
    ])
    |> validate_inclusion(:kind, ~w(identity_linked identity_unlinked email_mismatch))
    |> validate_length(:provider_email, max: 320)
  end
end
