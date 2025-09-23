defmodule Hexpm.OAuth.DeviceCode do
  use Hexpm.Schema

  @derive {Phoenix.Param, key: :user_code}

  # Use default integer primary key to match existing schema pattern

  schema "device_codes" do
    field :device_code, :string
    field :user_code, :string
    field :verification_uri, :string
    field :verification_uri_complete, :string
    field :expires_at, :utc_datetime_usec
    field :interval, :integer, default: 5
    field :status, :string, default: "pending"
    field :scopes, {:array, :string}, default: []
    field :name, :string

    belongs_to :user, User

    belongs_to :client, Hexpm.OAuth.Client, references: :client_id, type: :binary_id

    timestamps()
  end

  # Valid statuses for device authorization flow:
  # - "pending": Waiting for user authorization
  # - "authorized": User has authorized the device
  # - "expired": Device code has expired
  # - "denied": User has denied authorization
  @valid_statuses ~w(pending authorized expired denied)

  @doc """
  Creates a changeset for device code creation.
  """
  def changeset(device_code, attrs) do
    device_code
    |> cast(attrs, [
      :device_code,
      :user_code,
      :verification_uri,
      :verification_uri_complete,
      :client_id,
      :expires_at,
      :interval,
      :scopes,
      :name
    ])
    |> validate_required([
      :device_code,
      :user_code,
      :verification_uri,
      :client_id,
      :expires_at
    ])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:interval, greater_than: 0)
    |> unique_constraint(:device_code)
    |> unique_constraint(:user_code)
  end

  @doc """
  Creates a changeset for authorizing a device code.
  """
  def authorize_changeset(device_code, user) do
    device_code
    |> change()
    |> put_change(:status, "authorized")
    |> put_change(:user_id, user.id)
  end

  @doc """
  Creates a changeset for denying a device code.
  """
  def deny_changeset(device_code) do
    device_code
    |> change()
    |> put_change(:status, "denied")
  end

  @doc """
  Creates a changeset for expiring a device code.
  """
  def expire_changeset(device_code) do
    device_code
    |> change()
    |> put_change(:status, "expired")
  end

end
