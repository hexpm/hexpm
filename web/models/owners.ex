defmodule HexWeb.Owners do
  use HexWeb.Web, :crud

  def all(package) do
    assoc(package, :owners)
    |> Repo.all
  end

  def get(email) do
    Repo.get_by!(User, email: email)
  end

  def add(package, owner, [audit: audit_data]) do
    multi =
      Ecto.Multi.new
      |> Ecto.Multi.insert(:owner, Package.build_owner(package, owner))
      |> audit(audit_data, "owner.add", {package, owner})

    case Repo.transaction(multi) do
      {:ok, _} ->
        owners = all(package)

        HexWeb.Mailer.send(
          "owner_add.html",
          "Hex.pm - Owner added",
          Enum.map(owners, & &1.email),
          username: owner.username,
          email: owner.email,
          package: package.name
        )
        :ok

      {:error, :owner, changeset, _} ->
        {:error, changeset}
    end
  end

  def remove(package, owner, [audit: audit_data]) do
    owners = all(package)

    if length(owners) == 1 do
      {:error, :last_owner}
    else
      multi =
        Ecto.Multi.new
        |> Ecto.Multi.delete_all(:package_owner, Package.owner(package, owner))
        |> audit(audit_data, "owner.remove", {package, owner})

      {:ok, _} = Repo.transaction(multi)

      HexWeb.Mailer.send(
        "owner_remove.html",
        "Hex.pm - Owner removed",
        Enum.map(owners, & &1.email),
        username: owner.username,
        email: owner.email,
        package: package.name
      )
      :ok
    end
  end
end
