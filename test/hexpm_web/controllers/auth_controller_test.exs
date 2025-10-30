defmodule HexpmWeb.AuthControllerTest do
  use HexpmWeb.ConnCase

  alias Hexpm.Accounts.{Users, UserProviders}

  setup do
    mock_pwned()
    :ok
  end

  describe "GET /auth/github/callback - GitHub signup (new user)" do
    test "redirects to username selection form" do
      email = Hexpm.Fake.sequence(:email)
      username = Hexpm.Fake.sequence(:username)
      name = Hexpm.Fake.sequence(:full_name)

      conn =
        build_conn()
        |> mock_github_auth_success("12345", email,
          name: name,
          nickname: username
        )
        |> HexpmWeb.AuthController.callback(%{})

      # Should redirect to username selection form
      assert redirected_to(conn) == "/auth/complete-signup"

      # OAuth data should be stored in session
      pending_oauth = get_session(conn, "pending_oauth")
      assert pending_oauth
      assert pending_oauth[:provider] == "github"
      assert pending_oauth[:provider_uid] == "12345"
      assert pending_oauth[:provider_email] == email
      assert pending_oauth[:provider_name] == name
      assert pending_oauth[:provider_nickname] == username

      # User should NOT be created yet
      refute Users.get(username)
    end

    test "stores OAuth data for user with empty nickname" do
      email = Hexpm.Fake.sequence(:email)
      name = Hexpm.Fake.sequence(:full_name)

      conn =
        build_conn()
        |> mock_github_auth_success("54321", email,
          name: name,
          nickname: ""
        )
        |> HexpmWeb.AuthController.callback(%{})

      assert redirected_to(conn) == "/auth/complete-signup"

      pending_oauth = get_session(conn, "pending_oauth")
      assert pending_oauth
      assert pending_oauth[:provider_nickname] == ""

      # User should NOT be created yet
      refute UserProviders.get_by_provider("github", "54321")
    end
  end

  describe "GET /auth/github/callback - GitHub login (existing user)" do
    test "logs in existing user with GitHub provider" do
      email = Hexpm.Fake.sequence(:email)
      user = insert(:user)
      insert(:user_provider, user: user, provider: "github", provider_uid: "67890")

      conn =
        build_conn()
        |> mock_github_auth_success("67890", email)
        |> HexpmWeb.AuthController.callback(%{})

      assert redirected_to(conn) == "/users/#{user.username}"
      assert get_session(conn, "user_id") == user.id
    end

    test "redirects to TFA when user has TFA enabled" do
      email = Hexpm.Fake.sequence(:email)
      user = insert(:user_with_tfa)
      insert(:user_provider, user: user, provider: "github", provider_uid: "99999")

      conn =
        build_conn()
        |> mock_github_auth_success("99999", email)
        |> HexpmWeb.AuthController.callback(%{})

      assert redirected_to(conn) == "/tfa"
      assert get_session(conn, "tfa_user_id") == %{uid: user.id, return: nil}
    end
  end

  describe "GET /auth/github/callback - Email conflicts" do
    test "shows error when email already exists for different user" do
      existing_user = insert(:user)
      email = hd(existing_user.emails).email
      name = Hexpm.Fake.sequence(:full_name)
      username = Hexpm.Fake.sequence(:username)

      conn =
        build_conn()
        |> mock_github_auth_success("11111", email,
          name: name,
          nickname: username
        )
        |> HexpmWeb.AuthController.callback(%{})

      assert redirected_to(conn) == "/login"

      assert Phoenix.Flash.get(conn.assigns.flash, "error") =~
               "An account with email #{email} already exists"
    end
  end

  describe "GET /auth/github/callback - Link to logged-in user" do
    test "links GitHub to currently logged-in user" do
      email = Hexpm.Fake.sequence(:email)
      user = insert(:user)

      conn =
        build_conn()
        |> mock_github_auth_success("22222", email)
        |> Plug.Conn.assign(:current_user, user)
        |> HexpmWeb.AuthController.callback(%{})

      assert redirected_to(conn) == "/dashboard/security"

      assert Phoenix.Flash.get(conn.assigns.flash, "info") ==
               "GitHub account successfully connected."

      user_provider = UserProviders.get_by_provider("github", "22222")
      assert user_provider
      assert user_provider.user_id == user.id
    end

    test "shows error when linking fails" do
      email = Hexpm.Fake.sequence(:email)
      user = insert(:user)
      # Create provider with same uid for different user
      other_user = insert(:user)
      insert(:user_provider, user: other_user, provider: "github", provider_uid: "33333")

      conn =
        build_conn()
        |> mock_github_auth_success("33333", email)
        |> Plug.Conn.assign(:current_user, user)
        |> HexpmWeb.AuthController.callback(%{})

      assert redirected_to(conn) == "/dashboard/security"
      assert Phoenix.Flash.get(conn.assigns.flash, "error") == "Failed to connect GitHub account."
    end
  end

  describe "GET /auth/github/callback - Failed authentication" do
    test "redirects to login with error message" do
      conn =
        build_conn()
        |> mock_github_auth_failure()
        |> HexpmWeb.AuthController.callback(%{})

      assert redirected_to(conn) == "/login"

      assert Phoenix.Flash.get(conn.assigns.flash, "error") ==
               "Failed to authenticate with GitHub."
    end
  end

  describe "GET /auth/complete-signup - Username selection form" do
    test "shows form with suggested username" do
      email = Hexpm.Fake.sequence(:email)
      username = Hexpm.Fake.sequence(:username)
      name = Hexpm.Fake.sequence(:full_name)

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "pending_oauth" => %{
            provider: "github",
            provider_uid: "12345",
            provider_email: email,
            provider_name: name,
            provider_nickname: username
          }
        })
        |> get("/auth/complete-signup")

      assert html_response(conn, 200) =~ "Complete your signup"
      assert html_response(conn, 200) =~ username
    end

    test "redirects to signup when session expired" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> get("/auth/complete-signup")

      assert redirected_to(conn) == "/signup"
      assert Phoenix.Flash.get(conn.assigns.flash, "error") =~ "Session expired"
    end
  end

  describe "POST /auth/complete-signup - Complete signup" do
    test "creates user and logs them in with chosen username" do
      email = Hexpm.Fake.sequence(:email)
      username = Hexpm.Fake.sequence(:username)
      chosen_username = Hexpm.Fake.sequence(:username)
      name = Hexpm.Fake.sequence(:full_name)

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "pending_oauth" => %{
            provider: "github",
            provider_uid: "12345",
            provider_email: email,
            provider_name: name,
            provider_nickname: username
          }
        })
        |> post("/auth/complete-signup", %{"user" => %{"username" => chosen_username}})

      # User should be created with chosen username
      user = Users.get(chosen_username, [:emails])
      assert user
      assert user.full_name == name
      refute user.password

      # GitHub email is pre-verified, user logged in immediately
      assert redirected_to(conn) == "/users/#{chosen_username}"
      assert Phoenix.Flash.get(conn.assigns.flash, "info") == "Account created successfully!"
      assert get_session(conn, "user_id") == user.id

      # Session should be cleared
      refute get_session(conn, "pending_oauth")

      # Email should be verified
      user_email = hd(user.emails)
      assert user_email.verified

      # Provider should be linked
      user_provider = UserProviders.get_by_provider("github", "12345")
      assert user_provider
      assert user_provider.provider_email == email
      assert user_provider.user_id == user.id
    end

    test "shows validation error when username is taken" do
      existing_username = Hexpm.Fake.sequence(:username)
      existing_user = insert(:user, username: existing_username)
      email = Hexpm.Fake.sequence(:email)
      username = Hexpm.Fake.sequence(:username)
      name = Hexpm.Fake.sequence(:full_name)

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "pending_oauth" => %{
            provider: "github",
            provider_uid: "12345",
            provider_email: email,
            provider_name: name,
            provider_nickname: username
          }
        })
        |> post("/auth/complete-signup", %{"user" => %{"username" => existing_username}})

      # Should re-render the form
      assert html_response(conn, 200) =~ "Complete your signup"
      assert html_response(conn, 200) =~ "has already been taken"

      # Should NOT create a new user beyond the existing one
      users_with_taken_username =
        Hexpm.Accounts.User
        |> Ecto.Query.where(username: ^existing_username)
        |> Hexpm.Repo.all()

      assert length(users_with_taken_username) == 1
      assert hd(users_with_taken_username).id == existing_user.id
    end

    test "shows validation error when username is too short" do
      email = Hexpm.Fake.sequence(:email)
      username = Hexpm.Fake.sequence(:username)
      name = Hexpm.Fake.sequence(:full_name)

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "pending_oauth" => %{
            provider: "github",
            provider_uid: "12345",
            provider_email: email,
            provider_name: name,
            provider_nickname: username
          }
        })
        |> post("/auth/complete-signup", %{"user" => %{"username" => "ab"}})

      # Should re-render the form
      assert html_response(conn, 200) =~ "Complete your signup"
      assert html_response(conn, 200) =~ "at least 3 character"

      # Should NOT create user
      refute Users.get("ab")
    end

    test "shows validation error when username has invalid characters" do
      email = Hexpm.Fake.sequence(:email)
      username = Hexpm.Fake.sequence(:username)
      name = Hexpm.Fake.sequence(:full_name)

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "pending_oauth" => %{
            provider: "github",
            provider_uid: "12345",
            provider_email: email,
            provider_name: name,
            provider_nickname: username
          }
        })
        |> post("/auth/complete-signup", %{"user" => %{"username" => "invalid user!"}})

      # Should re-render the form
      assert html_response(conn, 200) =~ "Complete your signup"

      # Should NOT create user
      refute Users.get("invalid user!")
    end

    test "redirects to signup when session expired" do
      username = Hexpm.Fake.sequence(:username)

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/auth/complete-signup", %{"user" => %{"username" => username}})

      assert redirected_to(conn) == "/signup"
      assert Phoenix.Flash.get(conn.assigns.flash, "error") =~ "Session expired"

      # Should NOT create user
      refute Users.get(username)
    end
  end
end
