defmodule Hexpm.Cache do
  use GenServer

  alias Hexpm.Repo
  alias Hexpm.Repository.{Download, Release}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def release_count(table \\ __MODULE__) do
    lookup(table, :release_count, fn -> Repo.one!(Release.count()) end)
  end

  def last_download_day(table \\ __MODULE__) do
    lookup(table, :last_download_day, fn -> Repo.one(Download.last_day()) end)
  end

  def refresh(server \\ __MODULE__) do
    GenServer.call(server, :refresh)
  end

  @impl true
  def init(opts) do
    table = opts[:name] || __MODULE__
    :ets.new(table, [:named_table, :public, :set, read_concurrency: true])
    state = %{table: table, interval: opts[:interval]}
    populate(state)
    schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_info(:update, state) do
    populate(state)
    schedule(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:refresh, _from, state) do
    populate(state)
    {:reply, :ok, state}
  end

  defp lookup(table, key, fallback) do
    case :ets.whereis(table) do
      :undefined ->
        fallback.()

      _ ->
        case :ets.lookup(table, key) do
          [{^key, value}] -> value
          [] -> fallback.()
        end
    end
  end

  defp populate(%{table: table}) do
    :ets.insert(table, {:release_count, Repo.one!(Release.count())})
    :ets.insert(table, {:last_download_day, Repo.one(Download.last_day())})
  end

  defp schedule(%{interval: interval}) do
    Process.send_after(self(), :update, interval)
  end
end
