defmodule Hexpm.Accounts.OrganizationRecoveriesTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.{
    OrganizationRecoveries,
    OrganizationRecovery,
    Organizations,
    OrganizationUser
  }

  alias Hexpm.Emails.OutboxEntry

  setup :verify_on_exit!

  setup do
    organization = insert(:organization, billing_seats: 2)
    old_admin = insert(:user)
    member = insert(:user)
    insert(:organization_user, organization: organization, user: old_admin, role: "admin")
    insert(:organization_user, organization: organization, user: member, role: "read")
    new_admin = insert(:user)

    %{organization: organization, old_admin: old_admin, member: member, new_admin: new_admin}
  end

  defp stub_billing(email \\ "billing@example.com") do
    stub(Hexpm.Billing.Mock, :get, fn _organization, _opts -> %{"email" => email} end)
  end

  defp expect_payment_verification(organization) do
    name = organization.name

    expect(Hexpm.Billing.Mock, :create_payment_verification, fn ^name ->
      {:ok, %{"brand" => "visa", "last4" => "4242", "amount" => 100, "currency" => "usd"}}
    end)
  end

  defp start!(organization, user) do
    stub_billing()
    expect_payment_verification(organization)
    {:ok, recovery} = OrganizationRecoveries.start(organization, user, nil)
    recovery
  end

  defp verify!(recovery, user) do
    expect(Hexpm.Billing.Mock, :verify_payment, fn _name, "ABC123" -> :ok end)
    recovery = OrganizationRecoveries.get_by_token(recovery.raw_token)
    {:ok, recovery} = OrganizationRecoveries.verify(recovery, user, "ABC123")
    recovery
  end

  defp make_due!(recovery) do
    recovery
    |> Ecto.Changeset.change(completes_at: DateTime.add(DateTime.utc_now(), -1, :second))
    |> Repo.update!()
  end

  defp entries(recovery) do
    Repo.all(
      from(e in OutboxEntry,
        where: e.group_key == ^"organization-recovery:#{recovery.id}",
        order_by: e.id
      )
    )
  end

  defp addresses(entry), do: Enum.map(entry.email["to"], & &1["address"]) |> Enum.sort()

  defp primary(user), do: hd(Repo.preload(user, :emails).emails).email

  describe "start/3" do
    test "charges the card and mails the billing address", context do
      %{organization: organization, old_admin: old_admin, new_admin: new_admin} = context
      recovery = start!(organization, new_admin)

      assert recovery.user_id == new_admin.id
      assert recovery.old_admin_id == old_admin.id
      assert recovery.billing_email == "billing@example.com"
      assert recovery.card_brand == "visa"
      assert recovery.card_last4 == "4242"
      assert recovery.token_hash == :crypto.hash(:sha256, recovery.raw_token)

      assert [%OutboxEntry{type: "organization_recovery_verification"} = entry] =
               entries(recovery)

      assert addresses(entry) == ["billing@example.com"]
      assert entry.email["text_body"] =~ "/organization-recovery?token=#{recovery.raw_token}"
      assert entry.email["text_body"] =~ "visa card ending in 4242"
    end

    test "refuses while another administrator can act", context do
      %{organization: organization, member: member, new_admin: new_admin} = context
      Organizations.change_role(organization, member, %{"role" => "admin"}, audit: audit())

      assert OrganizationRecoveries.start(organization, new_admin, nil) == {:error, :other_admins}
    end

    test "starts without an old administrator when there is none", context do
      %{organization: organization, old_admin: old_admin, new_admin: new_admin} = context
      Repo.delete_all(from(m in OrganizationUser, where: m.user_id == ^old_admin.id))

      recovery = start!(organization, new_admin)
      assert recovery.old_admin_id == nil
    end

    test "refuses an account that is already the administrator", context do
      %{organization: organization, old_admin: old_admin} = context

      assert OrganizationRecoveries.start(organization, old_admin, nil) ==
               {:error, :already_admin}
    end

    test "refuses an organization behind single sign-on", context do
      %{organization: organization, new_admin: new_admin} = context
      insert(:organization_sso_connection, organization: organization)

      assert OrganizationRecoveries.start(organization, new_admin, nil) ==
               {:error, :sso_connection}
    end

    test "refuses an account without a verified primary email", context do
      %{organization: organization} = context
      user = insert(:user, emails: [build(:email, verified: false)])

      assert OrganizationRecoveries.start(organization, user, nil) ==
               {:error, :unverified_primary_email}
    end

    test "refuses a second recovery", context do
      %{organization: organization, new_admin: new_admin} = context
      start!(organization, new_admin)

      assert OrganizationRecoveries.start(organization, insert(:user), nil) ==
               {:error, :recovery_in_progress}
    end

    test "refuses without a billing email", context do
      %{organization: organization, new_admin: new_admin} = context
      stub(Hexpm.Billing.Mock, :get, fn _organization, _opts -> nil end)

      assert OrganizationRecoveries.start(organization, new_admin, nil) == {:error, :no_billing}
    end

    test "passes on why the card couldn't be charged", context do
      %{organization: organization, new_admin: new_admin} = context
      stub_billing()

      expect(Hexpm.Billing.Mock, :create_payment_verification, fn _name ->
        {:error, %{"errors" => %{"payment_verification" => "no_card"}}}
      end)

      assert OrganizationRecoveries.start(organization, new_admin, nil) ==
               {:error, {:payment_verification, "no_card"}}

      refute OrganizationRecoveries.get_open(organization)
    end
  end

  describe "get_by_token/1" do
    test "finds nothing for an expired link", context do
      %{organization: organization, new_admin: new_admin} = context
      recovery = start!(organization, new_admin)

      recovery
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
      |> Repo.update!()

      refute OrganizationRecoveries.get_by_token(recovery.raw_token)
      refute OrganizationRecoveries.get_by_token("unknown")
    end

    test "still finds a verified recovery after the link expires", context do
      %{organization: organization, new_admin: new_admin} = context
      recovery = start!(organization, new_admin)
      verify!(recovery, new_admin)

      recovery
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
      |> Repo.update!()

      assert OrganizationRecoveries.get_by_token(recovery.raw_token).id == recovery.id
    end
  end

  describe "verify/3" do
    test "starts the notice period and tells the members", context do
      %{organization: organization, old_admin: old_admin, member: member} = context
      %{new_admin: new_admin} = context
      second_address = insert(:email, user: old_admin, primary: false, public: false)

      recovery = start!(organization, new_admin)
      verified = verify!(recovery, new_admin)

      assert DateTime.diff(verified.completes_at, verified.verified_at, :day) == 14

      assert [_verification, %OutboxEntry{type: "organization_recovery_notice"} = notice] =
               entries(recovery)

      assert addresses(notice) ==
               Enum.sort([primary(old_admin), second_address.email, primary(member)])

      assert notice.email["text_body"] =~ "#{old_admin.username} is removed from it"
    end

    test "refuses another account", context do
      %{organization: organization, member: member, new_admin: new_admin} = context
      recovery = start!(organization, new_admin)
      recovery = OrganizationRecoveries.get_by_token(recovery.raw_token)

      assert OrganizationRecoveries.verify(recovery, member, "ABC123") == {:error, :wrong_user}
    end

    test "passes on a wrong code", context do
      %{organization: organization, new_admin: new_admin} = context
      recovery = start!(organization, new_admin)
      recovery = OrganizationRecoveries.get_by_token(recovery.raw_token)

      expect(Hexpm.Billing.Mock, :verify_payment, fn _name, "WRONG1" ->
        {:error, %{"errors" => %{"code" => "invalid"}}}
      end)

      assert OrganizationRecoveries.verify(recovery, new_admin, "WRONG1") ==
               {:error, {:code, "invalid"}}

      refute reload(recovery).verified_at
    end

    test "leaves a recovery canceled while the code was checked canceled", context do
      %{organization: organization, new_admin: new_admin} = context
      recovery = start!(organization, new_admin)
      recovery = OrganizationRecoveries.get_by_token(recovery.raw_token)

      expect(Hexpm.Billing.Mock, :verify_payment, fn _name, _code ->
        :ok = OrganizationRecoveries.cancel(organization)
        :ok
      end)

      assert OrganizationRecoveries.verify(recovery, new_admin, "ABC123") ==
               {:error, :recovery_unavailable}

      assert reload(recovery).canceled_at
      refute reload(recovery).verified_at
    end
  end

  describe "complete/2" do
    test "refuses before the notice period has passed", context do
      %{organization: organization, new_admin: new_admin} = context
      recovery = organization |> start!(new_admin) |> verify!(new_admin)

      assert OrganizationRecoveries.complete(recovery, audit: audit()) ==
               {:error, :notice_period}
    end

    test "refuses an unverified recovery", context do
      %{organization: organization, new_admin: new_admin} = context
      recovery = start!(organization, new_admin)

      assert OrganizationRecoveries.complete(recovery, audit: audit()) ==
               {:error, :recovery_unavailable}
    end

    test "swaps the administrators without taking a seat", context do
      %{organization: organization, old_admin: old_admin, new_admin: new_admin} = context
      recovery = organization |> start!(new_admin) |> verify!(new_admin) |> make_due!()

      assert OrganizationRecoveries.complete(recovery, audit: audit()) == :ok

      assert Organizations.get_role(organization, new_admin) == "admin"
      refute Organizations.get_role(organization, old_admin)
      assert reload(recovery).completed_at

      assert [
               _verification,
               _notice,
               %OutboxEntry{type: "organization_recovery_completed"} = done
             ] =
               entries(recovery)

      assert addresses(done) == Enum.sort([primary(new_admin), primary(old_admin)])
    end

    test "promotes an account that is already a member", context do
      %{organization: organization, old_admin: old_admin, member: member} = context
      recovery = organization |> start!(member) |> verify!(member) |> make_due!()

      assert OrganizationRecoveries.complete(recovery, audit: audit()) == :ok

      assert Organizations.get_role(organization, member) == "admin"
      refute Organizations.get_role(organization, old_admin)
    end

    test "takes a seat when there was no old administrator", context do
      %{organization: organization, old_admin: old_admin, new_admin: new_admin} = context
      Repo.delete_all(from(m in OrganizationUser, where: m.user_id == ^old_admin.id))
      recovery = organization |> start!(new_admin) |> verify!(new_admin) |> make_due!()

      Repo.update!(Ecto.Changeset.change(organization, billing_seats: 1))

      assert OrganizationRecoveries.complete(recovery, audit: audit()) ==
               {:error, :seats_exhausted}

      refute Organizations.get_role(organization, new_admin)
      assert OrganizationRecovery.open?(reload(recovery))
    end

    test "can't run twice", context do
      %{organization: organization, new_admin: new_admin} = context
      recovery = organization |> start!(new_admin) |> verify!(new_admin) |> make_due!()

      assert OrganizationRecoveries.complete(recovery, audit: audit()) == :ok

      assert OrganizationRecoveries.complete(recovery, audit: audit()) ==
               {:error, :recovery_unavailable}

      assert OrganizationRecoveries.cancel(organization) == {:error, :no_recovery}
    end

    test "refuses once the organization has another administrator again", context do
      %{organization: organization, old_admin: old_admin, member: member} = context
      %{new_admin: new_admin} = context
      recovery = organization |> start!(new_admin) |> verify!(new_admin) |> make_due!()
      Organizations.change_role(organization, member, %{"role" => "admin"}, audit: audit())

      assert OrganizationRecoveries.complete(recovery, audit: audit()) ==
               {:error, :other_admins}

      refute Organizations.get_role(organization, new_admin)
      assert Organizations.get_role(organization, old_admin) == "admin"
    end

    test "refuses once the organization has a single sign-on connection", context do
      %{organization: organization, new_admin: new_admin} = context
      recovery = organization |> start!(new_admin) |> verify!(new_admin) |> make_due!()
      insert(:organization_sso_connection, organization: organization)

      assert OrganizationRecoveries.complete(recovery, audit: audit()) ==
               {:error, :sso_connection}

      refute Organizations.get_role(organization, new_admin)
    end

    test "changes nothing when the old administrator can't be removed", context do
      %{organization: organization, old_admin: old_admin, new_admin: new_admin} = context
      recovery = organization |> start!(new_admin) |> verify!(new_admin) |> make_due!()
      Repo.update!(Ecto.Changeset.change(new_admin, deactivated_at: DateTime.utc_now()))

      assert OrganizationRecoveries.complete(recovery, audit: audit()) == {:error, :last_admin}

      refute Organizations.get_role(organization, new_admin)
      assert Organizations.get_role(organization, old_admin) == "admin"
      assert OrganizationRecovery.open?(reload(recovery))
      assert length(entries(recovery)) == 2
    end
  end

  describe "cancel/1" do
    test "cancels the recovery and its queued mail", context do
      %{organization: organization, new_admin: new_admin} = context
      recovery = start!(organization, new_admin)

      assert OrganizationRecoveries.cancel(organization) == :ok

      assert reload(recovery).canceled_at
      assert entries(recovery) == []
      refute OrganizationRecoveries.get_by_token(recovery.raw_token)
      assert OrganizationRecoveries.cancel(organization) == {:error, :no_recovery}
    end
  end

  describe "run/1" do
    test "completes the due recoveries only", context do
      %{organization: organization, new_admin: new_admin} = context
      due = organization |> start!(new_admin) |> verify!(new_admin) |> make_due!()

      other = insert(:organization, billing_seats: 2)
      insert(:organization_user, organization: other, user: insert(:user), role: "admin")
      other_admin = insert(:user)
      waiting = other |> start!(other_admin) |> verify!(other_admin)

      assert OrganizationRecoveries.run() == [{organization.name, :ok}]

      assert reload(due).completed_at
      refute reload(waiting).completed_at
    end

    test "cancels a recovery once the organization has another administrator", context do
      %{organization: organization, member: member, new_admin: new_admin} = context
      recovery = organization |> start!(new_admin) |> verify!(new_admin) |> make_due!()
      Organizations.change_role(organization, member, %{"role" => "admin"}, audit: audit())

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert OrganizationRecoveries.run() == [{organization.name, {:canceled, :other_admins}}]
        end)

      assert log =~ "Organization recovery canceled"
      assert reload(recovery).canceled_at
      refute Organizations.get_role(organization, new_admin)
    end
  end

  defp audit(), do: Hexpm.Accounts.AuditLogs.admin()

  defp reload(recovery), do: Repo.get!(OrganizationRecovery, recovery.id)
end
