defmodule HexpmWeb.StagedReleaseController do
  use HexpmWeb, :controller

  alias Hexpm.Repository.{Releases, StagedRelease, StagedReleases}

  plug :requires_login
  plug :fetch_staged when action != :index

  plug HexpmWeb.Plugs.Sudo,
       [force: true] when action in [:show, :approve, :reject, :tarball, :docs]

  def index(conn, _params) do
    render(conn, :index,
      title: "Staged releases",
      container: "container page dashboard",
      staged_releases:
        StagedReleases.for_user(conn.assigns.current_user, conn.assigns.current_session.id)
    )
  end

  def show(conn, _params) do
    staged = conn.assigns.staged_release

    render(conn, :show,
      title: "Review #{staged.name} #{staged.version}",
      container: "container page dashboard",
      staged_release: staged,
      replacement?:
        staged.kind == "release" && staged.replace && is_nil(staged.publication) &&
          Releases.exists?(staged.repository.name, staged.name, to_string(staged.version)),
      approval_checksum: StagedRelease.checksum(staged)
    )
  end

  def approve(conn, params) do
    case StagedReleases.approve(
           conn.assigns.staged_release.id,
           conn.assigns.current_user,
           params["checksum"],
           audit: audit_data(conn),
           session_id: conn.assigns.current_session.id
         ) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "The staged release was approved.")
        |> redirect(to: ~p"/dashboard/staged-releases")

      {:error, reason} ->
        approval_error(conn, reason)
    end
  end

  def reject(conn, _params) do
    case StagedReleases.reject(conn.assigns.staged_release.id, conn.assigns.current_user,
           audit: audit_data(conn),
           session_id: conn.assigns.current_session.id
         ) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "The staged release was rejected.")
        |> redirect(to: ~p"/dashboard/staged-releases")

      {:error, reason} ->
        approval_error(conn, reason)
    end
  end

  def tarball(conn, _params), do: download(conn, :storage_key, "release.tar")
  def docs(conn, _params), do: download(conn, :docs_storage_key, "docs.tar.gz")

  defp download(conn, field, filename) do
    staged = conn.assigns.staged_release

    with key when not is_nil(key) <- Map.fetch!(staged, field),
         body when is_binary(body) <- Hexpm.Store.get(:repo_bucket, key) do
      conn
      |> put_resp_content_type("application/octet-stream")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> put_resp_header("cache-control", "private, no-store")
      |> send_resp(200, body)
    else
      _ -> not_found(conn)
    end
  end

  defp fetch_staged(conn, _opts) do
    staged = StagedReleases.get(conn.params["id"])

    if staged &&
         StagedReleases.can_approve?(
           staged,
           conn.assigns.current_user,
           conn.assigns.current_session.id
         ) do
      conn
      |> assign(:staged_release, staged)
      |> put_resp_header("cache-control", "private, no-store")
    else
      conn |> not_found() |> halt()
    end
  end

  defp approval_error(conn, reason) do
    message =
      case reason do
        :publishing ->
          "This release is already being published and can't be rejected."

        :changed ->
          "The staged files changed. Open the review page again."

        :expired ->
          "This staged release expired."

        :credential_revoked ->
          "The staging credential no longer has permission to publish this release."

        :forbidden ->
          "You no longer have permission to approve this release."

        :artifact_missing ->
          "The staged files are unavailable."

        :not_found ->
          "The staged release is no longer available."

        %Ecto.Changeset{} ->
          "The release no longer passes publish validation."
      end

    render_error(conn, 409, message: message)
  end
end
