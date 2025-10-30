defmodule Hexpm.Billing.Report do
  use GenServer
  import Ecto.Query, only: [from: 2]
  alias Hexpm.Repo
  alias Hexpm.Accounts.Organization

  @report_timeout 20_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  def init(opts) do
    Process.send_after(self(), :update, opts[:interval])
    {:ok, opts}
  end

  def handle_info(:update, opts) do
    if Application.fetch_env!(:hexpm, :billing_report) and Repo.write_mode?() do
      report_data = report_request()
      {report_tokens, report_map} = parse_report(report_data)
      organizations = organizations()

      updates = to_update(organizations, report_tokens, report_map)

      {set_active, set_inactive} =
        Enum.split_with(updates, fn {_name, active?, _old_seats, _new_seats} -> active? end)

      do_update(set_active, true)
      do_update(set_inactive, false)
    end

    Process.send_after(self(), :update, opts[:interval])
    {:noreply, opts}
  end

  defp parse_report(report_data) do
    # Support both old format (list of strings) and new format (list of maps)
    # Old format: ["org1", "org2"]
    # New format: [%{"token" => "org1", "quantity" => 5}, ...]

    case report_data do
      [first | _] when is_binary(first) ->
        # Old format: list of strings
        {MapSet.new(report_data), %{}}

      [first | _] when is_map(first) ->
        # New format: list of maps with token and quantity
        report_tokens = MapSet.new(report_data, & &1["token"])
        report_map = Map.new(report_data, &{&1["token"], &1["quantity"]})
        {report_tokens, report_map}

      [] ->
        # Empty report
        {MapSet.new(), %{}}
    end
  end

  defp report_request() do
    Task.async(fn -> Hexpm.Billing.report() end)
    |> Task.await(@report_timeout)
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

      # Revoke excess sessions for organizations with reduced seats
      if new_billing_seats do
        Enum.each(updates, fn {name, _active?, old_seats, new_seats} ->
          # Only revoke if seats were reduced (and both values are present)
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
