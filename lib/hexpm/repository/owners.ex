defmodule Hexpm.Repository.Owners do
  use Hexpm.Context

  alias Hexpm.Accounts.OptionalEmails

  def all(package, preload \\ []) do
    from(owner in assoc(package, :package_owners),
      join: user in assoc(owner, :user),
      order_by: user.username
    )
    |> Repo.all()
    |> Repo.preload(preload)
  end

  def get(package, user) do
    if owner = Repo.get_by(PackageOwner, package_id: package.id, user_id: user.id) do
      %{owner | package: package, user: user}
    end
  end

  @doc """
  Whether `user` appears in `owners` with `level: "full"`. Safe to call with a
  nil user (returns false) and an empty owners list. `owners` is the
  already-loaded list from `Owners.all/2`.
  """
  def full_owner?(_owners, nil), do: false

  def full_owner?(owners, %User{id: user_id}) do
    Enum.any?(owners, &(&1.user_id == user_id && &1.level == "full"))
  end

  def add(package, user, params, audit: audit_data) do
    repository = package.repository
    repository_access = Organizations.access?(repository.organization, user, "read")

    cond do
      repository.id != 1 and not repository_access ->
        {:error, :not_member}

      not User.organization?(user) and not User.verified_primary_email?(user) ->
        {:error, :unverified_primary_email}

      User.organization?(user) and Map.get(params, "transfer", false) != true ->
        {:error, :not_organization_transfer}

      User.organization?(user) and Map.get(params, "level", "full") != "full" ->
        {:error, :organization_level}

      not User.organization?(user) && Organizations.get(user.username) ->
        {:error, :organization_user_conflict}

      true ->
        add_owner(package, user, params, audit_data)
    end
  end

  defp add_owner(package, user, params, audit_data) do
    new_level = Map.get(params, "level", "full")

    multi =
      Multi.new()
      |> Multi.run(:owners, fn _repo, _changes ->
        {:ok, lock_owners(package, user: [:emails, :organization])}
      end)
      |> Multi.run(:existing, fn _repo, %{owners: owners} ->
        owner = Enum.find(owners, &(&1.user_id == user.id))

        # Prevent demoting the last full owner via an upsert (e.g. from the API).
        if owner && owner.level == "full" && new_level != "full" && last_full_owner?(owners),
          do: {:error, :last_full_owner},
          else: {:ok, owner}
      end)
      |> Multi.insert_or_update(:owner, fn %{existing: owner} ->
        owner = owner || %PackageOwner{package_id: package.id, user_id: user.id}
        PackageOwner.changeset(owner, params)
      end)
      |> remove_existing_owners(params)
      |> audit(audit_data, add_owner_audit_log_action(params), fn %{owner: owner} ->
        {package, owner.level, user}
      end)

    case Repo.transaction(multi) do
      {:ok, %{owner: owner, owners: owners}} ->
        owners =
          owners
          |> Enum.map(& &1.user)
          |> Kernel.++([user])
          |> Repo.preload(organization: [organization_users: [user: :emails]])
          |> Enum.filter(&OptionalEmails.allowed?(&1, :owner_added_to_package))

        if owners != [] do
          Emails.owner_added(package, owners, user)
          |> Mailer.deliver!()
        end

        {:ok, %{owner | user: user}}

      {:error, :existing, reason, _} ->
        {:error, reason}

      {:error, :owner, changeset, _} ->
        {:error, changeset}
    end
  end

  defp add_owner_audit_log_action(%{"transfer" => true}), do: "owner.transfer"
  defp add_owner_audit_log_action(_params), do: "owner.add"

  defp remove_existing_owners(multi, %{"transfer" => true}) do
    Multi.run(multi, :removed_owners, fn repo, %{owner: owner, owners: owners} ->
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

  defp remove_existing_owners(multi, _params) do
    multi
  end

  def update_level(package, user, level, audit: audit_data) do
    multi =
      Multi.new()
      |> Multi.run(:existing, fn _repo, _changes ->
        owners = lock_owners(package, user: [:emails, :organization])
        owner = Enum.find(owners, &(&1.user_id == user.id))

        cond do
          !owner ->
            {:error, :not_owner}

          owner.level == "full" and level != "full" and last_full_owner?(owners) ->
            {:error, :last_full_owner}

          true ->
            {:ok, owner}
        end
      end)
      |> Multi.update(:owner, fn %{existing: owner} ->
        PackageOwner.changeset(owner, %{"level" => level})
      end)
      |> audit(audit_data, "owner.update", fn %{owner: owner} ->
        {package, owner.level, user}
      end)

    case Repo.transaction(multi) do
      {:ok, %{owner: owner}} -> {:ok, %{owner | user: user}}
      {:error, :existing, reason, _} -> {:error, reason}
      {:error, :owner, changeset, _} -> {:error, changeset}
    end
  end

  def remove(package, user, audit: audit_data) do
    multi =
      Multi.new()
      |> Multi.run(:owners, fn _repo, _changes -> {:ok, lock_owners(package, user: :emails)} end)
      |> Multi.run(:owner, fn _repo, %{owners: owners} ->
        owner = Enum.find(owners, &(&1.user_id == user.id))

        cond do
          !owner ->
            {:error, :not_owner}

          # Only enforced for the public hexpm repository; private org repos
          # can intentionally orphan a package (e.g. when dissolving an org).
          length(owners) == 1 and package.repository.id == 1 ->
            {:error, :last_owner}

          owner.level == "full" and last_full_owner?(owners) and package.repository.id == 1 ->
            {:error, :last_full_owner}

          true ->
            {:ok, owner}
        end
      end)
      |> Multi.delete(:removed, fn %{owner: owner} -> owner end)
      |> audit(audit_data, "owner.remove", fn %{owner: owner} ->
        {package, owner.level, owner.user}
      end)

    case Repo.transaction(multi) do
      {:ok, %{owners: owners, owner: owner}} ->
        owners =
          owners
          |> Enum.map(& &1.user)
          |> Repo.preload(organization: [users: :emails])
          |> Enum.filter(&OptionalEmails.allowed?(&1, :owner_removed_from_package))

        if owners != [] do
          Emails.owner_removed(package, owners, owner.user)
          |> Mailer.deliver!()
        end

        :ok

      {:error, :owner, reason, _} ->
        {:error, reason}
    end
  end

  # Owner changes to one package take the package row lock first, so each
  # change reads the owners the previous one left and the last-owner checks
  # can't pass for two changes at once.
  defp lock_owners(package, preload) do
    Repo.one!(from(p in Package, where: p.id == ^package.id, lock: "FOR NO KEY UPDATE"))
    all(package, preload)
  end

  defp last_full_owner?(owners), do: Enum.count(owners, &(&1.level == "full")) == 1
end
