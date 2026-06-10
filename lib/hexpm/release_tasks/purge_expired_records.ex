defmodule Hexpm.ReleaseTasks.PurgeExpiredRecords do
  import Ecto.Query, only: [from: 2]
  require Logger

  @repos Application.compile_env!(:hexpm, :ecto_repos)
  @retention_days 90
  # Plug session cookies have a 30-day max_age; rows older than that are unreachable.
  @plug_session_retention_days 30
  # Deletes run in batches so each statement stays well below the query timeout
  # regardless of how many rows have accumulated.
  @batch_size 10_000

  def run(opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @batch_size)

    Enum.each(@repos, fn repo ->
      app = Keyword.get(repo.config(), :otp_app)
      Logger.info("[task] Purging expired records for #{app}")

      purge_authorization_codes(repo, batch_size)
      purge_device_codes(repo, batch_size)
      purge_oauth_tokens(repo, batch_size)
      purge_user_sessions(repo, batch_size)
      purge_plug_sessions(repo, batch_size)
      purge_password_resets(repo, batch_size)
      purge_keys(repo, batch_size)
    end)
  end

  defp purge_authorization_codes(repo, batch_size) do
    count =
      delete_in_batches(
        repo,
        Hexpm.OAuth.AuthorizationCode,
        from(ac in Hexpm.OAuth.AuthorizationCode,
          where: ac.expires_at < fragment("NOW()")
        ),
        batch_size
      )

    Logger.info("[task] Purged #{count} expired authorization codes")
  end

  defp purge_device_codes(repo, batch_size) do
    count =
      delete_in_batches(
        repo,
        Hexpm.OAuth.DeviceCode,
        from(dc in Hexpm.OAuth.DeviceCode,
          where: dc.expires_at < fragment("NOW()")
        ),
        batch_size
      )

    Logger.info("[task] Purged #{count} expired device codes")
  end

  defp purge_oauth_tokens(repo, batch_size) do
    count =
      delete_in_batches(
        repo,
        Hexpm.OAuth.Token,
        from(t in Hexpm.OAuth.Token,
          where: t.expires_at < fragment("NOW()") or not is_nil(t.revoked_at)
        ),
        batch_size
      )

    Logger.info("[task] Purged #{count} expired/revoked OAuth tokens")
  end

  defp purge_user_sessions(repo, batch_size) do
    count =
      delete_in_batches(
        repo,
        Hexpm.UserSession,
        from(us in Hexpm.UserSession,
          where:
            (not is_nil(us.expires_at) and us.expires_at < fragment("NOW()")) or
              not is_nil(us.revoked_at)
        ),
        batch_size
      )

    Logger.info("[task] Purged #{count} expired/revoked user sessions")
  end

  defp purge_plug_sessions(repo, batch_size) do
    count =
      delete_in_batches(
        repo,
        Hexpm.PlugSession,
        from(s in Hexpm.PlugSession,
          where:
            s.updated_at <
              fragment("NOW() - make_interval(days => ?)", @plug_session_retention_days)
        ),
        batch_size
      )

    Logger.info("[task] Purged #{count} stale plug sessions")
  end

  defp purge_password_resets(repo, batch_size) do
    count =
      delete_in_batches(
        repo,
        Hexpm.Accounts.PasswordReset,
        from(pr in Hexpm.Accounts.PasswordReset,
          where: pr.inserted_at < fragment("NOW() - make_interval(days => ?)", @retention_days)
        ),
        batch_size
      )

    Logger.info("[task] Purged #{count} expired password resets")
  end

  defp purge_keys(repo, batch_size) do
    count =
      delete_in_batches(
        repo,
        Hexpm.Accounts.Key,
        from(k in Hexpm.Accounts.Key,
          where:
            not is_nil(k.revoke_at) and
              k.revoke_at < fragment("NOW() - make_interval(days => ?)", @retention_days)
        ),
        batch_size
      )

    Logger.info("[task] Purged #{count} revoked keys")
  end

  defp delete_in_batches(repo, schema, query, batch_size, total \\ 0) do
    ids = from(r in query, select: r.id, limit: ^batch_size)
    {count, _} = repo.delete_all(from(r in schema, where: r.id in subquery(ids)))

    if count < batch_size do
      total + count
    else
      delete_in_batches(repo, schema, query, batch_size, total + count)
    end
  end
end
