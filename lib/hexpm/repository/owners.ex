defmodule Hexpm.Repository.Owners do
  use Hexpm.Web, :context

  def all(package, preload \\ []) do
    from(u in assoc(package, :owners), preload: ^preload)
    |> Repo.all
  end

  def add(package, owner, [audit: audit_data]) do
    multi =
      Multi.new
      |> Multi.insert(:owner, Package.build_owner(package, owner), on_conflict: :nothing, conflict_target: [:package_id, :owner_id])
      |> audit(audit_data, "owner.add", {package, owner})

    case Repo.transaction(multi) do
      {:ok, _} ->
        owners = package |> all |> Users.with_emails
        owner = Enum.find(owners, &(&1.id == owner.id))
        Emails.owner_added(package, owners, owner) |> Mailer.deliver_now_throttled
        :ok
      {:error, :owner, changeset, _} ->
        {:error, changeset}
    end
  end

  def remove(package, owner, [audit: audit_data]) do
    owners = package |> all |> Users.with_emails

    if length(owners) == 1 do
      {:error, :last_owner}
    else
      multi =
        Multi.new
        |> Multi.delete_all(:package_owner, Package.owner(package, owner))
        |> audit(audit_data, "owner.remove", {package, owner})

      {:ok, _} = Repo.transaction(multi)
      owner = Enum.find(owners, &(&1.id == owner.id))
      Emails.owner_removed(package, owners, owner) |> Mailer.deliver_now_throttled
      :ok
    end
  end
end
