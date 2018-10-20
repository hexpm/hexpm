defmodule Hexpm.Repository.Owners do
  use HexpmWeb, :context

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
    organization = package.organization
    owners = all(package, user: :emails)
    owner = Enum.find(owners, &(&1.user_id == user.id))
    owner = owner || %PackageOwner{package_id: package.id, user_id: user.id}
    changeset = PackageOwner.changeset(owner, params)

    if organization.public or Organizations.access?(organization, user, "read") do
      multi =
        Multi.new()
        |> Multi.insert_or_update(:owner, changeset)
        |> audit(audit_data, "owner.add", fn %{owner: owner} ->
          {package, owner.level, user}
        end)

      case Repo.transaction(multi) do
        {:ok, %{owner: owner}} ->
          # TODO: Separate email for the affected person
          owners = Enum.map(owners, & &1.user)

          Emails.owner_added(package, [user | owners], user)
          |> Mailer.deliver_now_throttled()

          {:ok, %{owner | user: user}}

        {:error, :owner, changeset, _} ->
          {:error, changeset}
      end
    else
      {:error, :not_member}
    end
  end

  def remove(package, user, audit: audit_data) do
    owners = all(package, user: :emails)
    owner = Enum.find(owners, &(&1.user_id == user.id))

    cond do
      !owner ->
        {:error, :not_owner}

      length(owners) == 1 and package.organization.public ->
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
        owners = Enum.map(owners, & &1.user)

        Emails.owner_removed(package, owners, owner.user)
        |> Mailer.deliver_now_throttled()

        :ok
    end
  end
end
