defmodule HexWeb.API.OwnerController do
  use HexWeb.Web, :controller

  plug :fetch_package
  plug :authorize, fun: &package_owner?/2

  def index(conn, _params) do
    owners = assoc(conn.assigns.package, :owners) |> HexWeb.Repo.all
    conn
    |> api_cache(:private)
    |> render(:index, owners: owners)
  end

  def show(conn, %{"email" => email}) do
    email = URI.decode_www_form(email)
    owner = HexWeb.Repo.get_by!(User, email: email)

    if package_owner?(conn.assigns.package, owner) do
      conn
      |> api_cache(:private)
      |> send_resp(204, "")
    else
      not_found(conn)
    end
  end

  def create(conn, %{"email" => email}) do
    email = URI.decode_www_form(email)
    new_owner = HexWeb.Repo.get_by!(User, email: email)
    current_owner = conn.assigns.user
    package = conn.assigns.package

    case add_owner(current_owner, package, new_owner) do
      :ok ->
        conn
        |> api_cache(:private)
        |> send_resp(204, "")
      {:error, changeset} ->
        validation_failed(conn, changeset)
    end
  end

  def delete(conn, %{"email" => email}) do
    email = URI.decode_www_form(email)
    remove_owner = HexWeb.Repo.get_by!(User, email: email)
    owner = conn.assigns.user
    package = conn.assigns.package
    owners = package_owners(package)

    if length(owners) == 1 do
      conn
      |> api_cache(:private)
      |> send_resp(403, "")
    else
      remove_owner(owner, package, remove_owner, owners)

      conn
      |> api_cache(:private)
      |> send_resp(204, "")
    end
  end

  def add_owner(current_owner, package, new_owner) do
    multi =
      Ecto.Multi.new
      |> Ecto.Multi.insert(:owner, Package.build_owner(package, new_owner))
      |> audit(current_owner, "owner.add", {package, new_owner})

    case HexWeb.Repo.transaction(multi) do
      {:ok, _} ->
        owners = assoc(package, :owners) |> HexWeb.Repo.all

        HexWeb.Mailer.send(
          "owner_add.html",
          "Hex.pm - Owner added",
          Enum.map(owners, fn owner -> owner.email end),
          username: new_owner.username,
          email: new_owner.email,
          package: package.name
        )
        :ok

      {:error, :owner, changeset, _} ->
        {:error, changeset}
    end
  end

  def remove_owner(owner, package, remove_owner, owners \\ nil) do
    owners = owners || package_owners(package)

    {:ok, _} =
      Ecto.Multi.new
      |> Ecto.Multi.delete_all(:package_owner, Package.owner(package, remove_owner))
      |> audit(owner, "owner.remove", {package, remove_owner})
      |> HexWeb.Repo.transaction

    HexWeb.Mailer.send(
      "owner_remove.html",
      "Hex.pm - Owner removed",
      Enum.map(owners, fn owner -> owner.email end),
      username: remove_owner.username,
      email: remove_owner.email,
      package: package.name
    )
  end

  defp package_owners(package) do
    assoc(package, :owners) |> HexWeb.Repo.all
  end
end
