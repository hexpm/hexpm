defmodule Hexpm.Accounts.AuditLogTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.AuditLog

  setup do
    user = build(:user, id: 1)
    package = build(:package, id: 2)
    release = build(:release, id: 3)
    %{user: user, package: package, release: release}
  end

  describe "build/4" do
    test "action password.reset.init" do
      audit = AuditLog.build(nil, "user_agent", "password.reset.init", nil)
      assert audit.action == "password.reset.init"
      assert audit.user_id == nil
      assert audit.user_agent == "user_agent"
      assert audit.params == %{}
    end

    test "action password.reset.finish" do
      audit = AuditLog.build(nil, "user_agent", "password.reset.finish", nil)
      assert audit.action == "password.reset.finish"
      assert audit.user_id == nil
      assert audit.user_agent == "user_agent"
      assert audit.params == %{}
    end

    test "action owner.add", %{user: user, package: package} do
      user = %{user | handles: build(:user_handles, github: user.username)}
      audit = AuditLog.build(user, "user_agent", "owner.add", {package, "full", user})

      assert audit.action == "owner.add"
      assert audit.user_id == user.id
      assert audit.user_agent == "user_agent"
      assert audit.params.level == "full"
      assert audit.params.package.id == package.id
      assert audit.params.package.name == package.name
      assert audit.params.package.meta.description == package.meta.description
      assert audit.params.user.id == user.id
      assert audit.params.user.username == user.username
      assert audit.params.user.handles.github == user.handles.github
    end
  end

  describe "audit/4" do
    test "with params", %{user: user, package: package, release: release} do
      multi =
        AuditLog.audit(Ecto.Multi.new(), {user, "user_agent"}, "docs.publish", {package, release})

      assert {:insert, changeset, []} = Ecto.Multi.to_list(multi)[:"log.docs.publish"]
      assert changeset.valid?
    end

    test "with fun", %{user: user} do
      multi =
        AuditLog.audit(Ecto.Multi.new(), {user, "user_agent"}, "key.generate", fn %{} ->
          build(:key)
        end)

      assert {:merge, merge} = Ecto.Multi.to_list(multi)[:merge]
      multi = merge.(multi)
      assert {:insert, changeset, []} = Ecto.Multi.to_list(multi)[:"log.key.generate"]
      assert changeset.valid?
    end
  end

  describe "audit_with_user/4" do
    test "action user.create", %{user: user} do
      fun = fn %{user: user} -> user end
      multi = AuditLog.audit_with_user(Ecto.Multi.new(), {nil, "user_agent"}, "user.create", fun)

      assert {_, fun} = Ecto.Multi.to_list(multi)[:"log.user.create"]
      assert {:ok, %AuditLog{action: "user.create"}} = fun.(Hexpm.Repo, %{user: user})
    end
  end

  describe "audit_many/5" do
    test "action key.remove", %{user: user} do
      keys = build_list(2, :key)
      multi = AuditLog.audit_many(Ecto.Multi.new(), {user, "user_agent"}, "key.remove", keys)

      assert {:insert_all, AuditLog, [params1, params2], []} =
               Ecto.Multi.to_list(multi)[:"log.key.remove"]

      assert params1.action == "key.remove"
      assert params1.user_id == user.id
      assert params2.action == "key.remove"
      assert params2.user_id == user.id
    end
  end
end
