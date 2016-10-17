defmodule HexWeb.Case do
  import ExUnit.Callbacks

  def reset_store(tags) do
    if tags[:integration] && Application.get_env(:hex_web, :s3_bucket) do
      Application.put_env(:hex_web, :store_impl, HexWeb.Store.S3)
      on_exit fn -> Application.put_env(:hex_web, :store_impl, HexWeb.Store.Local) end
    end
  end

  def create_user(username, email, password, confirmed? \\ true) do
    HexWeb.User.build(%{username: username, password: password, emails: [%{email: email}]}, confirmed?)
    |> HexWeb.Repo.insert!
  end

  def key_for(username) when is_binary(username) do
    HexWeb.Repo.get_by!(HexWeb.User, username: username)
    |> key_for
  end

  def key_for(user) do
    key = user
          |> HexWeb.Key.build(%{name: "any_key_name"})
          |> HexWeb.Repo.insert!
    key.user_secret
  end
end
