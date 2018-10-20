defmodule HexpmWeb.SignupControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Accounts.Users

  setup do
    %{user: create_user("eric", "eric@mail.com", "hunter42")}
  end

  test "show create user page" do
    conn = get(build_conn(), "signup")
    assert response(conn, 200) =~ "Sign up"
  end

  test "create user" do
    conn =
      post(build_conn(), "signup", %{
        user: %{
          username: "jose",
          emails: [%{email: "jose@mail.com"}],
          password: "hunter42",
          full_name: "José"
        }
      })

    assert redirected_to(conn) == "/"
    user = Users.get("jose")
    assert user.username == "jose"
    assert user.full_name == "José"
  end

  test "create user invalid" do
    conn =
      post(build_conn(), "signup", %{
        user: %{
          username: "eric",
          emails: [%{email: "jose@mail.com"}],
          password: "hunter42",
          full_name: "José"
        }
      })

    assert response(conn, 400) =~ "Sign up"
    assert conn.resp_body =~ "Oops, something went wrong!"
  end
end
