defmodule Hexpm.Accounts.SSO.EnforcementWorkerTest do
  use Hexpm.DataCase

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.Enforcement
  alias Hexpm.Emails.OutboxEntry

  setup do
    organization = insert(:organization)
    admin = insert(:user, emails: [build(:email, verified: true, primary: true)])
    member = insert(:user, emails: [build(:email, verified: true, primary: true)])
    insert(:organization_user, organization: organization, user: admin, role: "admin")
    insert(:organization_user, organization: organization, user: member, role: "write")

    config = Application.fetch_env!(:hexpm, :organization_sso)

    Application.put_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, mode: :beta, beta_organizations: [organization.name])
    )

    on_exit(fn -> Application.put_env(:hexpm, :organization_sso, config) end)

    connection =
      insert(:organization_sso_connection,
        organization: organization,
        tested_at: DateTime.utc_now(),
        enabled_at: DateTime.utc_now()
      )

    insert(:organization_sso_identity,
      connection: connection,
      organization: organization,
      user: admin
    )

    %{organization: organization, admin: admin, member: member, connection: connection}
  end

  describe "warn_pending/0" do
    test "mails a member who has not linked before the date", context do
      require_sso(context, DateTime.add(DateTime.utc_now(), 3 * 24 * 60 * 60, :second))

      assert Enforcement.warn_pending() == 1
      assert [entry] = pending_entries()
      assert entry.category == "sso.enforcement_pending"

      assert entry.email["text_body"] =~
               Application.fetch_env!(:hexpm, :email_base_url) <>
                 "/sso/org/#{context.organization.name}"
    end

    test "builds the login link without the web endpoint" do
      # This runs on `queue: :periodic`, which is configured only for
      # `HEXPM_MODE=worker`, and worker pods start no endpoint. A call to
      # `HexpmWeb.Endpoint.url/0` from here raises on every run in production
      # and the suite would not see it, because `mode(:test, _)` is `:all`.
      {:ok, {_module, [imports: imports]}} =
        :beam_lib.chunks(:code.which(Enforcement), [:imports])

      refute Enum.any?(imports, fn {module, _fun, _arity} -> module == HexpmWeb.Endpoint end)
    end

    test "says nothing twice", context do
      require_sso(context, DateTime.add(DateTime.utc_now(), 3 * 24 * 60 * 60, :second))

      assert Enforcement.warn_pending() == 1
      assert Enforcement.warn_pending() == 0
      assert length(pending_entries()) == 1
    end

    test "says nothing twice once the mail has gone out", context do
      require_sso(context, DateTime.add(DateTime.utc_now(), 3 * 24 * 60 * 60, :second))

      assert Enforcement.warn_pending() == 1

      # The outbox row is the mail waiting to be sent, and the worker deletes it
      # on delivery. Tomorrow's tick has only the audit entry to go on.
      Enum.each(pending_entries(), &Repo.delete!/1)

      assert Enforcement.warn_pending() == 0
      assert pending_entries() == []
    end

    test "leaves a linked member alone", context do
      insert(:organization_sso_identity,
        connection: context.connection,
        organization: context.organization,
        user: context.member,
        subject: "linked-member"
      )

      require_sso(context, DateTime.add(DateTime.utc_now(), 3 * 24 * 60 * 60, :second))

      assert Enforcement.warn_pending() == 0
    end

    test "leaves an exempt member alone", context do
      {:ok, _member} =
        SSO.set_member_enforcement(context.organization, context.member, "exempt",
          audit: audit_data(context.admin)
        )

      require_sso(context, DateTime.add(DateTime.utc_now(), 3 * 24 * 60 * 60, :second))

      assert Enforcement.warn_pending() == 0
    end

    test "says nothing while the date is far off", context do
      require_sso(context, DateTime.add(DateTime.utc_now(), 60 * 24 * 60 * 60, :second))

      assert Enforcement.warn_pending() == 0
    end

    test "says nothing once the date has passed", context do
      require_sso(context, DateTime.add(DateTime.utc_now(), -60, :second))

      assert Enforcement.warn_pending() == 0
    end

    test "goes away with the account it was addressed to", context do
      require_sso(context, DateTime.add(DateTime.utc_now(), 3 * 24 * 60 * 60, :second))

      assert Enforcement.warn_pending() == 1

      :ok = Hexpm.Accounts.Users.delete(context.member, audit: audit_data(context.member))

      assert pending_entries() == []
    end
  end

  describe "sweep_personal_keys/0" do
    test "removes the organization's permissions and leaves the rest", context do
      key = personal_key(context, [%{domain: "repository", resource: context.organization.name}])

      other = insert(:organization)
      insert(:organization_user, organization: other, user: context.member, role: "write")

      key =
        add_permissions(key, [
          %{domain: "repository", resource: other.name},
          %{domain: "api", resource: "write"}
        ])

      require_sso(context, DateTime.add(DateTime.utc_now(), -60, :second))

      assert Enforcement.sweep_personal_keys() == 1

      permissions = Repo.get!(Hexpm.Accounts.Key, key.id).permissions
      domains = Enum.map(permissions, &{&1.domain, &1.resource})

      refute {"repository", context.organization.name} in domains
      assert {"repository", other.name} in domains
      assert {"api", "write"} in domains
    end

    test "leaves a key naming every repository for the request to refuse", context do
      key = personal_key(context, [%{domain: "repositories", resource: nil}])

      require_sso(context, DateTime.add(DateTime.utc_now(), -60, :second))

      assert Enforcement.sweep_personal_keys() == 0

      # Removing it here would take every other organization's access with it.
      assert [%{domain: "repositories"}] = Repo.get!(Hexpm.Accounts.Key, key.id).permissions
    end

    test "is idempotent", context do
      personal_key(context, [%{domain: "repository", resource: context.organization.name}])
      require_sso(context, DateTime.add(DateTime.utc_now(), -60, :second))

      assert Enforcement.sweep_personal_keys() == 1
      assert Enforcement.sweep_personal_keys() == 0
    end

    test "does nothing while the organization allows personal keys", context do
      personal_key(context, [%{domain: "repository", resource: context.organization.name}])

      {:ok, _connection} =
        SSO.configure_enforcement(
          context.organization,
          %{
            "enforcement_mode" => "required",
            "required_at" => DateTime.add(DateTime.utc_now(), -60, :second),
            "personal_keys" => "allow"
          },
          audit: audit_data(context.admin)
        )

      assert Enforcement.sweep_personal_keys() == 0
    end

    test "does nothing during the grace period", context do
      personal_key(context, [%{domain: "repository", resource: context.organization.name}])
      require_sso(context, DateTime.add(DateTime.utc_now(), 3 * 24 * 60 * 60, :second))

      assert Enforcement.sweep_personal_keys() == 0
    end

    test "leaves organization-owned keys alone", context do
      insert(:key,
        organization: context.organization,
        user: nil,
        permissions: [
          build(:key_permission, domain: "repository", resource: context.organization.name)
        ]
      )

      require_sso(context, DateTime.add(DateTime.utc_now(), -60, :second))

      assert Enforcement.sweep_personal_keys() == 0
    end

    test "mails the owner and audits the removal", context do
      key = personal_key(context, [%{domain: "repository", resource: context.organization.name}])
      require_sso(context, DateTime.add(DateTime.utc_now(), -60, :second))

      assert Enforcement.sweep_personal_keys() == 1

      assert [entry] = Repo.all(from(e in OutboxEntry, where: e.category == "sso.key_revoked"))
      assert entry.group_key =~ to_string(context.member.id)

      log =
        Hexpm.Accounts.AuditLogs.all_by(context.member)
        |> Enum.find(&(&1.action == "sso.key.revoke"))

      assert log.params["key"]["name"] == key.name
      assert log.params["removed_permissions"] == ["repository:#{context.organization.name}"]
    end
  end

  describe "the sweep and the members it governs" do
    test "leaves an exempt member's key alone", context do
      key = personal_key(context, [%{domain: "repository", resource: context.organization.name}])
      require_sso(context, DateTime.add(DateTime.utc_now(), -60, :second))
      exempt(context, context.member)

      assert Enforcement.sweep_personal_keys() == 0
      assert Repo.get!(Hexpm.Accounts.Key, key.id).permissions == key.permissions
      assert Repo.all(from(e in OutboxEntry, where: e.category == "sso.key_revoked")) == []
    end

    test "takes a key that expires later but has not expired yet", context do
      key =
        personal_key(context, [%{domain: "repository", resource: context.organization.name}])
        |> Ecto.Changeset.change(revoke_at: DateTime.add(DateTime.utc_now(), 86_400, :second))
        |> Repo.update!()

      require_sso(context, DateTime.add(DateTime.utc_now(), -60, :second))

      assert Enforcement.sweep_personal_keys() == 1
      assert Repo.get!(Hexpm.Accounts.Key, key.id).permissions == []
    end

    test "leaves a key that has already expired", context do
      key = personal_key(context, [%{domain: "repository", resource: context.organization.name}])

      Repo.update_all(
        from(k in Hexpm.Accounts.Key, where: k.id == ^key.id),
        set: [revoke_at: DateTime.add(DateTime.utc_now(), -60, :second)]
      )

      require_sso(context, DateTime.add(DateTime.utc_now(), -60, :second))

      assert Enforcement.sweep_personal_keys() == 0
    end

    test "revokes a key stripping leaves with nothing", context do
      key = personal_key(context, [%{domain: "repository", resource: context.organization.name}])
      require_sso(context, DateTime.add(DateTime.utc_now(), -60, :second))

      assert Enforcement.sweep_personal_keys() == 1

      key = Repo.get!(Hexpm.Accounts.Key, key.id)
      assert key.permissions == []
      assert key.revoke_at
    end

    test "leaves a key that still carries something else alive", context do
      key =
        personal_key(context, [
          %{domain: "repository", resource: context.organization.name},
          %{domain: "api", resource: "read"}
        ])

      require_sso(context, DateTime.add(DateTime.utc_now(), -60, :second))

      assert Enforcement.sweep_personal_keys() == 1

      key = Repo.get!(Hexpm.Accounts.Key, key.id)
      assert Enum.map(key.permissions, & &1.domain) == ["api"]
      refute key.revoke_at
    end

    test "tells an owner about all their keys at once", context do
      personal_key(context, [%{domain: "repository", resource: context.organization.name}])
      personal_key(context, [%{domain: "docs", resource: context.organization.name}])
      require_sso(context, DateTime.add(DateTime.utc_now(), -60, :second))

      assert Enforcement.sweep_personal_keys() == 2

      assert [_one] = Repo.all(from(e in OutboxEntry, where: e.category == "sso.key_revoked"))
    end
  end

  describe "the sweep and the keys it only refuses" do
    test "tells a piloted member their key is turned away and leaves it alone", context do
      key = personal_key(context, [%{domain: "repository", resource: context.organization.name}])
      pilot_sso(context)
      enforce(context, context.member)

      assert Enforcement.sweep_personal_keys() == 0
      assert Repo.get!(Hexpm.Accounts.Key, key.id).permissions == key.permissions
      assert [entry] = blocked_entries()
      assert entry.group_key =~ to_string(context.member.id)
      assert Repo.all(from(e in OutboxEntry, where: e.category == "sso.key_revoked")) == []
    end

    test "says nothing to a member the pilot does not cover", context do
      personal_key(context, [%{domain: "repository", resource: context.organization.name}])
      pilot_sso(context)

      assert Enforcement.sweep_personal_keys() == 0
      assert blocked_entries() == []
    end

    test "says it once however many sweeps run", context do
      personal_key(context, [%{domain: "repository", resource: context.organization.name}])
      pilot_sso(context)
      enforce(context, context.member)

      assert Enforcement.sweep_personal_keys() == 0
      assert Enforcement.sweep_personal_keys() == 0
      assert [_entry] = blocked_entries()
    end

    test "says it once once the mail has gone out", context do
      personal_key(context, [%{domain: "repository", resource: context.organization.name}])
      pilot_sso(context)
      enforce(context, context.member)

      assert Enforcement.sweep_personal_keys() == 0

      # A blocked key changes nothing, so it is blocked again tomorrow. The
      # outbox row is gone by then and only the audit entry stops the mail.
      Enum.each(blocked_entries(), &Repo.delete!/1)

      assert Enforcement.sweep_personal_keys() == 0
      assert blocked_entries() == []
    end

    test "says it again for a key minted after the first notice", context do
      personal_key(context, [%{domain: "repository", resource: context.organization.name}])
      pilot_sso(context)
      enforce(context, context.member)

      assert Enforcement.sweep_personal_keys() == 0
      Enum.each(blocked_entries(), &Repo.delete!/1)

      second = personal_key(context, [%{domain: "docs", resource: context.organization.name}])

      assert Enforcement.sweep_personal_keys() == 0
      assert [entry] = blocked_entries()
      assert entry.email["text_body"] =~ second.name
    end

    test "tells a member whose key names every repository, which is kept", context do
      key = personal_key(context, [%{domain: "repositories", resource: nil}])
      require_sso(context, DateTime.add(DateTime.utc_now(), -60, :second))

      assert Enforcement.sweep_personal_keys() == 0
      assert Repo.get!(Hexpm.Accounts.Key, key.id).permissions == key.permissions
      assert [_entry] = blocked_entries()
    end

    test "names the key and what still works", context do
      key = personal_key(context, [%{domain: "repositories", resource: nil}])
      require_sso(context, DateTime.add(DateTime.utc_now(), -60, :second))

      assert Enforcement.sweep_personal_keys() == 0
      assert [entry] = blocked_entries()

      body = entry.email["text_body"]

      assert body =~ "chose not to accept personal API keys"
      assert body =~ "your key #{key.name} no longer reaches"
      assert body =~ "The key itself is untouched"
      assert body =~ "mix hex.user auth"
      assert body =~ "organization key"
      assert entry.email["subject"] =~ "does not accept personal API keys"
    end

    test "goes away with the account it was addressed to", context do
      personal_key(context, [%{domain: "repositories", resource: nil}])
      require_sso(context, DateTime.add(DateTime.utc_now(), -60, :second))

      assert Enforcement.sweep_personal_keys() == 0
      assert [_entry] = blocked_entries()

      :ok = Hexpm.Accounts.Users.delete(context.member, audit: audit_data(context.member))

      assert blocked_entries() == []
    end
  end

  defp pilot_sso(context) do
    {:ok, connection} =
      SSO.configure_enforcement(
        context.organization,
        %{"enforcement_mode" => "pilot", "personal_keys" => "block"},
        audit: audit_data(context.admin)
      )

    connection
  end

  defp enforce(context, user) do
    {:ok, _member} =
      SSO.set_member_enforcement(context.organization, user, "enforced",
        audit: audit_data(context.admin)
      )
  end

  defp blocked_entries do
    Repo.all(from(e in OutboxEntry, where: e.category == "sso.key_blocked"))
  end

  defp exempt(context, user) do
    {:ok, _member} =
      SSO.set_member_enforcement(context.organization, user, "exempt",
        audit: audit_data(context.admin)
      )
  end

  defp require_sso(context, required_at) do
    {:ok, connection} =
      SSO.configure_enforcement(
        context.organization,
        %{
          "enforcement_mode" => "required",
          "required_at" => required_at,
          "personal_keys" => "block"
        },
        audit: audit_data(context.admin)
      )

    connection
  end

  defp personal_key(context, permissions) do
    insert(:key,
      user: context.member,
      organization: nil,
      permissions: Enum.map(permissions, &build(:key_permission, &1))
    )
  end

  defp add_permissions(key, permissions) do
    key
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_embed(
      :permissions,
      key.permissions ++ Enum.map(permissions, &struct(Hexpm.Accounts.KeyPermission, &1))
    )
    |> Repo.update!()
  end

  defp pending_entries do
    Repo.all(from(e in OutboxEntry, where: e.category == "sso.enforcement_pending"))
  end
end
