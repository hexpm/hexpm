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
    owner = HexWeb.Repo.get_by!(User, email: email)
    package = conn.assigns.package

    multi =
      Ecto.Multi.new
      |> Ecto.Multi.insert(:owner, Package.build_owner(conn.assigns.package, owner))
      |> Ecto.Multi.insert(:log, audit(conn, "owner.add", {package, owner}))

    case HexWeb.Repo.transaction(multi) do
      {:ok, _} ->
        owners = assoc(package, :owners) |> HexWeb.Repo.all

        HexWeb.Mailer.send(
          "owner_add.html",
          "Hex.pm - Owner added",
          Enum.map(owners, fn owner -> owner.email end),
          username: owner.username,
          email: email,
          package: package.name)

        conn
        |> api_cache(:private)
        |> send_resp(204, "")
      {:error, :owner, changeset, _} ->
        validation_failed(conn, changeset)
    end
  end

  def delete(conn, %{"email" => email}) do
    email = URI.decode_www_form(email)
    owner = HexWeb.Repo.get_by!(User, email: email)
    package = conn.assigns.package
    owners = assoc(package, :owners) |> HexWeb.Repo.all

    if length(owners) == 1 do
      conn
      |> api_cache(:private)
      |> send_resp(403, "")
    else
      multi =
        Ecto.Multi.new
        |> Ecto.Multi.delete_all(:package_owner, Package.owner(package, owner))
        |> Ecto.Multi.insert(:log, audit(conn, "owner.remove", {package, owner}))

      case HexWeb.Repo.transaction(multi) do
        {:ok, %{}} ->
          HexWeb.Mailer.send(
            "owner_remove.html",
            "Hex.pm - Owner removed",
            Enum.map(owners, fn owner -> owner.email end),
            username: owner.username,
            email: email,
            package: package.name)

          conn
          |> api_cache(:private)
          |> send_resp(204, "")
      end
    end
  end
end
