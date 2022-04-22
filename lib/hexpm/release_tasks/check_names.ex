defmodule Hexpm.ReleaseTasks.CheckNames do
  require Logger

  def run() do
    # Trigger error_handler and rollbar reporting on 'hexpm eval ...'
    Task.async(&do_run/0)
    |> Task.await(:infinity)
  end

  def do_run() do
    threshold = Application.get_env(:hexpm, :levenshtein_threshold)

    threshold
    |> to_integer()
    |> find_candidates()
    |> log_result()
    |> send_email(threshold)
  catch
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
    |> Hexpm.Emails.Mailer.deliver_later!()
  end

  def find_candidates(threshold) do
    query = """
    SELECT pnew.name new_name, pall.name curr_name, levenshtein(pall.name, pnew.name) as dist
    FROM packages as pall
    CROSS JOIN packages as pnew
    WHERE pall.name <> pnew.name
      AND pnew.inserted_at >= CURRENT_DATE AT TIME ZONE 'UTC'
      AND levenshtein(pall.name, pnew.name) <= $1
    ORDER BY pall.name, dist
    """

    Hexpm.Repo.query!(query, [threshold])
    |> Map.fetch!(:rows)
    |> Enum.uniq_by(fn [a, b, _] -> if a > b, do: "#{a}-#{b}", else: "#{b}-#{a}" end)
  end

  defp to_integer(int) when is_integer(int), do: int
  defp to_integer(string) when is_binary(string), do: String.to_integer(string)
end
