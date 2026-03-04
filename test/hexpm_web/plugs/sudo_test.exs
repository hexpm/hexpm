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

  describe "clear_sudo/1" do
    test "removes timestamp from session" do
      timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"sudo_authenticated_at" => timestamp})
        |> Sudo.clear_sudo()

      refute get_session(conn, "sudo_authenticated_at")
    end
  end

  describe "call/2" do
    test "allows request when sudo active" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> Sudo.call([])

      refute conn.halted
    end

    test "redirects to /sudo when not active" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> fetch_flash()
        |> Sudo.call([])

      assert conn.halted
      assert redirected_to(conn) == "/sudo"
      assert get_session(conn, "sudo_return_to") == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "verify your identity"
    end

    test "stores return path in session" do
      user = insert(:user)

      conn =
        build_conn(:get, "/dashboard/security")
        |> test_login(user, sudo: false)
        |> fetch_flash()
        |> Sudo.call([])

      assert get_session(conn, "sudo_return_to") == "/dashboard/security"
    end
  end
end
