defmodule Hexpm.Case do
  import ExUnit.Callbacks

  def reset_store(tags) do
    if tags[:integration] && Application.get_env(:hexpm, :s3_bucket) do
      Application.put_env(:hexpm, :store_impl, Hexpm.Store.S3)
      on_exit fn -> Application.put_env(:hexpm, :store_impl, Hexpm.Store.Local) end
    end
  end

  def create_user(username, email, password, confirmed? \\ true) do
    Hexpm.Accounts.User.build(%{username: username, password: password, emails: [%{email: email}]}, confirmed?)
    |> Hexpm.Repo.insert!()
  end

  def key_for(user, type \\ :api)

  def key_for(username, type) when is_binary(username) do
    Hexpm.Repo.get_by!(Hexpm.Accounts.User, username: username)
    |> key_for(type)
  end

  def key_for(user, _type) do
    key =
      user
      |> Hexpm.Accounts.Key.build(%{name: "any_key_name"})
      |> Hexpm.Repo.insert!
    key.user_secret
  end

  def read_fixture(path) do
    Path.join([__DIR__, "..", "fixtures", path])
    |> File.read!()
  end
end
