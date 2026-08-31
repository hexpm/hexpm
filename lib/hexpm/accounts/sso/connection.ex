defmodule Hexpm.Accounts.SSO.Connection do
  use Hexpm.Schema

  @type t :: %__MODULE__{}

  schema "organization_sso_connections" do
    field :issuer, :string
    field :client_id, :string
    field :client_secret, :string, redact: true
    field :pending_client_secret, :string, redact: true
    field :discovery_document, :map
    field :jwks_document, :map
    field :discovery_expires_at, :utc_datetime_usec
    field :jwks_expires_at, :utc_datetime_usec
    field :metadata_expires_at, :utc_datetime_usec
    field :version, :integer, default: 1
    field :pending_client_secret_version, :integer
    field :tested_at, :utc_datetime_usec
    field :pending_client_secret_tested_at, :utc_datetime_usec
    field :enabled_at, :utc_datetime_usec
    field :jit_seat_policy, :string
    field :jit_role, :string, default: "read"
    field :enforcement_mode, :string, default: "optional"
    field :required_at, :utc_datetime_usec
    field :session_lifetime_seconds, :integer, default: 86_400
    field :personal_keys, :string
    field :scim_token_first, :string, redact: true
    field :scim_token_second, :string, redact: true
    field :scim_token, :string, virtual: true, redact: true
    field :scim_seat_policy, :string
    field :scim_role, :string, default: "read"

    belongs_to :organization, Organization
    belongs_to :configured_by_user, User
    has_many :identities, Hexpm.Accounts.SSO.Identity
    has_many :transactions, Hexpm.Accounts.SSO.Transaction
    has_many :failures, Hexpm.Accounts.SSO.Failure

    timestamps()
  end

  def credentials_changeset(connection, attrs) do
    connection
    |> cast(attrs, [:organization_id, :issuer, :client_id, :client_secret])
    |> validate_required([:organization_id, :issuer, :client_id, :client_secret])
    |> validate_length(:issuer, max: 2_048)
    |> validate_length(:client_id, max: 1_024)
    |> validate_length(:client_secret, max: 4_096)
  end

  def configuration_changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :organization_id,
      :issuer,
      :client_id,
      :client_secret,
      :discovery_document,
      :jwks_document,
      :discovery_expires_at,
      :jwks_expires_at,
      :metadata_expires_at,
      :configured_by_user_id,
      :version,
      :pending_client_secret_version,
      :tested_at,
      :pending_client_secret,
      :pending_client_secret_tested_at,
      :enabled_at
    ])
    |> validate_required([
      :organization_id,
      :issuer,
      :client_id,
      :client_secret,
      :discovery_document,
      :jwks_document,
      :discovery_expires_at,
      :jwks_expires_at,
      :metadata_expires_at,
      :version
    ])
    |> validate_length(:issuer, max: 2_048)
    |> validate_length(:client_id, max: 1_024)
    |> validate_length(:client_secret, max: 4_096)
    |> unique_constraint(:organization_id)
  end

  def rotation_changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :pending_client_secret,
      :pending_client_secret_version,
      :pending_client_secret_tested_at
    ])
    |> validate_required([:pending_client_secret])
    |> validate_length(:pending_client_secret, max: 4_096)
  end

  @jit_seat_policies ~w(block expand)
  @jit_roles ~w(admin write read)

  @doc """
  Turns just-in-time membership on or off. `jit_seat_policy` is required to turn
  it on and there is no default, because auto-expanding a subscription is a
  billing change and nobody should get it without having asked for it.
  """
  def jit_changeset(connection, attrs) do
    connection
    |> cast(attrs, [:jit_seat_policy, :jit_role])
    |> update_change(:jit_seat_policy, &nilify_blank/1)
    |> validate_required([:jit_role])
    |> validate_inclusion(:jit_seat_policy, @jit_seat_policies)
    |> validate_inclusion(:jit_role, @jit_roles)
  end

  @enforcement_modes ~w(optional pilot required)
  @personal_key_policies ~w(block allow)
  @session_lifetimes [3_600, 28_800, 86_400, 604_800, 2_592_000]

  @doc """
  Sets the enforcement mode, when required mode starts biting, how long an
  organization access session lasts, and what happens to personal API keys.

  `personal_keys` defaults to allowing them. Blocking breaks publishing
  workflows that only the organization can weigh, and SCIM will close the
  offboarding half of what blocking is for.
  """
  def enforcement_changeset(connection, attrs) do
    connection
    |> cast(normalize_required_at(attrs), [
      :enforcement_mode,
      :required_at,
      :session_lifetime_seconds,
      :personal_keys
    ])
    |> update_change(:personal_keys, &nilify_blank/1)
    |> validate_required([:enforcement_mode, :session_lifetime_seconds])
    |> validate_inclusion(:enforcement_mode, @enforcement_modes)
    |> validate_inclusion(:personal_keys, @personal_key_policies)
    |> validate_inclusion(:session_lifetime_seconds, @session_lifetimes)
    |> validate_required_at()
  end

  # The form offers a date, which is what an administrator picks, and the column
  # holds an instant. An empty box means "as soon as this is saved".
  defp normalize_required_at(%{"required_at" => value} = attrs) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> Map.put(attrs, "required_at", DateTime.new!(date, ~T[00:00:00], "Etc/UTC"))
      {:error, _reason} -> attrs
    end
  end

  defp normalize_required_at(attrs), do: attrs

  defp validate_required_at(changeset) do
    mode = get_field(changeset, :enforcement_mode)
    required_at = get_field(changeset, :required_at)
    now = DateTime.utc_now()

    cond do
      mode == "required" and is_nil(required_at) ->
        put_change(changeset, :required_at, now)

      mode != "required" and not is_nil(required_at) ->
        put_change(changeset, :required_at, nil)

      # A date already past means the same thing as an empty box, and storing it
      # as given would leave the screen showing a grace period that never
      # existed.
      mode == "required" and DateTime.compare(required_at, now) == :lt ->
        put_change(changeset, :required_at, now)

      true ->
        changeset
    end
  end

  @scim_seat_policies ~w(block expand)
  @scim_roles ~w(admin write read)

  @doc """
  The provisioning settings. `scim_seat_policy` is a forced choice while SCIM
  is on, for the reason `jit_seat_policy` is: provisioning claims seats, and
  auto-expanding a subscription is a billing change nobody should get without
  having asked for it. `scim_role` is separate from `jit_role` because either
  feature runs without the other, and a setting labeled for one silently
  governing the other is a support ticket waiting to happen.
  """
  def scim_changeset(connection, attrs) do
    changeset =
      connection
      |> cast(attrs, [:scim_seat_policy, :scim_role])
      |> update_change(:scim_seat_policy, &nilify_blank/1)
      |> validate_required([:scim_role])
      |> validate_inclusion(:scim_seat_policy, @scim_seat_policies)
      |> validate_inclusion(:scim_role, @scim_roles)

    if scim_enabled?(connection) do
      validate_required(changeset, [:scim_seat_policy])
    else
      changeset
    end
  end

  @doc """
  Turns provisioning on, or replaces the bearer token of a connection that
  already has one. The plaintext lands in the virtual `scim_token` for the one
  screen that shows it; only the split hash is stored.
  """
  def scim_generate_changeset(connection, attrs) do
    {token, first, second} = Hexpm.Accounts.Key.gen_key()

    connection
    |> scim_changeset(attrs)
    |> validate_required([:scim_seat_policy])
    |> put_change(:scim_token_first, first)
    |> put_change(:scim_token_second, second)
    |> put_change(:scim_token, token)
  end

  def scim_delete_changeset(connection) do
    change(connection, scim_token_first: nil, scim_token_second: nil)
  end

  def scim_enabled?(%__MODULE__{scim_token_first: first}), do: not is_nil(first)

  def enabled?(%__MODULE__{enabled_at: enabled_at}), do: not is_nil(enabled_at)

  def jit_enabled?(%__MODULE__{jit_seat_policy: policy}), do: policy in @jit_seat_policies

  @doc """
  The mode in force now. A required organization with a future `required_at` is
  still in its grace period, so it enforces the members it would have enforced
  in pilot and nobody else.
  """
  def enforcement_mode(connection, now \\ DateTime.utc_now())

  def enforcement_mode(%__MODULE__{enforcement_mode: "required", required_at: required_at}, now)
      when not is_nil(required_at) do
    if DateTime.compare(now, required_at) == :lt, do: "pilot", else: "required"
  end

  def enforcement_mode(%__MODULE__{enforcement_mode: mode}, _now), do: mode

  @doc """
  Whether this organization turns personal API keys away. Which members that
  applies to is their own enforcement to decide, so a pilot turns them away for
  the members it pilots and for nobody else.
  """
  def blocks_personal_keys?(%__MODULE__{personal_keys: "block"} = connection) do
    enforcement_mode(connection) in ["pilot", "required"]
  end

  def blocks_personal_keys?(%__MODULE__{}), do: false

  def blocks_personal_keys?(nil), do: false
end
