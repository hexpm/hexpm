defmodule Hexpm.Security.AdvisoryAffectedVersion do
  use Hexpm.Schema

  alias Hexpm.Repository.Package

  schema "security_advisory_affected_versions" do
    field :advisory_id, :string
    field :requirement, Hexpm.VersionRequirement
    belongs_to :package, Package
  end

  def changeset(affected_version, params) do
    affected_version
    |> cast(params, ~w(package_id requirement)a)
    |> validate_required(~w(package_id requirement)a)
    |> assoc_constraint(:package)
  end
end
