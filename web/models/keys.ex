defmodule HexWeb.Keys do
  use HexWeb.Web, :crud

  def all(user) do
    Key.all(user)
    |> Repo.all
  end

  def get(user, name) do
    HexWeb.Repo.one!(Key.get(user, name))
  end

  def add(user, params, [audit: audit_data]) do
    Ecto.Multi.new
    |> Ecto.Multi.insert(:key, Key.build(user, params))
    |> audit(audit_data, "key.generate", fn %{key: key} -> key end)
    |> HexWeb.Repo.transaction
  end

  def remove(user, name, [audit: audit_data]) do
    if key = HexWeb.Repo.one(Key.get(user, name)) do
      remove(key, [audit: audit_data])
    else
      {:error, :not_found}
    end
  end
  def remove(key, [audit: audit_data]) do
    Ecto.Multi.new
    |> Ecto.Multi.update(:key, Key.revoke(key))
    |> audit(audit_data, "key.remove", key)
    |> HexWeb.Repo.transaction
  end

  def remove_all(user, [audit: audit_data]) do
    Ecto.Multi.new
    |> Ecto.Multi.update_all(:keys, Key.revoke_all(user), [])
    |> audit_many(audit_data, "key.remove", all(user))
    |> HexWeb.Repo.transaction
  end
end
