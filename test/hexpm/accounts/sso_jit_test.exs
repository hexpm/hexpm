defmodule Hexpm.Accounts.SSOJITTest do
  use Hexpm.DataCase

  alias Hexpm.Accounts.{OrganizationDomains, Organizations, Seats, SSO}
  alias Hexpm.Accounts.SSO.{Connection, Failure, Identity, OIDC}
  alias Hexpm.Emails.OutboxEntry

  setup :verify_on_exit!

  defmodule Resolver do
    def lookup(domain) do
      Agent.get(__MODULE__, &Map.get(&1, to_string(domain), []))
    end

    def start, do: Agent.start_link(fn -> %{} end, name: __MODULE__)

    def publish(domain, value) do
      Agent.update(__MODULE__, &Map.put(&1, domain, [value]))
    end
  end

  setup do
    organization = insert(:organization, billing_seats: 3)
    admin = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")

    config = Application.fetch_env!(:hexpm, :organization_sso)

    Application.put_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, mode: :beta, beta_organizations: [organization.name])
    )

    on_exit(fn -> Application.put_env(:hexpm, :organization_sso, config) end)

    Resolver.start()
    app_env(:hexpm, :domain_dns_resolver, Resolver)

    connection =
      insert(:organization_sso_connection,
        organization: organization,
        tested_at: DateTime.utc_now(),
        enabled_at: DateTime.utc_now()
      )

    %{organization: organization, admin: admin, connection: connection}
  end

  describe "configure_jit/3" do
    test "refuses to turn on without a verified domain", context do
      assert {:error, :domain_required} = enable_jit(context, "block")
      assert {:error, :domain_required} = enable_jit(context, "expand")
    end

    test "turns on once a domain is verified", context do
      verify_domain(context, "example.com")

      assert {:ok, connection} = enable_jit(context, "block", "write")
      assert connection.jit_seat_policy == "block"
      assert connection.jit_role == "write"
      assert Connection.jit_enabled?(connection)
    end

    test "cannot be turned on without choosing what happens at the limit", context do
      verify_domain(context, "example.com")

      assert {:ok, connection} =
               SSO.configure_jit(context.organization, %{"jit_role" => "read"},
                 audit: audit_data(context.admin)
               )

      refute Connection.jit_enabled?(connection)
    end

    test "can always be turned off", context do
      verify_domain(context, "example.com")
      {:ok, _connection} = enable_jit(context, "block")

      assert {:ok, connection} =
               SSO.configure_jit(
                 context.organization,
                 %{"jit_seat_policy" => "", "jit_role" => "read"},
                 audit: audit_data(context.admin)
               )

      refute Connection.jit_enabled?(connection)
    end

    test "rejects a policy that is not one of the two", context do
      verify_domain(context, "example.com")

      assert {:error, %Ecto.Changeset{}} = enable_jit(context, "whatever")
    end
  end

  describe "with just-in-time membership off" do
    test "a non-member cannot even start", context do
      stub_authorization_uri()

      assert {:error, :not_member} =
               SSO.start_login(context.organization, insert(:user), nil, callback_url())
    end
  end

  describe "with just-in-time membership on" do
    setup context do
      verify_domain(context, "example.com")
      {:ok, connection} = enable_jit(context, "block", "write")
      Map.put(context, :connection, connection)
    end

    test "a non-member on a verified domain joins after consenting", context do
      newcomer = insert(:user)
      transaction = start_login(context, newcomer)

      assert {:ok, {:link, transaction_id, link_token, _return}} =
               complete(transaction, claims("newcomer@example.com"), newcomer)

      # Consent has not been given, so nothing has been joined or billed.
      refute Organizations.get_role(context.organization, newcomer)

      assert {:ok, {%Identity{}, _org_session}} =
               SSO.complete_link(
                 transaction_id,
                 link_token,
                 Repo.preload(newcomer, :emails),
                 browser_session(newcomer).id,
                 audit_data(newcomer)
               )

      assert Organizations.get_role(context.organization, newcomer) == "write"
    end

    test "abandoning the consent screen leaves no membership", context do
      newcomer = insert(:user)
      transaction = start_login(context, newcomer)

      assert {:ok, {:link, _transaction_id, _token, _return}} =
               complete(transaction, claims("newcomer@example.com"), newcomer)

      refute Organizations.get_role(context.organization, newcomer)
      assert Seats.used(context.organization) == 1
    end

    test "a non-member on an unverified domain is turned away", context do
      newcomer = insert(:user)
      transaction = start_login(context, newcomer)

      assert {:error, :not_member} =
               complete(transaction, claims("newcomer@elsewhere.com"), newcomer)

      refute Organizations.get_role(context.organization, newcomer)
    end

    test "an address the provider did not confirm is turned away", context do
      newcomer = insert(:user)
      transaction = start_login(context, newcomer)

      assert {:error, :provider_email_unverified} =
               complete(transaction, claims("newcomer@example.com", false), newcomer)

      refute Organizations.get_role(context.organization, newcomer)
    end

    test "a subdomain of a verified domain does not count", context do
      newcomer = insert(:user)
      transaction = start_login(context, newcomer)

      assert {:error, :not_member} =
               complete(transaction, claims("newcomer@mail.example.com"), newcomer)
    end

    test "an existing member still links the ordinary way", context do
      member = insert(:user)
      insert(:organization_user, organization: context.organization, user: member, role: "read")
      transaction = start_login(context, member)

      assert {:ok, {:link, _id, _token, _return}} =
               complete(transaction, claims("member@elsewhere.com"), member)

      # Their role is untouched by the connection's join role.
      assert Organizations.get_role(context.organization, member) == "read"
    end

    test "refuses and notifies the administrators when the seats have run out", context do
      fill_seats(context.organization)
      newcomer = insert(:user)
      transaction = start_login(context, newcomer)

      assert {:error, :seats_exhausted} =
               complete(transaction, claims("newcomer@example.com"), newcomer)

      refute Organizations.get_role(context.organization, newcomer)
      assert [failure] = SSO.failures(context.connection)
      assert failure.code == "seats_exhausted"
      assert [entry] = Repo.all(OutboxEntry)
      assert entry.category == "sso.seats_exhausted"
    end

    test "does not mail the administrators again within the hour", context do
      fill_seats(context.organization)

      for _attempt <- 1..3 do
        newcomer = insert(:user)
        transaction = start_login(context, newcomer)
        assert {:error, :seats_exhausted} = complete(transaction, claims(), newcomer)
      end

      assert length(Repo.all(OutboxEntry)) == 1
      assert length(Repo.all(Failure)) == 3
    end

    test "re-admits a linked account whose membership was removed", context do
      member = insert(:user)
      insert(:organization_user, organization: context.organization, user: member, role: "read")

      insert(:organization_sso_identity,
        connection: context.connection,
        organization: context.organization,
        user: member
      )

      Repo.delete_all(
        from(organization_user in Hexpm.Accounts.OrganizationUser,
          where: organization_user.user_id == ^member.id
        )
      )

      transaction = start_login(context, member)

      assert {:ok, {:login, user, _org_session, _return}} =
               complete(
                 transaction,
                 claims("member@example.com"),
                 member,
                 browser_session(member).id
               )

      assert user.id == member.id
      assert Organizations.get_role(context.organization, member) == "write"
    end

    test "does not re-admit when the address is no longer on a verified domain", context do
      member = insert(:user)

      insert(:organization_sso_identity,
        connection: context.connection,
        organization: context.organization,
        user: member
      )

      transaction = start_login(context, member)

      assert {:error, :not_member} =
               complete(transaction, claims("member@elsewhere.com"), member)

      refute Organizations.get_role(context.organization, member)
      refute Repo.exists?(Identity)
    end
  end

  describe "maybe_expand_seats/3" do
    setup context do
      verify_domain(context, "example.com")
      {:ok, connection} = enable_jit(context, "expand")
      Map.put(context, :connection, connection)
    end

    test "buys a seat when the organization is full", context do
      fill_seats(context.organization)
      newcomer = insert(:user)
      transaction = start_login(context, newcomer)

      Mox.stub(Hexpm.Billing.Mock, :update, fn name, params ->
        assert name == context.organization.name
        assert params["quantity"] == 4
        {:ok, %{"quantity" => params["quantity"]}}
      end)

      assert :ok = SSO.maybe_expand_seats(transaction, newcomer, claims("newcomer@example.com"))
      assert Repo.get!(Hexpm.Accounts.Organization, context.organization.id).billing_seats == 4

      assert {:ok, {:link, _id, _token, _return}} =
               complete(transaction, claims("newcomer@example.com"), newcomer)
    end

    test "buys nothing when a seat is already free", context do
      newcomer = insert(:user)
      transaction = start_login(context, newcomer)

      Mox.stub(Hexpm.Billing.Mock, :update, fn _name, _params ->
        flunk("billing must not be called when a seat is free")
      end)

      assert :ok = SSO.maybe_expand_seats(transaction, newcomer, claims("newcomer@example.com"))
    end

    test "buys nothing for someone who is already a member", context do
      member = insert(:user)
      insert(:organization_user, organization: context.organization, user: member, role: "read")
      fill_seats(context.organization)
      transaction = start_login(context, member)

      Mox.stub(Hexpm.Billing.Mock, :update, fn _name, _params ->
        flunk("billing must not be called for an existing member")
      end)

      assert :ok = SSO.maybe_expand_seats(transaction, member, claims("member@example.com"))
    end

    test "buys nothing when the address is not on a verified domain", context do
      fill_seats(context.organization)
      newcomer = insert(:user)
      transaction = start_login(context, newcomer)

      Mox.stub(Hexpm.Billing.Mock, :update, fn _name, _params ->
        flunk("billing must not be called for an unverified domain")
      end)

      assert :ok = SSO.maybe_expand_seats(transaction, newcomer, claims("newcomer@elsewhere.com"))
    end

    test "does not buy a seat for an address the provider did not confirm", context do
      fill_seats(context.organization)
      newcomer = insert(:user)
      transaction = start_login(context, newcomer)

      Mox.stub(Hexpm.Billing.Mock, :update, fn _name, _params ->
        flunk("billing must not be called for an unverified address")
      end)

      assert :ok =
               SSO.maybe_expand_seats(
                 transaction,
                 newcomer,
                 claims("newcomer@example.com", false)
               )
    end

    test "does not retry a purchase that already failed", context do
      fill_seats(context.organization)
      calls = :counters.new(1, [])

      Mox.stub(Hexpm.Billing.Mock, :update, fn _name, _params ->
        :counters.add(calls, 1, 1)
        {:error, %{"errors" => "card declined"}}
      end)

      for _attempt <- 1..3 do
        newcomer = insert(:user)
        transaction = start_login(context, newcomer)
        assert :ok = SSO.maybe_expand_seats(transaction, newcomer, claims())
      end

      # A card that needs attention must not turn every login into another
      # charge attempt.
      assert :counters.get(calls, 1) == 1
    end

    test "a failed purchase does not admit anyone", context do
      fill_seats(context.organization)
      newcomer = insert(:user)
      transaction = start_login(context, newcomer)

      Mox.stub(Hexpm.Billing.Mock, :update, fn _name, _params ->
        {:error, %{"errors" => "card declined"}}
      end)

      assert :ok = SSO.maybe_expand_seats(transaction, newcomer, claims("newcomer@example.com"))

      assert {:error, :seats_exhausted} =
               complete(transaction, claims("newcomer@example.com"), newcomer)

      refute Organizations.get_role(context.organization, newcomer)
    end
  end

  defp enable_jit(context, policy, role \\ "read") do
    SSO.configure_jit(
      context.organization,
      %{"jit_seat_policy" => policy, "jit_role" => role},
      audit: audit_data(context.admin)
    )
  end

  defp verify_domain(context, domain) do
    {:ok, record} =
      OrganizationDomains.add(context.organization, %{"domain" => domain}, context.admin,
        audit: audit_data(context.admin)
      )

    Resolver.publish(domain, Hexpm.Accounts.OrganizationDomain.record_value(record))

    {:ok, record} =
      OrganizationDomains.verify(context.organization, record, audit: audit_data(context.admin))

    record
  end

  # One admin plus two more members against three paid seats.
  defp fill_seats(organization) do
    for _seat <- 1..2 do
      insert(:organization_user, organization: organization, user: insert(:user), role: "read")
    end
  end

  defp start_login(context, user) do
    stub_authorization_uri()

    {:ok, transaction, _uri} =
      SSO.start_login(context.organization, user, nil, callback_url())

    SSO.get_transaction_by_state(transaction.raw_state)
  end

  defp complete(transaction, claims, user, user_session_id \\ nil) do
    SSO.complete_callback(transaction, claims, user, user_session_id, audit_data(user))
  end

  defp browser_session(user) do
    {:ok, session, _token} =
      Hexpm.UserSessions.create_browser_session(user, audit: audit_data(user))

    session
  end

  defp stub_authorization_uri do
    Mox.stub(OIDC.Mock, :authorization_uri, fn _connection,
                                               _transaction,
                                               _redirect_uri,
                                               _secret ->
      {:ok, "https://identity.example.com/authorize"}
    end)
  end

  defp claims(email \\ "newcomer@example.com", email_verified \\ true) do
    %{
      issuer: "https://identity.example.com/oauth2/default",
      subject: "00u123",
      email: email,
      email_verified: email_verified,
      jwks_document: nil
    }
  end

  defp callback_url, do: "https://hex.pm/sso/callback"
end
