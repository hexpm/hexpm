defmodule Hexpm.Repository.Owners do
  use Hexpm.Web, :context

  def all(package, preload \\ []) do
    from(u in assoc(package, :owners), preload: ^preload)
    |> Repo.all()
  end

  def add(package, owner, audit: audit_data) do
    repository = package.repository

    if repository.public or Repositories.access?(repository, owner, "read") do
      multi =
        Multi.new()
        |> Multi.insert(
          :owner,
          Package.build_owner(package, owner),
          on_conflict: :nothing,
          conflict_target: [:package_id, :owner_id]
        )
        |> audit(audit_data, "owner.add", {package, owner})

      case Repo.transaction(multi) do
        {:ok, _} ->
          owners = package |> all([:emails])
          owner = Enum.find(owners, &(&1.id == owner.id))
          Emails.owner_added(package, owners, owner) |> Mailer.deliver_now_throttled()
          :ok

        {:error, :owner, changeset, _} ->
          {:error, changeset}
      end
    else
      {:error, :not_member}
    end
  end

  def remove(package, owner, audit: audit_data) do
    owners = all(package, [:emails])
    owner = Enum.find(owners, &(&1.id == owner.id))

    cond do
      !owner ->
        {:error, :not_owner}

      length(owners) == 1 and package.repository.public ->
        {:error, :last_owner}

      true ->
        multi =
          Multi.new()
          |> Multi.delete_all(:package_owner, Package.owner(package, owner))
          |> audit(audit_data, "owner.remove", {package, owner})

        {:ok, _} = Repo.transaction(multi)
        owner = Enum.find(owners, &(&1.id == owner.id))

        Emails.owner_removed(package, owners, owner)
        |> Mailer.deliver_now_throttled()

        :ok
    end
  end
end
