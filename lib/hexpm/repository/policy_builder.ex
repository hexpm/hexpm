defmodule Hexpm.Repository.PolicyBuilder do
  @moduledoc """
  Encodes, signs, uploads, and Fastly-purges an `Policy`
  resource. Synchronous in-request (mirrors `RegistryBuilder.repository/1`).
  """

  alias Hexpm.Repository.{Policy, Storage}

  @doc """
  Builds the signed, gzipped Policy payload (no upload).

  The policy must be preloaded with `:organization`.
  """
  @spec build(Policy.t()) :: binary()
  def build(%Policy{} = policy) do
    policy
    |> to_protobuf_map()
    |> :hex_registry.encode_policy()
    |> Storage.sign_and_gzip()
  end

  @doc """
  Builds and uploads the policy to the repo bucket, then purges the
  Fastly surrogate key. Preloads `:organization` if needed.

  Concurrent rebuilds of the same policy are serialized via a Postgres
  advisory transaction lock scoped to the policy id, so two dashboard edits
  of one policy can't race on the bucket object while edits to different
  policies still run in parallel.
  """
  @spec rebuild(Policy.t()) :: :ok
  def rebuild(%Policy{} = policy) do
    policy = Hexpm.Repo.preload(policy, :organization)

    {:ok, :ok} =
      Hexpm.Repo.transaction(fn ->
        Hexpm.Repo.advisory_xact_lock(:policy, sub_key: policy.id)
        contents = build(policy)
        cdn_key = cdn_key(policy)
        Storage.put_object(store_key(policy), contents, [cdn_key], cache_control(policy))
        Storage.purge([cdn_key])
        :ok
      end)

    :ok
  end

  @doc """
  Deletes the bucket object and purges its CDN key. Used when a policy
  is deleted from the dashboard.
  """
  @spec delete(Policy.t()) :: :ok
  def delete(%Policy{} = policy) do
    policy = Hexpm.Repo.preload(policy, :organization)
    Storage.delete_object(store_key(policy))
    Storage.purge([cdn_key(policy)])
    :ok
  end

  defp to_protobuf_map(policy) do
    repositories =
      policy.repositories
      |> Enum.filter(&publish_repository?(&1, policy.visibility))
      |> Enum.map(&repository_to_protobuf/1)

    %{
      repository: policy.organization.name,
      name: policy.name,
      visibility: visibility_to_enum(policy.visibility),
      repositories: repositories
    }
    |> maybe_put(:description, policy.description)
  end

  # A public policy is fetchable by anyone, so it only publishes rules for the
  # public `hexpm` repository; a private policy publishes every tab.
  defp publish_repository?(_repository_policy, "private"), do: true

  defp publish_repository?(repository_policy, "public"),
    do: repository_policy.repository == "hexpm"

  defp repository_to_protobuf(repository_policy) do
    %{
      repository: repository_policy.repository,
      overrides: Enum.map(repository_policy.overrides, &override_to_protobuf/1)
    }
    |> maybe_put_restriction(repository_policy)
  end

  defp maybe_put_restriction(map, repository_policy) do
    restriction =
      %{}
      |> maybe_put(:advisory_min_severity, repository_policy.advisory_min_severity)
      |> maybe_put_reasons(repository_policy.retirement_reasons)
      |> maybe_put(:cooldown, repository_policy.cooldown)

    if restriction == %{}, do: map, else: Map.put(map, :restriction, restriction)
  end

  defp override_to_protobuf(override) do
    %{
      action: action_to_enum(override.action),
      ref: maybe_put(%{package: override.package}, :requirement, override.requirement)
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_reasons(map, nil), do: map
  defp maybe_put_reasons(map, []), do: map
  defp maybe_put_reasons(map, reasons), do: Map.put(map, :retirement_reasons, reasons)

  defp visibility_to_enum("public"), do: :VISIBILITY_PUBLIC
  defp visibility_to_enum("private"), do: :VISIBILITY_PRIVATE

  defp action_to_enum(:allow), do: :OVERRIDE_ACTION_ALLOW
  defp action_to_enum(:deny), do: :OVERRIDE_ACTION_DENY

  defp store_key(policy),
    do: "repos/#{policy.organization.name}/policies/#{policy.name}"

  defp cdn_key(policy),
    do: "policy/#{policy.organization.name}/#{policy.name}"

  defp cache_control(%{visibility: "public"}), do: "public, max-age=600"
  defp cache_control(%{visibility: "private"}), do: "private, max-age=60"
end
