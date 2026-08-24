defmodule Hexpm.Accounts.Keys do
  use Hexpm.Context

  alias Hexpm.Accounts.{Organization, OrganizationUser}

  def all(user_or_organization) do
    Key.all(user_or_organization)
    |> Repo.all()
    |> Enum.map(&Key.associate_owner(&1, user_or_organization))
  end

  @doc """
  Personal API keys held by this organization's members that reach it.

  This is the list an administrator reviews before turning enforcement on and
  the list the sweep works from, so it has to hold every key the organization
  will turn away. That includes the ones carrying only an `api` permission: the
  API authorizes an organization action against any one of the domains it
  accepts, so `api:write` plus membership publishes, retires and changes owners
  without a repository permission anywhere on the key.
  """
  def personal_reaching_organization(%Organization{} = organization) do
    from(
      key in Key,
      join: member in OrganizationUser,
      on: member.user_id == key.user_id,
      where: member.organization_id == ^organization.id,
      where: is_nil(key.revoke_at) or key.revoke_at > fragment("NOW()"),
      order_by: [asc: key.name],
      preload: [:user]
    )
    |> Repo.all()
    |> Enum.filter(&reaches_organization?(&1, organization))
  end

  @doc """
  Whether a key reaches this organization, by naming it, by covering every
  repository, or by carrying an `api` permission.
  """
  def reaches_organization?(%Key{} = key, %Organization{} = organization) do
    Enum.any?(key.permissions, fn permission ->
      KeyPermission.organization_reach(permission) in [:every, organization.name] or
        permission.domain == "api"
    end)
  end

  @doc """
  Whether a key names this organization rather than reaching it through
  something wider.

  The distinction is what an administrator's list can honestly say about a key's
  last use: `last_use` records when a key was used and not what it was used for,
  so a key naming the organization did reach it and a key carrying `api` or
  `repositories` only could have.
  """
  def names_organization?(%Key{} = key, %Organization{} = organization) do
    Enum.any?(key.permissions, &(KeyPermission.organization_reach(&1) == organization.name))
  end

  @doc """
  The permissions on a key that name this organization, which are the ones a
  sweep can remove without touching anything else the key reaches.

  A `repositories` permission reaches the organization too but reaches every
  other one as well, so removing it would take unrelated access with it. Those
  keys are refused at the request instead.
  """
  def organization_permissions(%Key{} = key, %Organization{} = organization) do
    Enum.filter(key.permissions, &(KeyPermission.organization_reach(&1) == organization.name))
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
