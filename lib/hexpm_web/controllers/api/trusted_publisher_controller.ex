defmodule HexpmWeb.API.TrustedPublisherController do
  use HexpmWeb, :controller

  alias Hexpm.TrustedPublishers

  plug :feature_enabled
  plug :rewrite_github_repository_param
  plug :maybe_fetch_package

  plug :authorize,
       [
         authentication: :required,
         domains: [{"api", "read"}],
         fun: [{AuthHelpers, :package_owner}, {AuthHelpers, :organization_access}]
       ]
       when action in [:index, :show]

  # Management is api:write only — package-scoped keys must not install durable
  # trusted-publisher configs that survive key rotation.
  plug :authorize,
       [
         authentication: :required,
         domains: [{"api", "write"}],
         fun: [
           {AuthHelpers, :package_owner, [owner_level: "full"]},
           {AuthHelpers, :organization_billing_active}
         ]
       ]
       when action in [:create, :delete]

  def index(conn, _params) do
    if package = conn.assigns.package do
      publishers = TrustedPublishers.list(package)

      conn
      |> api_cache(:private)
      |> render(:index, trusted_publishers: publishers)
    else
      not_found(conn)
    end
  end

  def show(conn, %{"id" => id}) do
    if package = conn.assigns.package do
      case TrustedPublishers.get(package, id) do
        nil ->
          not_found(conn)

        trusted_publisher ->
          conn
          |> api_cache(:private)
          |> render(:show, trusted_publisher: trusted_publisher)
      end
    else
      not_found(conn)
    end
  end

  def create(conn, params) do
    if package = conn.assigns.package do
      create_params = %{
        "provider" => params["provider"],
        "repository_owner" => params["repository_owner"],
        "repository" => params["github_repository"],
        "workflow" => params["workflow"],
        "environment" => params["environment"]
      }

      case TrustedPublishers.create(package, create_params, audit: audit_data(conn)) do
        {:ok, trusted_publisher} ->
          conn
          |> put_status(201)
          |> api_cache(:private)
          |> render(:show, trusted_publisher: trusted_publisher)

        {:error, %Ecto.Changeset{} = changeset} ->
          validation_failed(conn, changeset)

        {:error, :unknown_provider} ->
          validation_failed(conn, %{provider: "is invalid"})

        {:error, :repository_owner_not_found} ->
          validation_failed(conn, %{repository_owner: "could not be resolved on GitHub"})

        {:error, :repository_not_found} ->
          validation_failed(conn, %{github_repository: "could not be resolved on GitHub"})

        {:error, _} ->
          validation_failed(conn, %{
            repository_owner: "could not be resolved; try again later"
          })
      end
    else
      not_found(conn)
    end
  end

  def delete(conn, %{"id" => id}) do
    if package = conn.assigns.package do
      case TrustedPublishers.get(package, id) do
        nil ->
          not_found(conn)

        trusted_publisher ->
          case TrustedPublishers.delete(trusted_publisher, audit: audit_data(conn)) do
            {:ok, _} ->
              send_resp(conn, 204, "")

            {:error, _} ->
              render_error(conn, 500, message: "Failed to delete trusted publisher")
          end
      end
    else
      not_found(conn)
    end
  end

  defp feature_enabled(conn, _opts) do
    if TrustedPublishers.enabled?() do
      conn
    else
      not_found(conn)
    end
  end

  # Body field "repository" means the GitHub repository and must not shadow the
  # Hex repository path/default param used by maybe_fetch_package/1.
  # Only body_params are consulted — never merged path/default params.
  defp rewrite_github_repository_param(conn, _opts) do
    body = conn.body_params || %{}

    github_repository =
      cond do
        is_binary(body["github_repository"]) and body["github_repository"] != "" ->
          body["github_repository"]

        is_binary(body["repository"]) and is_binary(body["repository_owner"]) and
            body["repository_owner"] != "" ->
          body["repository"]

        true ->
          nil
      end

    if github_repository do
      hex_repository = Map.get(conn.path_params, "repository") || "hexpm"

      %{
        conn
        | params:
            conn.params
            |> Map.put("github_repository", github_repository)
            |> Map.put("repository", hex_repository)
      }
    else
      conn
    end
  end
end
