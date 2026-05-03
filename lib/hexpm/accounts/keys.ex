defmodule Hexpm.Accounts.Keys do
  use Hexpm.Context

  require Logger

  alias Hexpm.Accounts.Organization

  def all(user_or_organization) do
    Key.all(user_or_organization)
    |> Repo.all()
    |> Enum.map(&Key.associate_owner(&1, user_or_organization))
  end

  def get(id) do
    Repo.get(Key, id)
    |> Repo.preload([:organization, :user])
  end

  def get(user_or_organization, name) do
    Repo.one(Key.get(user_or_organization, name))
    |> Key.associate_owner(user_or_organization)
  end

  def create(user_or_organization, params, audit: audit_data) do
    Multi.new()
    |> Multi.insert(:key, Key.build(user_or_organization, params))
    |> audit(audit_data, "key.generate", fn %{key: key} -> key end)
    |> Repo.transaction()
    |> tap(fn
      {:ok, %{key: key}} ->
        user_or_organization
        |> preload_for_email()
        |> Emails.api_key_created(key)
        |> Mailer.deliver!()

      _ ->
        :ok
    end)
    |> maybe_retry_for_unique_name(fn ->
      create(user_or_organization, params, audit: audit_data)
    end)
  end

  def revoke(key, audit: audit_data) do
    Multi.new()
    |> Multi.update(:key, Key.revoke(key))
    |> audit(audit_data, "key.remove", key)
    |> Repo.transaction()
  end

  def revoke(user_or_organization, name, audit: audit_data) do
    if key = get(user_or_organization, name) do
      result = revoke(key, audit: audit_data)

      if match?({:ok, _}, result) do
        user_or_organization
        |> preload_for_email()
        |> Emails.api_key_revoked(key)
        |> Mailer.deliver!()
      end

      result
    else
      {:error, :not_found}
    end
  end

  @doc """
  Looks up an active key by its `secret_first` hash, preloading the owning user
  with emails. Used by the GitHub secret scanning revocation flow where we only
  have the raw token, not the owner identity.

  Returns `{key, user}` or `nil` if not found / already revoked.
  """
  def get_by_secret_first(secret_first) do
    case Key.get_active_by_secret_first(secret_first) |> Repo.one() do
      %Key{} = key -> {key, key.user}
      nil -> nil
    end
  end

  def revoke_immediately(%Key{} = key) do
    Logger.info("Automated key revocation: key_id=#{key.id}")

    key
    |> Key.revoke()
    |> Repo.update!()
  end

  def revoke_all(user_or_organization, audit: audit_data) do
    Multi.new()
    |> Multi.update_all(:keys, Key.revoke_all(user_or_organization), [])
    |> audit_many(audit_data, "key.remove", all(user_or_organization))
    |> Repo.transaction()
    |> tap(fn
      {:ok, %{keys: {count, _}}} when count > 0 ->
        user_or_organization
        |> preload_for_email()
        |> Emails.api_keys_all_revoked()
        |> Mailer.deliver!()

      _ ->
        :ok
    end)
  end

  # Throttle last_use updates to at most once per 5 minutes per key,
  # matching the browser session throttle behavior.
  @last_use_throttle_seconds 300

  def update_last_use(%Key{public: true} = key, usage_info) do
    if Repo.write_mode?() && should_update_last_use?(key) do
      key
      |> Key.update_last_use(usage_info)
      |> Repo.update!()
    end
  end

  def update_last_use(%Key{public: false} = key, _usage_info) do
    key
  end

  defp preload_for_email(%Organization{} = org),
    do: Repo.preload(org, organization_users: [user: :emails])

  defp preload_for_email(user), do: user

  defp should_update_last_use?(%Key{last_use: %{used_at: used_at}})
       when not is_nil(used_at) do
    DateTime.diff(DateTime.utc_now(), used_at, :second) >= @last_use_throttle_seconds
  end

  defp should_update_last_use?(_key), do: true

  defp maybe_retry_for_unique_name(
         {:error, :key, %Ecto.Changeset{errors: [{:name, {"has already been taken", _}}]}, _},
         fun
       ) do
    fun.()
  end

  defp maybe_retry_for_unique_name(other, _fun) do
    other
  end
end
