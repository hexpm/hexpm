defmodule Hexpm.Accounts.AuditLogTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.AuditLog

  setup do
    user = build(:user)
    key = build(:key)
    package = build(:package)
    release = build(:release)
    %{user: user, key: key, package: package, release: release}
  end

  describe "build/4" do
    test "action password.reset.init" do
      audit_data = %{user: nil, key: nil, user_agent: "user_agent", remote_ip: "127.0.0.1"}
      audit = AuditLog.build(audit_data, "password.reset.init", nil)
      assert audit.organization_id == nil
      assert audit.action == "password.reset.init"
      assert audit.user_id == nil
      assert audit.user_agent == "user_agent"
      assert audit.remote_ip == "127.0.0.1"
      assert audit.params == %{}
    end

    test "action password.reset.finish" do
      audit_data = %{user: nil, key: nil, user_agent: "user_agent", remote_ip: "127.0.0.1"}
      audit = AuditLog.build(audit_data, "password.reset.finish", nil)
      assert audit.organization_id == nil
      assert audit.action == "password.reset.finish"
      assert audit.user_id == nil
      assert audit.user_agent == "user_agent"
      assert audit.remote_ip == "127.0.0.1"
      assert audit.params == %{}
    end

    test "action owner.add", %{user: user, key: key, package: package} do
      user = %{user | handles: build(:user_handles, github: user.username)}
      audit_data = %{user: user, key: key, user_agent: "user_agent", remote_ip: "127.0.0.1"}

      audit = AuditLog.build(audit_data, "owner.add", {package, "full", user})

      assert audit.action == "owner.add"
      assert audit.user_id == user.id
      assert audit.user_agent == "user_agent"
      assert audit.remote_ip == "127.0.0.1"
      assert audit.params.level == "full"
      assert audit.params.package.id == package.id
      assert audit.params.package.name == package.name
      assert audit.params.package.meta.description == package.meta.description
      assert audit.params.user.id == user.id
      assert audit.params.user.username == user.username
      assert audit.params.user.handles.github == user.handles.github
    end

    test "action organization.create", %{user: user, key: key} do
      organization =
        build(:organization,
          id: 5,
          billing_active: false,
          name: "Test"
        )

      audit_data = %{user: user, key: key, user_agent: "user_agent", remote_ip: "127.0.0.1"}

      audit = AuditLog.build(audit_data, "organization.create", organization)

      assert audit.action == "organization.create"
      assert audit.user_id == user.id
      assert audit.user_agent == "user_agent"
      assert audit.remote_ip == "127.0.0.1"
      assert audit.organization_id == 5
      assert audit.params == %{billing_active: false, name: "Test", id: 5}
    end

    test "action billing.checkout", %{user: user} do
      organization = build(:organization, name: "Organization Name")
      audit_data = %{user: user, key: nil, user_agent: "user_agent", remote_ip: "127.0.0.1"}

      audit =
        AuditLog.build(
          audit_data,
          "billing.checkout",
          {organization, %{payment_source: "a token"}}
        )

      assert audit.action == "billing.checkout"
      assert audit.user_id == user.id
      assert audit.user_agent == "user_agent"
      assert audit.remote_ip == "127.0.0.1"
      assert audit.params.organization.name == "Organization Name"
      assert audit.params.payment_source == "a token"
    end

    test "action billing.cancel", %{user: user} do
      organization = build(:organization, name: "Organization Name")
      audit_data = %{user: user, key: nil, user_agent: "user_agent", remote_ip: "127.0.0.1"}

      audit = AuditLog.build(audit_data, "billing.cancel", {organization, "Organization Name"})
      assert audit.action == "billing.cancel"
      assert audit.user_id == user.id
      assert audit.user_agent == "user_agent"
      assert audit.remote_ip == "127.0.0.1"
      assert audit.params.organization.name == "Organization Name"
    end

    test "action billing.create", %{user: user} do
      organization = build(:organization, name: "Organization Name")
      audit_data = %{user: user, key: nil, user_agent: "user_agent", remote_ip: "127.0.0.1"}

      audit =
        AuditLog.build(
          audit_data,
          "billing.create",
          {organization,
           %{
             "email" => "test@example.com",
             "person" => "Test Person",
             "company" => "Test Company",
             "token" => "Test Token",
             "quantity" => 11
           }}
        )

      assert audit.action == "billing.create"
      assert audit.user_id == user.id
      assert audit.user_agent == "user_agent"
      assert audit.remote_ip == "127.0.0.1"
      assert audit.params.organization.name == "Organization Name"
      assert audit.params.email == "test@example.com"
      assert audit.params.person == "Test Person"
      assert audit.params.company == "Test Company"
      assert audit.params.token == "Test Token"
      assert audit.params.quantity == 11
    end

    test "action billing.change_plan", %{user: user} do
      organization = build(:organization, name: "Organization Name")
      audit_data = %{user: user, key: nil, user_agent: "user_agent", remote_ip: "127.0.0.1"}

      audit =
        AuditLog.build(
          audit_data,
          "billing.change_plan",
          {organization, %{"plan_id" => "test plan"}}
        )

      assert audit.action == "billing.change_plan"
      assert audit.user_id == user.id
      assert audit.user_agent == "user_agent"
      assert audit.remote_ip == "127.0.0.1"
      assert audit.params.organization.name == "Organization Name"
      assert audit.params.plan_id == "test plan"
    end

    test "action billing.pay_invoice", %{user: user} do
      organization = build(:organization, name: "Organization Name")
      audit_data = %{user: user, key: nil, user_agent: "user_agent", remote_ip: "127.0.0.1"}

      audit = AuditLog.build(audit_data, "billing.pay_invoice", {organization, 897})
      assert audit.action == "billing.pay_invoice"
      assert audit.user_id == user.id
      assert audit.user_agent == "user_agent"
      assert audit.remote_ip == "127.0.0.1"
      assert audit.params.organization.name == "Organization Name"
      assert audit.params.invoice_id == 897
    end
  end

  describe "audit/3" do
    test "with params", %{user: user, key: key, package: package, release: release} do
      audit_data = %{user: user, key: key, user_agent: "user_agent", remote_ip: "127.0.0.1"}
      audit_log = AuditLog.audit(audit_data, "docs.revert", {package, release})

      assert %AuditLog{action: "docs.revert"} = audit_log
    end

    test "billing.update", %{user: user} do
      organization = build(:organization, name: "Organization Name")
      audit_data = %{user: user, key: nil, user_agent: "user_agent", remote_ip: "127.0.0.1"}

      audit =
        AuditLog.audit(
          audit_data,
          "billing.update",
          {
            organization,
            %{
              "email" => "test@example.com",
              "person" => "Test Person",
              "company" => "Test Company",
              "token" => "Test Token",
              "quantity" => 11
            }
          }
        )

      assert audit.action == "billing.update"
      assert audit.user_id == user.id
      assert audit.user_agent == "user_agent"
      assert audit.remote_ip == "127.0.0.1"
      assert audit.params.organization.name == "Organization Name"
      assert audit.params.email == "test@example.com"
      assert audit.params.person == "Test Person"
      assert audit.params.company == "Test Company"
      assert audit.params.token == "Test Token"
      assert audit.params.quantity == 11
    end
  end

  describe "audit/4" do
    test "with params", %{user: user, key: key, package: package, release: release} do
      audit_data = %{user: user, key: key, user_agent: "user_agent", remote_ip: "127.0.0.1"}

      multi =
        AuditLog.audit(
          Ecto.Multi.new(),
          audit_data,
          "docs.publish",
          {package, release}
        )

      assert {:insert, changeset, []} = Ecto.Multi.to_list(multi)[:"log.docs.publish.0"]
      assert changeset.valid?
    end

    test "with fun", %{user: user, key: key} do
      audit_data = %{user: user, key: key, user_agent: "user_agent", remote_ip: "127.0.0.1"}

      multi =
        AuditLog.audit(Ecto.Multi.new(), audit_data, "key.generate", fn %{} -> build(:key) end)

      assert {:merge, merge} = Ecto.Multi.to_list(multi)[:merge]
      multi = merge.(multi)
      assert {:insert, changeset, []} = Ecto.Multi.to_list(multi)[:"log.key.generate.0"]
      assert changeset.valid?
    end
  end

  describe "audit_with_user/4" do
    test "action user.create", %{user: user, key: key} do
      audit_data = %{user: nil, key: key, user_agent: "user_agent", remote_ip: "127.0.0.1"}

      multi =
        AuditLog.audit_with_user(
          Ecto.Multi.new(),
          audit_data,
          "user.create",
          fn %{user: user} -> user end
        )

      assert {_, fun} = Ecto.Multi.to_list(multi)[:"log.user.create.0"]
      assert {:ok, %AuditLog{action: "user.create"}} = fun.(Hexpm.Repo, %{user: user})
    end
  end

  describe "audit_many/5" do
    test "action key.remove", %{user: user, key: key} do
      keys = build_list(2, :key)
      audit_data = %{user: user, key: key, user_agent: "user_agent", remote_ip: "127.0.0.1"}
      multi = AuditLog.audit_many(Ecto.Multi.new(), audit_data, "key.remove", keys)

      assert {:insert_all, AuditLog, [params1, params2], []} =
               Ecto.Multi.to_list(multi)[:"log.key.remove.0"]

      assert params1.action == "key.remove"
      assert params1.user_id == user.id
      assert params2.action == "key.remove"
      assert params2.user_id == user.id
    end
  end
end
