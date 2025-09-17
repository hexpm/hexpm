defmodule Hexpm.OAuth.Token do
  use Hexpm.Schema

  alias Hexpm.Accounts.User
  alias Hexpm.Permissions

  @token_length 32
  @refresh_token_length 32
  @default_expires_in 60 * 60

  schema "oauth_tokens" do
    field :token_first, :string
    field :token_second, :string
    field :token_hash, :string
    field :token_type, :string, default: "bearer"
    field :refresh_token_first, :string
    field :refresh_token_second, :string
    field :refresh_token_hash, :string
    field :scopes, {:array, :string}, default: []
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :grant_type, :string
    field :grant_reference, :string

    belongs_to :user, User
    field :client_id, :string

    timestamps()
  end

  @valid_grant_types ~w(authorization_code urn:ietf:params:oauth:grant-type:device_code refresh_token)

  def changeset(token, attrs) do
    token
    |> cast(attrs, [
      :token_first,
      :token_second,
      :token_hash,
      :token_type,
      :refresh_token_first,
      :refresh_token_second,
      :refresh_token_hash,
      :scopes,
      :expires_at,
      :revoked_at,
      :grant_type,
      :grant_reference,
      :user_id,
      :client_id
    ])
    |> validate_required([
      :token_first,
      :token_second,
      :token_hash,
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
  """
  def create_for_user(user, client_id, scopes, grant_type, grant_reference \\ nil, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, @default_expires_in)
    expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

    {user_token, token_first, token_second} = generate_access_token()

    attrs = %{
      token_first: token_first,
      token_second: token_second,
      token_hash: user_token,
      scopes: scopes,
      expires_at: expires_at,
      grant_type: grant_type,
      grant_reference: grant_reference,
      user_id: user.id,
      client_id: client_id
    }

    attrs =
      if Keyword.get(opts, :with_refresh_token, false) do
        {user_refresh_token, refresh_first, refresh_second} = generate_refresh_token()

        Map.merge(attrs, %{
          refresh_token_first: refresh_first,
          refresh_token_second: refresh_second,
          refresh_token_hash: user_refresh_token
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
  Revokes the token.
  """
  def revoke(%__MODULE__{} = token) do
    changeset(token, %{revoked_at: DateTime.utc_now()})
  end

  @doc """
  Validates that the token has the required scopes.
  """
  def has_scopes?(%__MODULE__{scopes: token_scopes}, required_scopes) do
    Enum.all?(required_scopes, &(&1 in token_scopes))
  end

  @doc """
  Returns a token response suitable for OAuth responses.
  """
  def to_response(%__MODULE__{} = token) do
    expires_in = DateTime.diff(token.expires_at, DateTime.utc_now())

    response = %{
      access_token: token.token_hash,
      token_type: token.token_type,
      expires_in: max(expires_in, 0),
      scope: Enum.join(token.scopes, " ")
    }

    if token.refresh_token_hash do
      Map.put(response, :refresh_token, token.refresh_token_hash)
    else
      response
    end
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      case Permissions.validate_scopes(scopes) do
        :ok -> []
        {:error, message} -> [scopes: message]
      end
    end)
  end
end
