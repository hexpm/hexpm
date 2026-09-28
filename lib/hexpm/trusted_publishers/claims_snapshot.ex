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

  @github "https://github.com"

  def commit_url(%__MODULE__{repository: repository, sha: sha})
      when is_binary(repository) and is_binary(sha),
      do: "#{@github}/#{repository}/commit/#{sha}"

  def commit_url(%__MODULE__{}), do: nil

  def workflow_path(%__MODULE__{repository: repository, workflow_ref: workflow_ref})
      when is_binary(repository) and is_binary(workflow_ref) do
    [path | _ref] = String.split(workflow_ref, "@", parts: 2)
    String.replace_prefix(path, repository <> "/", "")
  end

  def workflow_path(%__MODULE__{}), do: nil

  def workflow_url(%__MODULE__{repository: repository, sha: sha} = snapshot)
      when is_binary(repository) and is_binary(sha) do
    case workflow_path(snapshot) do
      nil -> nil
      path -> "#{@github}/#{repository}/blob/#{sha}/#{path}"
    end
  end

  def workflow_url(%__MODULE__{}), do: nil

  def run_url(%__MODULE__{repository: repository, run_id: run_id, run_attempt: run_attempt})
      when is_binary(repository) and is_binary(run_id) and is_binary(run_attempt),
      do: "#{@github}/#{repository}/actions/runs/#{run_id}/attempts/#{run_attempt}"

  def run_url(%__MODULE__{}), do: nil
end
