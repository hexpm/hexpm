defmodule HexpmWeb.TestController do
  use HexpmWeb, :controller

  alias Hexpm.Accounts.Users
  alias Hexpm.OAuth.{Client, DeviceCode, DeviceCodes, Tokens}
  alias Hexpm.Repo
  import Ecto.Query

  def names(conn, _params) do
    Hexpm.Store.get(:repo_bucket, "names", [])
    |> send_object(conn)
  end

  def versions(conn, _params) do
    Hexpm.Store.get(:repo_bucket, "versions", [])
    |> send_object(conn)
  end

  def package(conn, %{"repository" => repository, "package" => package}) do
    Hexpm.Store.get(:repo_bucket, "repos/#{repository}/packages/#{package}", [])
    |> send_object(conn)
  end

  def package(conn, %{"package" => package}) do
    Hexpm.Store.get(:repo_bucket, "packages/#{package}", [])
    |> send_object(conn)
  end

  def tarball(conn, %{"repository" => repository, "ball" => ball}) do
    Hexpm.Store.get(:repo_bucket, "repos/#{repository}/tarballs/#{ball}", [])
    |> send_object(conn)
  end

  def tarball(conn, %{"ball" => ball}) do
    Hexpm.Store.get(:repo_bucket, "tarballs/#{ball}", [])
    |> send_object(conn)
  end

  def repo(conn, params) do
    {:ok, organization} =
      Organizations.create(conn.assigns.current_user, params,
        audit: %{
          user: %User{},
          user_agent: "TEST",
          remote_ip: "127.0.0.1",
          auth_credential: conn.assigns.auth_credential
        }
      )

    organization
    |> Ecto.Changeset.change(%{billing_active: true})
    |> Hexpm.Repo.update!()

    send_resp(conn, 204, "")
  end

  def installs_csv(conn, _params) do
    send_resp(conn, 200, "")
  end

  def oauth_client(conn, params) do
    attrs = %{
      name: params["name"],
      client_id: params["client_id"],
      client_type: params["client_type"] || "public",
      client_secret: params["client_secret"],
      redirect_uris: params["redirect_uris"] || []
    }

    changeset = Client.changeset(%Client{}, attrs)

    case Repo.insert(changeset, on_conflict: :replace_all, conflict_target: :client_id) do
      {:ok, _client} ->
        send_resp(conn, 201, "")

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render(:error,
          error: %{error: "Failed to create client", details: inspect(changeset.errors)}
        )
    end
  end

  def oauth_token(conn, params) do
    user = Users.get(params["username"])

    if is_nil(user) do
      conn
      |> put_status(400)
      |> render(:error, error: %{error: "User not found"})
    else
      client_id = params["client_id"] || "78ea6566-89fd-481e-a1d6-7d9d78eacca8"
      scopes = String.split(params["scope"] || "api repositories", " ")
      usage_info = build_usage_info(conn)

      case Tokens.create_session_and_token_for_user(
             user,
             client_id,
             scopes,
             "authorization_code",
             "test_grant",
             with_refresh_token: true,
             usage_info: usage_info
           ) do
        {:ok, token} ->
          render(conn, :oauth_token, token: token)

        {:error, changeset} ->
          conn
          |> put_status(400)
          |> render(:error,
            error: %{error: "Failed to create token", details: inspect(changeset.errors)}
          )
      end
    end
  end

  def oauth_device_authorize(conn, params) do
    user_code = params["user_code"]
    username = params["username"]

    if is_nil(user_code) or is_nil(username) do
      conn
      |> put_status(400)
      |> render(:error, error: %{error: "Missing user_code or username"})
    else
      user = Users.get(username)

      if is_nil(user) do
        conn
        |> put_status(400)
        |> render(:error, error: %{error: "User not found"})
      else
        device_code = DeviceCodes.get_by_user_code(user_code)

        if is_nil(device_code) do
          conn
          |> put_status(400)
          |> render(:error, error: %{error: "Device code not found"})
        else
          case DeviceCodes.authorize_device(user_code, user, device_code.scopes) do
            {:ok, _device_code} ->
              render(conn, :oauth_device_authorize, response: %{status: "authorized"})

            {:error, reason, description} ->
              conn
              |> put_status(400)
              |> render(:error, error: %{error: Atom.to_string(reason), description: description})
          end
        end
      end
    end
  end

  def oauth_device_pending(conn, _params) do
    device_code =
      from(d in DeviceCode,
        where: d.status == "pending",
        order_by: [desc: d.inserted_at],
        limit: 1
      )
      |> Repo.one()

    if device_code do
      response = %{
        user_code: device_code.user_code,
        device_code: device_code.device_code,
        status: device_code.status
      }

      render(conn, :oauth_device_pending, response: response)
    else
      conn
      |> put_status(404)
      |> render(:error, error: %{error: "No pending device codes"})
    end
  end

  defp build_usage_info(conn) do
    %{
      ip: parse_ip(conn.remote_ip),
      used_at: DateTime.utc_now(),
      user_agent: parse_user_agent(get_req_header(conn, "user-agent"))
    }
  end

  defp parse_ip(nil), do: nil

  defp parse_ip(ip_tuple) do
    ip_tuple
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  defp parse_user_agent([]), do: nil
  defp parse_user_agent([value | _]), do: value
  defp parse_user_agent(nil), do: nil

  defp send_object(nil, conn), do: send_resp(conn, 404, "")
  defp send_object(obj, conn), do: send_resp(conn, 200, obj)
end
