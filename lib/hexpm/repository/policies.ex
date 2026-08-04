defmodule Hexpm.Repository.Policies do
  use Hexpm.Context
  import Ecto.Query

  alias Hexpm.Repository.Policy

  def all(organization) do
    Policy
    |> where([p], p.organization_id == ^organization.id)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  def get(organization, name) do
    Policy
    |> where([p], p.organization_id == ^organization.id and p.name == ^name)
    |> Repo.one()
  end

  def change(organization, %Policy{} = policy, params \\ %{}) do
    params = put_repositories(params, organization.name, policy.repositories)
    Policy.changeset(policy, params)
  end

  def create(organization, params, audit: audit_data) do
    params = put_repositories(params, organization.name, [])

    changeset =
      %Policy{organization_id: organization.id}
      |> Policy.changeset(params)

    Multi.new()
    |> Multi.insert(:policy, changeset)
    |> audit(audit_data, "policy.create", fn %{policy: policy} -> policy end)
    |> Repo.transaction()
    |> tap(&maybe_rebuild/1)
  end

  def update(%Policy{} = policy, params, audit: audit_data) do
    policy = Repo.preload(policy, :organization)
    params = put_repositories(params, policy.organization.name, policy.repositories)
    changeset = Policy.changeset(policy, params)

    Multi.new()
    |> Multi.update(:policy, changeset)
    |> audit(audit_data, "policy.update", fn %{policy: updated} -> updated end)
    |> Repo.transaction()
    |> tap(&maybe_rebuild/1)
  end

  # Every policy carries a tab for `hexpm` and one for the organization's own
  # repository. The org tab is only published for private policies (see
  # `PolicyBuilder`) but is always stored so toggling visibility keeps its
  # rules. The source is the submitted tabs, or the policy's existing tabs when
  # the caller did not resubmit them; tabs are matched by repository name so
  # their id and rules survive.
  defp put_repositories(params, org_name, existing) do
    source =
      case params["repositories"] do
        nil ->
          Enum.map(existing, &tab_to_params/1)

        repositories ->
          repositories |> submitted_repositories() |> Enum.map(&put_overrides/1)
      end

    by_repository = Map.new(source, &{&1["repository"], &1})

    repositories =
      Enum.map(["hexpm", org_name], fn repository ->
        Map.get(by_repository, repository, %{"repository" => repository})
      end)

    Map.put(params, "repositories", repositories)
  end

  defp put_overrides(repository) do
    Map.put(repository, "overrides", submitted_overrides(repository["overrides"]))
  end

  # A submitted tab carries its whole override list, and `cast_embed` reads a
  # missing key as unchanged, so no key at all means every row was removed.
  # Every rendered row submits its package, so an entry holding nothing but an
  # id is the leftover of a row the page removed and drops out with it.
  defp submitted_overrides(nil), do: []

  defp submitted_overrides(list) when is_list(list), do: Enum.filter(list, &override_row?/1)

  defp submitted_overrides(map) when is_map(map),
    do: Map.filter(map, fn {_index, override} -> override_row?(override) end)

  defp override_row?(override) when is_map(override), do: Map.has_key?(override, "package")
  defp override_row?(_override), do: false

  defp submitted_repositories(nil), do: []
  defp submitted_repositories(list) when is_list(list), do: list

  defp submitted_repositories(map) when is_map(map) do
    map |> Enum.sort_by(fn {key, _value} -> key end) |> Enum.map(fn {_key, value} -> value end)
  end

  defp tab_to_params(repository_policy) do
    %{
      "id" => repository_policy.id,
      "repository" => repository_policy.repository,
      "cooldown" => repository_policy.cooldown,
      "advisory_min_severity" => repository_policy.advisory_min_severity,
      "retirement_reasons" => repository_policy.retirement_reasons,
      "overrides" =>
        Enum.map(repository_policy.overrides, fn override ->
          %{
            "id" => override.id,
            "action" => override.action,
            "package" => override.package,
            "requirement" => override.requirement
          }
        end)
    }
  end

  def delete(%Policy{} = policy, audit: audit_data) do
    Multi.new()
    |> Multi.delete(:policy, policy)
    |> audit(audit_data, "policy.delete", policy)
    |> Repo.transaction()
    |> tap(&maybe_delete/1)
  end

  defp maybe_rebuild({:ok, %{policy: policy}}), do: Hexpm.Repository.PolicyBuilder.rebuild(policy)
  defp maybe_rebuild(_), do: :ok

  defp maybe_delete({:ok, %{policy: policy}}), do: Hexpm.Repository.PolicyBuilder.delete(policy)
  defp maybe_delete(_), do: :ok
end
