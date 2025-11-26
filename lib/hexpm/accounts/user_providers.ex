defmodule Hexpm.Accounts.UserProviders do
  use Hexpm.Context

  alias Hexpm.Accounts.UserProvider

  def get_by_provider(provider, provider_uid, preload \\ []) do
    Repo.get_by(UserProvider, provider: provider, provider_uid: provider_uid)
    |> Repo.preload(preload)
  end

  def get_for_user(user, provider) do
    Repo.get_by(UserProvider, user_id: user.id, provider: provider)
  end

  def create(user, provider, provider_uid, provider_email, provider_data \\ %{},
        audit: audit_data
      ) do
    user_provider =
      UserProvider.build(user, provider, provider_uid, provider_email, provider_data)

    multi =
      Multi.new()
      |> Multi.insert(:user_provider, UserProvider.changeset(user_provider, %{}))
      |> audit(audit_data, "user_provider.create", fn %{user_provider: up} -> up end)

    case Repo.transaction(multi) do
      {:ok, %{user_provider: user_provider}} -> {:ok, user_provider}
      {:error, :user_provider, changeset, _} -> {:error, changeset}
    end
  end

  def delete(user_provider, audit: audit_data) do
    multi =
      Multi.new()
      |> Multi.delete(:user_provider, user_provider)
      |> audit(audit_data, "user_provider.delete", user_provider)

    case Repo.transaction(multi) do
      {:ok, _} -> :ok
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  def has_provider?(user, provider) do
    query =
      from(up in UserProvider,
        where: up.user_id == ^user.id and up.provider == ^provider
      )

    Hexpm.Repo.exists?(query)
  end
end
