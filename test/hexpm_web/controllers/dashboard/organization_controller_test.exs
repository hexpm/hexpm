defmodule HexpmWeb.Dashboard.OrganizationControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test

  alias Hexpm.Accounts.{Organizations, Users, AuditLogs}

  defp add_email(user, email) do
    {:ok, user} = Users.add_email(user, %{email: email}, audit: audit_data(user))
    user
  end

  defp mock_customer(organization) do
    Mox.stub(Hexpm.Billing.Mock, :get, fn token ->
      assert organization.name == token

      %{
        "checkout_html" => "",
        "invoices" => []
      }
    end)
  end

  setup do
    repository = insert(:repository)

    %{
      user: insert(:user),
      organization: repository.organization
    }
  end

  test "show organization", %{user: user, organization: organization} do
    insert(:organization_user, organization: organization, user: user)

    mock_customer(organization)

    conn =
      build_conn()
      |> test_login(user)
      |> get("dashboard/orgs/#{organization.name}")

    assert response(conn, 200) =~ "Members"
  end

  test "show organization without associated user", %{user: user} do
    repository = insert(:repository, organization: build(:organization, user: nil))
    insert(:organization_user, organization: repository.organization, user: user)

    mock_customer(repository.organization)

    conn =
      build_conn()
      |> test_login(user)
      |> get("dashboard/orgs/#{repository.organization.name}")

    assert response(conn, 200) =~ "Members"
  end

  test "requires login" do
    conn = get(build_conn(), "dashboard/orgs")
    assert redirected_to(conn) == "/login?return=dashboard%2Forgs"
  end

  test "show organization authenticates", %{user: user, organization: organization} do
    build_conn()
    |> test_login(user)
    |> get("dashboard/orgs/#{organization.name}")
    |> response(404)
  end

  test "add member to organization", %{user: user, organization: organization} do
    Mox.stub(Hexpm.Billing.Mock, :get, fn token ->
      assert organization.name == token

      %{
        "checkout_html" => "",
        "invoices" => [],
        "quantity" => 2
      }
    end)

    insert(:organization_user, organization: organization, user: user, role: "admin")
    new_user = insert(:user)
    add_email(new_user, "new@mail.com")
    params = %{"username" => new_user.username, role: "write"}

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/orgs/#{organization.name}", %{
        "action" => "add_member",
        "organization_user" => params
      })

    assert redirected_to(conn) == "/dashboard/orgs/#{organization.name}"
    assert repo_user = Repo.get_by(assoc(organization, :organization_users), user_id: new_user.id)
    assert repo_user.role == "write"

    assert_delivered_email(Hexpm.Emails.organization_invite(organization, new_user))
  end

  test "add member to organization without enough seats", %{
    user: user,
    organization: organization
  } do
    Mox.stub(Hexpm.Billing.Mock, :get, fn token ->
      assert organization.name == token

      %{
        "checkout_html" => "",
        "invoices" => [],
        "quantity" => 1,
        "subscription" => %{
          "current_period_end" => "2017-12-12T00:00:00Z",
          "status" => "active",
          "cancel_at_period_end" => false
        },
        "plan_id" => "organization-monthly",
        "amount_with_tax" => 700,
        "proration_amount" => 0
      }
    end)

    insert(:organization_user, organization: organization, user: user, role: "admin")
    new_user = insert(:user)
    add_email(new_user, "new@mail.com")
    params = %{"username" => new_user.username, role: "write"}

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/orgs/#{organization.name}", %{
        "action" => "add_member",
        "organization_user" => params
      })

    response(conn, 400)
    assert get_flash(conn, :error) == "Not enough seats in organization to add member."
  end

  test "remove member from organization", %{user: user, organization: organization} do
    insert(:organization_user, organization: organization, user: user, role: "admin")
    new_user = insert(:user)
    insert(:organization_user, organization: organization, user: new_user)
    params = %{"username" => new_user.username}

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/orgs/#{organization.name}", %{
        "action" => "remove_member",
        "organization_user" => params
      })

    assert redirected_to(conn) == "/dashboard/orgs/#{organization.name}"
    refute Repo.get_by(assoc(organization, :organization_users), user_id: new_user.id)
  end

  test "change role of member in organization", %{user: user, organization: organization} do
    insert(:organization_user, organization: organization, user: user, role: "admin")
    new_user = insert(:user)
    insert(:organization_user, organization: organization, user: new_user, role: "write")
    params = %{"username" => new_user.username, "role" => "read"}

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/orgs/#{organization.name}", %{
        "action" => "change_role",
        "organization_user" => params
      })

    assert redirected_to(conn) == "/dashboard/orgs/#{organization.name}"
    assert repo_user = Repo.get_by(assoc(organization, :organization_users), user_id: new_user.id)
    assert repo_user.role == "read"
  end

  test "leave organization", %{user: user, organization: organization} do
    insert(:organization_user, organization: organization, user: user, role: "admin")
    new_user = insert(:user)
    insert(:organization_user, organization: organization, user: new_user, role: "admin")
    params = %{"organization_name" => organization.name}

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/orgs/#{organization.name}/leave", params)

    assert redirected_to(conn) == "/dashboard/profile"
    refute Repo.get_by(assoc(organization, :organization_users), user_id: user.id)
  end

  describe "update payment method" do
    test "calls Hexpm.Billing.checkout/2 when user is admin", %{
      user: user,
      organization: organization
    } do
      insert(:organization_user, organization: organization, user: user, role: "admin")

      Mox.expect(Hexpm.Billing.Mock, :checkout, fn organization_name, params ->
        assert organization_name == organization.name
        assert params == %{payment_source: "Test Token"}
        {:ok, :whatever}
      end)

      conn =
        build_conn()
        |> test_login(user)
        |> post("dashboard/orgs/#{organization.name}/billing-token", %{"token" => "Test Token"})

      assert json_response(conn, :ok) == %{}
    end

    test "create audit_log with action billing.checkout", %{
      user: user,
      organization: organization
    } do
      insert(:organization_user, organization: organization, user: user, role: "admin")

      Mox.expect(Hexpm.Billing.Mock, :checkout, fn _, _ -> {:ok, :whatever} end)

      build_conn()
      |> test_login(user)
      |> post("dashboard/orgs/#{organization.name}/billing-token", %{"token" => "Test Token"})

      assert [audit_log] = AuditLogs.all_by(user)
      assert audit_log.action == "billing.checkout"
      assert audit_log.params["organization"]["name"] == organization.name
      assert audit_log.params["payment_source"] == "Test Token"
    end
  end

  describe "show billing section" do
    test "show for admins", %{user: user, organization: organization} do
      insert(:organization_user, organization: organization, user: user, role: "admin")

      mock_customer(organization)

      conn =
        build_conn()
        |> test_login(user)
        |> get("dashboard/orgs/#{organization.name}")

      assert response(conn, 200) =~ "Billing"
      assert response(conn, 200) =~ "Billing information"
    end

    test "hide for non-admins", %{user: user, organization: organization} do
      insert(:organization_user, organization: organization, user: user, role: "read")

      mock_customer(organization)

      conn =
        build_conn()
        |> test_login(user)
        |> get("dashboard/orgs/#{organization.name}")

      refute response(conn, 200) =~ "Billing"
      refute response(conn, 200) =~ "Billing information"
    end
  end

  describe "cancel billing" do
    test "with subscription", %{user: user, organization: organization} do
      Mox.stub(Hexpm.Billing.Mock, :cancel, fn token ->
        assert organization.name == token

        %{
          "subscription" => %{
            "cancel_at_period_end" => true,
            "current_period_end" => "2017-12-12T00:00:00Z"
          }
        }
      end)

      insert(:organization_user, organization: organization, user: user, role: "admin")

      conn =
        build_conn()
        |> test_login(user)
        |> post("dashboard/orgs/#{organization.name}/cancel-billing")

      message =
        "Your subscription is cancelled, you will have access to the organization until " <>
          "the end of your billing period at December 12, 2017"

      assert redirected_to(conn) == "/dashboard/orgs/#{organization.name}"
      assert get_flash(conn, :info) == message
    end

    # This can happen when the subscription is cancelled before the trial is over
    test "without subscription", %{user: user, organization: organization} do
      Mox.stub(Hexpm.Billing.Mock, :cancel, fn token ->
        assert organization.name == token
        %{}
      end)

      insert(:organization_user, organization: organization, user: user, role: "admin")

      conn =
        build_conn()
        |> test_login(user)
        |> post("dashboard/orgs/#{organization.name}/cancel-billing")

      assert redirected_to(conn) == "/dashboard/orgs/#{organization.name}"
      assert get_flash(conn, :info) == "Your subscription is cancelled"
    end

    test "create audit_log with action billing.cancel", %{user: user, organization: organization} do
      Mox.stub(Hexpm.Billing.Mock, :cancel, fn token ->
        assert organization.name == token

        %{
          "subscription" => %{
            "cancel_at_period_end" => true,
            "current_period_end" => "2017-12-12T00:00:00Z"
          }
        }
      end)

      insert(:organization_user, organization: organization, user: user, role: "admin")

      build_conn()
      |> test_login(user)
      |> post("dashboard/orgs/#{organization.name}/cancel-billing")

      assert [audit_log] = AuditLogs.all_by(user)
      assert audit_log.action == "billing.cancel"
      assert audit_log.params["organization"]["name"] == organization.name
    end
  end

  test "show invoice", %{user: user, organization: organization} do
    Mox.stub(Hexpm.Billing.Mock, :get, fn token ->
      assert organization.name == token
      %{"invoices" => [%{"id" => 123}]}
    end)

    Mox.stub(Hexpm.Billing.Mock, :invoice, fn id ->
      assert id == 123
      "Invoice"
    end)

    insert(:organization_user, organization: organization, user: user, role: "admin")

    conn =
      build_conn()
      |> test_login(user)
      |> get("dashboard/orgs/#{organization.name}/invoices/123")

    assert response(conn, 200) == "Invoice"
  end

  describe "pay invoice" do
    test "pay invoice succeed", %{user: user, organization: organization} do
      Mox.stub(Hexpm.Billing.Mock, :get, fn token ->
        assert organization.name == token

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

      insert(:organization_user, organization: organization, user: user, role: "admin")

      conn =
        build_conn()
        |> test_login(user)
        |> post("dashboard/orgs/#{organization.name}/invoices/123/pay")

      assert redirected_to(conn) == "/dashboard/orgs/#{organization.name}"
      assert get_flash(conn, :info) == "Invoice paid."
    end

    test "pay invoice failed", %{user: user, organization: organization} do
      Mox.stub(Hexpm.Billing.Mock, :get, fn token ->
        assert organization.name == token

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

      insert(:organization_user, organization: organization, user: user, role: "admin")

      conn =
        build_conn()
        |> test_login(user)
        |> post("dashboard/orgs/#{organization.name}/invoices/123/pay")

      response(conn, 400)
      assert get_flash(conn, :error) == "Failed to pay invoice: Card failure."
    end

    test "create audit_log with action billing.pay_invoice", %{
      user: user,
      organization: organization
    } do
      Mox.stub(Hexpm.Billing.Mock, :get, fn _token -> %{"invoices" => [%{"id" => 123}]} end)
      Mox.stub(Hexpm.Billing.Mock, :pay_invoice, fn _id -> :ok end)

      insert(:organization_user, organization: organization, user: user, role: "admin")

      build_conn()
      |> test_login(user)
      |> post("dashboard/orgs/#{organization.name}/invoices/123/pay")

      assert [audit_log] = AuditLogs.all_by(user)
      assert audit_log.action == "billing.pay_invoice"
      assert audit_log.params["invoice_id"] == 123
      assert audit_log.params["organization"]["name"] == organization.name
    end
  end

  describe "POST /dashboard/orgs/:dashboard_org/update-billing" do
    test "update billing email", %{user: user, organization: organization} do
      mock_customer(organization)

      Mox.stub(Hexpm.Billing.Mock, :update, fn token, params ->
        assert organization.name == token
        assert %{"email" => "billing@example.com"} = params
        {:ok, %{}}
      end)

      insert(:organization_user, organization: organization, user: user, role: "admin")

      conn =
        build_conn()
        |> test_login(user)
        |> post("dashboard/orgs/#{organization.name}/update-billing", %{
          "email" => "billing@example.com"
        })

      assert redirected_to(conn) == "/dashboard/orgs/#{organization.name}"
      assert get_flash(conn, :info) == "Updated your billing information."
    end

    test "create audit_log with action billing.update", %{user: user, organization: organization} do
      mock_customer(organization)
      Mox.stub(Hexpm.Billing.Mock, :update, fn _, _ -> {:ok, %{}} end)

      insert(:organization_user, organization: organization, user: user, role: "admin")

      build_conn()
      |> test_login(user)
      |> post("dashboard/orgs/#{organization.name}/update-billing", %{
        "email" => "billing@example.com"
      })

      assert [audit_log] = AuditLogs.all_by(user)
      assert audit_log.action == "billing.update"
      assert audit_log.params["email"] == "billing@example.com"
      assert audit_log.params["organization"]["name"] == organization.name
    end
  end

  test "create organization", %{user: user} do
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
      "organization" => %{"name" => "createrepo"},
      "person" => %{"country" => "SE"},
      "email" => "eric@mail.com"
    }

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/orgs", params)

    response(conn, 302)
    assert get_resp_header(conn, "location") == ["/dashboard/orgs/createrepo"]

    assert get_flash(conn, :info) ==
             "Organization created with one month free trial period active."

    assert organization = Organizations.get("createrepo", [:repository])
    assert organization.repository.name == "createrepo"
  end

  test "create organization validates name", %{user: user} do
    insert(:organization, name: "createrepovalidates")

    params = %{
      "organization" => %{"name" => "createrepovalidates"},
      "person" => %{"country" => "SE"},
      "email" => "eric@mail.com"
    }

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/orgs", params)

    assert response(conn, 400) =~ "Oops, something went wrong"
    assert response(conn, 400) =~ "has already been taken"
  end

  describe "POST /dashboard/orgs/:dashboard_org/create-billing" do
    test "create billing customer after organization", %{user: user, organization: organization} do
      Mox.stub(Hexpm.Billing.Mock, :create, fn params ->
        assert params == %{
                 "person" => %{"country" => "SE"},
                 "token" => organization.name,
                 "company" => nil,
                 "email" => "eric@mail.com",
                 "quantity" => 1
               }

        {:ok, %{}}
      end)

      insert(:organization_user, organization: organization, user: user, role: "admin")

      params = %{
        "organization" => %{"name" => organization.name},
        "person" => %{"country" => "SE"},
        "email" => "eric@mail.com"
      }

      conn =
        build_conn()
        |> test_login(user)
        |> post("dashboard/orgs/#{organization.name}/create-billing", params)

      response(conn, 302)
      assert get_resp_header(conn, "location") == ["/dashboard/orgs/#{organization.name}"]
      assert get_flash(conn, :info) == "Updated your billing information."
    end

    test "create audit_log with action billing.create", %{user: user, organization: organization} do
      Mox.stub(Hexpm.Billing.Mock, :create, fn _ -> {:ok, %{}} end)

      insert(:organization_user, organization: organization, user: user, role: "admin")

      params = %{"company" => nil, "person" => nil}

      build_conn()
      |> test_login(user)
      |> post("dashboard/orgs/#{organization.name}/create-billing", params)

      assert [%{action: "billing.create"} = audit_log] = AuditLogs.all_by(user)
      assert audit_log.params["organization"]["name"] == organization.name
    end
  end

  describe "POST /dashboard/orgs/:dashboard_org/add-seats" do
    test "increase number of seats", %{organization: organization, user: user} do
      Mox.stub(Hexpm.Billing.Mock, :update, fn organization_name, map ->
        assert organization_name == organization.name
        assert map == %{"quantity" => 3}
        {:ok, %{}}
      end)

      insert(:organization_user, organization: organization, user: user, role: "admin")

      conn =
        build_conn()
        |> test_login(user)
        |> post("dashboard/orgs/#{organization.name}/add-seats", %{
          "current-seats" => "1",
          "add-seats" => "2"
        })

      assert redirected_to(conn) == "/dashboard/orgs/#{organization.name}"
      assert get_flash(conn, :info) == "The number of open seats have been increased."
    end

    test "seats cannot be less than number of members", %{organization: organization, user: user} do
      mock_customer(organization)

      insert(:organization_user, organization: organization, user: user, role: "admin")
      insert(:organization_user, organization: organization, user: build(:user))
      insert(:organization_user, organization: organization, user: build(:user))

      conn =
        build_conn()
        |> test_login(user)
        |> post("dashboard/orgs/#{organization.name}/add-seats", %{
          "current-seats" => "1",
          "add-seats" => "1"
        })

      response(conn, 400)

      assert get_flash(conn, :error) ==
               "The number of open seats cannot be less than the number of organization members."
    end

    test "create audit_log with action billing.update", %{organization: organization, user: user} do
      Mox.stub(Hexpm.Billing.Mock, :update, fn _organization_name, _map -> {:ok, %{}} end)

      insert(:organization_user, organization: organization, user: user, role: "admin")

      build_conn()
      |> test_login(user)
      |> post("dashboard/orgs/#{organization.name}/add-seats", %{
        "current-seats" => "1",
        "add-seats" => "1"
      })

      assert [audit_log] = AuditLogs.all_by(user)
      assert audit_log.action == "billing.update"
      assert audit_log.params["quantity"] == 2
      assert audit_log.params["organization"]["name"] == organization.name
    end
  end

  describe "POST /dashboard/orgs/:dashboard_org/remove-seats" do
    test "increase number of seats", %{organization: organization, user: user} do
      Mox.stub(Hexpm.Billing.Mock, :update, fn organization_name, map ->
        assert organization_name == organization.name
        assert map == %{"quantity" => 3}
        {:ok, %{}}
      end)

      insert(:organization_user, organization: organization, user: user, role: "admin")

      conn =
        build_conn()
        |> test_login(user)
        |> post("dashboard/orgs/#{organization.name}/remove-seats", %{
          "seats" => "3"
        })

      assert redirected_to(conn) == "/dashboard/orgs/#{organization.name}"
      assert get_flash(conn, :info) == "The number of open seats have been reduced."
    end

    test "seats cannot be less than number of members", %{organization: organization, user: user} do
      mock_customer(organization)

      insert(:organization_user, organization: organization, user: build(:user))
      insert(:organization_user, organization: organization, user: user, role: "admin")

      conn =
        build_conn()
        |> test_login(user)
        |> post("dashboard/orgs/#{organization.name}/remove-seats", %{
          "seats" => "1"
        })

      response(conn, 400)

      assert get_flash(conn, :error) ==
               "The number of open seats cannot be less than the number of organization members."
    end

    test "create audit_log with action billing.update", %{organization: organization, user: user} do
      Mox.stub(Hexpm.Billing.Mock, :update, fn _organization_name, _map -> {:ok, %{}} end)

      insert(:organization_user, organization: organization, user: user, role: "admin")

      build_conn()
      |> test_login(user)
      |> post("dashboard/orgs/#{organization.name}/remove-seats", %{
        "seats" => "4"
      })

      assert [audit_log] = AuditLogs.all_by(user)
      assert audit_log.action == "billing.update"
      assert audit_log.params["quantity"] == 4
      assert audit_log.params["organization"]["name"] == organization.name
    end
  end

  describe "POST /dashboard/orgs/:dashboard_org/change-plan" do
    test "change plan", %{organization: organization, user: user} do
      Mox.stub(Hexpm.Billing.Mock, :change_plan, fn organization_name, map ->
        assert organization_name == organization.name
        assert map == %{"plan_id" => "organization-annually"}
        {:ok, %{}}
      end)

      insert(:organization_user, organization: organization, user: user, role: "admin")

      conn =
        build_conn()
        |> test_login(user)
        |> post("dashboard/orgs/#{organization.name}/change-plan", %{
          "plan_id" => "organization-annually"
        })

      assert redirected_to(conn) == "/dashboard/orgs/#{organization.name}"
      assert get_flash(conn, :info) == "You have switched to the annual organization plan."
    end

    test "create audit_log with action billing.change_plan", %{
      organization: organization,
      user: user
    } do
      Mox.stub(Hexpm.Billing.Mock, :change_plan, fn _organization_name, _map -> {:ok, %{}} end)

      insert(:organization_user, organization: organization, user: user, role: "admin")

      build_conn()
      |> test_login(user)
      |> post("dashboard/orgs/#{organization.name}/change-plan", %{
        "plan_id" => "organization-annually"
      })

      assert [audit_log] = AuditLogs.all_by(user)
      assert audit_log.action == "billing.change_plan"
      assert audit_log.params["organization"]["name"] == organization.name
      assert audit_log.params["plan_id"] == "organization-annually"
    end
  end

  describe "POST /dashboard/orgs/:dashboard_org/keys" do
    test "generate a new key", c do
      insert(:organization_user, organization: c.organization, user: c.user, role: "admin")

      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/orgs/#{c.organization.name}/keys", %{key: %{name: "computer"}})

      assert redirected_to(conn) == "/dashboard/orgs/#{c.organization.name}"
      assert get_flash(conn, :info) =~ "The key computer was successfully generated"
    end
  end

  describe "DELETE /dashboard/orgs/:dashboard_org/keys" do
    test "revoke key", c do
      insert(:organization_user, organization: c.organization, user: c.user, role: "admin")
      insert(:key, organization: c.organization, name: "computer")

      mock_customer(c.organization)

      conn =
        build_conn()
        |> test_login(c.user)
        |> delete("/dashboard/orgs/#{c.organization.name}/keys", %{name: "computer"})

      assert redirected_to(conn) == "/dashboard/orgs/#{c.organization.name}"
      assert get_flash(conn, :info) =~ "The key computer was revoked successfully"
    end

    test "revoking an already revoked key throws an error", c do
      insert(:organization_user, organization: c.organization, user: c.user, role: "admin")

      insert(
        :key,
        organization: c.organization,
        name: "computer",
        revoked_at: ~N"2017-01-01 00:00:00"
      )

      mock_customer(c.organization)

      conn =
        build_conn()
        |> test_login(c.user)
        |> delete("/dashboard/orgs/#{c.organization.name}/keys", %{name: "computer"})

      assert response(conn, 400) =~ "The key computer was not found"
    end
  end

  describe "POST /dashboard/orgs/:dashboard_org/profile" do
    test "requires admin role", c do
      insert(:organization_user, organization: c.organization, user: c.user, role: "write")
      mock_customer(c.organization)

      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/orgs/#{c.organization.name}/profile", %{profile: %{}})

      assert response(conn, 400) =~ "You do not have permission for this action."
    end

    test "when update succeeds", c do
      insert(:organization_user, organization: c.organization, user: c.user, role: "admin")
      mock_customer(c.organization)

      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/orgs/#{c.organization.name}/profile", %{profile: %{}})

      assert redirected_to(conn) == "/dashboard/orgs/#{c.organization.name}"
      assert get_flash(conn, :info) == "Profile updated successfully."
    end

    test "when update fails", c do
      insert(:organization_user, organization: c.organization, user: c.user, role: "admin")
      mock_customer(c.organization)

      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/orgs/#{c.organization.name}/profile", %{
          profile: %{public_email: "invalid_email"}
        })

      assert get_flash(conn, :error) == "Oops, something went wrong!"
      assert response(conn, 400)
    end
  end
end
