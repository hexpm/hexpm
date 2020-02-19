defmodule HexpmWeb.Dashboard.PasswordControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test

  alias Hexpm.Accounts.Auth

  setup do
    mock_pwned()

    %{
      user: insert(:user)
    }
  end

  test "show password", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> get("dashboard/password")

    assert response(conn, 200) =~ "Change password"
  end

  test "requires login" do
    conn = get(build_conn(), "dashboard/password")
    assert redirected_to(conn) == "/login?return=dashboard%2Fpassword"
  end

  test "update password", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/password", %{
        user: %{
          password_current: "password",
          password: "newpass",
          password_confirmation: "newpass"
        }
      })

    assert redirected_to(conn) == "/dashboard/password"
    assert get_flash(conn, :info) =~ "Your password has been updated"
    assert {:ok, _} = Auth.password_auth(c.user.username, "newpass")
    assert :error = Auth.password_auth(c.user.username, "password")

    assert_delivered_email(Hexpm.Emails.password_changed(c.user))
  end

  test "update password invalid current password", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/password", %{
        user: %{password_current: "WRONG", password: "newpass", password_confirmation: "newpass"}
      })

    assert response(conn, 400) =~ "Change password"
    assert {:ok, _} = Auth.password_auth(c.user.username, "password")
  end

  test "update password invalid confirmation password", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/password", %{
        user: %{password_current: "password", password: "newpass", password_confirmation: "WRONG"}
      })

    assert response(conn, 400) =~ "Change password"
    assert {:ok, _} = Auth.password_auth(c.user.username, "password")
    assert :error = Auth.password_auth(c.user.username, "newpass")
  end

  test "update password missing current password", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/password", %{
        user: %{password: "newpass", password_confirmation: "newpass"}
      })

    assert response(conn, 400) =~ "Change password"
    assert {:ok, _} = Auth.password_auth(c.user.username, "password")
    assert :error = Auth.password_auth(c.user.username, "newpass")
  end
end
