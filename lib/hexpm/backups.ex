defmodule Hexpm.Backups do
  @moduledoc """
  The record of organizations whose stored data was deleted, read by the
  nightly backup to remove them from every snapshot. One object per
  organization under `organizations/` in the deletions bucket; the backup
  acts on it once the organization has been gone from the mirror for a week.
  """

  @name_regex ~r/\A[a-z0-9_][a-z0-9_.-]*\z/

  def delete_organization(name) when is_binary(name) do
    unless Regex.match?(@name_regex, name) do
      raise ArgumentError, "not an organization name: #{inspect(name)}"
    end

    body = JSON.encode!(%{name: name, deleted_at: DateTime.utc_now()})

    {:ok, _} =
      Hexpm.Store.put(:deletions_bucket, "organizations/#{name}", body,
        meta: [],
        cache_control: "private",
        content_type: "application/json"
      )

    :ok
  end
end
