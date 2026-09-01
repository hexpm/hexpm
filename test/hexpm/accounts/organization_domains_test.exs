defmodule Hexpm.Accounts.OrganizationDomainsTest do
  use Hexpm.DataCase, async: false

  alias Hexpm.Accounts.{AuditLogs, OrganizationDomain, OrganizationDomains}

  defmodule Resolver do
    def lookup(domain) do
      case Agent.get(__MODULE__, &Map.get(&1, to_string(domain), [])) do
        :unreachable -> raise "resolver did not answer"
        records -> records
      end
    end

    def break(domain) do
      Agent.update(__MODULE__, &Map.put(&1, domain, :unreachable))
    end

    def start(records) do
      {:ok, pid} = Agent.start_link(fn -> records end, name: __MODULE__)
      pid
    end

    def publish(domain, value) do
      Agent.update(__MODULE__, &Map.update(&1, domain, [value], fn rest -> [value | rest] end))
    end

    def withdraw(domain) do
      Agent.update(__MODULE__, &Map.delete(&1, domain))
    end
  end

  setup do
    organization = insert(:organization)
    admin = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")

    Resolver.start(%{})
    app_env(:hexpm, :domain_dns_resolver, Resolver)

    %{organization: organization, admin: admin}
  end

  describe "add/4" do
    test "normalizes and issues a token", %{organization: organization, admin: admin} do
      assert {:ok, domain} = add(organization, admin, "  Example.COM ")

      assert domain.domain == "example.com"
      assert byte_size(domain.verification_token) > 20
      refute OrganizationDomain.verified?(domain)
    end

    test "drops a wildcard prefix rather than storing it", %{
      organization: organization,
      admin: admin
    } do
      assert {:ok, domain} = add(organization, admin, "*.example.com")
      assert domain.domain == "example.com"
    end

    test "rejects something that is not a domain", %{organization: organization, admin: admin} do
      assert {:error, changeset} = add(organization, admin, "not a domain")
      assert errors_on(changeset).domain == "is not a valid domain name"

      assert {:error, changeset} = add(organization, admin, "localhost")
      assert errors_on(changeset).domain == "is not a valid domain name"
    end

    test "refuses the same domain twice for one organization", %{
      organization: organization,
      admin: admin
    } do
      assert {:ok, _domain} = add(organization, admin, "example.com")
      assert {:error, changeset} = add(organization, admin, "example.com")
      assert errors_on(changeset).domain == "has already been added"
    end

    test "lets two organizations claim the same domain", %{
      organization: organization,
      admin: admin
    } do
      other = insert(:organization)

      assert {:ok, first} = add(organization, admin, "example.com")
      assert {:ok, second} = add(other, admin, "example.com")

      refute first.verification_token == second.verification_token
    end
  end

  describe "verify/3" do
    test "verifies when the record is published", %{organization: organization, admin: admin} do
      {:ok, domain} = add(organization, admin, "example.com")
      Resolver.publish("example.com", OrganizationDomain.record_value(domain))

      assert {:ok, domain} = verify(organization, domain, admin)
      assert OrganizationDomain.verified?(domain)
      assert domain.last_checked_at
    end

    @tag :capture_log
    test "says the lookup failed rather than that the record is missing", %{
      organization: organization,
      admin: admin
    } do
      {:ok, domain} = add(organization, admin, "example.com")
      Resolver.break("example.com")

      assert {:error, :lookup_failed} = verify(organization, domain, admin)
    end

    test "refuses when the record is missing", %{organization: organization, admin: admin} do
      {:ok, domain} = add(organization, admin, "example.com")

      assert {:error, :record_not_found} = verify(organization, domain, admin)
      refute OrganizationDomain.verified?(Repo.get!(OrganizationDomain, domain.id))
      assert Repo.get!(OrganizationDomain, domain.id).last_checked_at
    end

    test "refuses another organization's token", %{organization: organization, admin: admin} do
      other = insert(:organization)
      insert(:organization_user, organization: other, user: admin, role: "admin")
      {:ok, ours} = add(organization, admin, "example.com")
      {:ok, theirs} = add(other, admin, "example.com")

      Resolver.publish("example.com", OrganizationDomain.record_value(theirs))

      assert {:error, :record_not_found} = verify(organization, ours, admin)
      assert {:ok, _domain} = verify(other, theirs, admin)
    end

    test "refuses someone who lost their role while the lookup ran", %{
      organization: organization,
      admin: admin
    } do
      {:ok, domain} = add(organization, admin, "example.com")
      Resolver.publish("example.com", OrganizationDomain.record_value(domain))

      Repo.update_all(
        from(member in Hexpm.Accounts.OrganizationUser,
          where: member.organization_id == ^organization.id,
          where: member.user_id == ^admin.id
        ),
        set: [role: "write"]
      )

      # A verified domain admits people through just-in-time membership, so the
      # role is taken again under a lock rather than trusted from before the
      # lookup.
      assert {:error, :admin_required} = verify(organization, domain, admin)
      refute OrganizationDomain.verified?(Repo.get!(OrganizationDomain, domain.id))
    end

    test "ignores unrelated records on the same name", %{
      organization: organization,
      admin: admin
    } do
      {:ok, domain} = add(organization, admin, "example.com")
      Resolver.publish("example.com", "v=spf1 include:example.net ~all")
      Resolver.publish("example.com", OrganizationDomain.record_value(domain))

      assert {:ok, _domain} = verify(organization, domain, admin)
    end

    test "audits the verification", %{organization: organization, admin: admin} do
      {:ok, domain} = add(organization, admin, "example.com")
      Resolver.publish("example.com", OrganizationDomain.record_value(domain))
      {:ok, _domain} = verify(organization, domain, admin)

      actions = AuditLogs.all_by(admin) |> Enum.map(& &1.action)
      assert "organization.domain.add" in actions
      assert "organization.domain.verify" in actions
    end
  end

  describe "verified_for_email?/2" do
    test "matches the address domain exactly", %{organization: organization, admin: admin} do
      {:ok, domain} = add(organization, admin, "example.com")
      Resolver.publish("example.com", OrganizationDomain.record_value(domain))
      {:ok, _domain} = verify(organization, domain, admin)

      assert OrganizationDomains.verified_for_email?(organization, "person@example.com")
      assert OrganizationDomains.verified_for_email?(organization, "person@EXAMPLE.com")
    end

    test "does not extend to subdomains", %{organization: organization, admin: admin} do
      {:ok, domain} = add(organization, admin, "example.com")
      Resolver.publish("example.com", OrganizationDomain.record_value(domain))
      {:ok, _domain} = verify(organization, domain, admin)

      refute OrganizationDomains.verified_for_email?(organization, "person@mail.example.com")
    end

    test "is false while the domain is only claimed", %{
      organization: organization,
      admin: admin
    } do
      {:ok, _domain} = add(organization, admin, "example.com")

      refute OrganizationDomains.verified_for_email?(organization, "person@example.com")
    end

    test "is false for another organization's verified domain", %{
      organization: organization,
      admin: admin
    } do
      {:ok, domain} = add(organization, admin, "example.com")
      Resolver.publish("example.com", OrganizationDomain.record_value(domain))
      {:ok, _domain} = verify(organization, domain, admin)

      refute OrganizationDomains.verified_for_email?(insert(:organization), "person@example.com")
    end

    test "is false for something that is not an address", %{organization: organization} do
      refute OrganizationDomains.verified_for_email?(organization, "person")
      refute OrganizationDomains.verified_for_email?(organization, nil)
    end
  end

  describe "recheck_all/1" do
    test "clears a domain whose record has gone", %{organization: organization, admin: admin} do
      {:ok, domain} = add(organization, admin, "example.com")
      Resolver.publish("example.com", OrganizationDomain.record_value(domain))
      {:ok, domain} = verify(organization, domain, admin)

      age_out(domain)
      Resolver.withdraw("example.com")

      assert OrganizationDomains.recheck_all() == 1
      refute OrganizationDomain.verified?(Repo.get!(OrganizationDomain, domain.id))

      assert Enum.any?(
               AuditLogs.all_by(organization),
               &(&1.action == "organization.domain.unverify")
             )
    end

    @tag :capture_log
    test "leaves a domain verified when the resolver does not answer", %{
      organization: organization,
      admin: admin
    } do
      {:ok, domain} = add(organization, admin, "example.com")
      Resolver.publish("example.com", OrganizationDomain.record_value(domain))
      {:ok, domain} = verify(organization, domain, admin)

      age_out(domain)
      Resolver.break("example.com")

      # A resolver that cannot answer is not a record that is gone. Clearing on
      # this would take every organization's domains down with one bad minute
      # of DNS, and nothing re-checks a cleared domain.
      assert OrganizationDomains.recheck_all() == 0
      assert OrganizationDomain.verified?(Repo.get!(OrganizationDomain, domain.id))
      refute Repo.get!(OrganizationDomain, domain.id).last_checked_at == nil
    end

    test "leaves a domain whose record is still there", %{
      organization: organization,
      admin: admin
    } do
      {:ok, domain} = add(organization, admin, "example.com")
      Resolver.publish("example.com", OrganizationDomain.record_value(domain))
      {:ok, domain} = verify(organization, domain, admin)

      age_out(domain)

      assert OrganizationDomains.recheck_all() == 0
      assert OrganizationDomain.verified?(Repo.get!(OrganizationDomain, domain.id))
    end

    test "does not re-check a domain looked at recently", %{
      organization: organization,
      admin: admin
    } do
      {:ok, domain} = add(organization, admin, "example.com")
      Resolver.publish("example.com", OrganizationDomain.record_value(domain))
      {:ok, domain} = verify(organization, domain, admin)

      Resolver.withdraw("example.com")

      assert OrganizationDomains.recheck_all() == 0
      assert OrganizationDomain.verified?(Repo.get!(OrganizationDomain, domain.id))
    end
  end

  defp add(organization, admin, domain) do
    OrganizationDomains.add(organization, %{"domain" => domain}, admin, audit: audit_data(admin))
  end

  defp verify(organization, domain, admin) do
    OrganizationDomains.verify(organization, domain, audit: audit_data(admin))
  end

  defp age_out(domain) do
    domain
    |> Ecto.Changeset.change(
      last_checked_at: DateTime.add(DateTime.utc_now(), -2 * 24 * 60 * 60, :second)
    )
    |> Repo.update!()
  end
end
