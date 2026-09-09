defmodule Hexpm.Accounts.TFASessions do
  @moduledoc """
  Account 2FA proof, independent of organization SSO authentication.
  """
  use Hexpm.Context

  alias Hexpm.UserSession

  def lock_user!(user) do
    Repo.one!(from(u in User, where: u.id == ^user.id, lock: "FOR NO KEY UPDATE"))
    |> Repo.preload(:emails)
  end

  def record_verified!(user, session_id) do
    Repo.transaction(fn ->
      current = lock_user!(user)

      unless User.tfa_enabled?(current) and current.tfa_generation == user.tfa_generation do
        Repo.rollback(:credentials_changed)
      end

      now = DateTime.utc_now()

      {count, _} =
        Repo.update_all(
          from(s in UserSession,
            where: s.id == ^session_id and s.user_id == ^user.id,
            where: is_nil(s.revoked_at) and s.expires_at > ^now
          ),
          set: [
            tfa_verified_at: now,
            tfa_generation: current.tfa_generation,
            tfa_source_session_id: nil,
            tfa_copied: false
          ]
        )

      if count != 1, do: Repo.rollback(:invalid_session)
      :ok
    end)
  end

  def proof(user, session_id, now \\ DateTime.utc_now())
  def proof(_user, nil, _now), do: nil

  def proof(user, session_id, now) do
    Repo.one(
      from(s in UserSession,
        join: u in User,
        on: u.id == s.user_id,
        left_join: source in UserSession,
        on: source.id == s.tfa_source_session_id,
        where: s.id == ^session_id and s.user_id == ^user.id,
        where: not is_nil(u.tfa) and s.tfa_generation == u.tfa_generation,
        where: not is_nil(s.tfa_verified_at) and s.tfa_verified_at <= ^now,
        where: is_nil(s.revoked_at) and s.expires_at > ^now,
        where:
          not s.tfa_copied or
            (source.user_id == s.user_id and is_nil(source.revoked_at) and
               source.expires_at > ^now),
        select_merge: %{tfa_source_expires_at: source.expires_at}
      )
    )
  end

  def verified?(user, session_id, interval, now \\ DateTime.utc_now()) do
    case proof(user, session_id, now) do
      nil -> false
      session -> DateTime.compare(now, DateTime.add(session.tfa_verified_at, interval)) == :lt
    end
  end

  def copy!(nil, _target_id, _user), do: :ok

  def copy!(source_id, target_id, user) do
    {:ok, :ok} =
      Repo.transaction(fn ->
        user = lock_user!(user)

        target =
          Repo.one(
            from(s in UserSession,
              where: s.id == ^target_id and s.user_id == ^user.id and s.type == "oauth",
              lock: "FOR UPDATE"
            )
          )

        now = DateTime.utc_now()

        with %UserSession{revoked_at: nil} <- target,
             true <- DateTime.compare(target.expires_at, now) == :gt,
             %UserSession{type: "browser", tfa_copied: false} = source <-
               proof(user, source_id, now) do
          existing = proof(user, target_id, now)

          if is_nil(existing) or
               DateTime.compare(source.tfa_verified_at, existing.tfa_verified_at) == :gt do
            target
            |> Ecto.Changeset.change(
              tfa_verified_at: source.tfa_verified_at,
              tfa_generation: source.tfa_generation,
              tfa_source_session_id: source.id,
              tfa_copied: true
            )
            |> Repo.update!()
          end
        end

        :ok
      end)

    :ok
  end
end
