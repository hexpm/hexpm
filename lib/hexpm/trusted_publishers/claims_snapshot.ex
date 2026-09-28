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

  def repository_url(%__MODULE__{repository: repository}) when is_binary(repository),
    do: "#{@github}/#{repository}"

  def repository_url(%__MODULE__{}), do: nil

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

  def ref_name(%__MODULE__{ref: "refs/heads/" <> name}), do: name
  def ref_name(%__MODULE__{ref: "refs/tags/" <> name}), do: name
  def ref_name(%__MODULE__{ref: ref}), do: ref

  def ref_url(%__MODULE__{repository: repository, ref: "refs/" <> kind_and_name})
      when is_binary(repository) do
    case String.split(kind_and_name, "/", parts: 2) do
      [kind, name] when kind in ["heads", "tags"] ->
        "#{@github}/#{repository}/tree/#{URI.encode(name)}"

      _ ->
        nil
    end
  end

  def ref_url(%__MODULE__{}), do: nil

  def environment_url(%__MODULE__{repository: repository, environment: environment})
      when is_binary(repository) and is_binary(environment) do
    query = URI.encode_query(%{"environments_filter" => environment})
    "#{@github}/#{repository}/deployments/activity_log?#{query}"
  end

  def environment_url(%__MODULE__{}), do: nil

  def actor_url(%__MODULE__{actor: actor}) when is_binary(actor), do: "#{@github}/#{actor}"
  def actor_url(%__MODULE__{}), do: nil

  def run_url(%__MODULE__{repository: repository, run_id: run_id, run_attempt: run_attempt})
      when is_binary(repository) and is_binary(run_id) and is_binary(run_attempt),
      do: "#{@github}/#{repository}/actions/runs/#{run_id}/attempts/#{run_attempt}"

  def run_url(%__MODULE__{}), do: nil
end
