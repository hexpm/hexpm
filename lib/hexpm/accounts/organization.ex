defmodule Hexpm.Accounts.Organization do
  use HexpmWeb, :schema

  @derive HexpmWeb.Stale
  @derive {Phoenix.Param, key: :name}

  schema "organizations" do
    field :name, :string
    field :billing_active, :boolean, default: false
    timestamps()

    has_one :repository, Repository
    has_many :organization_users, OrganizationUser
    has_many :users, through: [:organization_users, :user]
    has_many :keys, Key
    has_many :audit_logs, AuditLog, foreign_key: :organization_id
  end

  @name_regex ~r"^[a-z0-9_\-\.]+$"
  @roles ~w(admin write read)

  @reserved_names ~w(www staging elixir erlang otp rebar rebar3 nerves phoenix acme)

  def changeset(struct, params) do
    cast(struct, params, ~w(name)a)
    |> validate_required(~w(name)a)
    |> unique_constraint(:name)
    |> update_change(:name, &String.downcase/1)
    |> validate_length(:name, min: 3)
    |> validate_format(:name, @name_regex)
    |> validate_exclusion(:name, @reserved_names)
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

  def has_access(organization, user, role) do
    from(
      ro in OrganizationUser,
      where: ro.organization_id == ^organization.id,
      where: ro.user_id == ^user.id,
      where: ro.role in ^role_or_higher(role),
      select: count(ro.id) >= 1
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

  def verify_permissions(%Organization{name: name} = organization, "repository", name) do
    {:ok, organization}
  end

  def verify_permissions(%Organization{}, _domain, _resource) do
    :error
  end
end
