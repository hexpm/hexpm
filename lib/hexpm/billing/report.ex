defmodule Hexpm.Billing.Report do
  use GenServer
  import Ecto.Query, only: [from: 2]
  alias Hexpm.Repo
  alias Hexpm.Repository.Repository

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  def init(opts) do
    Process.send_after(self(), :update, opts[:interval])
    {:ok, opts}
  end

  def handle_info(:update, opts) do
    report = report()
    repositories = repositories()

    set_active(repositories, report)
    set_inactive(repositories, report)

    Process.send_after(self(), :update, opts[:interval])
    {:noreply, opts}
  end

  defp report() do
     Hexpm.Billing.report()
     |> MapSet.new()
  end

  defp repositories() do
    from(r in Repository, select: {r.name, r.billing_active})
    |> Repo.all()
  end

  defp set_active(repositories, report) do
    to_update =
      Enum.flat_map(repositories, fn {name, active} ->
        if not active and name in report do
          [name]
        else
          []
        end
      end)

    from(r in Repository, where: r.name in ^to_update)
    |> Repo.update_all(set: [billing_active: true])
  end

  defp set_inactive(repositories, report) do
    to_update =
      Enum.flat_map(repositories, fn {name, active} ->
        if active and name not in report do
          [name]
        else
          []
        end
      end)

    from(r in Repository, where: r.name in ^to_update)
    |> Repo.update_all(set: [billing_active: false])
  end
end
