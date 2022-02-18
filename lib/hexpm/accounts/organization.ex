defmodule Hexpm.Accounts.Organization do
  use Hexpm.Schema

  @derive HexpmWeb.Stale
  @derive {Phoenix.Param, key: :name}
  @month_seconds 31 * 24 * 60 * 60

  schema "organizations" do
    field :name, :string
    field :billing_active, :boolean, default: false
    field :trial_end, :utc_datetime_usec
    timestamps()

    has_one :repository, Repository
    has_one :user, User
    has_many :organization_users, OrganizationUser
    has_many :users, through: [:organization_users, :user]
    has_many :keys, Key
    has_many :audit_logs, AuditLog, foreign_key: :organization_id
  end

  @name_regex ~r"^[a-z0-9_\-\.]+$"
  @roles ~w(admin write read)

  @reserved_names ~w(www staging elixir erlang otp rebar rebar3 phoenix acme)

  def changeset(struct, params) do
    cast(struct, params, ~w(name)a)
    |> put_change(:trial_end, default_trial_end())
    |> validate_required(~w(name)a)
    |> unique_constraint(:name)
    |> update_change(:name, &String.downcase/1)
    |> validate_length(:name, min: 3)
    |> validate_format(:name, @name_regex)
    |> validate_exclusion(:name, @reserved_names)
  end

  def build_from_user(user) do
    changeset(%Organization{}, %{name: user.username})
  end

  def add_member(struct, params) do
    cast(struct, params, ~w(role)a)
    |> validate_required(~w(role)a)
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(
      :user_id,
      name: "organization_users_organization_id_user_id_index",
      message: "is already member"
    )
  end

  def change_role(struct, params) do
    cast(struct, params, ~w(role)a)
    |> validate_required(~w(role)a)
    |> validate_inclusion(:role, @roles)
  end

  def access(organization, user, role) do
    from(
      ou in OrganizationUser,
      where: ou.organization_id == ^organization.id,
      where: ou.user_id == ^user.id,
      where: ou.role in ^role_or_higher(role),
      select: count(ou.id) >= 1
    )
  end

  def role_or_higher("read"), do: ["read", "write", "admin"]
  def role_or_higher("write"), do: ["write", "admin"]
  def role_or_higher("admin"), do: ["admin"]

  def hexpm(opts \\ []) do
    repository =
      if Keyword.get(opts, :recursive, true) do
        Repository.hexpm(recursive: false)
      else
        %Ecto.Association.NotLoaded{}
      end

    %__MODULE__{
      id: 1,
      name: "hexpm",
      billing_active: true,
      repository: repository
    }
  end

  def verify_permissions(%Organization{}, "api", _resource) do
    {:ok, nil}
  end

  def verify_permissions(%Organization{name: name} = organization, domain, name)
      when domain in ["repository", "docs"] do
    {:ok, organization}
  end

  def verify_permissions(%Organization{}, _domain, _resource) do
    :error
  end

  def billing_active?(%Organization{billing_active: active} = organization) do
    active or trialing?(organization)
  end

  def trialing?(%Organization{trial_end: trial_end}) do
    DateTime.compare(trial_end, DateTime.utc_now()) == :gt
  end

  defp default_trial_end() do
    DateTime.utc_now()
    |> DateTime.add(@month_seconds)
    |> to_start_of_day()
  end

  defp to_start_of_day(%DateTime{} = datetime) do
    %DateTime{datetime | hour: 0, minute: 0, second: 0}
  end
end
