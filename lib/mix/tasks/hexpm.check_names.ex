defmodule Mix.Tasks.Hexpm.CheckNames do
  use Mix.Task
  require Logger

  @shortdoc "Check package names for typosquatters"

  def run(_args) do
    Mix.Task.run "app.start"

    threshold = Application.get_env(:hexpm, :levenshtein_threshold)

    threshold
    |> to_integer()
    |> find_candidates()
    |> send_email(threshold)

    :ok
  end

  defp send_email([], _threshold), do: :ok
  defp send_email(candidates, threshold) do
    candidates
    |> Hexpm.Emails.typosquat_candidates(threshold)
    |> Hexpm.Emails.Mailer.deliver_now_throttled()
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

    Ecto.Adapters.SQL.query!(Hexpm.Repo, query, [threshold])
    |> Map.fetch!(:rows)
    |> Enum.uniq_by(fn([a, b, _]) -> if a > b, do: "#{a}-#{b}", else: "#{b}-#{a}" end)
  end

  defp to_integer(int) when is_integer(int), do: int
  defp to_integer(string) when is_binary(string), do: String.to_integer(string)
end
