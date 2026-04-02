defmodule HexpmWeb.Plugs.SudoTest do
  use HexpmWeb.ConnCase, async: true

  alias HexpmWeb.Plugs.Sudo

  describe "sudo_active?/1" do
    test "returns false with no timestamp" do
      conn = build_conn() |> Plug.Test.init_test_session(%{})
      refute Sudo.sudo_active?(conn)
    end

    test "returns true with recent timestamp" do
      timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601()
      conn = build_conn() |> Plug.Test.init_test_session(%{"sudo_authenticated_at" => timestamp})
      assert Sudo.sudo_active?(conn)
    end

    test "returns false with expired timestamp (>1 hour)" do
      timestamp =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-3601, :second)
        |> NaiveDateTime.to_iso8601()

      conn = build_conn() |> Plug.Test.init_test_session(%{"sudo_authenticated_at" => timestamp})
      refute Sudo.sudo_active?(conn)
    end

    test "returns false with invalid timestamp" do
      conn = build_conn() |> Plug.Test.init_test_session(%{"sudo_authenticated_at" => "invalid"})
      refute Sudo.sudo_active?(conn)
    end
  end

  describe "set_sudo_authenticated/1" do
    test "sets timestamp in session" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> Sudo.set_sudo_authenticated()

      timestamp = get_session(conn, "sudo_authenticated_at")
      assert timestamp
      assert {:ok, _datetime} = NaiveDateTime.from_iso8601(timestamp)
    end
  end

  describe "call/2" do
    test "allows GET request when sudo active" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> Sudo.call([])

      refute conn.halted
    end

    test "redirects GET to /sudo when not active" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> fetch_flash()
        |> Sudo.call([])

      assert conn.halted
      assert redirected_to(conn) == "/sudo"
      assert get_session(conn, "sudo_return_to") == "/"
    end

    test "stores return path in session for GET requests" do
      user = insert(:user)

      conn =
        build_conn(:get, "/dashboard/security")
        |> test_login(user, sudo: false)
        |> fetch_flash()
        |> Sudo.call([])

      assert get_session(conn, "sudo_return_to") == "/dashboard/security"
    end

    test "does not store return path for POST requests" do
      user = insert(:user)

      conn =
        build_conn(:post, "/dashboard/security/verify-tfa-code", %{})
        |> test_login(user, sudo: false)
        |> fetch_flash()
        |> Sudo.call([])

      assert conn.halted
      assert redirected_to(conn) == "/sudo"
      refute get_session(conn, "sudo_return_to")
    end
  end

  describe "form token" do
    test "allows POST with valid form token when sudo expired" do
      user = insert(:user)

      token =
        Sudo.generate_form_token(user.id, "POST", "/dashboard/security/change-password")

      conn =
        build_conn(:post, "/dashboard/security/change-password", %{
          "_sudo_token" => token
        })
        |> test_login(user, sudo: false)
        |> Plug.Conn.assign(:current_user, user)
        |> Sudo.call([])

      refute conn.halted
    end

    test "rejects form token for wrong path" do
      user = insert(:user)

      token =
        Sudo.generate_form_token(user.id, "POST", "/dashboard/security/change-password")

      conn =
        build_conn(:post, "/dashboard/security/disable-tfa", %{"_sudo_token" => token})
        |> test_login(user, sudo: false)
        |> Plug.Conn.assign(:current_user, user)
        |> fetch_flash()
        |> Sudo.call([])

      assert conn.halted
    end

    test "rejects form token for wrong user" do
      user1 = insert(:user)
      user2 = insert(:user)

      token = Sudo.generate_form_token(user1.id, "POST", "/dashboard/security/change-password")

      conn =
        build_conn(:post, "/dashboard/security/change-password", %{"_sudo_token" => token})
        |> test_login(user2, sudo: false)
        |> Plug.Conn.assign(:current_user, user2)
        |> fetch_flash()
        |> Sudo.call([])

      assert conn.halted
    end

    test "rejects form token for wrong method" do
      user = insert(:user)

      token =
        Sudo.generate_form_token(user.id, "POST", "/dashboard/keys")

      conn =
        build_conn(:delete, "/dashboard/keys", %{"_sudo_token" => token})
        |> test_login(user, sudo: false)
        |> Plug.Conn.assign(:current_user, user)
        |> fetch_flash()
        |> Sudo.call([])

      assert conn.halted
    end
  end
end
