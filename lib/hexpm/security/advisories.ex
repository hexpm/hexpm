defmodule Hexpm.Security.Advisories do
  use Hexpm.Context

  alias Hexpm.Security.Advisory

  def all(subject) do
    subject
    |> Advisory.all()
    |> Repo.all()
  end

  def upsert(attributes) do
    {_count, nil} =
      Repo.insert_all(Advisory, attributes, on_conflict: :replace_all, conflict_target: [:id])

    :ok
  end

  def refresh_affected_releases(concurrently \\ true) do
    Repo.refresh_view("security_advisory_affected_releases", concurrently: concurrently)
  end
end
