defmodule HexpmWeb.DeviceController do
  use HexpmWeb, :controller

  alias Hexpm.OAuth.DeviceFlow
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

    if logged_in?(conn) do
      current_user = conn.assigns.current_user

      # Check rate limits before processing any user codes
      case user_code do
        nil ->
          render_verification_form(conn, nil, nil)

        code ->
          case check_rate_limits(conn, current_user) do
            {:rate_limited, message} ->
              render_verification_form(conn, nil, message)

            :ok ->
              normalized_code = DeviceView.normalize_user_code(code)

              case DeviceFlow.get_device_code_for_verification(normalized_code) do
                {:ok, device_code} ->
                  render_verification_form(conn, device_code, nil)

                {:error, :invalid_code} ->
                  render_verification_form(conn, nil, "Invalid verification code")

                {:error, :expired} ->
                  render_verification_form(conn, nil, "Verification code has expired")

                {:error, :already_processed} ->
                  render_verification_form(conn, nil, "This device has already been processed")
              end
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
    # Default to "authorize" if no action specified
    action = params["action"] || "authorize"

    unless logged_in?(conn) do
      redirect(conn, to: build_login_redirect_path(user_code))
    else
      current_user = conn.assigns.current_user

      # Check rate limits before processing any device operations
      case check_rate_limits(conn, current_user) do
        {:rate_limited, message} ->
          render_verification_form(conn, nil, message)

        :ok ->
          case action do
            "authorize" ->
              normalized_code = DeviceView.normalize_user_code(user_code)
              handle_authorization(conn, normalized_code, current_user)

            "deny" ->
              normalized_code = DeviceView.normalize_user_code(user_code)
              handle_denial(conn, normalized_code)

            _ ->
              render_verification_form(conn, nil, "Invalid action")
          end
      end
    end
  end

  def create(conn, _params) do
    render_verification_form(conn, nil, "Missing verification code")
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

  defp handle_authorization(conn, user_code, user) do
    case DeviceFlow.authorize_device(user_code, user) do
      {:ok, _device_code} ->
        conn
        |> put_flash(:info, "Device has been successfully authorized!")
        |> render_verification_form(nil, nil)

      {:error, :invalid_code, message} ->
        render_verification_form(conn, nil, message)

      {:error, :expired_token, message} ->
        render_verification_form(conn, nil, message)

      {:error, :invalid_grant, message} ->
        render_verification_form(conn, nil, message)

      {:error, changeset} ->
        error_message =
          case changeset do
            %Ecto.Changeset{} -> "Authorization failed due to validation errors"
            _ -> "Authorization failed"
          end

        render_verification_form(conn, nil, error_message)
    end
  end

  defp handle_denial(conn, user_code) do
    case DeviceFlow.deny_device(user_code) do
      {:ok, _device_code} ->
        conn
        |> put_flash(:info, "Device authorization has been denied.")
        |> render_verification_form(nil, nil)

      {:error, :invalid_code, message} ->
        render_verification_form(conn, nil, message)

      {:error, changeset} ->
        error_message =
          case changeset do
            %Ecto.Changeset{} -> "Denial failed due to validation errors"
            _ -> "Denial failed"
          end

        render_verification_form(conn, nil, error_message)
    end
  end

  defp render_verification_form(conn, device_code, error_message) do
    render(
      conn,
      "show.html",
      title: "Device Authorization",
      container: "container page page-xs device",
      device_code: device_code,
      error_message: error_message,
      user_code: conn.params["user_code"]
    )
  end
end
