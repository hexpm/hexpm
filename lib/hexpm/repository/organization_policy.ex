defmodule Hexpm.Repository.OrganizationPolicy do
  use Hexpm.Schema

  alias Hexpm.Repository.OrganizationPolicy.RepositoryPolicy

  @valid_visibilities ~w(public private)
  @name_format ~r/^[a-z0-9][a-z0-9_\-\.]*[a-z0-9]$/

  # Names that would collide with the policy sub-routes under
  # `/policies/:name` (see `HexpmWeb.Router`).
  @reserved_names ~w(new package-suggestions version-suggestions)

  @retirement_reasons %{
    0 => "other",
    1 => "invalid",
    2 => "security",
    3 => "deprecated",
    4 => "renamed"
  }

  @severity_names ~w(none low medium high critical)

  @doc "Map of retirement reason integer -> wire-format name."
  def retirement_reasons, do: @retirement_reasons

  @doc "List of severity names indexed by their integer value (0..4)."
  def severity_names, do: @severity_names

  schema "organization_policies" do
    field :name, :string
    field :description, :string
    field :visibility, :string

    embeds_many :repositories, RepositoryPolicy, on_replace: :delete

    belongs_to :organization, Hexpm.Accounts.Organization

    timestamps()
  end

  @doc false
  def changeset(policy, attrs) do
    policy
    |> cast(attrs, castable_fields(policy))
    |> cast_embed(:repositories)
    |> validate_required([:name, :visibility])
    |> validate_length(:name, min: 3, max: 64)
    |> validate_format(:name, @name_format)
    |> validate_exclusion(:name, @reserved_names)
    |> validate_length(:description, max: 500)
    |> validate_inclusion(:visibility, @valid_visibilities)
    |> unique_constraint([:organization_id, :name])
    |> check_constraint(:visibility, name: :visibility_must_be_known)
  end

  # The name is the key of the policy's signed bucket object, so it is fixed at
  # creation and cannot be changed afterwards; an existing policy only casts the
  # fields that are safe to edit in place.
  defp castable_fields(%__MODULE__{id: nil}), do: [:name, :description, :visibility]
  defp castable_fields(%__MODULE__{}), do: [:description, :visibility]
end
