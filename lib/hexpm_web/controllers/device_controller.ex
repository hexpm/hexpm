defmodule HexpmWeb.DeviceController do
  use HexpmWeb, :controller

  alias Hexpm.OAuth.DeviceCodes
  alias HexpmWeb.Plugs.Attack
  alias HexpmWeb.DeviceView

  plug :nillify_params, ["user_code"]

  @doc """
  Shows the device verification page.

  GET /oauth/device
  GET /oauth/device?user_code=XXXX-XXXX
  """
  def show(conn, params) do
    user_code = params["user_code"]
    show_authorization = params["verified"] == "true"

    if logged_in?(conn) do
      # Don't check rate limits for just viewing the form (GET request)
      cond do
        # No code provided, show empty form
        is_nil(user_code) ->
          render_verification_form(conn, nil, nil, nil)

        # Code provided and verified, show authorization
        show_authorization ->
          normalized_code = DeviceView.normalize_user_code(user_code)

          case DeviceCodes.get_for_verification(normalized_code) do
            {:ok, device_code} ->
              render_verification_form(conn, device_code, nil, nil)

            {:error, :invalid_code} ->
              render_verification_form(conn, nil, "Invalid verification code", user_code)

            {:error, :expired} ->
              render_verification_form(conn, nil, "Verification code has expired", user_code)

            {:error, :already_processed} ->
              render_verification_form(
                conn,
                nil,
                "This application has already been processed",
                user_code
              )
          end

        # Code provided but not verified yet, show pre-filled form for verification
        true ->
          normalized_code = DeviceView.normalize_user_code(user_code)

          # Validate the code exists but show verification form
          case DeviceCodes.get_for_verification(normalized_code) do
            {:ok, _device_code} ->
              # Code is valid, show pre-filled verification form
              render_verification_form(conn, nil, nil, user_code)

            {:error, :invalid_code} ->
              render_verification_form(conn, nil, "Invalid verification code", user_code)

            {:error, :expired} ->
              render_verification_form(conn, nil, "Verification code has expired", user_code)

            {:error, :already_processed} ->
              render_verification_form(
                conn,
                nil,
                "This application has already been processed",
                user_code
              )
          end
      end
    else
      redirect(conn, to: build_login_redirect_path(user_code))
    end
  end

  @doc """
  Handles device authorization or denial.

  POST /oauth/device
  """
  def create(conn, %{"user_code" => user_code} = params) do
    if logged_in?(conn) do
      current_user = conn.assigns.current_user

      # Check rate limits before processing any device operations
      case check_rate_limits(conn, current_user) do
        {:rate_limited, message} ->
          render_verification_form(conn, nil, message, user_code)

        :ok ->
          case params["action"] do
            "authorize" ->
              normalized_code = DeviceView.normalize_user_code(user_code)
              handle_authorization(conn, normalized_code, current_user, params)

            "deny" ->
              normalized_code = DeviceView.normalize_user_code(user_code)
              handle_denial(conn, normalized_code)

            _ ->
              render_verification_form(conn, nil, "Invalid action", user_code)
          end
      end
    else
      redirect(conn, to: build_login_redirect_path(user_code))
    end
  end

  def create(conn, _params) do
    render_verification_form(conn, nil, "Missing verification code", nil)
  end

  defp build_login_redirect_path(user_code) do
    redirect_path =
      case user_code do
        nil ->
          ~p"/oauth/device"

        code ->
          normalized_code = DeviceView.normalize_user_code(code)
          ~p"/oauth/device?user_code=#{normalized_code}"
      end

    ~p"/login?return=#{redirect_path}"
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
      render_verification_form(conn, nil, "At least one permission must be selected", user_code)
    else
      case DeviceCodes.authorize_device(user_code, user, selected_scopes) do
        {:ok, _device_code} ->
          conn
          |> put_flash(:info, "Device has been successfully authorized!")
          |> redirect(to: ~p"/")

        {:error, :invalid_code, message} ->
          render_verification_form(conn, nil, message, user_code)

        {:error, :expired_token, message} ->
          render_verification_form(conn, nil, message, user_code)

        {:error, :invalid_grant, message} ->
          render_verification_form(conn, nil, message, user_code)

        {:error, :invalid_scopes, message} ->
          render_verification_form(conn, nil, message, user_code)

        {:error, changeset} ->
          error_message =
            case changeset do
              %Ecto.Changeset{} -> "Authorization failed due to validation errors"
              _ -> "Authorization failed"
            end

          render_verification_form(conn, nil, error_message, user_code)
      end
    end
  end

  defp handle_denial(conn, user_code) do
    case DeviceCodes.deny_device(user_code) do
      {:ok, _device_code} ->
        conn
        |> put_flash(:info, "Device authorization has been denied.")
        |> redirect(to: ~p"/")

      {:error, :invalid_code, message} ->
        render_verification_form(conn, nil, message, user_code)

      {:error, changeset} ->
        error_message =
          case changeset do
            %Ecto.Changeset{} -> "Denial failed due to validation errors"
            _ -> "Denial failed"
          end

        render_verification_form(conn, nil, error_message, user_code)
    end
  end

  defp render_verification_form(conn, device_code, error_message, pre_filled_code) do
    render(
      conn,
      "show.html",
      title: "Device Authorization",
      container: "container page page-xs device",
      device_code: device_code,
      error_message: error_message,
      user_code: pre_filled_code || conn.params["user_code"],
      pre_filled: not is_nil(pre_filled_code) and is_nil(device_code)
    )
  end
end
