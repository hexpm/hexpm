defmodule Hexpm.Accounts.OrganizationDeletions do
  @moduledoc """
  Deletes organizations that have had no active billing for 90 days.

  `Hexpm.Billing.Report` records when billing stopped in
  `billing_inactive_since`. The daily run schedules every such organization
  for deletion 90 days after that (or after its trial ended, whichever is
  later), tells its admins, reminds them a week and a day before, and on the
  day deletes the organization with its stored data through
  `Hexpm.AdminTasks.delete_organization/2`. Billing coming back clears the
  schedule, in the report as soon as it sees the subscription and here as a
  last check against the billing service before anything is deleted.

  A run deletes at most `@max_deletions` organizations, so a mistake in the
  scheduling is bounded to a day's worth, and every step is posted to Slack
  and Sentry.

  `config :hexpm, :organization_deletions` (`HEXPM_ORGANIZATION_DELETIONS`)
  switches it: `:off` does nothing, `:report` posts to Slack what a run would
  schedule, remind and delete without writing, emailing or deleting
  anything, and `:on` runs it. The billing-cancelled email is only sent
  with `:on`, since it announces the deletion.
  """

  import Ecto.Query, only: [from: 2]
  require Logger

  alias Hexpm.Repo
  alias Hexpm.Accounts.{Organization, OrganizationUser}
  alias Hexpm.Emails
  alias Hexpm.Emails.Outbox

  @grace_days 90
  @reminder_days [7, 1]
  @max_deletions 5
  @category "organization_deletion"

  def grace_days(), do: @grace_days

  def mode(), do: Application.fetch_env!(:hexpm, :organization_deletions)

  @doc """
  Tells the organization's admins that billing was cancelled from the
  dashboard, until when the organization stays usable (`period_end`, an ISO
  8601 string or unix timestamp from the billing service, `nil` when nothing
  was paid for) and the earliest day it is deleted after that.
  """
  def notify_billing_cancelled(organization, period_end) do
    if mode() == :on, do: do_notify_billing_cancelled(organization, period_end), else: :ok
  end

  defp do_notify_billing_cancelled(organization, period_end) do
    access_until = parse_period_end(period_end)
    deletion_at = DateTime.add(access_until || DateTime.utc_now(), @grace_days, :day)

    notify(organization, "billing_cancelled", fn recipients ->
      Emails.organization_billing_cancelled(
        organization.name,
        access_until,
        deletion_at,
        recipients
      )
    end)
  end

  defp parse_period_end(nil), do: nil
  defp parse_period_end(unix) when is_integer(unix), do: DateTime.from_unix!(unix)

  defp parse_period_end(iso) when is_binary(iso) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(iso)
    datetime
  end

  def run(), do: run(mode())

  defp run(:off), do: :off

  # Nothing is written: no organization has a schedule in this mode, so the
  # report is who would be scheduled and when, and any deletion already due
  # under a schedule made while the job was on.
  defp run(:report) do
    now = DateTime.utc_now()

    would_schedule =
      schedulable()
      |> Repo.all()
      |> Enum.map(&{&1.name, deletion_at(&1, now)})

    would_delete =
      deletable(now, [])
      |> Repo.all()
      |> Enum.map(& &1.name)

    first =
      case Enum.min_by(would_schedule, &elem(&1, 1), DateTime, fn -> nil end) do
        nil -> ""
        {name, at} -> ", the first (#{name}) on #{date(at)}"
      end

    Hexpm.Slack.post(
      "Organization deletions, report only: #{length(would_schedule)} would be scheduled" <>
        "#{first}; #{length(would_delete)} would be deleted today#{names(would_delete)}"
    )

    %{would_schedule: would_schedule, would_delete: would_delete}
  end

  defp run(:on) do
    cleared = clear_reactivated()
    scheduled = schedule()
    reminded = remind()
    deleted = delete(Enum.map(reminded, &elem(&1, 0)))
    %{cleared: cleared, scheduled: scheduled, reminded: reminded, deleted: deleted}
  end

  # The report clears the schedule when a subscription is back; this catches
  # an override or a trial extension set by hand.
  defp clear_reactivated() do
    from(o in Organization,
      where: not is_nil(o.deletion_scheduled_at),
      where:
        o.billing_active or o.billing_override == true or o.trial_end > ^DateTime.utc_now() or
          is_nil(o.billing_inactive_since)
    )
    |> Repo.all()
    |> Enum.map(fn organization ->
      clear(organization)

      Hexpm.Slack.post(
        "Deletion of organization #{organization.name} cancelled, billing is active again"
      )

      organization.name
    end)
  end

  defp clear(organization) do
    from(o in Organization, where: o.id == ^organization.id)
    |> Repo.update_all(set: [deletion_scheduled_at: nil, deletion_notices: []])

    :ok
  end

  defp schedule() do
    now = DateTime.utc_now()

    scheduled =
      schedulable()
      |> Repo.all()
      |> Enum.map(&schedule(&1, now))

    post_scheduled(scheduled)
    Enum.map(scheduled, &elem(&1, 0))
  end

  defp schedulable() do
    now = DateTime.utc_now()

    from(o in Organization,
      where: o.id != 1,
      where: is_nil(o.deletion_scheduled_at),
      where: not is_nil(o.billing_inactive_since),
      where: not o.billing_active,
      where: is_nil(o.billing_override) or o.billing_override == false,
      where: o.trial_end < ^now,
      order_by: o.billing_inactive_since
    )
  end

  # An organization overdue by the time it is scheduled (the job did not run
  # for a while) still gets the week of notice.
  defp deletion_at(organization, now) do
    since = Enum.max([organization.billing_inactive_since, organization.trial_end], DateTime)

    Enum.max(
      [DateTime.add(since, @grace_days, :day), DateTime.add(now, hd(@reminder_days), :day)],
      DateTime
    )
  end

  defp schedule(organization, now) do
    deletion_at = deletion_at(organization, now)

    # The notice is recorded with its email or not at all: the deletion
    # counts on the notices having gone out.
    Repo.transaction(fn ->
      from(o in Organization, where: o.id == ^organization.id)
      |> Repo.update_all(
        set: [deletion_scheduled_at: deletion_at, deletion_notices: ["scheduled"]]
      )

      notify(organization, "scheduled", fn recipients ->
        Emails.organization_deletion_scheduled(organization.name, deletion_at, recipients)
      end)
    end)

    Logger.info(%{
      message: "Organization scheduled for deletion",
      event: "organization_deletion.scheduled",
      organization: organization.name,
      deletion_at: deletion_at
    })

    {organization.name, deletion_at}
  end

  # One post per run: the first run after the columns were added schedules
  # every organization that was already inactive.
  defp post_scheduled([]), do: :ok

  defp post_scheduled(scheduled) do
    {first_name, first_at} = Enum.min_by(scheduled, &elem(&1, 1), DateTime)
    scheduled_names = Enum.map(scheduled, &elem(&1, 0))

    Hexpm.Slack.post(
      "#{length(scheduled_names)} organization(s) scheduled for deletion, the first " <>
        "(#{first_name}) on #{date(first_at)}#{names(scheduled_names)}"
    )
  end

  defp remind() do
    now = DateTime.utc_now()

    from(o in Organization, where: not is_nil(o.deletion_scheduled_at))
    |> Repo.all()
    |> Enum.flat_map(fn organization ->
      Enum.flat_map(@reminder_days, fn days ->
        notice = "#{days}_days"
        due = DateTime.add(organization.deletion_scheduled_at, -days, :day)

        if notice in organization.deletion_notices or DateTime.compare(now, due) == :lt do
          []
        else
          Repo.transaction(fn ->
            from(o in Organization, where: o.id == ^organization.id)
            |> Repo.update_all(push: [deletion_notices: notice])

            notify(organization, notice, fn recipients ->
              Emails.organization_deletion_reminder(
                organization.name,
                organization.deletion_scheduled_at,
                days,
                recipients
              )
            end)
          end)

          if days == 1 do
            Hexpm.Slack.post(
              "Organization #{organization.name} is deleted at the next run, " <>
                "scheduled for #{date(organization.deletion_scheduled_at)} (#{describe(organization)})"
            )
          end

          [{organization.name, notice}]
        end
      end)
    end)
  end

  # Only an organization whose admins had the last reminder before this run
  # is deleted; the notices are recorded, so a run that missed days does not
  # remind and delete in one go.
  defp delete(reminded_now) do
    DateTime.utc_now()
    |> deletable(reminded_now)
    |> Repo.all()
    |> Enum.map(fn organization ->
      {organization.name, delete_organization(organization)}
    end)
  end

  defp deletable(now, reminded_now) do
    last_notice = "#{List.last(@reminder_days)}_days"

    from(o in Organization,
      where: o.id != 1,
      where: o.deletion_scheduled_at <= ^now,
      where: ^last_notice in o.deletion_notices,
      where: o.name not in ^reminded_now,
      where: not o.billing_active,
      where: is_nil(o.billing_override) or o.billing_override == false,
      where: o.trial_end < ^now,
      order_by: o.deletion_scheduled_at,
      limit: @max_deletions
    )
  end

  # The billing service is asked once more right before the delete, by the
  # admin task on the lookup it cancels from: the cached flag was set by a
  # report up to a day old. A failure, the billing service unreachable say,
  # leaves the organization for the next run.
  defp delete_organization(organization) do
    recipients = admin_emails(organization)
    description = describe(organization)

    case Hexpm.AdminTasks.delete_organization(organization.name,
           delete_data: true,
           unless_billing_live: true
         ) do
      :ok ->
        deliver(organization, "deleted", recipients, fn recipients ->
          Emails.organization_deleted(organization.name, recipients)
        end)

        report(:info, "Organization deleted", organization, contents: description)
        :ok

      {:error, {:billing_live, status}} ->
        clear(organization)

        report(:warning, "Organization deletion skipped, billing is live", organization,
          status: status
        )

        {:skipped, :billing_live}

      {:error, reason} ->
        report(:error, "Organization deletion failed", organization, reason: inspect(reason))
        {:error, reason}
    end
  rescue
    error ->
      report(:error, "Organization deletion failed", organization,
        reason: Exception.message(error)
      )

      {:error, error}
  end

  defp report(level, message, organization, extra) do
    extra = Map.new([{:organization, organization.name} | extra])

    Logger.log(level, Map.merge(%{message: message, event: "organization_deletion"}, extra))

    Sentry.capture_message(message, level: level, extra: extra)

    Hexpm.Slack.post(
      "#{message}: #{organization.name} #{inspect(Map.delete(extra, :organization))}"
    )
  end

  defp notify(organization, notice, build) do
    deliver(organization, notice, admin_emails(organization), build)
  end

  defp deliver(_organization, _notice, [], _build), do: :ok

  defp deliver(organization, notice, recipients, build) do
    Outbox.enqueue!(build.(recipients),
      category: @category,
      group_key: "#{@category}:#{notice}:#{organization.id}",
      scope_key: "organization:#{organization.id}"
    )

    :ok
  end

  defp admin_emails(organization) do
    from(
      member in OrganizationUser,
      join: user in assoc(member, :user),
      join: address in assoc(user, :emails),
      where: member.organization_id == ^organization.id,
      where: member.role == "admin",
      where: address.primary and address.verified,
      where: is_nil(user.deactivated_at),
      select: address.email
    )
    |> Repo.all()
  end

  defp describe(organization) do
    organization = Repo.preload(organization, :repository)

    packages =
      case organization.repository do
        nil ->
          0

        repository ->
          Repo.aggregate(
            from(p in Hexpm.Repository.Package, where: p.repository_id == ^repository.id),
            :count
          )
      end

    members =
      Repo.aggregate(
        from(m in OrganizationUser, where: m.organization_id == ^organization.id),
        :count
      )

    "#{packages} packages, #{members} members"
  end

  defp date(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d")

  defp names([]), do: ""

  defp names(names) do
    shown = Enum.take(names, 20)
    more = length(names) - length(shown)
    ": " <> Enum.join(shown, ", ") <> if(more > 0, do: " and #{more} more", else: "")
  end
end

defmodule Hexpm.Accounts.OrganizationDeletions.Worker do
  use Oban.Worker,
    queue: :periodic,
    max_attempts: 3,
    unique: [
      period: :infinity,
      states: :incomplete,
      fields: [:worker]
    ]

  alias Hexpm.CronMonitor

  @monitor_slug "hexpm-organization-deletions"
  @monitor_schedule "0 5 * * *"

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(60)

  @impl Oban.Worker
  def perform(_job) do
    if Hexpm.Repo.write_mode?() do
      CronMonitor.run(@monitor_slug, @monitor_schedule, fn ->
        Hexpm.Accounts.OrganizationDeletions.run()
        :ok
      end)
    else
      :ok
    end
  end
end
