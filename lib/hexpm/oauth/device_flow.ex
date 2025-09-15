defmodule Hexpm.OAuth.DeviceFlow do
  @moduledoc """
  OAuth 2.0 Device Authorization Grant implementation (RFC 8628).

  This module handles the device flow authorization process, allowing
  devices without browsers or input capabilities to obtain access tokens.
  """

  import Ecto.Query, only: [from: 2]
  alias Hexpm.OAuth.DeviceCode
  alias Hexpm.OAuth.Token
  alias Hexpm.Repo

  @default_device_code_expiry_seconds 10 * 60
  @default_token_expiry_seconds 60 * 60
  @default_polling_interval 5

  @doc """
  Initiates the device authorization flow.

  Creates a new device code entry and returns the necessary information
  for the client to display to the user.
  """
  def initiate_device_authorization(client_id, scopes) do
    device_code = DeviceCode.generate_device_code()
    user_code = DeviceCode.generate_user_code()
    expires_at = DateTime.add(DateTime.utc_now(), @default_device_code_expiry_seconds, :second)

    verification_uri = build_verification_uri()
    verification_uri_complete = build_verification_uri_complete(user_code)

    changeset =
      DeviceCode.changeset(%DeviceCode{}, %{
        device_code: device_code,
        user_code: user_code,
        verification_uri: verification_uri,
        verification_uri_complete: verification_uri_complete,
        client_id: client_id,
        expires_at: expires_at,
        interval: @default_polling_interval,
        scopes: scopes
      })

    case Repo.insert(changeset) do
      {:ok, device_code_record} ->
        {:ok,
         %{
           device_code: device_code_record.device_code,
           user_code: device_code_record.user_code,
           verification_uri: device_code_record.verification_uri,
           verification_uri_complete: device_code_record.verification_uri_complete,
           expires_in: @default_device_code_expiry_seconds,
           interval: device_code_record.interval
         }}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Handles token polling from the device.

  Returns appropriate responses based on the current state of the device code.
  """
  def poll_device_token(device_code, client_id) do
    if is_nil(device_code) or device_code == "" do
      {:error, :invalid_grant, "Invalid device code"}
    else
      case get_device_code_by_code(device_code) do
        nil ->
          {:error, :invalid_grant, "Invalid device code"}

        device_code_record ->
          if device_code_record.client_id != client_id do
            {:error, :invalid_client, "Invalid client"}
          else
            handle_device_code_status(device_code_record)
          end
      end
    end
  end

  @doc """
  Authorizes a device using the user code.

  This is called when a user enters the user code on the verification page.
  """
  def authorize_device(user_code, user) do
    case get_device_code_by_user_code(user_code) do
      nil ->
        {:error, :invalid_code, "Invalid user code"}

      device_code_record ->
        cond do
          DeviceCode.expired?(device_code_record) ->
            Repo.update(DeviceCode.expire_changeset(device_code_record))
            {:error, :expired_token, "Device code has expired"}

          not DeviceCode.pending?(device_code_record) ->
            {:error, :invalid_grant, "Device code is not pending authorization"}

          true ->
            perform_authorization(device_code_record, user)
        end
    end
  end

  @doc """
  Denies authorization for a device using the user code.
  """
  def deny_device(user_code) do
    case get_device_code_by_user_code(user_code) do
      nil ->
        {:error, :invalid_code, "Invalid user code"}

      device_code_record ->
        Repo.update(DeviceCode.deny_changeset(device_code_record))
    end
  end

  @doc """
  Gets a device code record by user code for verification page display.
  """
  def get_device_code_for_verification(user_code) do
    case get_device_code_by_user_code(user_code) do
      nil ->
        {:error, :invalid_code}

      device_code_record ->
        cond do
          DeviceCode.expired?(device_code_record) ->
            Repo.update(DeviceCode.expire_changeset(device_code_record))
            {:error, :expired}

          not DeviceCode.pending?(device_code_record) ->
            {:error, :already_processed}

          true ->
            {:ok, device_code_record}
        end
    end
  end

  @doc """
  Cleans up expired device codes.

  This should be called periodically to remove old records.
  """
  def cleanup_expired_device_codes do
    now = DateTime.utc_now()

    from(dc in DeviceCode,
      where: dc.expires_at < ^now and dc.status == "pending"
    )
    |> Repo.update_all(set: [status: "expired", updated_at: now])
  end

  defp get_device_code_by_code(device_code) do
    from(dc in DeviceCode,
      where: dc.device_code == ^device_code,
      preload: [:user]
    )
    |> Repo.one()
  end

  defp get_device_code_by_user_code(user_code) do
    from(dc in DeviceCode,
      where: dc.user_code == ^user_code,
      preload: [:user]
    )
    |> Repo.one()
  end

  defp handle_device_code_status(device_code_record) do
    cond do
      DeviceCode.expired?(device_code_record) ->
        Repo.update(DeviceCode.expire_changeset(device_code_record))
        {:error, :expired_token, "Device code has expired"}

      DeviceCode.denied?(device_code_record) ->
        {:error, :access_denied, "Authorization denied by user"}

      DeviceCode.authorized?(device_code_record) ->
        # Look up the associated token
        case get_device_token(device_code_record) do
          nil ->
            {:error, :invalid_grant, "No token found for authorized device"}

          token ->
            {:ok, Token.to_response(token)}
        end

      DeviceCode.pending?(device_code_record) ->
        {:error, :authorization_pending, "Authorization pending"}

      true ->
        {:error, :invalid_grant, "Invalid device code state"}
    end
  end

  defp perform_authorization(device_code_record, user) do
    # Create OAuth token for the device flow with refresh token
    token_changeset =
      Token.create_for_user(
        user,
        device_code_record.client_id,
        device_code_record.scopes,
        "urn:ietf:params:oauth:grant-type:device_code",
        device_code_record.device_code,
        expires_in: @default_token_expiry_seconds,
        with_refresh_token: true
      )

    case Repo.insert(token_changeset) do
      {:ok, token} ->
        # Update device code to authorized status
        changeset = DeviceCode.authorize_changeset(device_code_record, user)

        case Repo.update(changeset) do
          {:ok, updated_device_code} ->
            {:ok, updated_device_code}

          {:error, changeset} ->
            # Clean up the created token if device code update fails
            Repo.update(Token.revoke(token))
            {:error, changeset}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp get_device_token(device_code_record) do
    from(t in Token,
      where:
        t.grant_type == "urn:ietf:params:oauth:grant-type:device_code" and
          t.grant_reference == ^device_code_record.device_code and
          t.client_id == ^device_code_record.client_id,
      preload: [:user]
    )
    |> Repo.one()
  end

  defp build_verification_uri do
    case Application.get_env(:hexpm, HexpmWeb.Endpoint)[:url] do
      nil ->
        "http://localhost:4000/device"

      url_config ->
        scheme = url_config[:scheme] || "https"
        host = url_config[:host] || "hex.pm"
        port = url_config[:port]

        case port do
          nil -> "#{scheme}://#{host}/device"
          80 when scheme == "http" -> "#{scheme}://#{host}/device"
          443 when scheme == "https" -> "#{scheme}://#{host}/device"
          _ -> "#{scheme}://#{host}:#{port}/device"
        end
    end
  end

  defp build_verification_uri_complete(user_code) do
    "#{build_verification_uri()}?user_code=#{user_code}"
  end
end
