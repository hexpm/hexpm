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

  @doc """
  Checks if a device code is expired.
  """
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Checks if a device code is still pending authorization.
  """
  def pending?(%__MODULE__{status: "pending"} = device_code) do
    not expired?(device_code)
  end

  def pending?(_), do: false

  @doc """
  Checks if a device code has been authorized.
  """
  def authorized?(%__MODULE__{status: "authorized"}), do: true
  def authorized?(_), do: false

  @doc """
  Checks if a device code has been denied.
  """
  def denied?(%__MODULE__{status: "denied"}), do: true
  def denied?(_), do: false

  @doc """
  Generates a random device code.
  """
  def generate_device_code do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
    |> String.slice(0, 32)
  end

  @doc """
  Generates a human-readable user code.

  Per RFC 8628, user codes should be short and easy for users to enter.
  Uses a character set without ambiguous characters (excludes 0, 1, I, O).
  Returns 8 characters without formatting - UI formatting should be handled at presentation layer.
  """
  def generate_user_code do
    # Character set excludes ambiguous characters (0, 1, I, O) and vowels (A, E, U) to avoid forming words
    charset = "23456789BCDFGHJKLMNPQRSTVWXYZ"
    charset_size = String.length(charset)

    # Generate 8 random characters using cryptographically secure randomness with uniform distribution
    # Use 4 bytes of entropy per character to eliminate bias (2^32 >> 29)
    1..8
    |> Enum.map(fn _ ->
      <<random_int::unsigned-32>> = :crypto.strong_rand_bytes(4)
      index = rem(random_int, charset_size)
      String.at(charset, index)
    end)
    |> Enum.join()
  end
end
