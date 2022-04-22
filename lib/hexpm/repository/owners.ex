defmodule Hexpm.Repository.Owners do
  use Hexpm.Context

  def all(package, preload \\ []) do
    assoc(package, :package_owners)
    |> Repo.all()
    |> Repo.preload(preload)
  end

  def get(package, user) do
    if owner = Repo.get_by(PackageOwner, package_id: package.id, user_id: user.id) do
      %{owner | package: package, user: user}
    end
  end

  def add(package, user, params, audit: audit_data) do
    repository = package.repository
    owners = all(package, user: [:emails, :organization])
    organization_owner = Enum.find(owners, &User.organization?(&1.user))
    repository_access = Organizations.access?(repository.organization, user, "read")
    owner_organization = organization_owner && organization_owner.user.organization

    organization_access =
      owner_organization && Organizations.access?(owner_organization, user, "read")

    cond do
      repository.id != 1 && !repository_access ->
        {:error, :not_member}

      # Outside collaborators are not allowed at this time
      owner_organization && !organization_access ->
        {:error, :not_member}

      User.organization?(user) && Map.get(params, "transfer", false) != true ->
        {:error, :not_organization_transfer}

      User.organization?(user) && Map.get(params, "level", "full") != "full" ->
        {:error, :organization_level}

      !User.organization?(user) && Organizations.get(user.username) ->
        {:error, :organization_user_conflict}

      true ->
        add_owner(package, owners, user, params, audit_data)
    end
  end

  defp add_owner(package, owners, user, params, audit_data) do
    owner = Enum.find(owners, &(&1.user_id == user.id))
    owner = owner || %PackageOwner{package_id: package.id, user_id: user.id}
    changeset = PackageOwner.changeset(owner, params)

    multi =
      Multi.new()
      |> Multi.insert_or_update(:owner, changeset)
      |> remove_existing_owners(owners, params)
      |> audit(audit_data, add_owner_audit_log_action(params), fn %{owner: owner} ->
        {package, owner.level, user}
      end)

    case Repo.transaction(multi) do
      {:ok, %{owner: owner}} ->
        # TODO: Separate email for the affected person
        owners =
          owners
          |> Enum.map(& &1.user)
          |> Kernel.++([user])
          |> Repo.preload(organization: [organization_users: [user: :emails]])

        Emails.owner_added(package, owners, user)
        |> Mailer.deliver_later!()

        {:ok, %{owner | user: user}}

      {:error, :owner, changeset, _} ->
        {:error, changeset}
    end
  end

  defp add_owner_audit_log_action(%{"transfer" => true}), do: "owner.transfer"
  defp add_owner_audit_log_action(_params), do: "owner.add"

  defp remove_existing_owners(multi, owners, %{"transfer" => true}) do
    Multi.run(multi, :removed_owners, fn repo, %{owner: owner} ->
      owner_ids =
        owners
        |> Enum.filter(&(&1.id != owner.id))
        |> Enum.map(& &1.id)

      {num_rows, _} =
        from(po in PackageOwner, where: po.id in ^owner_ids)
        |> repo.delete_all()

      {:ok, num_rows}
    end)
  end

  defp remove_existing_owners(multi, _owners, _params) do
    multi
  end

  def remove(package, user, audit: audit_data) do
    owners = all(package, user: :emails)
    owner = Enum.find(owners, &(&1.user_id == user.id))

    cond do
      !owner ->
        {:error, :not_owner}

      length(owners) == 1 and package.repository.id == 1 ->
        {:error, :last_owner}

      true ->
        multi =
          Multi.new()
          |> Multi.delete(:owner, owner)
          |> audit(audit_data, "owner.remove", fn %{owner: owner} ->
            {package, owner.level, owner.user}
          end)

        {:ok, _} = Repo.transaction(multi)

        # TODO: Separate email for the affected person
        owners =
          owners
          |> Enum.map(& &1.user)
          |> Repo.preload(organization: [users: :emails])

        Emails.owner_removed(package, owners, owner.user)
        |> Mailer.deliver_later!()

        :ok
    end
  end
end
