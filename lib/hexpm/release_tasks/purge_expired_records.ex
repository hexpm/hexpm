defmodule Hexpm.ReleaseTasks.PurgeExpiredRecords do
  import Ecto.Query, only: [from: 2]
  require Logger

  @repos Application.compile_env!(:hexpm, :ecto_repos)
  @retention_days 90
  # Plug session cookies have a 30-day max_age; rows older than that are unreachable.
  @plug_session_retention_days 30

  def run() do
    Enum.each(@repos, fn repo ->
      app = Keyword.get(repo.config(), :otp_app)
      Logger.info("[task] Purging expired records for #{app}")

      purge_authorization_codes(repo)
      purge_device_codes(repo)
      purge_oauth_tokens(repo)
      purge_user_sessions(repo)
      purge_plug_sessions(repo)
      purge_password_resets(repo)
      purge_keys(repo)
    end)
  end

  defp purge_authorization_codes(repo) do
    {count, _} =
      repo.delete_all(
        from(ac in Hexpm.OAuth.AuthorizationCode,
          where: ac.expires_at < fragment("NOW()")
        )
      )

    Logger.info("[task] Purged #{count} expired authorization codes")
  end

  defp purge_device_codes(repo) do
    {count, _} =
      repo.delete_all(
        from(dc in Hexpm.OAuth.DeviceCode,
          where: dc.expires_at < fragment("NOW()")
        )
      )

    Logger.info("[task] Purged #{count} expired device codes")
  end

  defp purge_oauth_tokens(repo) do
    {count, _} =
      repo.delete_all(
        from(t in Hexpm.OAuth.Token,
          where: t.expires_at < fragment("NOW()") or not is_nil(t.revoked_at)
        )
      )

    Logger.info("[task] Purged #{count} expired/revoked OAuth tokens")
  end

  defp purge_user_sessions(repo) do
    {count, _} =
      repo.delete_all(
        from(us in Hexpm.UserSession,
          where:
            (not is_nil(us.expires_at) and us.expires_at < fragment("NOW()")) or
              not is_nil(us.revoked_at)
        )
      )

    Logger.info("[task] Purged #{count} expired/revoked user sessions")
  end

  defp purge_plug_sessions(repo) do
    {count, _} =
      repo.delete_all(
        from(s in Hexpm.PlugSession,
          where:
            s.updated_at <
              fragment("NOW() - make_interval(days => ?)", @plug_session_retention_days)
        )
      )

    Logger.info("[task] Purged #{count} stale plug sessions")
  end

  defp purge_password_resets(repo) do
    {count, _} =
      repo.delete_all(
        from(pr in Hexpm.Accounts.PasswordReset,
          where: pr.inserted_at < fragment("NOW() - make_interval(days => ?)", @retention_days)
        )
      )

    Logger.info("[task] Purged #{count} expired password resets")
  end

  defp purge_keys(repo) do
    {count, _} =
      repo.delete_all(
        from(k in Hexpm.Accounts.Key,
          where:
            not is_nil(k.revoke_at) and
              k.revoke_at < fragment("NOW() - make_interval(days => ?)", @retention_days)
        )
      )

    Logger.info("[task] Purged #{count} revoked keys")
  end
end
