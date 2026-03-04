defmodule HexpmWeb.Plugs.Sudo do
  @moduledoc """
  Plug that enforces sudo mode for sensitive operations.

  Sudo mode requires users to re-authenticate when accessing sensitive dashboard pages.
  The authentication duration is configured via `:hexpm, :sudo_timeout` and is
  automatically granted on login.

  Usage in controllers:
      plug HexpmWeb.Plugs.Sudo when action in [:change_password, :disable_tfa]
  """

  use HexpmWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if sudo_active?(conn) do
      conn
    else
      conn
      |> put_session("sudo_return_to", conn.request_path)
      |> put_flash(:info, "Please verify your identity to continue.")
      |> redirect(to: ~p"/sudo")
      |> halt()
    end
  end

  @spec sudo_active?(Plug.Conn.t()) :: boolean()
  def sudo_active?(conn) do
    case get_session(conn, "sudo_authenticated_at") do
      nil ->
        false

      timestamp_string ->
        case NaiveDateTime.from_iso8601(timestamp_string) do
          {:ok, authenticated_at} ->
            expires_at = NaiveDateTime.shift(authenticated_at, sudo_timeout())
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

  @spec set_sudo_authenticated(Plug.Conn.t()) :: Plug.Conn.t()
  def set_sudo_authenticated(conn) do
    put_session(
      conn,
      "sudo_authenticated_at",
      NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601()
    )
  end

  @spec clear_sudo(Plug.Conn.t()) :: Plug.Conn.t()
  def clear_sudo(conn) do
    delete_session(conn, "sudo_authenticated_at")
  end
end
