defmodule Hexpm.OAuth.Token do
  use Hexpm.Schema
  import Ecto.Query

  alias Hexpm.Accounts.User
  alias Hexpm.Permissions
  alias Hexpm.Repo
  alias Hexpm.OAuth.Session

  @token_length 32
  @refresh_token_length 32
  @default_expires_in 30 * 60
  @default_refresh_token_expires_in 30 * 24 * 60 * 60
  @restricted_refresh_token_expires_in 60 * 60

  schema "oauth_tokens" do
    field :token_first, :string
    field :token_second, :string
    field :token_type, :string, default: "bearer"
    field :refresh_token_first, :string
    field :refresh_token_second, :string
    field :scopes, {:array, :string}, default: []
    field :expires_at, :utc_datetime
    field :refresh_token_expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :grant_type, :string
    field :grant_reference, :string

    # Virtual fields for raw tokens (not persisted)
    field :access_token, :string, virtual: true
    field :refresh_token, :string, virtual: true

    belongs_to :user, User
    belongs_to :parent_token, __MODULE__
    belongs_to :client, Hexpm.OAuth.Client, references: :client_id, type: :binary_id
    belongs_to :session, Session

    timestamps()
  end

  @valid_grant_types ~w(authorization_code urn:ietf:params:oauth:grant-type:device_code refresh_token urn:ietf:params:oauth:grant-type:token-exchange)

  def changeset(token, attrs) do
    token
    |> cast(attrs, [
      :token_first,
      :token_second,
      :token_type,
      :refresh_token_first,
      :refresh_token_second,
      :scopes,
      :expires_at,
      :refresh_token_expires_at,
      :revoked_at,
      :grant_type,
      :grant_reference,
      :parent_token_id,
      :session_id,
      :user_id,
      :client_id,
      :access_token,
      :refresh_token
    ])
    |> validate_required([
      :token_first,
      :token_second,
      :token_type,
      :scopes,
      :expires_at,
      :grant_type,
      :user_id,
      :client_id
    ])
    |> validate_inclusion(:grant_type, @valid_grant_types)
    |> validate_scopes()
    |> unique_constraint([:token_first, :token_second])
    |> unique_constraint([:refresh_token_first, :refresh_token_second])
  end

  @doc """
  Creates a new OAuth token.
  """
  def build(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end

  @doc """
  Generates a new access token with secure splitting.
  Returns {user_token, first_part, second_part}.
  """
  def generate_access_token do
    user_token = :crypto.strong_rand_bytes(@token_length) |> Base.url_encode64(padding: false)
    app_secret = Application.get_env(:hexpm, :secret)

    <<first::binary-size(32), second::binary-size(32)>> =
      :crypto.mac(:hmac, :sha256, app_secret, user_token)
      |> Base.encode16(case: :lower)

    {user_token, first, second}
  end

  @doc """
  Generates a new refresh token with secure splitting.
  Returns {user_token, first_part, second_part}.
  """
  def generate_refresh_token do
    user_token =
      :crypto.strong_rand_bytes(@refresh_token_length) |> Base.url_encode64(padding: false)

    app_secret = Application.get_env(:hexpm, :secret)

    <<first::binary-size(32), second::binary-size(32)>> =
      :crypto.mac(:hmac, :sha256, app_secret, user_token)
      |> Base.encode16(case: :lower)

    {user_token, first, second}
  end

  @doc """
  Creates a token for a user with the given client and scopes.
  Returns changeset with virtual fields set for raw token values.
  """
  def create_for_user(user, client_id, scopes, grant_type, grant_reference \\ nil, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, @default_expires_in)
    expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

    {user_token, token_first, token_second} = generate_access_token()

    attrs = %{
      token_first: token_first,
      token_second: token_second,
      access_token: user_token,
      scopes: scopes,
      expires_at: expires_at,
      grant_type: grant_type,
      grant_reference: grant_reference,
      user_id: user.id,
      client_id: client_id,
      session_id: Keyword.get(opts, :session_id),
      parent_token_id: Keyword.get(opts, :parent_token_id)
    }

    attrs =
      if Keyword.get(opts, :with_refresh_token, false) do
        {user_refresh_token, refresh_first, refresh_second} = generate_refresh_token()

        # Determine refresh token expiration based on scopes
        refresh_expires_in =
          if has_write_scope?(scopes) do
            @restricted_refresh_token_expires_in
          else
            @default_refresh_token_expires_in
          end

        refresh_expires_at = DateTime.add(DateTime.utc_now(), refresh_expires_in, :second)

        Map.merge(attrs, %{
          refresh_token_first: refresh_first,
          refresh_token_second: refresh_second,
          refresh_token: user_refresh_token,
          refresh_token_expires_at: refresh_expires_at
        })
      else
        attrs
      end

    build(attrs)
  end

  @doc """
  Checks if the token is expired.
  """
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Checks if the refresh token is expired.
  """
  def refresh_token_expired?(%__MODULE__{refresh_token_expires_at: nil}), do: false

  def refresh_token_expired?(%__MODULE__{refresh_token_expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Checks if the token is revoked.
  """
  def revoked?(%__MODULE__{revoked_at: nil}), do: false
  def revoked?(%__MODULE__{revoked_at: _}), do: true

  @doc """
  Checks if the token is valid (not expired and not revoked).
  """
  def valid?(%__MODULE__{} = token) do
    not expired?(token) and not revoked?(token)
  end

  @doc """
  Checks if the refresh token is valid (not expired and not revoked).
  """
  def refresh_token_valid?(%__MODULE__{} = token) do
    not refresh_token_expired?(token) and not revoked?(token)
  end

  @doc """
  Revokes the token. For backward compatibility, returns a changeset.
  Use revoke_token/1 for the new cascade logic.
  """
  def revoke(%__MODULE__{} = token) do
    changeset(token, %{revoked_at: DateTime.utc_now()})
  end

  @doc """
  Revokes the token. Individual tokens can be revoked without affecting the session.
  To revoke all tokens in a session, use Session.revoke/1.
  """
  def revoke_token(%__MODULE__{} = token) do
    token
    |> changeset(%{revoked_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Validates that the token has the required scopes.
  """
  def has_scopes?(%__MODULE__{scopes: token_scopes}, required_scopes) do
    Enum.all?(required_scopes, &(&1 in token_scopes))
  end

  @doc """
  Returns a token response suitable for OAuth responses using virtual fields.
  """
  def to_response(%__MODULE__{} = token) do
    expires_in = DateTime.diff(token.expires_at, DateTime.utc_now())

    response = %{
      access_token: token.access_token,
      token_type: token.token_type,
      expires_in: max(expires_in, 0),
      scope: Enum.join(token.scopes, " ")
    }

    if token.refresh_token,
      do: Map.put(response, :refresh_token, token.refresh_token),
      else: response
  end

  @doc """
  Looks up a token by its value, type, and optional constraints.

  ## Options
    * `:client_id` - Require token to belong to specific client
    * `:validate` - Check if token is valid (not expired/revoked), defaults to true
    * `:preload` - List of associations to preload, defaults to [:user]

  ## Returns
    * `{:ok, token}` - Token found and valid
    * `{:error, reason}` - Token not found, invalid, or validation failed
  """
  def lookup(user_token, type, opts \\ []) when type in [:access, :refresh] do
    client_id = Keyword.get(opts, :client_id)
    validate = Keyword.get(opts, :validate, true)
    preload = Keyword.get(opts, :preload, [:user])

    {first, second} = split_user_token(user_token)

    with {:ok, token} <- find_token_by_type(first, type, client_id),
         :ok <- secure_compare(token, second, type),
         :ok <- maybe_validate(token, validate),
         token <- maybe_preload(token, preload) do
      {:ok, token}
    end
  end

  @doc """
  Splits a user token into first and second parts using HMAC-SHA256.
  Returns {first, second} tuple where each part is 32 characters.
  """
  def split_user_token(user_token) do
    app_secret = Application.get_env(:hexpm, :secret)

    <<first::binary-size(32), second::binary-size(32)>> =
      :crypto.mac(:hmac, :sha256, app_secret, user_token)
      |> Base.encode16(case: :lower)

    {first, second}
  end

  defp find_token_by_type(first, :access, client_id) do
    query =
      if client_id do
        Repo.get_by(__MODULE__, token_first: first, client_id: client_id)
      else
        Repo.get_by(__MODULE__, token_first: first)
      end

    case query do
      nil -> {:error, :not_found}
      token -> {:ok, token}
    end
  end

  defp find_token_by_type(first, :refresh, client_id) do
    query =
      if client_id do
        Repo.get_by(__MODULE__, refresh_token_first: first, client_id: client_id)
      else
        Repo.get_by(__MODULE__, refresh_token_first: first)
      end

    case query do
      nil -> {:error, :not_found}
      token -> {:ok, token}
    end
  end

  defp secure_compare(token, second, :access) do
    if Hexpm.Utils.secure_check(token.token_second, second) do
      :ok
    else
      {:error, :invalid_token}
    end
  end

  defp secure_compare(token, second, :refresh) do
    if Hexpm.Utils.secure_check(token.refresh_token_second, second) do
      :ok
    else
      {:error, :invalid_token}
    end
  end

  defp maybe_validate(token, true) do
    if valid?(token) do
      :ok
    else
      {:error, :token_invalid}
    end
  end

  defp maybe_validate(_token, false), do: :ok

  defp maybe_preload(token, []), do: token
  defp maybe_preload(token, preload), do: Repo.preload(token, preload)

  @doc """
  Creates an exchanged token from a parent token with subset scopes.
  Always creates children of the root token to maintain a flat hierarchy.
  """
  def create_exchanged_token(parent_token, client_id, target_scopes, grant_reference) do
    # Find the root token (the one without a parent_token_id)
    root_token_id =
      if parent_token.parent_token_id do
        # If parent has a parent, use parent's parent (which should be the root)
        parent_token.parent_token_id
      else
        # Parent is already the root
        parent_token.id
      end

    opts = [
      session_id: parent_token.session_id,
      parent_token_id: root_token_id,
      expires_in: DateTime.diff(parent_token.expires_at, DateTime.utc_now()),
      with_refresh_token: not is_nil(parent_token.refresh_token_first)
    ]

    create_for_user(
      parent_token.user,
      client_id,
      target_scopes,
      "urn:ietf:params:oauth:grant-type:token-exchange",
      grant_reference,
      opts
    )
  end

  @doc """
  Cleans up expired OAuth tokens.

  This should be called periodically to remove old records.
  """
  def cleanup_expired_tokens do
    now = DateTime.utc_now()

    from(t in __MODULE__,
      where: t.expires_at < ^now and is_nil(t.revoked_at)
    )
    |> Repo.delete_all()
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      case Permissions.validate_scopes(scopes) do
        :ok -> []
        {:error, message} -> [scopes: message]
      end
    end)
  end

  @doc """
  Checks if the scopes include write permissions (api or api:write).
  """
  def has_write_scope?(scopes) do
    "api" in scopes or "api:write" in scopes
  end
end
