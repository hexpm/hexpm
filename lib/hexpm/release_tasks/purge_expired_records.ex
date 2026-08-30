defmodule Hexpm.ReleaseTasks.PurgeExpiredRecords do
  use Oban.Worker,
    queue: :periodic,
    max_attempts: 5,
    unique: [
      period: :infinity,
      states: :incomplete,
      fields: [:worker]
    ]

  import Ecto.Query, only: [from: 2]
  require Logger

  alias Hexpm.CronMonitor

  @repos Application.compile_env!(:hexpm, :ecto_repos)
  @retention_days 90
  # Deletes run in batches so each statement stays well below the query timeout
  # regardless of how many rows have accumulated.
  @batch_size 10_000
  @monitor_slug "hexpm-purge-expired-records"
  @monitor_schedule "0 2 * * *"

  # Every row goes to the audit bucket before it is deleted, as the whole row
  # minus these columns: the credential itself, never the record of who held it.
  @redacted %{
    Hexpm.OAuth.AuthorizationCode => ~w(code code_challenge),
    Hexpm.OAuth.DeviceCode => ~w(device_code user_code verification_uri_complete),
    Hexpm.OAuth.Token => ~w(refresh_token_hash),
    Hexpm.UserSession => ~w(session_token),
    Hexpm.Accounts.PasswordReset => ~w(key),
    Hexpm.Accounts.AccountDeletionRequest => ~w(key),
    Hexpm.Accounts.SSO.Transaction => ~w(state_hash nonce code_verifier link_token_hash),
    Hexpm.Accounts.SSO.OrgSession => [],
    Hexpm.Accounts.OrganizationInvitation => ~w(token_hash),
    Hexpm.Accounts.Key => ~w(secret_first secret_second)
  }

  @impl Oban.Worker
  def timeout(_job), do: 1_800_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) when map_size(args) == 0 do
    CronMonitor.run(@monitor_slug, @monitor_schedule, &run/0)
  end

  def perform(%Oban.Job{args: args}), do: {:cancel, {:invalid_args, args}}

  def run(opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @batch_size)
    run = new_run()

    Enum.each(@repos, fn repo ->
      app = Keyword.get(repo.config(), :otp_app)
      Logger.info("[task] Purging expired records for #{app}")

      purge_authorization_codes(repo, batch_size, run)
      purge_device_codes(repo, batch_size, run)
      purge_oauth_tokens(repo, batch_size, run)
      purge_user_sessions(repo, batch_size, run)
      purge_password_resets(repo, batch_size, run)
      purge_account_deletion_requests(repo, batch_size, run)
      purge_sso_transactions(repo, batch_size, run)
      purge_sso_sessions(repo, batch_size, run)
      purge_organization_invitations(repo, batch_size, run)
      purge_keys(repo, batch_size, run)
    end)
  end

  defp purge_authorization_codes(repo, batch_size, run) do
    count =
      archive_and_delete(
        repo,
        Hexpm.OAuth.AuthorizationCode,
        from(ac in Hexpm.OAuth.AuthorizationCode,
          where: ac.expires_at < fragment("NOW()"),
          order_by: ac.expires_at
        ),
        batch_size,
        run
      )

    Logger.info("[task] Purged #{count} expired authorization codes")
  end

  defp purge_device_codes(repo, batch_size, run) do
    count =
      archive_and_delete(
        repo,
        Hexpm.OAuth.DeviceCode,
        from(dc in Hexpm.OAuth.DeviceCode,
          where: dc.expires_at < fragment("NOW()"),
          order_by: dc.expires_at
        ),
        batch_size,
        run
      )

    Logger.info("[task] Purged #{count} expired device codes")
  end

  # A row has a reachable refresh token iff refresh_jti is set, since that is
  # what refresh lookups resolve by, and every path that sets it also sets
  # refresh_token_expires_at. The row is unreachable once both timestamps have
  # passed, not once the access token alone has.
  defp purge_oauth_tokens(repo, batch_size, run) do
    count =
      archive_and_delete(
        repo,
        Hexpm.OAuth.Token,
        from(t in Hexpm.OAuth.Token,
          where:
            (t.expires_at < fragment("NOW()") and
               (is_nil(t.refresh_jti) or t.refresh_token_expires_at < fragment("NOW()"))) or
              not is_nil(t.revoked_at),
          order_by: t.expires_at
        ),
        batch_size,
        run
      )

    Logger.info("[task] Purged #{count} expired/revoked OAuth tokens")
  end

  defp purge_user_sessions(repo, batch_size, run) do
    count =
      archive_and_delete(
        repo,
        Hexpm.UserSession,
        from(us in Hexpm.UserSession,
          where:
            (not is_nil(us.expires_at) and us.expires_at < fragment("NOW()")) or
              not is_nil(us.revoked_at),
          order_by: us.expires_at
        ),
        batch_size,
        run
      )

    Logger.info("[task] Purged #{count} expired/revoked user sessions")
  end

  defp purge_password_resets(repo, batch_size, run) do
    count =
      archive_and_delete(
        repo,
        Hexpm.Accounts.PasswordReset,
        from(pr in Hexpm.Accounts.PasswordReset,
          where: pr.inserted_at < fragment("NOW() - make_interval(days => ?)", @retention_days),
          order_by: pr.inserted_at
        ),
        batch_size,
        run
      )

    Logger.info("[task] Purged #{count} expired password resets")
  end

  defp purge_account_deletion_requests(repo, batch_size, run) do
    count =
      archive_and_delete(
        repo,
        Hexpm.Accounts.AccountDeletionRequest,
        from(r in Hexpm.Accounts.AccountDeletionRequest,
          where: r.inserted_at < ago(@retention_days, "day"),
          order_by: r.inserted_at
        ),
        batch_size,
        run
      )

    Logger.info("[task] Purged #{count} expired account deletion requests")
  end

  defp purge_sso_transactions(repo, batch_size, run) do
    count =
      archive_and_delete(
        repo,
        Hexpm.Accounts.SSO.Transaction,
        from(transaction in Hexpm.Accounts.SSO.Transaction,
          where: transaction.expires_at < fragment("NOW()"),
          order_by: transaction.expires_at
        ),
        batch_size,
        run
      )

    Logger.info("[task] Purged #{count} expired organization SSO transactions")
  end

  # One predicate rather than `expires_at < NOW() OR revoked_at IS NOT NULL`,
  # which could use neither index. A revoked session carries an expiry too, so
  # it is collected within the day. Nothing durable is lost: when a member last
  # authenticated lives on the identity, not here.
  defp purge_sso_sessions(repo, batch_size, run) do
    count =
      archive_and_delete(
        repo,
        Hexpm.Accounts.SSO.OrgSession,
        from(session in Hexpm.Accounts.SSO.OrgSession,
          where: session.expires_at < fragment("NOW()"),
          order_by: session.expires_at
        ),
        batch_size,
        run
      )

    Logger.info("[task] Purged #{count} expired organization SSO sessions")
  end

  # Accepted and revoked invitations carry an expiry too, so they are collected
  # within the week rather than needing a predicate that no index can serve.
  # What they recorded is already in the audit log.
  defp purge_organization_invitations(repo, batch_size, run) do
    count =
      archive_and_delete(
        repo,
        Hexpm.Accounts.OrganizationInvitation,
        from(invitation in Hexpm.Accounts.OrganizationInvitation,
          where: invitation.expires_at < fragment("NOW()"),
          order_by: invitation.expires_at
        ),
        batch_size,
        run
      )

    Logger.info("[task] Purged #{count} expired organization invitations")
  end

  defp purge_keys(repo, batch_size, run) do
    count =
      archive_and_delete(
        repo,
        Hexpm.Accounts.Key,
        from(k in Hexpm.Accounts.Key,
          where:
            not is_nil(k.revoke_at) and
              k.revoke_at < fragment("NOW() - make_interval(days => ?)", @retention_days),
          order_by: k.revoke_at
        ),
        batch_size,
        run
      )

    Logger.info("[task] Purged #{count} revoked keys")
  end

  # Each batch is uploaded before it is deleted, so a failed upload raises with
  # the rows still in place for the next attempt, and a failed delete leaves a
  # batch that the next attempt uploads again under a new run name; the
  # BigQuery views collapse those duplicates by source id.
  #
  # Queries order by their filtered timestamp column so the batch scans that
  # column's index; an unordered LIMIT tempts the planner into a seq scan per batch.
  defp archive_and_delete(repo, schema, query, batch_size, run, seq \\ 1, total \\ 0) do
    redacted = Map.fetch!(@redacted, schema)

    rows =
      repo.all(
        from(r in query,
          select: {r.id, fragment("(to_jsonb(?) - ?::text[])::text", r, ^redacted)},
          limit: ^batch_size
        )
      )

    if rows == [] do
      total
    else
      archive(schema, run, seq, rows)
      ids = Enum.map(rows, &elem(&1, 0))
      {count, _} = repo.delete_all(from(r in schema, where: r.id in ^ids))

      if length(rows) < batch_size do
        total + count
      else
        archive_and_delete(repo, schema, query, batch_size, run, seq + 1, total + count)
      end
    end
  end

  defp archive(schema, run, seq, rows) do
    table = schema.__schema__(:source)
    archived_at = DateTime.to_iso8601(run.archived_at)
    seq = seq |> Integer.to_string() |> String.pad_leading(4, "0")
    key = "#{table}-#{run.name}-#{seq}.json.gz"

    lines =
      Enum.map(rows, fn {id, row} ->
        [
          ~s({"archived_at":"),
          archived_at,
          ~s(","source_table":"),
          table,
          ~s(","source_id":),
          Integer.to_string(id),
          ~s(,"row":),
          row,
          "}\n"
        ]
      end)

    {:ok, _} =
      Hexpm.Store.put(:audit_bucket, key, :zlib.gzip(lines),
        meta: [rows: Integer.to_string(length(rows))],
        cache_control: "private",
        content_type: "application/gzip"
      )
  end

  # A retry uploads under a new name: the previous attempt may have left its
  # objects behind, and the bucket refuses overwrites.
  defp new_run() do
    archived_at = DateTime.utc_now()
    random = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    name = Calendar.strftime(archived_at, "%Y%m%dT%H%M%SZ") <> "-" <> random
    %{archived_at: archived_at, name: name}
  end
end
