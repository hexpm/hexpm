defmodule HexpmWeb.Plugs.Sudo do
  @moduledoc """
  Plug that enforces sudo mode for sensitive operations.

  Sudo mode requires users to re-authenticate when accessing sensitive dashboard pages.
  The authentication duration is configured via `:hexpm, :sudo_timeout` and is
  automatically granted on login.

  On GET requests where sudo is active, a signed form token is stored in
  `conn.assigns.sudo_form_token`. Forms on sudo-protected pages should include
  this as a hidden field. On non-GET requests, the plug accepts either active
  sudo or a valid form token, so form submissions work even if sudo expires
  between page load and form submit.

  Pass `force: true` to require a fresh authentication (`:hexpm, :sudo_force_timeout`)
  regardless of the rolling sudo window — used for destructive pages like account
  deletion. The signed form token still covers non-GET submissions.

  Usage in controllers:
      plug HexpmWeb.Plugs.Sudo
      plug HexpmWeb.Plugs.Sudo, force: true
  """

  use HexpmWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  @behaviour Plug

  @token_salt "sudo_form_token"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    force? = Keyword.get(opts, :force, false)

    cond do
      disabled?() ->
        conn

      sudo_satisfied?(conn, force?) ->
        conn

      conn.method != "GET" and valid_form_token?(conn) ->
        conn

      true ->
        return_to =
          if conn.method == "GET" do
            full_request_path(conn)
          end

        conn
        |> put_force_flag(force?)
        |> redirect_to_sudo(return_to)
        |> halt()
    end
  end

  @spec sudo_satisfied?(Plug.Conn.t(), boolean()) :: boolean()
  defp sudo_satisfied?(conn, false), do: sudo_active?(conn)
  defp sudo_satisfied?(conn, true), do: sudo_fresh?(conn)

  @spec put_force_flag(Plug.Conn.t(), boolean()) :: Plug.Conn.t()
  defp put_force_flag(conn, true), do: put_session(conn, "sudo_force", true)
  defp put_force_flag(conn, false), do: conn

  @doc """
  Redirects to the sudo verification page with a return URL.

  This can be used directly in controllers when manual sudo checks are needed:

      if not Sudo.sudo_active?(conn) do
        Sudo.redirect_to_sudo(conn, ~p"/some/path")
      end
  """
  @spec redirect_to_sudo(Plug.Conn.t(), String.t() | nil) :: Plug.Conn.t()
  def redirect_to_sudo(conn, return_to) do
    conn =
      if return_to do
        put_session(conn, "sudo_return_to", return_to)
      else
        conn
      end

    redirect(conn, to: ~p"/sudo")
  end

  @spec full_request_path(Plug.Conn.t()) :: String.t()
  defp full_request_path(conn) do
    case conn.query_string do
      "" -> conn.request_path
      qs -> conn.request_path <> "?" <> qs
    end
  end

  @spec sudo_active?(Plug.Conn.t()) :: boolean()
  def sudo_active?(conn) do
    authenticated_within?(conn, sudo_timeout())
  end

  @spec sudo_fresh?(Plug.Conn.t()) :: boolean()
  def sudo_fresh?(conn) do
    authenticated_within?(conn, sudo_force_timeout())
  end

  @spec authenticated_within?(Plug.Conn.t(), Duration.t()) :: boolean()
  defp authenticated_within?(conn, duration) do
    case get_session(conn, "sudo_authenticated_at") do
      nil ->
        false

      timestamp_string ->
        case NaiveDateTime.from_iso8601(timestamp_string) do
          {:ok, authenticated_at} ->
            expires_at = NaiveDateTime.shift(authenticated_at, duration)
            NaiveDateTime.compare(NaiveDateTime.utc_now(), expires_at) == :lt

          _ ->
            false
        end
    end
  end

  @spec sudo_timeout() :: Duration.t()
  defp sudo_timeout do
    Application.fetch_env!(:hexpm, :sudo_timeout)
  end

  @spec disabled?() :: boolean()
  defp disabled? do
    Application.get_env(:hexpm, :sudo, true) == false
  end

  @spec sudo_force_timeout() :: Duration.t()
  defp sudo_force_timeout do
    Application.fetch_env!(:hexpm, :sudo_force_timeout)
  end

  @spec set_sudo_authenticated(Plug.Conn.t()) :: Plug.Conn.t()
  def set_sudo_authenticated(conn) do
    put_session(
      conn,
      "sudo_authenticated_at",
      NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601()
    )
  end

  def clear_sudo_authentication(conn) do
    Enum.reduce(
      ~w(sudo_authenticated_at sudo_force sudo_verification sudo_return_to),
      conn,
      &delete_session(&2, &1)
    )
  end

  @doc """
  Generates a signed sudo form token for the given method and action.

  The token binds to the current user, the HTTP method, and the form action path,
  so it can only be used for the specific endpoint the form targets.
  """
  @spec generate_form_token(integer(), String.t(), String.t()) :: String.t()
  def generate_form_token(user_id, method, action) do
    Phoenix.Token.sign(HexpmWeb.Endpoint, @token_salt, {user_id, method, action})
  end

  @spec valid_form_token?(Plug.Conn.t()) :: boolean()
  defp valid_form_token?(conn) do
    case conn.params["_sudo_token"] do
      token when is_binary(token) ->
        case Phoenix.Token.verify(HexpmWeb.Endpoint, @token_salt, token, max_age: :infinity) do
          {:ok, {user_id, method, action}} ->
            user_id == conn.assigns.current_user.id and
              method == conn.method and
              action == conn.request_path

          _ ->
            false
        end

      _ ->
        false
    end
  end
end
