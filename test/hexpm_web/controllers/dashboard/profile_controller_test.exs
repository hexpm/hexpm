defmodule HexpmWeb.Dashboard.ProfileControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test

  alias Hexpm.Accounts.{User, Users}

  defp add_email(user, email) do
    {:ok, user} = Users.add_email(user, %{email: email}, audit: audit_data(user))
    user
  end

  setup do
    %{
      user: insert(:user)
    }
  end

  test "show profile", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> get("dashboard/profile")

    assert response(conn, 200) =~ "Public profile"
  end

  test "requires login" do
    conn = get(build_conn(), "dashboard/profile")
    assert redirected_to(conn) == "/login?return=dashboard%2Fprofile"
  end

  test "update profile", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/profile", %{user: %{full_name: "New Name"}})

    assert redirected_to(conn) == "/dashboard/profile"
    assert get_flash(conn, :info) =~ "Profile updated successfully"
    assert Users.get(c.user.username).full_name == "New Name"
  end

  test "update profile change public email", c do
    original_email = hd(c.user.emails)
    user = add_email(c.user, "new@mail.com")
    email = Enum.find(user.emails, &(&1.email == "new@mail.com"))
    Ecto.Changeset.change(email, %{verified: true}) |> Hexpm.Repo.update!()

    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/profile", %{user: %{public_email: "new@mail.com"}})

    assert redirected_to(conn) == "/dashboard/profile"
    assert get_flash(conn, :info) =~ "Profile updated successfully"

    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    assert Enum.find(user.emails, &(&1.email == "new@mail.com")).public
    refute Enum.find(user.emails, &(&1.email == original_email.email)).public
  end

  test "update profile change gravatar email", c do
    user = add_email(c.user, "gravatar@mail.com")
    original_email = hd(c.user.emails)
    email = Enum.find(user.emails, &(&1.email == "gravatar@mail.com"))
    Ecto.Changeset.change(email, %{verified: true}) |> Hexpm.Repo.update!()

    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/profile", %{user: %{gravatar_email: "gravatar@mail.com"}})

    assert redirected_to(conn) == "/dashboard/profile"
    assert get_flash(conn, :info) =~ "Profile updated successfully"

    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    assert Enum.find(user.emails, &(&1.email == "gravatar@mail.com")).gravatar
    refute Enum.find(user.emails, &(&1.email == original_email.email)).gravatar
  end

  test "update profile don't show public email", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/profile", %{user: %{public_email: "none"}})

    assert redirected_to(conn) == "/dashboard/profile"
    assert get_flash(conn, :info) =~ "Profile updated successfully"
    refute Users.get(c.user.username, [:emails]) |> User.email(:public)
  end

  test "update profile with no emails", c do
    Hexpm.Repo.delete_all(Hexpm.Accounts.Email)

    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/profile", %{user: %{public_email: "none"}})

    assert redirected_to(conn) == "/dashboard/profile"
    assert get_flash(conn, :info) =~ "Profile updated successfully"
  end
end
