defmodule Hexpm.Accounts.OrganizationDeletionsTest do
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Accounts.{Organization, OrganizationDeletions, Organizations}
  alias Hexpm.Emails.OutboxEntry

  @day 24 * 60 * 60

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()
    stub(Hexpm.Billing.Mock, :get, fn _organization, _opts -> nil end)
    :ok
  end

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days * @day, :second)
  defp days_from_now(days), do: DateTime.add(DateTime.utc_now(), days * @day, :second)

  defp inactive_organization(attrs) do
    attrs =
      Keyword.merge(
        [billing_active: false, trial_end: days_ago(400), billing_inactive_since: days_ago(100)],
        attrs
      )

    insert(:organization, attrs)
  end

  defp with_admin(organization) do
    user = insert(:user)
    insert(:organization_user, organization: organization, user: user, role: "admin")
    email = hd(user.emails).email
    {organization, email}
  end

  defp entries(), do: Repo.all(from(e in OutboxEntry, order_by: e.id))

  describe "schedule" do
    test "schedules 90 days after billing stopped and tells the admins" do
      {organization, email} =
        inactive_organization(billing_inactive_since: days_ago(10)) |> with_admin()

      assert %{scheduled: [name]} = OrganizationDeletions.run()
      assert name == organization.name

      organization = Organizations.get(name)

      assert DateTime.diff(organization.deletion_scheduled_at, days_from_now(80), :second)
             |> abs() < 60

      assert organization.deletion_notices == ["scheduled"]

      assert [entry] = entries()
      assert entry.type == "organization_deletion_scheduled"
      assert entry.recipients == [email]
      assert entry.subject =~ "#{name} will be deleted on"
    end

    test "counts from the end of the trial when that is later" do
      organization =
        inactive_organization(billing_inactive_since: days_ago(50), trial_end: days_ago(1))

      OrganizationDeletions.run()

      scheduled_at = Organizations.get(organization.name).deletion_scheduled_at
      assert DateTime.diff(scheduled_at, days_from_now(89), :second) |> abs() < 60
    end

    test "leaves active, comped, trialing and public organizations alone" do
      active = insert(:organization, billing_active: true, billing_inactive_since: days_ago(100))
      comped = inactive_organization(billing_override: true)
      trialing = inactive_organization(trial_end: days_from_now(5))
      never_billed = insert(:organization, billing_active: false, trial_end: days_ago(400))

      assert %{scheduled: []} = OrganizationDeletions.run()

      for organization <- [active, comped, trialing, never_billed] do
        refute Organizations.get(organization.name).deletion_scheduled_at
      end

      refute Repo.get!(Organization, 1).deletion_scheduled_at
    end

    test "posts one Slack message for the run" do
      for _ <- 1..3, do: inactive_organization(billing_inactive_since: days_ago(10))
      app_env(:hexpm, :slack_webhook_url, "https://hooks.slack.test/T/B/x")

      expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, %{text: text} ->
        assert text =~ "3 organization(s) scheduled for deletion, the first ("
        {:ok, 200, [], "ok"}
      end)

      assert %{scheduled: [_, _, _]} = OrganizationDeletions.run()
    end

    test "schedules once" do
      inactive_organization(billing_inactive_since: days_ago(10)) |> with_admin()
      assert %{scheduled: [_]} = OrganizationDeletions.run()
      assert %{scheduled: []} = OrganizationDeletions.run()
      assert length(entries()) == 1
    end

    test "gives an organization overdue when scheduled a week of notice" do
      {organization, _email} =
        inactive_organization(billing_inactive_since: days_ago(100)) |> with_admin()

      name = organization.name

      assert %{scheduled: [^name], reminded: [{^name, "7_days"}], deleted: []} =
               OrganizationDeletions.run()

      scheduled_at = Organizations.get(name).deletion_scheduled_at
      assert DateTime.diff(scheduled_at, days_from_now(7), :second) |> abs() < 60

      assert [
               %{type: "organization_deletion_scheduled"},
               %{type: "organization_deletion_reminder"}
             ] =
               entries()
    end
  end

  describe "remind" do
    test "reminds a week and a day before, once each" do
      {organization, email} =
        inactive_organization(
          deletion_scheduled_at: days_from_now(6),
          deletion_notices: ["scheduled"]
        )
        |> with_admin()

      assert %{reminded: [{name, "7_days"}]} = OrganizationDeletions.run()
      assert name == organization.name
      assert Organizations.get(name).deletion_notices == ["scheduled", "7_days"]
      assert [%{type: "organization_deletion_reminder", recipients: [^email]} = entry] = entries()
      assert entry.subject =~ "will be deleted in 7 days"

      assert %{reminded: []} = OrganizationDeletions.run()

      from(o in Organization, where: o.id == ^organization.id)
      |> Repo.update_all(
        set: [deletion_scheduled_at: DateTime.add(DateTime.utc_now(), 3600, :second)]
      )

      assert %{reminded: [{^name, "1_days"}]} = OrganizationDeletions.run()
      assert [_, entry] = entries()
      assert entry.subject =~ "will be deleted tomorrow"
    end

    test "records no notice when its email cannot be queued" do
      {organization, _email} =
        inactive_organization(
          deletion_scheduled_at: days_from_now(1),
          deletion_notices: ["scheduled", "7_days"]
        )
        |> with_admin()

      app_env(:hexpm, :email_base_url, "http://[")

      assert_raise URI.Error, fn -> OrganizationDeletions.run() end

      assert Organizations.get(organization.name).deletion_notices == ["scheduled", "7_days"]
      assert entries() == []
    end

    test "does not remind before the week" do
      inactive_organization(
        deletion_scheduled_at: days_from_now(8),
        deletion_notices: ["scheduled"]
      )

      assert %{reminded: []} = OrganizationDeletions.run()
      assert entries() == []
    end
  end

  describe "clear" do
    test "clears the schedule when billing is active again or comped" do
      active =
        inactive_organization(
          billing_active: true,
          deletion_scheduled_at: days_from_now(3),
          deletion_notices: ["scheduled"]
        )

      comped =
        inactive_organization(
          billing_override: true,
          deletion_scheduled_at: days_from_now(3),
          deletion_notices: ["scheduled"]
        )

      assert %{cleared: cleared} = OrganizationDeletions.run()
      assert Enum.sort(cleared) == Enum.sort([active.name, comped.name])

      for organization <- [active, comped] do
        organization = Organizations.get(organization.name)
        refute organization.deletion_scheduled_at
        assert organization.deletion_notices == []
      end
    end
  end

  describe "delete" do
    test "deletes the organization with its data on the day and tells the admins" do
      repository = insert(:repository)
      organization = repository.organization

      from(o in Organization, where: o.id == ^organization.id)
      |> Repo.update_all(
        set: [
          billing_active: false,
          trial_end: days_ago(400),
          billing_inactive_since: days_ago(100),
          deletion_scheduled_at: days_ago(1),
          deletion_notices: ["scheduled", "7_days", "1_days"]
        ]
      )

      {_organization, email} = with_admin(organization)
      name = organization.name
      Hexpm.Store.put(:repo_bucket, "repos/#{name}/tarballs/pkg-1.0.0.tar", "TARBALL", [])

      assert %{deleted: [{^name, :ok}]} = OrganizationDeletions.run()

      for job <- all_enqueued(worker: Hexpm.Accounts.OrganizationDataWorker) do
        assert :ok = perform_job(Hexpm.Accounts.OrganizationDataWorker, job.args)
      end

      refute Organizations.get(name)
      assert Repo.exists?(Hexpm.Accounts.ReservedUsername.by_name(name))
      assert Hexpm.Store.list(:repo_bucket, "repos/#{name}/") |> Enum.to_list() == []
      assert Hexpm.Store.get(:deletions_bucket, "organizations/#{name}", [])
      assert [%{type: "organization_deleted", recipients: [^email]}] = entries()
    end

    test "deletes at most five per run, oldest schedule first" do
      organizations =
        for days <- 1..7 do
          inactive_organization(
            deletion_scheduled_at: days_ago(days),
            deletion_notices: ["scheduled", "7_days", "1_days"]
          )
        end

      assert %{deleted: deleted} = OrganizationDeletions.run()
      assert length(deleted) == 5

      [first, second | _rest] = organizations
      assert Organizations.get(first.name)
      assert Organizations.get(second.name)
      refute Organizations.get(List.last(organizations).name)
    end

    test "skips and clears an organization whose subscription is live" do
      organization =
        inactive_organization(
          deletion_scheduled_at: days_ago(1),
          deletion_notices: ["scheduled", "7_days", "1_days"]
        )

      name = organization.name

      stub(Hexpm.Billing.Mock, :get, fn ^name, _opts ->
        %{"subscription" => %{"status" => "active"}}
      end)

      assert %{deleted: [{^name, {:skipped, :billing_live}}]} = OrganizationDeletions.run()

      organization = Organizations.get(name)
      assert organization
      refute organization.deletion_scheduled_at
    end

    test "skips an organization when the billing service is unreachable" do
      organization =
        inactive_organization(
          deletion_scheduled_at: days_ago(1),
          deletion_notices: ["scheduled", "7_days", "1_days"]
        )

      name = organization.name

      stub(Hexpm.Billing.Mock, :get, fn ^name, _opts -> raise "billing down" end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert %{deleted: [{^name, {:skipped, :billing_unreachable}}]} =
                   OrganizationDeletions.run()
        end)

      assert log =~ "billing unreachable"
      assert Organizations.get(name).deletion_scheduled_at
    end

    test "does not delete before the day, without the last reminder, or with billing back" do
      notices = ["scheduled", "7_days", "1_days"]

      pending =
        inactive_organization(deletion_scheduled_at: days_from_now(1), deletion_notices: notices)

      unreminded =
        inactive_organization(
          deletion_scheduled_at: days_ago(1),
          deletion_notices: ["scheduled", "7_days"]
        )

      back =
        inactive_organization(
          billing_active: true,
          deletion_scheduled_at: days_ago(1),
          deletion_notices: notices
        )

      assert %{deleted: []} = OrganizationDeletions.run()
      assert Organizations.get(pending.name)
      assert Organizations.get(unreminded.name)
      assert Organizations.get(back.name)
    end

    test "does not delete in the run that sent the last reminder" do
      {organization, _email} =
        inactive_organization(
          deletion_scheduled_at: days_ago(1),
          deletion_notices: ["scheduled", "7_days"]
        )
        |> with_admin()

      name = organization.name
      assert %{reminded: [{^name, "1_days"}], deleted: []} = OrganizationDeletions.run()
      assert %{reminded: [], deleted: [{^name, :ok}]} = OrganizationDeletions.run()
    end
  end

  describe "notify_billing_cancelled/2" do
    test "tells the admins until when the organization is usable and when it is deleted" do
      {organization, email} = insert(:organization) |> with_admin()

      assert :ok =
               OrganizationDeletions.notify_billing_cancelled(
                 organization,
                 "2027-01-15T00:00:00Z"
               )

      assert [entry] = entries()
      assert entry.type == "organization_billing_cancelled"
      assert entry.recipients == [email]
      assert entry.email["text_body"] =~ "January 15, 2027"
      assert entry.email["text_body"] =~ "April 15, 2027"
    end

    test "without a paid period counts from today" do
      {organization, _email} = insert(:organization) |> with_admin()
      assert :ok = OrganizationDeletions.notify_billing_cancelled(organization, nil)
      assert [entry] = entries()
      assert entry.email["text_body"] =~ "can no longer be used"
    end
  end

  describe "Worker" do
    test "runs under the cron monitor" do
      app_env(:hexpm, :sentry_impl, Hexpm.CronMonitor.SentryMock)
      expect(Hexpm.CronMonitor.SentryMock, :capture_check_in, fn _opts -> {:ok, "id"} end)

      expect(Hexpm.CronMonitor.SentryMock, :capture_check_in, fn opts ->
        assert opts[:status] == :ok
        {:ok, "id"}
      end)

      assert :ok = perform_job(OrganizationDeletions.Worker, %{})
    end
  end
end
