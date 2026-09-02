defmodule Hexpm.TestHelpers do
  @tmp Application.compile_env(:hexpm, :tmp_dir)

  @doc """
  The arguments of the newest purge job enqueued for `keys`, with the write
  number every target must carry taken out, so a test can compare the rest
  against a literal.
  """
  def purge_args(keys) do
    jobs =
      Oban.Testing.all_enqueued(Hexpm.RepoBase,
        worker: Hexpm.CDN.PurgeWorker,
        args: %{"keys" => keys}
      )

    %{args: args} = Enum.max_by(jobs, & &1.id)
    true = Enum.all?(args["verify"], &is_integer(&1["write"]))
    update_in(args["verify"], &Enum.map(&1, fn target -> Map.delete(target, "write") end))
  end

  @doc """
  Captures logs down to debug, including Ecto's query log.

  `capture_log/2`'s `:level` option filters what it keeps; it does not lower
  `Logger.level/0`, and the test environment runs at `:error`. Passing
  `level: :debug` to `capture_log/2` alone therefore returns an empty string,
  and a test asserting a secret is absent from it passes on nothing.
  """
  def capture_debug_log(fun) do
    level = Logger.level()
    Logger.configure(level: :debug)

    try do
      ExUnit.CaptureLog.capture_log(fun)
    after
      Logger.configure(level: level)
    end
  end

  @doc """
  Inserts a release whose tarball holds `files`, and puts it in the repo bucket.

  `Hexpm.Factory.insert_with_tarball/1` hardcodes a generated `mix.exs`, which
  is no use when the point of the test is what the files contain.
  """
  def insert_release_with_files(package, version, files, attrs \\ []) do
    {extra_metadata, attrs} = Keyword.pop(attrs, :metadata, %{})

    metadata =
      Map.merge(
        %{
          "name" => package.name,
          "version" => version,
          "description" => "Fake package #{package.name}",
          "licenses" => ["Apache-2.0"],
          "files" => Enum.map(files, &elem(&1, 0)),
          "requirements" => %{},
          "app" => package.name,
          "build_tools" => ["mix"]
        },
        extra_metadata
      )

    tar_files = Enum.map(files, fn {name, contents} -> {String.to_charlist(name), contents} end)

    {:ok, %{tarball: tarball, inner_checksum: inner, outer_checksum: outer}} =
      :hex_tarball.create(metadata, tar_files)

    release =
      Hexpm.Factory.insert(
        :release,
        [package: package, version: version, inner_checksum: inner, outer_checksum: outer] ++
          attrs
      )
      |> Hexpm.Repo.preload(package: :repository)

    Hexpm.Store.put(
      :repo_bucket,
      Hexpm.Repository.Assets.tarball_store_key(release),
      tarball,
      []
    )

    release
  end

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

  def create_docs_tar(files) do
    files = for {path, contents} <- files, do: {String.to_charlist(path), contents}
    {:ok, tarball} = :hex_tarball.create_docs(files)
    tarball
  end

  def create_docs_tar(files, mode) do
    path = Path.join(@tmp, "docs-#{Base.encode16(:crypto.strong_rand_bytes(4))}.tar")
    {:ok, tar} = :hex_erl_tar.open(String.to_charlist(path), [:write])

    try do
      Enum.each(files, fn {name, contents} ->
        :ok = :hex_erl_tar.add(tar, contents, String.to_charlist(name), mode: mode)
      end)
    after
      :ok = :hex_erl_tar.close(tar)
    end

    tarball = path |> File.read!() |> :zlib.gzip()
    File.rm!(path)
    tarball
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
      auth_credential: Keyword.get(opts, :auth_credential, Keyword.get(opts, :key)),
      user_agent: Keyword.get(opts, :user_agent, "TEST"),
      remote_ip: Keyword.get(opts, :remote_ip, "127.0.0.1"),
      request_id: Keyword.get(opts, :request_id)
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

  def recompute_dependants(package) do
    {:ok, _} =
      Hexpm.Repository.PackageDependants.recompute_for_package(Hexpm.Repo, package)

    package
  end

  @doc """
  Gives the organization a paid seat count, which is what `Hexpm.Accounts.Seats`
  reads. The factory leaves it unset, which reports the limit as unknown.
  """
  def seats(organization, seats) do
    organization
    |> Ecto.Changeset.change(billing_seats: seats)
    |> Hexpm.Repo.update!()
  end

  @doc """
  Returns every SQL statement `fun` ran in the calling process.

  The telemetry handler is global, so it compares against the caller to keep
  queries from concurrently running async tests out of the result.
  """
  def capture_queries(fun) do
    test = self()
    handler = {__MODULE__, System.unique_integer()}

    :telemetry.attach(
      handler,
      [:hexpm, :repo_base, :query],
      fn _event, _measurements, %{query: query}, _config ->
        if self() == test, do: send(test, {handler, query})
      end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    collect_queries(handler, [])
  end

  defp collect_queries(handler, acc) do
    receive do
      {^handler, query} -> collect_queries(handler, [query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
