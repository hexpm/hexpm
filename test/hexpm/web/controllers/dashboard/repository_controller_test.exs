defmodule Hexpm.Web.Dashboard.RepositoryControllerTest do
  use Hexpm.ConnCase, async: true
  use Bamboo.Test

  alias Hexpm.Accounts.Users

  defp add_email(user, email) do
    {:ok, user} = Users.add_email(user, %{email: email}, audit: audit_data(user))
    user
  end

  setup do
    %{
      user: create_user("eric", "eric@mail.com", "hunter42"),
      password: "hunter42",
      repository: insert(:repository)
    }
  end

  test "show repository", %{user: user, repository: repository} do
    Mox.stub(Hexpm.Billing.Mock, :dashboard, fn token ->
      assert repository.name == token

      %{
        "checkout_html" => "",
        "monthly_cost" => 800,
        "invoices" => []
      }
    end)

    insert(:repository_user, repository: repository, user: user)

    conn =
      build_conn()
      |> test_login(user)
      |> get("dashboard/repos/#{repository.name}")

    assert response(conn, 200) =~ "Members"
  end

  test "requires login" do
    conn = get(build_conn(), "dashboard/repos")
    assert redirected_to(conn) == "/login?return=dashboard%2Frepos"
  end

  test "show repository authenticates", %{user: user, repository: repository} do
    build_conn()
    |> test_login(user)
    |> get("dashboard/repos/#{repository.name}")
    |> response(404)
  end

  test "add member to repository", %{user: user, repository: repository} do
    Mox.stub(Hexpm.Billing.Mock, :update, fn repository_name, map ->
      assert repository_name == repository.name
      assert map == %{"quantity" => 2}
      {:ok, %{}}
    end)

    insert(:repository_user, repository: repository, user: user, role: "admin")
    new_user = insert(:user)
    add_email(new_user, "new@mail.com")
    params = %{"username" => new_user.username, role: "write"}

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/repos/#{repository.name}", %{
        "action" => "add_member",
        "repository_user" => params
      })

    assert redirected_to(conn) == "/dashboard/repos/#{repository.name}"
    assert repo_user = Repo.get_by(assoc(repository, :repository_users), user_id: new_user.id)
    assert repo_user.role == "write"

    assert_delivered_email(Hexpm.Emails.repository_invite(repository, new_user))
  end

  test "remove member from repository", %{user: user, repository: repository} do
    Mox.stub(Hexpm.Billing.Mock, :update, fn repository_name, map ->
      assert repository_name == repository.name
      assert map == %{"quantity" => 1}
      {:ok, %{}}
    end)

    insert(:repository_user, repository: repository, user: user, role: "admin")
    new_user = insert(:user)
    insert(:repository_user, repository: repository, user: new_user)
    params = %{"username" => new_user.username}

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/repos/#{repository.name}", %{
        "action" => "remove_member",
        "repository_user" => params
      })

    assert redirected_to(conn) == "/dashboard/repos/#{repository.name}"
    refute Repo.get_by(assoc(repository, :repository_users), user_id: new_user.id)
  end

  test "change role of member in repository", %{user: user, repository: repository} do
    insert(:repository_user, repository: repository, user: user, role: "admin")
    new_user = insert(:user)
    insert(:repository_user, repository: repository, user: new_user, role: "write")
    params = %{"username" => new_user.username, "role" => "read"}

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/repos/#{repository.name}", %{
        "action" => "change_role",
        "repository_user" => params
      })

    assert redirected_to(conn) == "/dashboard/repos/#{repository.name}"
    assert repo_user = Repo.get_by(assoc(repository, :repository_users), user_id: new_user.id)
    assert repo_user.role == "read"
  end

  test "cancel billing", %{user: user, repository: repository} do
    Mox.stub(Hexpm.Billing.Mock, :cancel, fn token ->
      assert repository.name == token

      %{
        "subscription" => %{
          "cancel_at_period_end" => true,
          "current_period_end" => "2017-12-12T00:00:00Z"
        }
      }
    end)

    insert(:repository_user, repository: repository, user: user, role: "admin")

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/repos/#{repository.name}/cancel-billing")

    message =
      "Your subscription is cancelled, you will have access to the repository until " <>
        "the end of your billing period at December 12, 2017"

    assert redirected_to(conn) == "/dashboard/repos/#{repository.name}"
    assert get_flash(conn, :info) == message
  end

  test "show invoice", %{user: user, repository: repository} do
    Mox.stub(Hexpm.Billing.Mock, :dashboard, fn token ->
      assert repository.name == token
      %{"invoices" => [%{"id" => 123}]}
    end)

    Mox.stub(Hexpm.Billing.Mock, :invoice, fn id ->
      assert id == 123
      "Invoice"
    end)

    insert(:repository_user, repository: repository, user: user, role: "admin")

    conn =
      build_conn()
      |> test_login(user)
      |> get("dashboard/repos/#{repository.name}/invoices/123")

    assert response(conn, 200) == "Invoice"
  end

  test "pay invoice", %{user: user, repository: repository} do
    Mox.stub(Hexpm.Billing.Mock, :dashboard, fn token ->
      assert repository.name == token

      invoice = %{
        "id" => 123,
        "date" => "2020-01-01T00:00:00Z",
        "amount_due" => 700,
        "paid" => true
      }

      %{"invoices" => [invoice]}
    end)

    Mox.stub(Hexpm.Billing.Mock, :pay_invoice, fn id ->
      assert id == 123
      :ok
    end)

    insert(:repository_user, repository: repository, user: user, role: "admin")

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/repos/#{repository.name}/invoices/123/pay")

    assert redirected_to(conn) == "/dashboard/repos/#{repository.name}"
    assert get_flash(conn, :info) == "Invoice paid."
  end

  test "pay invoice failed", %{user: user, repository: repository} do
    Mox.stub(Hexpm.Billing.Mock, :dashboard, fn token ->
      assert repository.name == token

      invoice = %{
        "id" => 123,
        "date" => "2020-01-01T00:00:00Z",
        "amount_due" => 700,
        "paid" => true
      }

      %{"invoices" => [invoice], "checkout_html" => ""}
    end)

    Mox.stub(Hexpm.Billing.Mock, :pay_invoice, fn id ->
      assert id == 123
      {:error, %{"errors" => "Card failure"}}
    end)

    insert(:repository_user, repository: repository, user: user, role: "admin")

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/repos/#{repository.name}/invoices/123/pay")

    response(conn, 400)
    assert get_flash(conn, :error) == "Failed to pay invoice: Card failure."
  end

  test "update billing email", %{user: user, repository: repository} do
    Mox.stub(Hexpm.Billing.Mock, :dashboard, fn token ->
      assert repository.name == token

      %{
        "checkout_html" => "",
        "monthly_cost" => 800,
        "invoices" => []
      }
    end)

    Mox.stub(Hexpm.Billing.Mock, :update, fn token, params ->
      assert repository.name == token
      assert %{"email" => "billing@example.com"} = params
      {:ok, %{}}
    end)

    insert(:repository_user, repository: repository, user: user, role: "admin")

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/repos/#{repository.name}/update-billing", %{
        "email" => "billing@example.com"
      })

    assert redirected_to(conn) == "/dashboard/repos/#{repository.name}"
    assert get_flash(conn, :info) == "Updated your billing information."
  end

  test "create repository", %{user: user} do
    Mox.stub(Hexpm.Billing.Mock, :create, fn params ->
      assert params == %{
               "person" => %{"country" => "SE"},
               "token" => "createrepo",
               "company" => nil,
               "email" => "eric@mail.com",
               "quantity" => 1
             }

      {:ok, %{}}
    end)

    params = %{
      "repository" => %{"name" => "createrepo"},
      "person" => %{"country" => "SE"},
      "email" => "eric@mail.com"
    }

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/repos", params)

    response(conn, 302)
    assert get_resp_header(conn, "location") == ["/dashboard/repos/createrepo"]
    assert get_flash(conn, :info) == "Organization created."
  end

  test "create repository validates name", %{user: user} do
    insert(:repository, name: "createrepovalidates")

    params = %{
      "repository" => %{"name" => "createrepovalidates"},
      "person" => %{"country" => "SE"},
      "email" => "eric@mail.com"
    }

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/repos", params)

    assert response(conn, 400) =~ "Oops, something went wrong"
    assert response(conn, 400) =~ "has already been taken"
  end

  test "create billing customer after repository", %{user: user, repository: repository} do
    Mox.stub(Hexpm.Billing.Mock, :create, fn params ->
      assert params == %{
               "person" => %{"country" => "SE"},
               "token" => repository.name,
               "company" => nil,
               "email" => "eric@mail.com",
               "quantity" => 1
             }

      {:ok, %{}}
    end)

    insert(:repository_user, repository: repository, user: user, role: "admin")

    params = %{
      "repository" => %{"name" => repository.name},
      "person" => %{"country" => "SE"},
      "email" => "eric@mail.com"
    }

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/repos/#{repository.name}/create-billing", params)

    response(conn, 302)
    assert get_resp_header(conn, "location") == ["/dashboard/repos/#{repository.name}"]
    assert get_flash(conn, :info) == "Updated your billing information."
  end
end
