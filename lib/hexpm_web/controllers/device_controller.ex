defmodule HexpmWeb.DeviceController do
  use HexpmWeb, :controller

  alias Hexpm.OAuth.DeviceCodes
  alias Hexpm.Accounts.User
  alias Hexpm.Permissions
  alias HexpmWeb.Plugs.{Attack, Sudo}
  alias HexpmWeb.DeviceView

  @verification_timeout_minutes 5

  plug :nillify_params, ["user_code"]
  plug :requires_login
  plug Sudo when action in [:authorize_show, :authorize_create]

  # GET /oauth/device
  def show(conn, params) do
    user_code = params["user_code"]

    if is_nil(user_code) do
      render_verification_form(conn, nil, nil)
    else
      normalized_code = DeviceView.normalize_user_code(user_code)

      case DeviceCodes.get_for_verification(normalized_code) do
        {:ok, _device_code} ->
          render_verification_form(conn, nil, user_code)

        {:error, :invalid_code} ->
          render_verification_form(conn, "Invalid verification code", user_code)

        {:error, :expired} ->
          render_verification_form(conn, "Verification code has expired", user_code)

        {:error, :already_processed} ->
          render_verification_form(conn, "This application has already been processed", user_code)
      end
    end
  end

  # POST /oauth/device — verifies user_code and sets session flag
  def create(conn, %{"user_code" => user_code}) do
    normalized_code = DeviceView.normalize_user_code(user_code)

    case DeviceCodes.get_for_verification(normalized_code) do
      {:ok, _device_code} ->
        conn
        |> put_session("device_code_verified", %{
          "user_code" => normalized_code,
          "verified_at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601()
        })
        |> redirect(to: ~p"/oauth/device/authorize")

      {:error, :invalid_code} ->
        render_verification_form(conn, "Invalid verification code", user_code)

      {:error, :expired} ->
        render_verification_form(conn, "Verification code has expired", user_code)

      {:error, :already_processed} ->
        render_verification_form(conn, "This application has already been processed", user_code)
    end
  end

  def create(conn, _params) do
    render_verification_form(conn, "Missing verification code", nil)
  end

  # GET /oauth/device/authorize — requires sudo (via plug) + valid session flag
  def authorize_show(conn, _params) do
    case get_verified_code(conn) do
      {:ok, user_code} ->
        case DeviceCodes.get_for_verification(user_code) do
          {:ok, device_code} ->
            render_authorization(conn, device_code, nil)

          {:error, :invalid_code} ->
            redirect_to_device(conn, "Invalid verification code")

          {:error, :expired} ->
            redirect_to_device(conn, "Verification code has expired")

          {:error, :already_processed} ->
            redirect_to_device(conn, "This application has already been processed")
        end

      :error ->
        redirect_to_device(conn, nil)
    end
  end

  # POST /oauth/device/authorize — requires sudo (via plug) + valid session flag
  def authorize_create(conn, params) do
    current_user = conn.assigns.current_user

    case get_verified_code(conn) do
      {:ok, user_code} ->
        with :ok <- check_rate_limits(conn, current_user) do
          case params["action"] do
            "authorize" -> handle_authorization(conn, user_code, current_user, params)
            "deny" -> handle_denial(conn, user_code)
            _ -> redirect_to_device(conn, "Invalid action")
          end
        else
          {:rate_limited, message} ->
            case DeviceCodes.get_for_verification(user_code) do
              {:ok, device_code} -> render_authorization(conn, device_code, message)
              _ -> redirect_to_device(conn, message)
            end
        end

      :error ->
        redirect_to_device(conn, nil)
    end
  end

  defp get_verified_code(conn) do
    case get_session(conn, "device_code_verified") do
      %{"user_code" => user_code, "verified_at" => verified_at_string}
      when is_binary(user_code) ->
        case NaiveDateTime.from_iso8601(verified_at_string) do
          {:ok, verified_at} ->
            expires_at = NaiveDateTime.shift(verified_at, minute: @verification_timeout_minutes)

            if NaiveDateTime.compare(NaiveDateTime.utc_now(), expires_at) == :lt do
              {:ok, user_code}
            else
              :error
            end

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp clear_verified_code(conn) do
    delete_session(conn, "device_code_verified")
  end

  defp redirect_to_device(conn, nil) do
    conn
    |> clear_verified_code()
    |> redirect(to: ~p"/oauth/device")
  end

  defp redirect_to_device(conn, message) do
    conn
    |> clear_verified_code()
    |> put_flash(:error, message)
    |> redirect(to: ~p"/oauth/device")
  end

  defp check_rate_limits(conn, user) do
    user_throttle = Attack.device_verification_user_throttle(user.id)
    ip_throttle = Attack.device_verification_ip_throttle(conn.remote_ip)

    case {user_throttle, ip_throttle} do
      {{:block, _}, _} ->
        {:rate_limited,
         "Too many verification attempts. Please wait 15 minutes before trying again."}

      {_, {:block, _}} ->
        {:rate_limited,
         "Too many verification attempts. Please wait 15 minutes before trying again."}

      _ ->
        :ok
    end
  end

  defp handle_authorization(conn, user_code, user, params) do
    selected_scopes = params["selected_scopes"] || []

    if selected_scopes == [] do
      case DeviceCodes.get_for_verification(user_code) do
        {:ok, device_code} ->
          render_authorization(conn, device_code, "At least one permission must be selected")

        _ ->
          redirect_to_device(conn, "Invalid verification code")
      end
    else
      case DeviceCodes.get_for_verification(user_code) do
        {:ok, device_code} ->
          requested_scopes = device_code.scopes || []
          invalid_scopes = Enum.reject(selected_scopes, &(&1 in requested_scopes))

          cond do
            invalid_scopes != [] ->
              render_authorization(
                conn,
                device_code,
                "Selected scopes not in original request"
              )

            Permissions.requires_write_access?(selected_scopes) and
                not User.tfa_enabled?(user) ->
              error_message =
                "Two-factor authentication is required for api:write permissions. " <>
                  "Please <a href='/dashboard/security'>enable 2FA in your security settings</a> and try again."

              render_authorization(conn, device_code, {:safe, error_message})

            true ->
              case DeviceCodes.authorize_device(user_code, user, selected_scopes,
                     audit: audit_data(conn)
                   ) do
                {:ok, _device_code} ->
                  conn
                  |> clear_verified_code()
                  |> put_flash(:info, "Device has been successfully authorized!")
                  |> redirect(to: ~p"/")

                {:error, :invalid_code, message} ->
                  redirect_to_device(conn, message)

                {:error, :expired_token, message} ->
                  redirect_to_device(conn, message)

                {:error, :invalid_grant, message} ->
                  redirect_to_device(conn, message)

                {:error, :invalid_scopes, message} ->
                  redirect_to_device(conn, message)

                {:error, changeset} ->
                  error_message =
                    case changeset do
                      %Ecto.Changeset{} -> "Authorization failed due to validation errors"
                      _ -> "Authorization failed"
                    end

                  redirect_to_device(conn, error_message)
              end
          end

        {:error, :invalid_code} ->
          redirect_to_device(conn, "Invalid user code")

        {:error, :expired} ->
          redirect_to_device(conn, "Device code has expired")

        {:error, :already_processed} ->
          redirect_to_device(conn, "Device code is not pending authorization")
      end
    end
  end

  defp handle_denial(conn, user_code) do
    case DeviceCodes.deny_device(user_code) do
      {:ok, _device_code} ->
        conn
        |> clear_verified_code()
        |> put_flash(:info, "Device authorization has been denied.")
        |> redirect(to: ~p"/")

      {:error, :invalid_code, message} ->
        redirect_to_device(conn, message)

      {:error, changeset} ->
        error_message =
          case changeset do
            %Ecto.Changeset{} -> "Denial failed due to validation errors"
            _ -> "Denial failed"
          end

        redirect_to_device(conn, error_message)
    end
  end

  defp render_verification_form(conn, error_message, pre_filled_code) do
    render(
      conn,
      "show.html",
      title: "Device Authorization",
      container: "container page page-xs device",
      error_message: error_message,
      user_code: pre_filled_code || conn.params["user_code"],
      pre_filled: not is_nil(pre_filled_code)
    )
  end

  defp render_authorization(conn, device_code, error_message) do
    render(
      conn,
      "authorize.html",
      title: "Device Authorization",
      container: "container page page-xs device",
      device_code: device_code,
      error_message: error_message,
      current_user: conn.assigns[:current_user]
    )
  end
end
