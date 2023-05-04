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
      report = report()
      organizations = organizations()

      updates = to_update(organizations, report)
      {set_active, set_inactive} = Enum.split_with(updates, fn {_name, active?} -> active? end)
      do_update(set_active, true)
      do_update(set_inactive, false)
    end

    Process.send_after(self(), :update, opts[:interval])
    {:noreply, opts}
  end

  defp report() do
    report_request()
    |> MapSet.new()
  end

  defp report_request() do
    Task.async(fn -> Hexpm.Billing.report() end)
    |> Task.await(@report_timeout)
  end

  defp organizations() do
    from(r in Organization, select: {r.name, r.billing_active, r.billing_override})
    |> Repo.all()
  end

  defp to_update(organizations, report) do
    Enum.flat_map(organizations, fn {name, already_active?, override} ->
      should_be_active? =
        if not is_nil(override) do
          override
        else
          name in report
        end

      if should_be_active? == already_active? do
        []
      else
        [{name, should_be_active?}]
      end
    end)
  end

  defp do_update([], _boolean) do
    :ok
  end

  defp do_update(to_update, boolean) do
    names = Enum.map(to_update, fn {name, _active?} -> name end)

    from(r in Organization, where: r.name in ^names)
    |> Repo.update_all(set: [billing_active: boolean])
  end
end
