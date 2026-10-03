defmodule Hexpm.Billing.Report do
  use Oban.Worker,
    queue: :periodic,
    max_attempts: 5,
    unique: [
      period: :infinity,
      states: :incomplete
    ]

  import Ecto.Query, only: [from: 2]
  require Logger
  alias Hexpm.Repo
  alias Hexpm.Accounts.Organization

  # An organization inactive for 90 days is deleted with its data
  # (`Hexpm.Accounts.OrganizationDeletions`), so a report that would set more
  # organizations inactive in one run than customers stop paying in a day is
  # taken for a broken report, not for that many cancellations, and its
  # deactivations are refused.
  @max_deactivations 10

  @impl Oban.Worker
  def timeout(_job), do: 20_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{}}) do
    if Application.fetch_env!(:hexpm, :billing_report) and Repo.write_mode?() do
      case Hexpm.Billing.report() do
        {:ok, report_data} ->
          report_map = Map.new(report_data, &{&1["token"], &1["quantity"]})
          report_tokens = MapSet.new(report_map, fn {token, _quantity} -> token end)
          updates = to_update(organizations(), report_tokens, report_map)

          {set_active, set_inactive} = Enum.split_with(updates, & &1.active?)

          do_update(set_active, true)
          deactivate(set_inactive)

        {:error, reason} ->
          {:error, reason}
      end
    else
      :ok
    end
  end

  defp organizations() do
    from(r in Organization,
      select: {r.name, r.billing_active, r.billing_override, r.billing_seats}
    )
    |> Repo.all()
  end

  defp to_update(organizations, report_tokens, report_map) do
    Enum.flat_map(organizations, fn {name, already_active?, override, current_billing_seats} ->
      should_be_active? =
        if not is_nil(override) do
          override
        else
          name in report_tokens
        end

      new_billing_seats = Map.get(report_map, name)
      seats_changed? = new_billing_seats != current_billing_seats
      active_changed? = should_be_active? != already_active?

      if active_changed? or seats_changed? do
        # Both old and new seats are kept so a reduction can be detected.
        [
          %{
            name: name,
            active?: should_be_active?,
            active_changed?: active_changed?,
            old_seats: current_billing_seats,
            new_seats: new_billing_seats
          }
        ]
      else
        []
      end
    end)
  end

  defp deactivate(updates) do
    newly_inactive = Enum.count(updates, & &1.active_changed?)

    if newly_inactive > @max_deactivations do
      :telemetry.execute([:hexpm, :billing, :report_refused], %{count: newly_inactive}, %{})

      Logger.error(%{
        message: "Billing report refused: too many organizations to set inactive",
        event: "billing.report_refused",
        count: newly_inactive,
        max: @max_deactivations
      })

      Sentry.capture_message("Billing report refused: too many organizations to set inactive",
        extra: %{count: newly_inactive, max: @max_deactivations}
      )

      {:error, :too_many_deactivations}
    else
      do_update(updates, false)
    end
  end

  defp do_update([], _boolean) do
    :ok
  end

  # One transaction: billing_active and the day billing stopped change
  # together, or a run stopped between them would leave an inactive
  # organization that no later report sees change and so never dates.
  defp do_update(to_update, boolean) do
    {:ok, :ok} = Repo.transaction(fn -> update(to_update, boolean) end)
    :ok
  end

  defp update(to_update, boolean) do
    now = DateTime.utc_now()

    # Grouped by the new seats value to keep the number of queries down.
    Enum.group_by(to_update, & &1.new_seats)
    |> Enum.each(fn {new_billing_seats, updates} ->
      names = Enum.map(updates, & &1.name)

      from(r in Organization, where: r.name in ^names)
      |> Repo.update_all(set: [billing_active: boolean, billing_seats: new_billing_seats])

      if new_billing_seats do
        Enum.each(updates, fn update ->
          if is_integer(update.old_seats) and is_integer(update.new_seats) and
               update.new_seats < update.old_seats do
            organization = Hexpm.Accounts.Organizations.get(update.name)

            if organization do
              Hexpm.UserSessions.revoke_excess_sessions_for_organization(
                organization,
                update.new_seats
              )
            end
          end
        end)
      end
    end)

    # The day billing stopped is what the deletion counts from, and it is
    # cleared with everything scheduled from it when billing is back.
    changed = to_update |> Enum.filter(& &1.active_changed?) |> Enum.map(& &1.name)

    set =
      if boolean,
        do: [billing_inactive_since: nil, deletion_scheduled_at: nil, deletion_notices: []],
        else: [billing_inactive_since: now]

    from(r in Organization, where: r.name in ^changed)
    |> Repo.update_all(set: set)

    if changed != [] do
      :telemetry.execute(
        [:hexpm, :billing, :organization_state_changed],
        %{count: length(changed)},
        %{billing_active: boolean}
      )
    end

    :ok
  end
end
