defmodule Hexpm.Billing.Report do
  use Oban.Worker,
    queue: :periodic,
    max_attempts: 5,
    unique: [
      period: :infinity,
      states: :incomplete
    ]

  import Ecto.Query, only: [from: 2]
  alias Hexpm.Repo
  alias Hexpm.Accounts.Organization

  @impl Oban.Worker
  def timeout(_job), do: 20_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{}}) do
    if Application.fetch_env!(:hexpm, :billing_report) and Repo.write_mode?() do
      report_data = Hexpm.Billing.report()
      report_map = Map.new(report_data, &{&1["token"], &1["quantity"]})
      report_tokens = MapSet.new(report_map, fn {token, _quantity} -> token end)
      updates = to_update(organizations(), report_tokens, report_map)

      {set_active, set_inactive} =
        Enum.split_with(updates, fn {_name, active?, _old_seats, _new_seats} -> active? end)

      do_update(set_active, true)
      do_update(set_inactive, false)
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
        # Include both old and new seats so we can detect reductions
        [{name, should_be_active?, current_billing_seats, new_billing_seats}]
      else
        []
      end
    end)
  end

  defp do_update([], _boolean) do
    :ok
  end

  defp do_update(to_update, boolean) do
    # Group updates by new seats value to minimize database queries
    Enum.group_by(to_update, fn {_name, _active?, _old_seats, new_seats} -> new_seats end)
    |> Enum.each(fn {new_billing_seats, updates} ->
      names = Enum.map(updates, fn {name, _active?, _old_seats, _new_seats} -> name end)

      from(r in Organization, where: r.name in ^names)
      |> Repo.update_all(set: [billing_active: boolean, billing_seats: new_billing_seats])

      if new_billing_seats do
        Enum.each(updates, fn {name, _active?, old_seats, new_seats} ->
          if is_integer(old_seats) and is_integer(new_seats) and new_seats < old_seats do
            organization = Hexpm.Accounts.Organizations.get(name)

            if organization do
              Hexpm.UserSessions.revoke_excess_sessions_for_organization(
                organization,
                new_seats
              )
            end
          end
        end)
      end
    end)
  end
end
