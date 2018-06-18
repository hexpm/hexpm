defmodule Hexpm.Case do
  import ExUnit.Callbacks

  def reset_store() do
    if Application.get_env(:hexpm, :s3_bucket) do
      Application.put_env(:hexpm, :store_impl, Hexpm.Store.S3)
      on_exit(fn -> Application.put_env(:hexpm, :store_impl, Hexpm.Store.Local) end)
    end
  end

  def create_user(username, email, password, confirmed? \\ true) do
    Hexpm.Accounts.User.build(
      %{username: username, password: password, emails: [%{email: email}]},
      confirmed?
    )
    |> Hexpm.Repo.insert!()
  end

  def key_for(user_or_organization) do
    key =
      user_or_organization
      |> Hexpm.Accounts.Key.build(%{name: "any_key_name"})
      |> Hexpm.Repo.insert!()

    key.user_secret
  end

  def read_fixture(path) do
    Path.join([__DIR__, "..", "fixtures", path])
    |> File.read!()
  end

  def audit_data(user) do
    {user, "TEST"}
  end

  def default_meta(name, version) do
    %{
      "name" => name,
      "description" => "description",
      "licenses" => [],
      "version" => version,
      "requirements" => [],
      "app" => name,
      "build_tools" => ["mix"]
    }
  end

  def default_requirement(name, requirement) do
    %{"name" => name, "app" => name, "requirement" => requirement, "optional" => false}
  end
end
