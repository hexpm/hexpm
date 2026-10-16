defmodule HexpmWeb.Dashboard.ProfileControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Accounts.{Organizations, User, Users}

  defp add_email(user, email) do
    {:ok, user} = Users.add_email(user, %{email: email}, audit: audit_data(user))
    user
  end

  setup do
    %{
      user: insert(:user)
    }
  end

  describe "organization membership visibility" do
    test "lists the account's organizations with their switches", c do
      organization = insert(:organization)
      insert(:organization_user, organization: organization, user: c.user, public: true)

      html =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/profile")
        |> html_response(200)

      assert html =~ ~s(id="membership-visibility-#{organization.name}")
      assert html =~ ~s(action="/dashboard/profile/organizations/#{organization.name}")
    end

    test "leaves the section out for an account without organizations", c do
      html =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/profile")
        |> html_response(200)

      refute html =~ ~s(id="membership-visibility")
    end

    test "lists and unlists the account's own membership", c do
      organization = insert(:organization)
      insert(:organization_user, organization: organization, user: c.user)

      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/profile/organizations/#{organization.name}", %{
          "organization_user" => %{"public" => "true"}
        })

      assert redirected_to(conn) == "/dashboard/profile"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Your membership in #{organization.name} is public."

      assert [%{id: id}] = Organizations.public_members(organization)
      assert id == c.user.id

      for path <- ["/users/#{c.user.username}", "/users/#{c.user.username}/stats"] do
        html = build_conn() |> get(path) |> html_response(200)
        assert html =~ ~s(href="/orgs/#{organization.name}")
      end

      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/profile/organizations/#{organization.name}", %{
          "organization_user" => %{"public" => "false"}
        })

      assert redirected_to(conn) == "/dashboard/profile"
      assert Organizations.public_members(organization) == []

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Your membership in #{organization.name} is hidden."

      for path <- ["/users/#{c.user.username}", "/users/#{c.user.username}/stats"] do
        html = build_conn() |> get(path) |> html_response(200)
        refute html =~ ~s(id="user-organizations")
        refute html =~ ~s(href="/orgs/#{organization.name}")
      end
    end

    test "can't change another member's listing", c do
      organization = insert(:organization)
      insert(:organization_user, organization: organization, user: c.user, role: "admin")
      other = insert(:user)
      insert(:organization_user, organization: organization, user: other)

      build_conn()
      |> test_login(c.user)
      |> post("/dashboard/profile/organizations/#{organization.name}", %{
        "organization_user" => %{"public" => "true", "user_id" => other.id},
        "user_id" => other.id
      })

      assert Enum.map(Organizations.public_members(organization), & &1.id) == [c.user.id]
    end

    test "is not found for an organization the account isn't a member of", c do
      organization = insert(:organization)

      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/profile/organizations/#{organization.name}", %{
          "organization_user" => %{"public" => "true"}
        })

      assert response(conn, 404)
      assert Organizations.public_members(organization) == []
    end
  end

  test "show profile", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> get("/dashboard/profile")

    assert response(conn, 200) =~ "Public profile"
  end

  test "does not show pending section when there are no invites", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> get("/dashboard/profile")

    refute response(conn, 200) =~ "Pending package invitations"
  end

  test "requires login" do
    conn = get(build_conn(), "/dashboard/profile")
    assert redirected_to(conn) == "/login?return=%2Fdashboard%2Fprofile"
  end

  test "sends a user with an unverified primary email to the email page" do
    user = insert(:user, emails: [build(:email, verified: false)])

    conn =
      build_conn()
      |> test_login(user)
      |> get("/dashboard/profile")

    assert redirected_to(conn) == "/dashboard/email"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Verify your primary email before editing your public profile."
  end

  test "does not update the profile of a user with an unverified primary email" do
    user = insert(:user, emails: [build(:email, verified: false)])

    conn =
      build_conn()
      |> test_login(user)
      |> post("/dashboard/profile", %{
        user: %{full_name: "New Name", handles: %{url: "https://example.com"}}
      })

    assert redirected_to(conn) == "/dashboard/email"

    user = Hexpm.Repo.get!(User, user.id)
    refute user.full_name == "New Name"
    refute user.handles && user.handles.url
  end

  test "update profile", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> post("/dashboard/profile", %{user: %{full_name: "New Name"}})

    assert redirected_to(conn) == "/dashboard/profile"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Profile updated successfully"
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
      |> post("/dashboard/profile", %{user: %{public_email: "new@mail.com"}})

    assert redirected_to(conn) == "/dashboard/profile"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Profile updated successfully"

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
      |> post("/dashboard/profile", %{user: %{gravatar_email: "gravatar@mail.com"}})

    assert redirected_to(conn) == "/dashboard/profile"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Profile updated successfully"

    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    assert Enum.find(user.emails, &(&1.email == "gravatar@mail.com")).gravatar
    refute Enum.find(user.emails, &(&1.email == original_email.email)).gravatar
  end

  test "update profile don't show public email", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> post("/dashboard/profile", %{user: %{public_email: "none"}})

    assert redirected_to(conn) == "/dashboard/profile"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Profile updated successfully"
    refute Users.get(c.user.username, [:emails]) |> User.email(:public)
  end

  test "update profile with no public email", c do
    Hexpm.Repo.update_all(Hexpm.Accounts.Email, set: [public: false])

    conn =
      build_conn()
      |> test_login(c.user)
      |> post("/dashboard/profile", %{user: %{public_email: "none"}})

    assert redirected_to(conn) == "/dashboard/profile"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Profile updated successfully"
  end
end
