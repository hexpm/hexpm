defmodule Mix.Tasks.Hexweb.CheckNames do
  use Mix.Task
  require Logger
  alias HexWeb.Package
  import Ecto.Query, only: [from: 2]

  @shortdoc "Check package names for typosquatters"


  def run(_args) do
    Mix.Task.run "app.start"

    threshold = Application.get_env(:hex_web, :jaro_threshold)

    threshold
    |> find_candidates
    |> send_mail(threshold)

    :ok
  end

  def new_packages do
    from(p in Package, select: p.name, where: fragment("inserted_at >= CURRENT_DATE"))
    |> HexWeb.Repo.all
  end


  def current_packages do
    from(p in Package, select: p.name, where: fragment("inserted_at < CURRENT_DATE"))
    |> HexWeb.Repo.all
  end


  def calculate_distances do
    for new <- new_packages(), curr <- current_packages() do
      [new, curr, String.jaro_distance(new, curr) |> Float.round(2)]
    end
  end

  def find_candidates(threshold) do
    calculate_distances
    |> Enum.filter(fn([_, _, d]) -> d > threshold end)
    |> Enum.sort(fn([_, _, d1], [_, _, d2]) -> d1 > d2 end)
  end


  def send_mail(candidates, threshold) do
    HexWeb.Mailer.send(
      "typosquat_candidates.html",
      "Hex.pm - Typosquat candidates",
      [Application.get_env(:hex_web, :support_email)],
      candidates: candidates,
      threshold: threshold)
  end
end
