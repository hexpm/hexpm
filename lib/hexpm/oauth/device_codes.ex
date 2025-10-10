defmodule Hexpm.OAuth.DeviceCodes do
  use Hexpm.Context

  alias Hexpm.OAuth.{DeviceCode, Sessions, Token, Tokens}

  @default_device_code_expiry_seconds 10 * 60
  @default_polling_interval 5

  @doc """
  Initiates the device authorization flow.
  Creates a new device code entry and returns the necessary information
  for the client to display to the user.
  """
  def initiate_device_authorization(conn, client_id, scopes, opts \\ []) do
    device_code = generate_device_code()
    user_code = generate_user_code()
    expires_at = DateTime.add(DateTime.utc_now(), @default_device_code_expiry_seconds, :second)

    verification_uri = build_verification_uri(conn)
    verification_uri_complete = build_verification_uri_complete(conn, user_code)

    changeset =
      DeviceCode.changeset(%DeviceCode{}, %{
        device_code: device_code,
        user_code: user_code,
        verification_uri: verification_uri,
        verification_uri_complete: verification_uri_complete,
        client_id: client_id,
        expires_at: expires_at,
        interval: @default_polling_interval,
        scopes: scopes,
        name: Keyword.get(opts, :name)
      })

    case Repo.insert(changeset) do
      {:ok, device_code} ->
        {:ok, device_code}

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
      case get_by_code(device_code) do
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
  Authorizes a device using the user code with selected scopes.
  Requires explicit scope selection - at least one scope must be provided.
  """
  def authorize_device(user_code, user, selected_scopes, opts \\ []) do
    case get_by_user_code(user_code) do
      nil ->
        {:error, :invalid_code, "Invalid user code"}

      device_code_record ->
        cond do
          expired?(device_code_record) ->
            Repo.update(DeviceCode.expire_changeset(device_code_record))
            {:error, :expired_token, "Device code has expired"}

          not pending?(device_code_record) ->
            {:error, :invalid_grant, "Device code is not pending authorization"}

          true ->
            perform_authorization(device_code_record, user, selected_scopes, opts)
        end
    end
  end

  @doc """
  Denies authorization for a device using the user code.
  """
  def deny_device(user_code) do
    case get_by_user_code(user_code) do
      nil ->
        {:error, :invalid_code, "Invalid user code"}

      device_code_record ->
        Repo.update(DeviceCode.deny_changeset(device_code_record))
    end
  end

  @doc """
  Gets a device code record by user code for verification page display.
  """
  def get_for_verification(user_code) do
    case get_by_user_code(user_code) do
      nil ->
        {:error, :invalid_code}

      device_code_record ->
        cond do
          expired?(device_code_record) ->
            Repo.update(DeviceCode.expire_changeset(device_code_record))
            {:error, :expired}

          not pending?(device_code_record) ->
            {:error, :already_processed}

          true ->
            {:ok, device_code_record}
        end
    end
  end

  @doc """
  Gets a device code by code.
  """
  def get_by_code(device_code) do
    from(dc in DeviceCode,
      where: dc.device_code == ^device_code,
      preload: [:user]
    )
    |> Repo.one()
  end

  @doc """
  Gets a device code by user code.
  """
  def get_by_user_code(user_code) do
    from(dc in DeviceCode,
      where: dc.user_code == ^user_code,
      preload: [:user, :client]
    )
    |> Repo.one()
  end

  @doc """
  Checks if a device code is expired.
  """
  def expired?(%DeviceCode{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Checks if a device code is still pending authorization.
  """
  def pending?(%DeviceCode{status: "pending"} = device_code) do
    not expired?(device_code)
  end

  def pending?(_), do: false

  @doc """
  Checks if a device code has been authorized.
  """
  def authorized?(%DeviceCode{status: "authorized"}), do: true
  def authorized?(_), do: false

  @doc """
  Checks if a device code has been denied.
  """
  def denied?(%DeviceCode{status: "denied"}), do: true
  def denied?(_), do: false

  @doc """
  Gets a device code for verification page display.
  """
  def get_device_code_for_verification(user_code) do
    case get_by_user_code(user_code) do
      nil ->
        {:error, :invalid_code}

      device_code_record ->
        cond do
          expired?(device_code_record) ->
            {:error, :expired}

          not pending?(device_code_record) ->
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
  def cleanup_expired do
    now = DateTime.utc_now()

    from(dc in DeviceCode,
      where: dc.expires_at < ^now and dc.status == "pending"
    )
    |> Repo.update_all(set: [status: "expired", updated_at: now])
  end

  # Alias for compatibility
  def cleanup_expired_device_codes, do: cleanup_expired()

  @doc """
  Generates a cryptographically secure device code.
  Returns a 32-character base64url encoded string.
  """
  def generate_device_code do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
    |> String.slice(0, 32)
  end

  @doc """
  Generates a user-friendly verification code.
  Returns an 8-character string using a reduced character set that excludes
  ambiguous characters (0, 1, I, O) and vowels (A, E, U) to avoid forming words.
  """
  def generate_user_code do
    # Character set excludes ambiguous characters (0, 1, I, O) and vowels (A, E, U) to avoid forming words
    charset = "23456789BCDFGHJKLMNPQRSTVWXYZ"
    charset_size = String.length(charset)

    # Generate 8 random characters using cryptographically secure randomness with uniform distribution
    1..8
    |> Enum.map(fn _ ->
      <<random_int::unsigned-32>> = :crypto.strong_rand_bytes(4)
      index = rem(random_int, charset_size)
      String.at(charset, index)
    end)
    |> Enum.join()
  end

  defp handle_device_code_status(device_code_record) do
    cond do
      expired?(device_code_record) ->
        Repo.update(DeviceCode.expire_changeset(device_code_record))
        {:error, :expired_token, "Device code has expired"}

      denied?(device_code_record) ->
        {:error, :access_denied, "Authorization denied by user"}

      authorized?(device_code_record) ->
        # Look up the associated token and generate a fresh response
        case get_device_token(device_code_record) do
          nil ->
            {:error, :invalid_grant, "No token found for authorized device"}

          token ->
            # Generate fresh tokens for device flow response
            {:ok, build_device_token_response(token)}
        end

      pending?(device_code_record) ->
        {:error, :authorization_pending, "Authorization pending"}

      true ->
        {:error, :invalid_grant, "Invalid device code state"}
    end
  end

  defp perform_authorization(device_code_record, user, selected_scopes, opts \\ []) do
    with {:ok, final_scopes} <- validate_and_get_scopes(device_code_record, selected_scopes) do
      result =
        Ecto.Multi.new()
        |> Ecto.Multi.run(:session, fn _repo, _changes ->
          Sessions.create_for_user(user, device_code_record.client_id,
            name: device_code_record.name
          )
        end)
        |> Ecto.Multi.run(:update_session_last_use, fn _repo, %{session: session} ->
          if Keyword.has_key?(opts, :usage_info) do
            Sessions.update_last_use(session, Keyword.get(opts, :usage_info))
          else
            {:ok, session}
          end
        end)
        |> Ecto.Multi.run(:token, fn _repo, %{update_session_last_use: session} ->
          changeset =
            Tokens.create_for_user(
              user,
              device_code_record.client_id,
              final_scopes,
              "urn:ietf:params:oauth:grant-type:device_code",
              device_code_record.device_code,
              session_id: session.id,
              with_refresh_token: true
            )

          Repo.insert(changeset)
        end)
        |> Ecto.Multi.update(
          :device_code,
          DeviceCode.authorize_changeset(device_code_record, user)
        )
        |> Repo.transaction()

      case result do
        {:ok, %{device_code: updated_device_code}} ->
          {:ok, updated_device_code}

        {:error, _failed_operation, changeset, _changes} ->
          {:error, changeset}
      end
    else
      error -> error
    end
  end

  defp validate_and_get_scopes(device_code_record, selected_scopes) do
    if selected_scopes == [] do
      {:error, :invalid_scopes, "At least one permission must be selected"}
    else
      requested_scopes = device_code_record.scopes || []
      invalid_scopes = Enum.reject(selected_scopes, &(&1 in requested_scopes))

      if invalid_scopes != [] do
        {:error, :invalid_scopes, "Selected scopes not in original request"}
      else
        {:ok, selected_scopes}
      end
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

  # Builds a secure token response for device flow by generating fresh tokens
  # and immediately revoking the old token for security
  defp build_device_token_response(old_token) do
    # Generate fresh tokens with the same permissions
    new_token_changeset =
      Tokens.create_for_user(
        old_token.user,
        old_token.client_id,
        old_token.scopes,
        "urn:ietf:params:oauth:grant-type:device_code",
        old_token.grant_reference,
        expires_in: DateTime.diff(old_token.expires_at, DateTime.utc_now()),
        with_refresh_token: not is_nil(old_token.refresh_jti),
        session_id: old_token.session_id
      )

    case Repo.insert(new_token_changeset) do
      {:ok, new_token} ->
        # Revoke the old token for security (one-time use pattern)
        Tokens.revoke(old_token)

        new_token

      {:error, _changeset} ->
        # Fallback: build minimal response from existing token info
        %{
          access_token: "ERROR_GENERATING_TOKEN",
          token_type: old_token.token_type,
          expires_in: max(DateTime.diff(old_token.expires_at, DateTime.utc_now()), 0),
          scope: Enum.join(old_token.scopes, " ")
        }
    end
  end

  defp build_verification_uri(conn) do
    scheme = Atom.to_string(conn.scheme)
    host = conn.host
    port = conn.port

    case port do
      nil -> "#{scheme}://#{host}/oauth/device"
      80 when scheme == "http" -> "#{scheme}://#{host}/oauth/device"
      443 when scheme == "https" -> "#{scheme}://#{host}/oauth/device"
      _ -> "#{scheme}://#{host}:#{port}/oauth/device"
    end
  end

  defp build_verification_uri_complete(conn, user_code) do
    "#{build_verification_uri(conn)}?user_code=#{user_code}"
  end
end
