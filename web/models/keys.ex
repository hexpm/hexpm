defmodule HexWeb.Keys do
  use HexWeb.Web, :crud

  def all(user) do
    Key.all(user)
    |> Repo.all
  end

  def get(id) do
    Repo.get(Key, id)
  end

  def get(user, name) do
    Repo.one(Key.get(user, name))
  end

  def add(user, params, [audit: audit_data]) do
    Multi.new
    |> Multi.insert(:key, Key.build(user, params))
    |> audit(audit_data, "key.generate", fn %{key: key} -> key end)
    |> Repo.transaction
  end

  def remove(key, [audit: audit_data]) do
    Multi.new
    |> Multi.update(:key, Key.revoke(key))
    |> audit(audit_data, "key.remove", key)
    |> Repo.transaction
  end

  def remove(user, name, [audit: audit_data]) do
    if key = Repo.one(Key.get(user, name)) do
      remove(key, [audit: audit_data])
    else
      {:error, :not_found}
    end
  end

  def remove_all(user, [audit: audit_data]) do
    Multi.new
    |> Multi.update_all(:keys, Key.revoke_all(user), [])
    |> audit_many(audit_data, "key.remove", all(user))
    |> Repo.transaction
  end
end
