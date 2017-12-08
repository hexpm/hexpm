defmodule Hexpm.Billing.Report do
  use GenServer
  import Ecto.Query, only: [from: 2]
  alias Hexpm.Repo
  alias Hexpm.Repository.Repository

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  def init(opts) do
    Process.send_after(self(), :timeout, opts[:timeout])
    {:ok, opts}
  end

  def handle_info(:timeout, opts) do
    report = Hexpm.Billing.report()
    repositories = repositories()

    Enum.each(report, fn %{"token" => token, "active" => billing_active} ->
      billing_active = !!billing_active
      case Map.fetch(repositories, token) do
        {:ok, ^billing_active} ->
          :ok
        {:ok, _active} ->
          from(r in Repository, where: r.name == ^token)
          |> Repo.update_all(set: [billing_active: billing_active])
        :error ->
          :ok
      end
    end)

    Process.send_after(self(), :timeout, opts[:timeout])
    {:noreply, opts}
  end

  defp repositories() do
    from(r in Repository, where: not r.public, select: {r.name, r.billing_active})
    |> Repo.all()
    |> Map.new()
  end
end
