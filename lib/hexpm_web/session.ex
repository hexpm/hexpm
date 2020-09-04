defmodule HexpmWeb.Session do
  import Plug.Conn

  alias Hexpm.Accounts.{Session, User}
  alias Hexpm.Repo
  alias HexpmWeb.Router.Helpers, as: Routes
  require Logger

  defdelegate redirect(conn, params), to: Phoenix.Controller
  defdelegate put_flash(conn, atom, message), to: Phoenix.Controller

  @type token() :: <<_::64>>
  @type session_id() :: binary()

  # Plug interface for authenticated areas
  @spec init(Keyword.t()) :: Keyword.t()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case get_session(conn, "session_id") do
      nil ->
        not_found(conn)

      session_id ->
        setup_session(conn, session_id)
    end
  end

  # Serializer for Plug.Session
  @spec encode(term()) :: {:ok, String.t()} | {:error, Jason.EncodeError.t() | Exception.t()}
  def encode(val), do: Jason.encode(val)

  @spec decode(String.t()) :: {:ok, term()} | {:error, Jason.DecodeError.t()}
  def decode(val), do: Jason.decode(val)

  # General Public API
  def gen_token(), do: :crypto.strong_rand_bytes(64)

  @spec get(String.t() | nil) ::
          {:ok, Session.t()} | {:error, :expired | :no_session | :invalid_token}
  def get(nil), do: {:error, :no_session}

  def get(session_id) do
    with {:ok, {id, token}} <- parse_session_str(session_id),
         {:ok, session} <- get_active_session(id),
         {:ok, session} <- validate_token(session, token) do
      maybe_expire(session)
    end
  end

  @spec delete(Plug.Conn.t()) :: Plug.Conn.t()
  def delete(conn) do
    with <<session_str::binary>> <- get_session(conn, "session_id"),
         {:ok, {id, _token}} <- parse_session_str(session_str),
         {:ok, session} <- get_active_session(id),
         {:ok, :expired} <- expire(session) do
      clear_and_drop(conn)
    else
      _ ->
        clear_and_drop(conn)
    end
  end

  @spec create(Plug.Conn.t(), User.t()) :: Plug.Conn.t()
  def create(conn, user) do
    token = gen_token()

    data = %{
      expires_in: max_age()
    }

    session =
      user
      |> Session.build(data, token)
      |> Repo.insert!()

    # Prune the table when we can until a concurrent session strategy (possibly non-concurrent), 
    # auditing capablities, and a sweeper job has been devised.
    user
    |> Session.all_inactive_by_user()
    |> Repo.delete_all()

    conn
    |> configure_session(renew: true)
    |> put_session(:session_id, to_id(session, token))
    |> assign(:current_user, user)
    |> assign(:current_organization, nil)
  end

  @spec max_age() :: pos_integer()
  def max_age(), do: 60 * 60 * 24 * 30

  def to_id(session, token) when byte_size(token) == 64 do
    "#{session.uuid}#{Base.url_encode64(token)}"
  end

  def to_id(_, _), do: {:error, :invalid_session_token}

  # Private API

  defp get_active_session(id) do
    case Repo.one(Session.get_active(id)) do
      nil ->
        {:error, :no_session}

      session ->
        {:ok, session}
    end
  end

  defp clear_and_drop(conn) do
    conn
    |> clear_session()
    |> configure_session(drop: true)
  end

  defp expire(nil), do: {:error, :no_session}

  defp expire(%Session{} = session) do
    session
    |> Session.expire()
    |> Repo.delete!()
  end

  defp hash_token(token), do: :crypto.hash(:sha256, token)

  defp parse_session_str(session_str) do
    with {:ok, {id, base64}} <- parse_id(session_str),
         {:ok, token} <- decode_token(base64) do
      {:ok, {id, token}}
    end
  end

  defp parse_id(<<uuid::binary-size(36), base64::binary-size(88)>>) do
    {:ok, {uuid, base64}}
  end

  defp parse_id(_), do: {:error, :invalid_session_id}

  defp decode_token(base64) do
    case Base.url_decode64(base64) do
      {:ok, _token} = return ->
        return

      _ ->
        {:error, :invalid_session_token}
    end
  end

  defp maybe_expire(session) do
    now = DateTime.utc_now()

    case DateTime.compare(now, session.expires_at) do
      :lt ->
        {:ok, session}

      :gt ->
        expire(session)
        {:error, :expired}
    end
  end

  defp validate_token(%Session{} = session, token) when byte_size(token) == 64 do
    case Plug.Crypto.secure_compare(hash_token(token), session.token_hash) do
      true ->
        {:ok, session}

      false ->
        {:error, :invalid_token}
    end
  end

  defp validate_token(_, _), do: {:error, :invalid_token}

  defp setup_session(conn, id) do
    case get(id) do
      {:error, :no_session} ->
        not_found(conn)

      {:error, :invalid_session_id} ->
        not_found(conn)

      {:error, :invalid_token} ->
        not_found(conn)

      {:error, :expired} ->
        expired(conn)

      {:ok, session} ->
        conn
        |> assign(:current_user, session.user)
        |> assign(:current_organization, session.user.organization)
        |> configure_session(renew: true)
    end
  end

  defp not_found(conn) do
    conn
    |> clear_session()
    |> configure_session(renew: true)
    |> put_flash(:error, "You must be signed in to access that page.")
    |> put_return()
    |> halt()
  end

  defp expired(conn) do
    conn
    |> clear_session()
    |> configure_session(renew: true)
    |> put_flash(:error, "Your session has expired. Please sign back in.")
    |> put_return()
    |> halt()
  end

  defp put_return(conn) do
    redirect(conn, to: Routes.login_path(conn, :show, return: conn.request_path))
  end
end
