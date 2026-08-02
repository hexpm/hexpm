defmodule Hexpm.Accounts.OrganizationDomain do
  use Hexpm.Schema

  @type t :: %__MODULE__{}

  @record_prefix "hexpm-domain-verification="

  # A label is 1-63 characters and the whole name is at most 253. Leading and
  # trailing dots are rejected rather than trimmed, because an administrator who
  # typed one probably pasted something else too.
  @domain_regex ~r/^(?!-)[a-z0-9-]{1,63}(?<!-)(\.(?!-)[a-z0-9-]{1,63}(?<!-))+$/

  schema "organization_domains" do
    field :domain, :string
    field :verification_token, :string
    field :verified_at, :utc_datetime_usec
    field :last_checked_at, :utc_datetime_usec

    belongs_to :organization, Organization
    belongs_to :added_by_user, User

    timestamps()
  end

  def record_prefix, do: @record_prefix

  @doc """
  The exact TXT value an administrator has to publish. The token is
  per-organization, so publishing one organization's record does not verify the
  domain for anyone else.
  """
  def record_value(%__MODULE__{verification_token: token}), do: @record_prefix <> token

  def record_name(%__MODULE__{domain: domain}), do: domain

  def changeset(domain, attrs) do
    domain
    |> cast(attrs, [:organization_id, :added_by_user_id, :domain, :verification_token])
    |> validate_required([:organization_id, :domain, :verification_token])
    |> update_change(:domain, &normalize/1)
    |> validate_length(:domain, max: 253)
    |> validate_format(:domain, @domain_regex, message: "is not a valid domain name")
    |> unique_constraint(:domain,
      name: :organization_domains_organization_id_domain_index,
      message: "has already been added"
    )
  end

  def verified_changeset(domain, now) do
    change(domain, verified_at: now, last_checked_at: now)
  end

  def unverified_changeset(domain, now) do
    change(domain, verified_at: nil, last_checked_at: now)
  end

  def verified?(%__MODULE__{verified_at: nil}), do: false
  def verified?(%__MODULE__{}), do: true

  def normalize(domain) when is_binary(domain) do
    domain
    |> String.trim()
    |> String.downcase()
    |> String.trim_leading("*.")
  end

  @doc """
  The domain part of an email address, or nil when there is not exactly one.
  """
  def from_email(email) when is_binary(email) do
    case String.split(email, "@") do
      [_local, domain] when domain != "" -> normalize(domain)
      _other -> nil
    end
  end

  def from_email(_email), do: nil
end
