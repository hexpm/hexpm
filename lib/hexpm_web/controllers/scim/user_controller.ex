defmodule HexpmWeb.SCIM.UserController do
  use HexpmWeb, :controller

  import HexpmWeb.SCIMHelpers

  alias Hexpm.Accounts.SCIM
  alias HexpmWeb.SSOEnforcement

  @user_schema "urn:ietf:params:scim:schemas:core:2.0:User"
  @list_schema "urn:ietf:params:scim:api:messages:2.0:ListResponse"

  @default_count 100
  @max_count 200

  @filter_regex ~r/^\s*(userName|externalId)\s+eq\s+"((?:[^"\\]|\\.)*)"\s*$/i

  def index(conn, %{"filter" => filter}) do
    case Regex.run(@filter_regex, filter) do
      [_all, attribute, value] ->
        value = String.replace(value, ~r/\\(.)/, "\\1")

        resolved =
          case String.downcase(attribute) do
            "username" -> SCIM.find_by_user_name(connection(conn), value)
            "externalid" -> SCIM.find_by_external_id(connection(conn), value)
          end

        resources = List.wrap(resolved)

        scim_json(conn, 200, %{
          "schemas" => [@list_schema],
          "totalResults" => length(resources),
          "startIndex" => 1,
          "itemsPerPage" => length(resources),
          "Resources" => Enum.map(resources, &user_json/1)
        })

      nil ->
        scim_error(conn, 400, "Unsupported filter", :invalidFilter)
    end
  end

  def index(conn, params) do
    start_index = max(Hexpm.Utils.safe_int(params["startIndex"]) || 1, 1)

    count =
      (Hexpm.Utils.safe_int(params["count"]) || @default_count)
      |> min(@max_count)
      |> max(0)

    listing = SCIM.list_users(connection(conn), start_index, count)

    scim_json(conn, 200, %{
      "schemas" => [@list_schema],
      "totalResults" => listing.total,
      "startIndex" => listing.start_index,
      "itemsPerPage" => length(listing.resources),
      "Resources" => Enum.map(listing.resources, &user_json/1)
    })
  end

  def show(conn, %{"id" => id}) do
    case SCIM.get_user(connection(conn), id) do
      {:ok, resolved} -> scim_json(conn, 200, user_json(resolved))
      {:error, reason} -> refuse(conn, reason)
    end
  end

  def create(conn, params) do
    case SCIM.create_user(connection(conn), params) do
      {:ok, resolved} ->
        conn
        |> put_resp_header("location", location(resolved))
        |> scim_json(201, user_json(resolved))

      {:error, reason} ->
        refuse(conn, reason)
    end
  end

  def update(conn, %{"id" => id} = params) do
    case SCIM.replace_user(connection(conn), id, params) do
      {:ok, resolved} -> scim_json(conn, 200, user_json(resolved))
      {:error, reason} -> refuse(conn, reason)
    end
  end

  def patch(conn, %{"id" => id} = params) do
    case SCIM.patch_user(connection(conn), id, params["Operations"]) do
      {:ok, resolved} -> scim_json(conn, 200, user_json(resolved))
      {:error, reason} -> refuse(conn, reason)
    end
  end

  def delete(conn, %{"id" => id}) do
    case SCIM.delete_user(connection(conn), id) do
      :ok -> send_resp(conn, 204, "")
      {:error, reason} -> refuse(conn, reason)
    end
  end

  defp connection(conn), do: conn.assigns.scim_connection

  defp refuse(conn, :not_found), do: scim_error(conn, 404, "Resource not found")

  defp refuse(conn, :uniqueness),
    do: scim_error(conn, 409, "userName is already in use", :uniqueness)

  defp refuse(conn, :seats_exhausted),
    do:
      scim_error(
        conn,
        409,
        "The organization has no seats left; expand the subscription on hex.pm"
      )

  defp refuse(conn, :seat_limit_unknown),
    do:
      scim_error(
        conn,
        409,
        "The organization's seat count could not be read; no member was added"
      )

  defp refuse(conn, :last_member),
    do: scim_error(conn, 409, "Cannot remove the organization's last member")

  defp refuse(conn, :unverified_member),
    do:
      scim_error(
        conn,
        409,
        "The address belongs to an existing member but is not a verified email on hex.pm"
      )

  defp refuse(conn, :invalid_value),
    do: scim_error(conn, 400, "userName must be an email address", :invalidValue)

  defp refuse(conn, :invalid_path),
    do: scim_error(conn, 400, "Unsupported patch operation", :invalidPath)

  defp refuse(conn, %Ecto.Changeset{}),
    do: scim_error(conn, 400, "The value could not be saved", :invalidValue)

  defp user_json(%{resource: resource, state: state, user: user}) do
    %{
      "schemas" => [@user_schema],
      "id" => resource.scim_id,
      "userName" => resource.user_name,
      "active" => state in [:member, :invited],
      "emails" => [%{"value" => resource.user_name, "primary" => true, "type" => "work"}],
      "meta" => %{
        "resourceType" => "User",
        "created" => DateTime.to_iso8601(resource.inserted_at),
        "lastModified" => DateTime.to_iso8601(resource.updated_at),
        "location" => location(%{resource: resource})
      }
    }
    |> put_present("externalId", resource.external_id)
    |> put_present("displayName", user && user.username)
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp location(%{resource: resource}) do
    SSOEnforcement.scim_base_url() <> "/Users/" <> resource.scim_id
  end
end
