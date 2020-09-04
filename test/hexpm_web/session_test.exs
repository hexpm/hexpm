defmodule HexpmWeb.SessionTest do
  use HexpmWeb.ConnCase, async: true
  alias HexpmWeb.Session
  alias Hexpm.Accounts

  setup do
    %{
      user: insert(:user),
      conn: setup_conn()
    }
  end

  test "init/1" do
    assert HexpmWeb.Session.init([]) == []
  end

  describe "call/2" do
    test "when session is found", %{conn: conn, user: user} do
      assert %Plug.Conn{} = conn = Session.create(conn, user)
      assert <<session_id::binary>> = conn.private.plug_session["session_id"]

      conn =
        conn
        |> fetch_flash()
        |> Session.call([])

      assert conn.assigns.current_user.id == user.id
    end

    test "when session is not found", %{conn: conn, user: user} do
      assert %Plug.Conn{} = conn = Session.create(conn, user)
      assert <<session_id::binary>> = conn.private.plug_session["session_id"]
      assert %Plug.Conn{} = conn = Session.delete(conn)
      refute conn.private.plug_session["id"]

      conn
      |> fetch_flash()
      |> Session.call([])
      |> html_response(302)
    end

    test "when session is expired", %{conn: conn, user: user} do
      assert %Plug.Conn{} = conn = Session.create(conn, user)
      assert <<session_id::binary>> = conn.private.plug_session["session_id"]

      {:ok, session} = HexpmWeb.Session.get(session_id)

      conn
      |> get("/dashboard/security")
      |> html_response(200)

      update_expires_at(session, HexpmWeb.Session.max_age() * -1)

      conn
      |> get("/dashboard/security")
      |> html_response(302)
    end

    test "when db session does not exist", %{conn: conn, user: user} do
      assert %Plug.Conn{} = conn = Session.create(conn, user)
      assert <<session_id::binary>> = conn.private.plug_session["session_id"]
      {:ok, session} = HexpmWeb.Session.get(session_id)

      expire_session(session)

      conn
      |> fetch_flash()
      |> Session.call([])
      |> html_response(302)
    end

    test "when session id is invalid", %{conn: conn, user: user} do
      assert %Plug.Conn{} = conn = Session.create(conn, user)

      conn
      |> put_session("session_id", "42")
      |> fetch_flash()
      |> Session.call([])
      |> html_response(302)
    end

    test "when session token is invalid", %{conn: conn, user: user} do
      assert %Plug.Conn{} = conn = Session.create(conn, user)

      [session] = Repo.all(Accounts.Session)

      bad_session_str = session.uuid <> Base.url_encode64(:crypto.strong_rand_bytes(64))

      conn
      |> put_session("session_id", bad_session_str)
      |> fetch_flash()
      |> Session.call([])
      |> html_response(302)
    end
  end

  describe "create/1" do
    test "only expunges expired sessions for the user who is logging in", %{
      conn: conn,
      user: user
    } do
      data = %{
        expires_in: 0
      }

      # 3 expired sessions for user 1
      for _n <- 1..3, do: insert_session(user, data, Session.gen_token())

      user2 = insert(:user)

      # 3 expired sessions for user 2
      for _n <- 1..3, do: insert_session(user2, data, Session.gen_token())

      assert session_count() == 6

      assert %Plug.Conn{} = Session.create(conn, user)

      assert session_count() == 4
    end

    test "when session id not set", %{conn: conn, user: user} do
      assert %Plug.Conn{} = conn = Session.create(conn, user)
      assert <<session_id::binary>> = conn.private.plug_session["session_id"]
      assert %Plug.Conn{} = conn = Session.delete(clear_session(conn))
      refute conn.private.plug_session["session_id"]
      assert {:ok, _session} = Session.get(session_id)
    end
  end

  describe "delete/1" do
    test "when session exists", %{conn: conn, user: user} do
      assert %Plug.Conn{} = conn = Session.create(conn, user)
      assert <<session_id::binary>> = conn.private.plug_session["session_id"]
      assert %Plug.Conn{} = conn = Session.delete(conn)
      refute conn.private.plug_session["session_id"]
      assert {:error, :no_session} = Session.get(session_id)
    end

    test "when session id not set", %{conn: conn, user: user} do
      assert %Plug.Conn{} = conn = Session.create(conn, user)
      assert <<session_id::binary>> = conn.private.plug_session["session_id"]
      assert %Plug.Conn{} = conn = Session.delete(clear_session(conn))
      refute conn.private.plug_session["session_id"]
      assert {:ok, _session} = Session.get(session_id)
    end
  end

  describe "get/1" do
    test "existing session", %{user: user} do
      token = HexpmWeb.Session.gen_token()

      data = %{
        expires_in: 42
      }

      session = insert_session(user, data, token)
      session_id = HexpmWeb.Session.to_id(session, token)
      assert {:ok, %Accounts.Session{} = got_session} = HexpmWeb.Session.get(session_id)
      assert got_session.expires_at == session.expires_at
    end

    test "get/1 when session has_expired", %{user: user} do
      token = HexpmWeb.Session.gen_token()

      data = %{
        expires_in: 0
      }

      session = insert_session(user, data, token)

      session_id = HexpmWeb.Session.to_id(session, token)

      assert {:error, :expired} = HexpmWeb.Session.get(session_id)
    end
  end

  defp setup_conn() do
    build_conn()
    |> Plug.Test.init_test_session(%{})
    |> fetch_session()
    |> fetch_query_params()
    |> put_req_header("content-type", "text/html")
    |> put_req_header("user-agent", "eh?")
  end

  defp shift_expires_at(session, seconds) do
    DateTime.add(session.expires_at, seconds, :second)
  end

  defp update_expires_at(session, seconds) do
    expires_at = shift_expires_at(session, seconds)

    Repo.query!("UPDATE SESSIONS set expires_at = $1 where id = $2", [
      expires_at,
      session.id
    ])
  end

  defp session_count() do
    Accounts.Session
    |> Repo.all()
    |> Enum.count()
  end

  defp expire_session(session) do
    session
    |> Hexpm.Accounts.Session.expire()
    |> Repo.update!()
  end

  defp insert_session(user, params, token) do
    user
    |> Accounts.Session.build(params, token)
    |> Repo.insert!()
  end
end
