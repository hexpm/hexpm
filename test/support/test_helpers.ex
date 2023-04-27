defmodule Hexpm.TestHelpers do
  @tmp Application.compile_env(:hexpm, :tmp_dir)

  def create_tar(meta, files \\ [{"mix.exs", "mix.exs"}]) do
    meta =
      meta
      |> Map.put_new(:app, meta[:name])
      |> Map.put_new(:build_tools, ["mix"])
      |> Map.put_new(:licenses, ["Apache-2.0"])
      |> Map.put_new(:requirements, %{})
      |> Map.put_new(:files, Enum.map(files, &elem(&1, 0)))

    contents_path = Path.join(@tmp, "#{meta[:name]}-#{meta[:version]}-contents.tar.gz")
    files = Enum.map(files, fn {name, bin} -> {String.to_charlist(name), bin} end)
    :ok = :erl_tar.create(contents_path, files, [:compressed])
    contents = File.read!(contents_path)

    meta_string = HexpmWeb.ConsultFormat.encode(meta)
    blob = "3" <> meta_string <> contents
    checksum = :crypto.hash(:sha256, blob) |> Base.encode16()

    files = [
      {~c"VERSION", "3"},
      {~c"CHECKSUM", checksum},
      {~c"metadata.config", meta_string},
      {~c"contents.tar.gz", contents}
    ]

    path = Path.join(@tmp, "#{meta[:name]}-#{meta[:version]}.tar")
    :ok = :erl_tar.create(path, files)

    File.read!(path)
  end

  def rel_meta(params) do
    params = params(params)

    meta =
      params
      |> Map.put_new("build_tools", ["mix"])
      |> Map.put_new("files", ["mix.exs"])

    params
    |> Map.put("meta", meta)
    |> Map.update("requirements", [], &requirements_meta/1)
  end

  def pkg_meta(meta) do
    params = params(meta)
    meta = Map.put_new(params, "licenses", ["Apache-2.0"])
    Map.put(params, "meta", meta)
  end

  def params(params) when is_map(params) do
    Enum.into(params, %{}, fn
      {binary, value} when is_binary(binary) -> {binary, params(value)}
      {atom, value} when is_atom(atom) -> {Atom.to_string(atom), params(value)}
    end)
  end

  def params(params) when is_list(params), do: Enum.map(params, &params/1)
  def params(other), do: other

  def mock_pwned() do
    Mox.stub(Hexpm.Pwned.Mock, :password_breached?, fn _password -> false end)
  end

  defp requirements_meta(list) do
    Enum.map(list, fn req ->
      req
      |> Map.put_new("repository", "hexpm")
      |> Map.put_new("optional", false)
      |> Map.put_new("app", req["name"])
    end)
  end

  def app_env(app, key, value) do
    original_env = Application.get_env(app, key)
    Application.put_env(app, key, value)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(app, key, original_env)
    end)
  end

  def key_for(user_or_organization, permissions \\ [%{domain: "api"}]) do
    {:ok, %{key: key}} =
      Hexpm.Accounts.Keys.create(
        user_or_organization,
        %{name: "any_key_name", permissions: permissions},
        audit: nil
      )

    key.user_secret
  end

  def read_fixture(path) do
    Path.join([__DIR__, "..", "fixtures", path])
    |> File.read!()
  end

  def audit_data(user, opts \\ [])

  def audit_data(%Hexpm.Accounts.Organization{user: user}, opts) do
    audit_data(user, opts)
  end

  def audit_data(%Hexpm.Accounts.User{} = user, opts) do
    %{
      user: user,
      key: Keyword.get(opts, :key),
      user_agent: Keyword.get(opts, :user_agent, "TEST"),
      remote_ip: Keyword.get(opts, :remote_ip, "127.0.0.1")
    }
  end

  def default_meta(name, version) do
    %{
      "name" => name,
      "description" => "description",
      "licenses" => [],
      "version" => version,
      "requirements" => [],
      "app" => name,
      "build_tools" => ["mix"],
      "files" => ["mix.exs"]
    }
  end

  def default_requirement(name, requirement) do
    %{"name" => name, "app" => name, "requirement" => requirement, "optional" => false}
  end
end
