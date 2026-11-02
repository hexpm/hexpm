defmodule HexpmWeb.API.StagedReleaseController do
  use HexpmWeb, :controller

  alias Hexpm.Repository.{StagedRelease, StagedReleases}
  alias Hexpm.Repo

  plug :maybe_fetch_package

  plug :authorize,
    authentication: :required,
    domains: [{"api", "read"}, "package"],
    allow_workload_identity: true,
    fun: {AuthHelpers, :package_owner}

  plug :fetch_staged

  def show(conn, _params) do
    staged = conn.assigns.staged_release

    if StagedReleases.readable?(staged, audit_data(conn)) do
      status =
        conn.assigns.staged_status ||
          if(StagedReleases.expired?(staged), do: "expired", else: "staged")

      conn |> api_cache(:private) |> render(:show, staged_release: staged, status: status)
    else
      not_found(conn)
    end
  end

  defp fetch_staged(conn, _opts) do
    %{"repository" => repository_name, "name" => name, "version" => version} = conn.params
    kind = conn.assigns.staged_kind

    {staged, status} =
      case StagedReleases.get(repository_name, name, version, kind) do
        nil -> terminal(conn.assigns.repository, name, version, kind)
        staged -> {staged, nil}
      end

    if staged do
      conn
      |> assign(:staged_release, staged)
      |> assign(:staged_status, status)
    else
      conn |> not_found() |> halt()
    end
  end

  defp terminal(repository, name, version, kind) do
    with %Repository{} <- repository,
         {:ok, version} <- Version.parse(version),
         log when not is_nil(log) <-
           Repo.one(
             from(l in AuditLog,
               where:
                 l.action in ["release.approve", "release.reject", "release.stage_expire"] and
                   fragment("? -> 'staged_release' ->> 'repository_id'", l.params) ==
                     ^to_string(repository.id) and
                   fragment("? -> 'staged_release' ->> 'name'", l.params) == ^name and
                   fragment("? -> 'staged_release' ->> 'version'", l.params) ==
                     ^to_string(version) and
                   fragment("? -> 'staged_release' ->> 'kind'", l.params) == ^kind,
               order_by: [desc: l.id],
               limit: 1
             )
           ) do
      data = log.params["staged_release"]

      staged =
        %StagedRelease{
          repository_id: data["repository_id"],
          name: data["name"],
          version: version,
          kind: data["kind"],
          key_id: data["key_id"],
          workload_identity_id: data["workload_identity_id"],
          user_id: data["user_id"],
          organization_id: data["organization_id"],
          credential_type: data["credential_type"],
          credential_name: data["credential_name"],
          outer_checksum: decode_checksum(data["outer_checksum"]),
          docs_checksum: decode_checksum(data["docs_checksum"]),
          expires_at: parse_expiry(data["expires_at"])
        }
        |> Repo.preload(repository: :organization)

      {staged,
       %{
         "release.approve" => "approved",
         "release.reject" => "rejected",
         "release.stage_expire" => "expired"
       }[log.action]}
    else
      _ -> {nil, nil}
    end
  end

  defp decode_checksum(nil), do: nil
  defp decode_checksum(checksum), do: Base.decode16!(checksum, case: :mixed)

  defp parse_expiry(value) do
    {:ok, datetime, _} = DateTime.from_iso8601(value)
    datetime
  end
end
