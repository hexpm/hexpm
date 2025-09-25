defmodule Hexpm.OAuth.AuthorizationCodes do
  use Hexpm.Context

  alias Hexpm.OAuth.AuthorizationCode

  @code_length 32
  @default_expires_in 60 * 10

  @doc """
  Gets an authorization code by code and client_id.
  """
  def get_by_code(code, client_id) do
    Repo.get_by(AuthorizationCode, code: code, client_id: client_id)
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
      client_id: client_id,
      code_challenge: Keyword.fetch!(opts, :code_challenge),
      code_challenge_method: Keyword.get(opts, :code_challenge_method, "S256")
    }

    AuthorizationCode.build(attrs)
  end

  @doc """
  Creates and inserts an authorization code for a user.
  """
  def create_and_insert_for_user(user, client_id, redirect_uri, scopes, opts \\ []) do
    changeset = create_for_user(user, client_id, redirect_uri, scopes, opts)
    Repo.insert(changeset)
  end

  @doc """
  Marks the authorization code as used.
  """
  def mark_as_used(%AuthorizationCode{} = auth_code) do
    auth_code
    |> AuthorizationCode.mark_as_used()
    |> Repo.update()
  end

  @doc """
  Checks if the authorization code is expired.
  """
  def expired?(%AuthorizationCode{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Checks if the authorization code has been used.
  """
  def used?(%AuthorizationCode{used_at: nil}), do: false
  def used?(%AuthorizationCode{used_at: _}), do: true

  @doc """
  Checks if the authorization code is valid (not expired and not used).
  """
  def valid?(%AuthorizationCode{} = auth_code) do
    not expired?(auth_code) and not used?(auth_code)
  end

  @doc """
  Validates the PKCE code verifier against the stored code challenge.
  Only supports S256 method for enhanced security.
  """
  def verify_code_challenge(
        %AuthorizationCode{code_challenge: challenge, code_challenge_method: "S256"},
        code_verifier
      ) do
    computed_challenge =
      :crypto.hash(:sha256, code_verifier)
      |> Base.url_encode64(padding: false)

    challenge == computed_challenge
  end

  # Private functions

  defp generate_code do
    :crypto.strong_rand_bytes(@code_length)
    |> Base.url_encode64(padding: false)
  end
end
