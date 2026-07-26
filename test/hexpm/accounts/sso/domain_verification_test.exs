defmodule Hexpm.Accounts.SSO.DomainVerificationTest do
  use Hexpm.DataCase

  alias Hexpm.Accounts.{AuditLogs, SSO}

  alias Hexpm.Accounts.SSO.{
    Connection,
    Domain,
    DomainName,
    DomainRevalidator,
    DomainVerification,
    Transaction
  }

  alias Hexpm.Emails.OutboxEntry

  setup :verify_on_exit!

  setup do
    organization = insert(:organization)
    admin = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")
    enable_beta_for([organization])

    %{admin: admin, organization: organization}
  end

  test "canonicalizes IDNA domains and rejects unsafe or non-registrable names" do
    assert DomainName.canonicalize(" Example.COM. ") == {:ok, "example.com"}
    assert DomainName.canonicalize("münchen.de") == {:ok, "xn--mnchen-3ya.de"}
    assert DomainName.from_email("user@EXAMPLE.com.") == {:ok, "example.com"}

    for invalid <- [
          "",
          "com",
          "co.uk",
          "github.io",
          "127.0.0.1",
          "::1",
          "*.example.com",
          ".example.com",
          "example..com",
          "example.com..",
          "-example.com",
          "example-.com"
        ] do
      assert DomainName.canonicalize(invalid) == {:error, :invalid_domain}
    end

    assert DomainName.from_email("user@@example.com") == {:error, :invalid_email}
    assert DomainName.from_email("@example.com") == {:error, :invalid_email}
    assert DomainName.from_email(String.duplicate("a", 321)) == {:error, :invalid_email}
    assert DomainName.canonicalize(<<255>>) == {:error, :invalid_domain}
    assert DomainName.from_email(<<"user@", 255>>) == {:error, :invalid_email}

    maximum_domain = long_domain(46)
    assert byte_size(maximum_domain) == 242
    assert DomainName.canonicalize(maximum_domain) == {:ok, maximum_domain}
    assert DomainName.canonicalize(long_domain(47)) == {:error, :invalid_domain}
  end

  test "atomically limits the number of domains per organization", context do
    for index <- 1..10 do
      insert(:organization_sso_domain,
        organization: context.organization,
        domain: "domain-#{index}.example.com",
        challenge: "hexpm-sso-verification=domain-#{index}"
      )
    end

    assert SSO.add_domain(context.organization, "overflow.example.com",
             audit: audit_data(context.admin)
           ) == {:error, :domain_limit_reached}

    domain =
      from(domain in Domain,
        where: domain.organization_id == ^context.organization.id,
        limit: 1
      )
      |> Repo.one!()

    Repo.delete!(domain)

    assert {:ok, %Domain{domain: "replacement.example.com"}} =
             SSO.add_domain(context.organization, "replacement.example.com",
               audit: audit_data(context.admin)
             )
  end

  test "allows a domain on multiple organizations with distinct challenges", context do
    other = insert(:organization)
    other_admin = insert(:user)
    insert(:organization_user, organization: other, user: other_admin, role: "admin")
    enable_beta_for([context.organization, other])

    assert {:ok, first} =
             SSO.add_domain(context.organization, "SHARED.example.com.",
               audit: audit_data(context.admin)
             )

    assert {:ok, second} =
             SSO.add_domain(other, "shared.example.com", audit: audit_data(other_admin))

    assert first.domain == "shared.example.com"
    assert second.domain == first.domain
    assert first.challenge != second.challenge
    assert first.challenge_generation == 1
    assert second.challenge_generation == 1

    assert Enum.sort(AuditLogs.all_by(context.organization) |> actions()) ==
             ["sso.domain.add"]
  end

  test "discovery returns only gated organizations with an enabled connection and current lease",
       context do
    other = insert(:organization)
    enable_beta_for([context.organization, other])

    insert(:organization_sso_connection,
      organization: context.organization,
      enabled_at: DateTime.utc_now()
    )

    insert(:organization_sso_connection, organization: other, enabled_at: DateTime.utc_now())

    first =
      verified_domain(context.organization,
        domain: "shared.example.com",
        discovery_enabled: true
      )

    unrelated_expired =
      verified_domain(context.organization,
        domain: "expired.example.com",
        valid_until: DateTime.add(DateTime.utc_now(), -1, :second)
      )

    verified_domain(other,
      domain: first.domain,
      discovery_enabled: true
    )

    assert Enum.map(SSO.discover_organizations("shared.example.com"), & &1.id) ==
             Enum.sort_by([context.organization, other], & &1.name)
             |> Enum.map(& &1.id)

    assert Repo.get!(Domain, unrelated_expired.id).state == "verified"

    Repo.update_all(
      from(domain in Domain, where: domain.organization_id == ^other.id),
      set: [valid_until: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert Enum.map(SSO.discover_organizations("shared.example.com"), & &1.id) ==
             [context.organization.id]

    Repo.update_all(
      from(domain in Domain, where: domain.id == ^first.id),
      set: [discovery_enabled: false]
    )

    assert SSO.discover_organizations("shared.example.com") == []
    assert SSO.discover_organizations("other.example.com") == []
  end

  test "every organization operation fails closed with the feature disabled", context do
    disable_sso()

    assert SSO.add_domain(context.organization, "example.com", audit: audit_data(context.admin)) ==
             {:error, :feature_disabled}

    refute Repo.exists?(Domain)
  end

  test "requires a current organization administrator", context do
    member = insert(:user)
    insert(:organization_user, organization: context.organization, user: member, role: "read")

    assert SSO.add_domain(context.organization, "example.com", audit: audit_data(member)) ==
             {:error, :admin_required}
  end

  test "verifies only an exact TXT challenge and starts a seven-day lease", context do
    {:ok, domain} =
      SSO.add_domain(context.organization, "example.com", audit: audit_data(context.admin))

    expect(Hexpm.Accounts.SSO.DomainResolver.Mock, :lookup_txt, fn name ->
      assert name == "_hexpm-sso.example.com"
      {:ok, ["unrelated=value", domain.challenge]}
    end)

    before_check = DateTime.utc_now()

    assert {:ok, {:verified, verified}} =
             SSO.verify_domain(context.organization, domain.id, audit: audit_data(context.admin))

    assert verified.state == "verified"
    assert verified.verified_at
    assert verified.last_checked_at
    assert verified.valid_until

    assert_datetime_between(
      verified.valid_until,
      DateTime.add(before_check, 7 * 24 * 60 * 60, :second),
      DateTime.add(DateTime.utc_now(), 7 * 24 * 60 * 60 + 1, :second)
    )

    assert "sso.domain.verify" in actions(AuditLogs.all_by(context.organization))
  end

  test "a missing initial challenge remains pending", context do
    {:ok, domain} =
      SSO.add_domain(context.organization, "example.com", audit: audit_data(context.admin))

    expect(Hexpm.Accounts.SSO.DomainResolver.Mock, :lookup_txt, fn _name ->
      {:definitive, :missing}
    end)

    assert {:ok, {:not_verified, checked}} =
             SSO.verify_domain(context.organization, domain.id, audit: audit_data(context.admin))

    assert checked.state == "pending"
    assert checked.last_checked_at
    refute checked.valid_until
  end

  test "successful background checks renew leases but transient failures never do", context do
    domain = verified_domain(context.organization, last_checked_at: ~U[2026-01-01 00:00:00Z])
    old_valid_until = domain.valid_until

    assert {:ok, {:transient, :servfail, transient}} =
             DomainVerification.apply_check(
               domain,
               {:transient, :servfail},
               :background
             )

    assert transient.state == "verified"
    assert transient.valid_until == old_valid_until

    assert {:ok, {:verified, renewed}} =
             DomainVerification.apply_check(
               transient,
               {:ok, [domain.challenge]},
               :background
             )

    assert DateTime.compare(renewed.valid_until, old_valid_until) == :gt
  end

  test "definitive background failure invalidates and cannot silently restore trust", context do
    domain =
      verified_domain(context.organization,
        discovery_enabled: true,
        automatic_linking_enabled: true
      )

    {transaction, outbox_entry} = pending_confirmation(context.organization, domain)

    assert {:ok, {:invalidated, invalid}} =
             DomainVerification.apply_check(
               domain,
               {:definitive, :missing},
               :background
             )

    assert invalid.state == "invalid"
    assert invalid.invalidated_at
    refute invalid.valid_until
    refute invalid.discovery_enabled
    refute invalid.automatic_linking_enabled
    assert_confirmation_cancelled(transaction, outbox_entry)

    audit =
      context.organization
      |> AuditLogs.all_by()
      |> Enum.find(&(&1.action == "sso.domain.invalidate"))

    assert audit.user_id == nil
    assert audit.organization_id == context.organization.id
    assert audit.params["domain"] == domain.domain
    assert audit.params["challenge_generation"] == domain.challenge_generation
    refute inspect(audit.params) =~ domain.challenge

    assert DomainVerification.apply_check(
             invalid,
             {:ok, [invalid.challenge]},
             :background
           ) == {:ok, :stale}

    assert {:ok, rotated} =
             SSO.rotate_domain(
               context.organization,
               invalid.id,
               audit: audit_data(context.admin)
             )

    assert rotated.state == "pending"
    assert rotated.challenge_generation == invalid.challenge_generation + 1
    assert rotated.challenge != invalid.challenge
    refute rotated.discovery_enabled
    refute rotated.automatic_linking_enabled
  end

  test "a result for an old challenge generation is discarded", context do
    domain = verified_domain(context.organization)

    assert {:ok, rotated} =
             SSO.rotate_domain(
               context.organization,
               domain.id,
               audit: audit_data(context.admin)
             )

    assert DomainVerification.apply_check(
             domain,
             {:ok, [domain.challenge]},
             :background
           ) == {:ok, :stale}

    assert Repo.get!(Domain, rotated.id).state == "pending"
  end

  test "query-time expiry invalidates the lease", context do
    other = insert(:organization)
    enable_beta_for([context.organization, other])

    unrelated_expired =
      verified_domain(other,
        domain: "unrelated.example.com",
        valid_until: DateTime.add(DateTime.utc_now(), -1, :second)
      )

    domain =
      verified_domain(context.organization,
        valid_until: DateTime.add(DateTime.utc_now(), -1, :second),
        discovery_enabled: true,
        automatic_linking_enabled: true
      )

    {transaction, outbox_entry} = pending_confirmation(context.organization, domain)

    assert [
             %Domain{
               state: "invalid",
               valid_until: nil,
               invalidated_at: invalidated_at,
               discovery_enabled: false,
               automatic_linking_enabled: false
             }
           ] =
             SSO.domains(context.organization)

    assert invalidated_at
    assert Repo.get!(Domain, domain.id).state == "invalid"
    assert Repo.get!(Domain, unrelated_expired.id).state == "verified"
    assert_confirmation_cancelled(transaction, outbox_entry)

    audit =
      context.organization
      |> AuditLogs.all_by()
      |> Enum.find(&(&1.action == "sso.domain.expire"))

    assert audit.user_id == nil
    assert audit.organization_id == context.organization.id
    assert audit.params["domain"] == domain.domain
    refute inspect(audit.params) =~ domain.challenge
  end

  test "rotation cancels pending confirmations after committing the new challenge", context do
    domain =
      verified_domain(context.organization,
        discovery_enabled: true,
        automatic_linking_enabled: true
      )

    {transaction, outbox_entry} = pending_confirmation(context.organization, domain)

    assert {:ok, rotated} =
             SSO.rotate_domain(context.organization, domain.id, audit: audit_data(context.admin))

    assert rotated.challenge_generation == domain.challenge_generation + 1
    refute rotated.discovery_enabled
    refute rotated.automatic_linking_enabled
    assert_confirmation_cancelled(transaction, outbox_entry)

    expect(Hexpm.Accounts.SSO.DomainResolver.Mock, :lookup_txt, fn _name ->
      {:ok, [rotated.challenge]}
    end)

    assert {:ok, {:verified, reverified}} =
             SSO.verify_domain(
               context.organization,
               rotated.id,
               audit: audit_data(context.admin)
             )

    refute reverified.discovery_enabled
    refute reverified.automatic_linking_enabled
  end

  test "disabling automatic linking cancels pending confirmations", context do
    domain = verified_domain(context.organization, automatic_linking_enabled: true)
    {transaction, outbox_entry} = pending_confirmation(context.organization, domain)

    assert {:ok, updated} =
             SSO.update_domain_policy(
               context.organization,
               domain.id,
               %{
                 "automatic_linking_enabled" => "false",
                 "discovery_enabled" => "false"
               },
               audit: audit_data(context.admin)
             )

    refute updated.automatic_linking_enabled
    assert_confirmation_cancelled(transaction, outbox_entry)
  end

  test "deleting a domain cancels confirmations captured before the foreign key is cleared",
       context do
    domain = verified_domain(context.organization, automatic_linking_enabled: true)
    {transaction, outbox_entry} = pending_confirmation(context.organization, domain)

    assert {:ok, %Domain{id: id}} =
             SSO.delete_domain(context.organization, domain.id, audit: audit_data(context.admin))

    assert id == domain.id
    refute Repo.get(Domain, domain.id)
    assert_confirmation_cancelled(transaction, outbox_entry)
  end

  test "domain policies require a current lease only when enabling a policy", context do
    pending = insert(:organization_sso_domain, organization: context.organization)

    assert SSO.update_domain_policy(
             context.organization,
             pending.id,
             %{"discovery_enabled" => "true"},
             audit: audit_data(context.admin)
           ) == {:error, :domain_not_verified}

    invalid =
      insert(:organization_sso_domain,
        organization: context.organization,
        state: "invalid",
        discovery_enabled: true,
        automatic_linking_enabled: true,
        valid_until: nil
      )

    assert {:ok, disabled} =
             SSO.update_domain_policy(
               context.organization,
               invalid.id,
               %{
                 "discovery_enabled" => "false",
                 "automatic_linking_enabled" => "false"
               },
               audit: audit_data(context.admin)
             )

    refute disabled.discovery_enabled
    refute disabled.automatic_linking_enabled

    verified = verified_domain(context.organization)

    assert SSO.update_domain_policy(
             context.organization,
             verified.id,
             %{"discovery_enabled" => "true"},
             audit: audit_data(context.admin)
           ) == {:error, :discovery_disclosure_acknowledgement_required}

    assert {:ok, updated} =
             SSO.update_domain_policy(
               context.organization,
               verified.id,
               %{
                 "discovery_enabled" => "true",
                 "discovery_disclosure_acknowledged" => "true",
                 "automatic_linking_enabled" => "true"
               },
               audit: audit_data(context.admin)
             )

    assert updated.discovery_enabled
    assert updated.automatic_linking_enabled
  end

  test "the scheduled worker is bounded and applies checks after resolution", context do
    due = verified_domain(context.organization, last_checked_at: ~U[2026-01-01 00:00:00Z])

    not_due =
      verified_domain(context.organization,
        domain: "recent.example.com",
        last_checked_at: DateTime.utc_now()
      )

    expect(Hexpm.Accounts.SSO.DomainResolver.Mock, :lookup_txt, fn name ->
      assert name == DomainVerification.challenge_name(due)
      {:ok, [due.challenge]}
    end)

    assert [{id, {:ok, {:verified, _domain}}}] =
             DomainVerification.revalidate_due(limit: 1)

    assert id == due.id
    assert Repo.get!(Domain, not_due.id).last_checked_at == not_due.last_checked_at

    assert DomainRevalidator.perform(%Oban.Job{args: %{"unexpected" => true}}) ==
             {:cancel, {:invalid_args, %{"unexpected" => true}}}
  end

  test "global lease expiry is bounded, deterministic, observable, and clears confirmations",
       context do
    expired_at = DateTime.add(DateTime.utc_now(), -1, :second)

    first =
      verified_domain(context.organization,
        domain: "first-expired.example.com",
        valid_until: expired_at,
        automatic_linking_enabled: true
      )

    second =
      verified_domain(context.organization,
        domain: "second-expired.example.com",
        valid_until: expired_at
      )

    third =
      verified_domain(context.organization,
        domain: "third-expired.example.com",
        valid_until: expired_at
      )

    {transaction, outbox_entry} = pending_confirmation(context.organization, first)
    handler_id = {__MODULE__, self(), make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:hexpm, :sso, :domain_expiration, :batch],
        fn _event, measurements, metadata, pid ->
          send(pid, {:domain_expiration_batch, measurements, metadata})
        end,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {2, nil} = DomainVerification.expire_leases(limit: 2)
    assert Repo.get!(Domain, first.id).state == "invalid"
    assert Repo.get!(Domain, second.id).state == "invalid"
    assert Repo.get!(Domain, third.id).state == "verified"
    assert_confirmation_cancelled(transaction, outbox_entry)

    assert_receive {:domain_expiration_batch,
                    %{due_count: 3, selected_count: 2, remaining_count: 1},
                    %{limit: 2, scope: :global}}
  end

  test "revalidation cannot renew an expired lease left in the expiration backlog", context do
    expired_at = DateTime.add(DateTime.utc_now(), -1, :second)

    first =
      verified_domain(context.organization,
        domain: "first-backlog.example.com",
        valid_until: expired_at,
        last_checked_at: ~U[2026-01-01 00:00:00Z]
      )

    second =
      verified_domain(context.organization,
        domain: "second-backlog.example.com",
        valid_until: expired_at,
        last_checked_at: ~U[2026-01-01 00:00:00Z]
      )

    assert DomainVerification.revalidate_due(expiration_limit: 1, limit: 1) == []
    assert Repo.get!(Domain, first.id).state == "invalid"
    assert Repo.get!(Domain, second.id).state == "verified"
    assert Repo.get!(Domain, second.id).valid_until == expired_at
  end

  test "the default revalidation batch fits inside the worker timeout" do
    assert DomainVerification.max_revalidation_batch_size() *
             Hexpm.Accounts.SSO.DomainResolver.Inet.timeout_ms() <
             DomainRevalidator.timeout_ms()
  end

  test "the scheduled worker filters gates before its fair lease-urgency limit", context do
    other = insert(:organization)
    disabled = insert(:organization)
    enable_beta_for([context.organization, other])

    old_check = ~U[2026-01-01 00:00:00Z]
    now = DateTime.utc_now()

    first =
      verified_domain(context.organization,
        domain: "first.example.com",
        last_checked_at: old_check,
        valid_until: DateTime.add(now, 2, :day)
      )

    second =
      verified_domain(context.organization,
        domain: "second.example.com",
        last_checked_at: old_check,
        valid_until: DateTime.add(now, 3, :day)
      )

    other_domain =
      verified_domain(other,
        domain: "other.example.com",
        last_checked_at: old_check,
        valid_until: DateTime.add(now, 6, :day)
      )

    verified_domain(disabled,
      domain: "disabled.example.com",
      last_checked_at: old_check,
      valid_until: DateTime.add(now, 1, :day)
    )

    challenges =
      Map.new([first, second, other_domain], fn domain ->
        {DomainVerification.challenge_name(domain), domain.challenge}
      end)

    stub(Hexpm.Accounts.SSO.DomainResolver.Mock, :lookup_txt, fn name ->
      {:ok, [Map.fetch!(challenges, name)]}
    end)

    handler_id = {__MODULE__, self(), make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:hexpm, :sso, :domain_revalidation, :batch],
        fn _event, measurements, metadata, pid ->
          send(pid, {:domain_revalidation_batch, measurements, metadata})
        end,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert [{first_id, _first_result}, {other_id, _other_result}] =
             DomainVerification.revalidate_due(limit: 2)

    assert first_id == first.id
    assert other_id == other_domain.id
    assert Repo.get!(Domain, second.id).last_checked_at == second.last_checked_at

    assert_receive {:domain_revalidation_batch,
                    %{due_count: 3, selected_count: 2, remaining_count: 1}, %{limit: 2}}
  end

  test "the scheduled worker fails closed without resolving when SSO is off", context do
    verified_domain(context.organization, last_checked_at: ~U[2026-01-01 00:00:00Z])
    disable_sso()

    assert DomainVerification.revalidate_due() == []
    assert DomainRevalidator.perform(%Oban.Job{args: %{}}) == :ok
  end

  defp verified_domain(organization, attrs \\ []) do
    defaults = [
      organization: organization,
      state: "verified",
      verified_at: DateTime.utc_now(),
      last_checked_at: DateTime.utc_now(),
      valid_until: DateTime.add(DateTime.utc_now(), 6 * 24 * 60 * 60, :second)
    ]

    insert(:organization_sso_domain, Keyword.merge(defaults, attrs))
  end

  defp pending_confirmation(organization, domain) do
    connection =
      Repo.get_by(Connection, organization_id: organization.id) ||
        insert(:organization_sso_connection,
          organization: organization,
          enabled_at: DateTime.utc_now()
        )

    user = insert(:user)
    insert(:organization_user, organization: organization, user: user, role: "read")
    email = List.first(user.emails)
    now = DateTime.utc_now()

    transaction =
      Repo.insert!(%Transaction{
        connection_id: connection.id,
        state_hash: :crypto.strong_rand_bytes(32),
        nonce: "nonce",
        code_verifier: "code-verifier",
        kind: "login",
        secret_slot: "active",
        connection_version: connection.version,
        secret_version: 1,
        redirect_uri: "https://hex.pm/sso/callback",
        expires_at: DateTime.add(now, 600, :second),
        consumed_at: now,
        issuer: connection.issuer,
        subject: "subject-#{System.unique_integer([:positive])}",
        provider_email: email.email,
        candidate_user_id: user.id,
        candidate_email_id: email.id,
        domain_id: domain.id,
        domain_challenge_generation: domain.challenge_generation,
        candidate_connection_version: connection.version,
        link_method: "confirmed_primary_email",
        confirmation_code_hash: :crypto.strong_rand_bytes(32),
        confirmation_expires_at: DateTime.add(now, 600, :second),
        confirmation_sends: 1,
        browser_capability_hash: :crypto.strong_rand_bytes(32)
      })

    outbox_entry =
      insert(:email_outbox_entry,
        category: "sso.confirmation_code",
        ordering_key: "sso-confirmation:#{transaction.id}",
        scope_key: "sso-confirmation:user:#{user.id}:connection:#{connection.id}"
      )

    {transaction, outbox_entry}
  end

  defp assert_confirmation_cancelled(transaction, outbox_entry) do
    transaction = Repo.get!(Transaction, transaction.id)

    assert transaction.cancelled_at
    refute transaction.candidate_user_id
    refute transaction.candidate_email_id
    refute transaction.domain_id
    refute transaction.confirmation_code_hash
    refute transaction.browser_capability_hash
    refute Repo.get(OutboxEntry, outbox_entry.id)
  end

  defp long_domain(final_label_length) do
    Enum.join(
      [
        String.duplicate("a", 63),
        String.duplicate("b", 63),
        String.duplicate("c", 63),
        String.duplicate("d", final_label_length),
        "com"
      ],
      "."
    )
  end

  defp actions(logs), do: Enum.map(logs, & &1.action)

  defp enable_beta_for(organizations) do
    config = Application.fetch_env!(:hexpm, :organization_sso)

    Application.put_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config,
        mode: :beta,
        beta_organizations: Enum.map(organizations, & &1.name)
      )
    )

    on_exit(fn -> Application.put_env(:hexpm, :organization_sso, config) end)
  end

  defp disable_sso do
    config = Application.fetch_env!(:hexpm, :organization_sso)
    Application.put_env(:hexpm, :organization_sso, Keyword.put(config, :mode, :off))
  end
end
