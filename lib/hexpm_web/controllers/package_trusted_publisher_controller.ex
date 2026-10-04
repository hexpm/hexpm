defmodule HexpmWeb.PackageTrustedPublisherController do
  use HexpmWeb, :controller

  alias HexpmWeb.{PackageLayoutAssigns, RepositoryAccess, SSOEnforcement, ViewHelpers}

  plug :feature_enabled
  plug :requires_login
  plug :fetch_package
  plug :requires_full_owner
  plug :requires_tfa
  plug HexpmWeb.Plugs.Sudo

  def index(conn, _params) do
    package = conn.assigns.package
    render_index(conn, package, TrustedPublisher.changeset(%TrustedPublisher{}, %{}, package))
  end

  def create(conn, params) do
    package = conn.assigns.package
    trusted_publisher_params = params["trusted_publisher"] || %{}

    case billing_active(package) do
      :ok -> do_create(conn, package, trusted_publisher_params)
      {:error, message} -> refuse_billing(conn, message)
    end
  end

  defp do_create(conn, package, params) do
    case TrustedPublishers.create(package, params, audit: audit_data(conn)) do
      {:ok, _trusted_publisher} ->
        conn
        |> put_flash(:info, "Trusted publisher added.")
        |> redirect(to: ViewHelpers.path_for_trusted_publishers(package))

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(400)
        |> render_index(package, changeset)

      {:error, :unknown_provider} ->
        conn
        |> put_flash(:error, "The provider is invalid.")
        |> redirect(to: ViewHelpers.path_for_trusted_publishers(package))

      {:error, :repository_not_found} ->
        conn
        |> put_flash(:error, "The GitHub repository could not be resolved.")
        |> redirect(to: ViewHelpers.path_for_trusted_publishers(package))

      {:error, _reason} ->
        conn
        |> put_flash(:error, "GitHub could not be reached, try again later.")
        |> redirect(to: ViewHelpers.path_for_trusted_publishers(package))
    end
  end

  def delete(conn, %{"id" => id}) do
    package = conn.assigns.package

    case TrustedPublishers.get(package, id) do
      nil ->
        conn
        |> render_error(404, message: "Trusted publisher not found")
        |> halt()

      trusted_publisher ->
        {:ok, _} = TrustedPublishers.delete(trusted_publisher, audit: audit_data(conn))

        conn
        |> put_flash(:info, "Trusted publisher removed.")
        |> redirect(to: ViewHelpers.path_for_trusted_publishers(package))
    end
  end

  defp render_index(conn, package, changeset) do
    render(
      conn,
      "index.html",
      [
        title: "Trusted publishers – #{package.name}",
        container: "container",
        trusted_publishers: TrustedPublishers.list(package),
        changeset: changeset
      ] ++ PackageLayoutAssigns.for_package(conn, package)
    )
  end

  defp billing_active(%{repository: %{organization: %Organization{id: 1}}}), do: :ok

  defp billing_active(%{repository: %{organization: %Organization{} = organization}}) do
    if Organization.billing_active?(organization) do
      :ok
    else
      {:error, "This organization has no active billing subscription."}
    end
  end

  defp refuse_billing(conn, message) do
    package = conn.assigns.package

    conn
    |> put_flash(:error, message)
    |> redirect(to: ViewHelpers.path_for_trusted_publishers(package))
  end

  defp feature_enabled(conn, _opts) do
    if TrustedPublishers.enabled?() do
      conn
    else
      conn
      |> render_error(404, message: "Page not found")
      |> halt()
    end
  end

  defp fetch_package(conn, _opts) do
    case RepositoryAccess.fetch_package(conn, conn.params["repository"], conn.params["name"]) do
      {:ok, package} ->
        conn
        |> assign(:repository, package.repository)
        |> assign(:package, package)

      {:error, requirement, organization} when requirement in [:sso_required, :tfa_required] ->
        SSOEnforcement.refuse(conn, :sso_required, organization)

      :error ->
        conn
        |> render_error(404, message: "Package not found")
        |> halt()
    end
  end

  defp requires_full_owner(conn, _opts) do
    package = conn.assigns.package
    current_user = conn.assigns.current_user

    if current_user && Packages.owner_with_access?(package, current_user, "full") do
      case SSOEnforcement.check_package(conn, package, current_user, "full") do
        :ok -> conn
        {:error, refusal, organization} -> SSOEnforcement.refuse(conn, refusal, organization)
      end
    else
      conn
      |> render_error(403, message: "You must be a full owner of this package")
      |> halt()
    end
  end

  defp requires_tfa(conn, _opts) do
    current_user = conn.assigns.current_user

    if User.tfa_enabled?(current_user) do
      conn
    else
      conn
      |> render_error(403,
        message:
          "Two-factor authentication is required to manage trusted publishers. " <>
            "Enable 2FA in your security settings (/dashboard/security) and try again."
      )
      |> halt()
    end
  end
end
