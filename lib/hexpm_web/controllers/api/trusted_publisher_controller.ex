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

  # Management is api:write only, because package-scoped keys must not install
  # durable trusted-publisher configs that survive key rotation.
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
        "repository_id" => params["repository_id"],
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

        {:error, :repository_not_found} ->
          validation_failed(conn, %{github_repository: "could not be resolved on GitHub"})

        # Everything else is a GitHub-side or transport failure rather than bad
        # input. A 422 would tell the client its request was wrong, and clients
        # do not retry those.
        {:error, _reason} ->
          render_error(conn, 503,
            message: "GitHub could not be reached to resolve the repository, try again later"
          )
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
  # Only body_params are consulted, never merged path/default params.
  #
  # The reset to the Hex repository must happen whenever the body carries a
  # "repository" key at all, not only when "repository_owner" is also present.
  # Otherwise a partial body silently shadows the Hex org lookup and surfaces
  # as an unrelated 404 instead of a validation error on the missing field.
  defp rewrite_github_repository_param(conn, _opts) do
    body = conn.body_params || %{}

    if Map.has_key?(body, "repository") do
      github_repository =
        case body do
          %{"github_repository" => value} when is_binary(value) and value != "" -> value
          %{"repository" => value} when is_binary(value) -> value
          _ -> nil
        end

      hex_repository = Map.get(conn.path_params, "repository") || "hexpm"

      params = Map.put(conn.params, "repository", hex_repository)

      params =
        if github_repository,
          do: Map.put(params, "github_repository", github_repository),
          else: params

      %{conn | params: params}
    else
      conn
    end
  end
end
