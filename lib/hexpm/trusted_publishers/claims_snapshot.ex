defmodule Hexpm.TrustedPublishers.ClaimsSnapshot do
  use Hexpm.Schema

  embedded_schema do
    field :repository, :string
    field :repository_id, :string
    field :repository_owner, :string
    field :repository_owner_id, :string
    field :workflow_ref, :string
    field :job_workflow_ref, :string
    field :environment, :string
    field :sha, :string
    field :ref, :string
    field :ref_type, :string
    field :run_id, :string
    field :run_number, :string
    field :run_attempt, :string
    field :actor, :string
    field :actor_id, :string
    field :event_name, :string
  end

  @fields ~w(repository repository_id repository_owner repository_owner_id workflow_ref job_workflow_ref environment sha ref ref_type run_id run_number run_attempt actor actor_id event_name)a

  def changeset(snapshot, params) do
    cast(snapshot, params, @fields)
  end
end
