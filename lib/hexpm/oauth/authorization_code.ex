defmodule Hexpm.OAuth.AuthorizationCode do
  use Hexpm.Schema

  alias Hexpm.Accounts.User

  @code_length 32
  @default_expires_in 60 * 10

  schema "authorization_codes" do
    field :code, :string
    field :redirect_uri, :string
    field :scopes, {:array, :string}, default: []
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime
    field :code_challenge, :string
    field :code_challenge_method, :string

    belongs_to :user, User
    field :client_id, :string

    timestamps()
  end

  @valid_scopes ~w(api api:read api:write repositories package)
  @valid_challenge_methods ~w(S256)

  def changeset(auth_code, attrs) do
    auth_code
    |> cast(attrs, [
      :code,
      :redirect_uri,
      :scopes,
      :expires_at,
      :used_at,
      :code_challenge,
      :code_challenge_method,
      :user_id,
      :client_id
    ])
    |> validate_required([:code, :redirect_uri, :scopes, :expires_at, :user_id, :client_id])
    |> validate_scopes()
    |> validate_code_challenge()
    |> unique_constraint(:code)
  end

  @doc """
  Creates a new authorization code.
  """
  def build(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end

  @doc """
  Generates a new authorization code.
  """
  def generate_code do
    :crypto.strong_rand_bytes(@code_length)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Creates an authorization code for a user with the given parameters.
  """
  def create_for_user(user, client_id, redirect_uri, scopes, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, @default_expires_in)
    expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

    attrs = %{
      code: generate_code(),
      redirect_uri: redirect_uri,
      scopes: scopes,
      expires_at: expires_at,
      user_id: user.id,
      client_id: client_id
    }

    # Add PKCE if provided
    attrs =
      case Keyword.get(opts, :code_challenge) do
        nil ->
          attrs

        challenge ->
          attrs
          |> Map.put(:code_challenge, challenge)
          |> Map.put(:code_challenge_method, Keyword.get(opts, :code_challenge_method, "S256"))
      end

    build(attrs)
  end

  @doc """
  Checks if the authorization code is expired.
  """
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Checks if the authorization code has been used.
  """
  def used?(%__MODULE__{used_at: nil}), do: false
  def used?(%__MODULE__{used_at: _}), do: true

  @doc """
  Checks if the authorization code is valid (not expired and not used).
  """
  def valid?(%__MODULE__{} = auth_code) do
    !expired?(auth_code) && !used?(auth_code)
  end

  @doc """
  Marks the authorization code as used.
  """
  def mark_as_used(%__MODULE__{} = auth_code) do
    changeset(auth_code, %{used_at: DateTime.utc_now()})
  end

  @doc """
  Validates the PKCE code verifier against the stored code challenge.
  Only supports S256 method for enhanced security.
  """
  def verify_code_challenge(%__MODULE__{code_challenge: nil}, _code_verifier), do: true

  def verify_code_challenge(
        %__MODULE__{code_challenge: challenge, code_challenge_method: "S256"},
        code_verifier
      ) do
    computed_challenge =
      :crypto.hash(:sha256, code_verifier)
      |> Base.url_encode64(padding: false)

    challenge == computed_challenge
  end

  # Private functions

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      invalid_scopes = Enum.reject(scopes, &(&1 in @valid_scopes))

      case invalid_scopes do
        [] -> []
        _ -> [scopes: "contains invalid scopes: #{Enum.join(invalid_scopes, ", ")}"]
      end
    end)
  end

  defp validate_code_challenge(changeset) do
    code_challenge = get_field(changeset, :code_challenge)
    code_challenge_method = get_field(changeset, :code_challenge_method)

    cond do
      is_nil(code_challenge) && is_nil(code_challenge_method) ->
        changeset

      is_nil(code_challenge) ->
        add_error(
          changeset,
          :code_challenge,
          "is required when code_challenge_method is specified"
        )

      is_nil(code_challenge_method) ->
        add_error(
          changeset,
          :code_challenge_method,
          "is required when code_challenge is specified"
        )

      code_challenge_method not in @valid_challenge_methods ->
        add_error(
          changeset,
          :code_challenge_method,
          "must be one of: #{Enum.join(@valid_challenge_methods, ", ")}"
        )

      true ->
        changeset
    end
  end
end
