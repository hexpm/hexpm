defmodule Hexpm.ReleaseTasks.CheckNames do
  use Oban.Worker,
    queue: :periodic,
    max_attempts: 5,
    unique: [
      period: :infinity,
      states: :incomplete,
      fields: [:worker]
    ]

  require Logger

  alias Hexpm.CronMonitor

  @monitor_slug "hexpm-check-names"
  @monitor_schedule "30 0 * * *"

  @impl Oban.Worker
  def timeout(_job), do: 600_000

  @impl Oban.Worker
  def perform(job) do
    case date(job) do
      {:ok, date} ->
        CronMonitor.run(@monitor_slug, @monitor_schedule, fn -> run(date) end)

      {:error, reason} ->
        {:cancel, reason}
    end
  end

  def run(date) do
    threshold = Application.get_env(:hexpm, :levenshtein_threshold)

    threshold
    |> to_integer()
    |> find_candidates(date)
    |> log_result()
    |> send_email(threshold)
  rescue
    exception ->
      Logger.error("[check_names] failed")
      reraise exception, __STACKTRACE__
  end

  defp log_result(candidates) do
    Logger.info("[check_names] job found #{length(candidates)} candidates")
    candidates
  end

  defp send_email([], _threshold), do: :ok

  defp send_email(candidates, threshold) do
    candidates
    |> Hexpm.Emails.typosquat_candidates(threshold)
    |> Hexpm.Emails.Mailer.deliver!()

    :ok
  end

  def find_candidates(threshold, date) do
    start_at = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_at = DateTime.add(start_at, 1, :day)

    query = """
    SELECT pnew.name new_name, pall.name curr_name, levenshtein(pall.name, pnew.name) as dist
    FROM packages as pall
    CROSS JOIN packages as pnew
    WHERE pall.name <> pnew.name
      AND pnew.inserted_at >= $2
      AND pnew.inserted_at < $3
      AND levenshtein(pall.name, pnew.name) <= $1
    ORDER BY pall.name, dist
    """

    Hexpm.Repo.query!(query, [threshold, start_at, end_at])
    |> Map.fetch!(:rows)
    |> Enum.uniq_by(fn [a, b, _] -> if a > b, do: "#{a}-#{b}", else: "#{b}-#{a}" end)
  end

  defp date(%Oban.Job{args: args, scheduled_at: scheduled_at}) when map_size(args) == 0 do
    case scheduled_at do
      %DateTime{} -> {:ok, DateTime.to_date(scheduled_at)}
      _other -> {:error, :missing_scheduled_at}
    end
  end

  defp date(%Oban.Job{args: %{"date" => date} = args})
       when map_size(args) == 1 and is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, {:invalid_date, date}}
    end
  end

  defp date(%Oban.Job{args: %{"date" => date} = args}) when map_size(args) == 1,
    do: {:error, {:invalid_date, date}}

  defp date(%Oban.Job{args: args}), do: {:error, {:invalid_args, args}}

  defp to_integer(int) when is_integer(int), do: int
  defp to_integer(string) when is_binary(string), do: String.to_integer(string)
end
