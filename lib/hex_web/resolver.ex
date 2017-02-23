defmodule HexWeb.Resolver do
  import Ecto.Query, only: [from: 2]

  @behaviour Hex.Registry

  def run(requirements, build_tools) do
    config = guess_config(build_tools)

    Code.ensure_loaded(Hex.Resolver)
    if function_exported?(Hex.Resolver, :resolve, 4) do
      resolve_old(requirements, config)
    else
      resolve_new(requirements, config)
    end
  end

  defp resolve_old(requirements, config) do
    Hex.Registry.open!(__MODULE__)

    deps = resolve_old_deps(requirements)
    top_level = Enum.map(deps, &elem(&1, 0))
    requests = resolve_old_requests(requirements, config)

    requests
    |> Enum.map(&elem(&1, 0))
    |> Hex.Registry.prefetch()

    Hex.Resolver.resolve(requests, deps, top_level, [])
    |> resolve_result()
  after
    Hex.Registry.close
  end

  defp resolve_new(requirements, config) do
    {:ok, _name} = open()

    deps = resolve_new_deps(requirements)
    top_level = Enum.map(deps, &elem(&1, 0))
    requests = resolve_new_requests(requirements, config)

    requests
    |> Enum.map(&{elem(&1, 0), elem(&1, 1)})
    |> prefetch()

    Hex.Resolver.resolve(__MODULE__, requests, deps, top_level, %{}, [])
    |> resolve_result()
  after
    close()
  end

  defp resolve_result({:ok, _}), do: :ok
  defp resolve_result({:error, {:version, messages}}), do: {:error, remove_ansi_escapes(messages)}
  defp resolve_result({:error, messages}), do: {:error, remove_ansi_escapes(messages)}

  defp remove_ansi_escapes(string) do
    String.replace(string, ~r"\e\[[0-9]+[a-zA-Z]", "")
  end

  defp resolve_old_deps(requirements) do
    Enum.map(requirements, fn %{app: app} ->
      {app, false, []}
    end)
  end

  defp resolve_new_deps(requirements) do
    Enum.map(requirements, fn %{app: app} ->
      {"hexpm", app, false, []}
    end)
  end

  defp resolve_old_requests(requirements, config) do
    Enum.map(requirements, fn %{name: name, app: app, requirement: req} ->
      {name, app, req, config}
    end)
  end

  defp resolve_new_requests(requirements, config) do
    Enum.map(requirements, fn %{name: name, app: app, requirement: req} ->
      {"hexpm", name, app, req, config}
    end)
  end

  defp guess_config(build_tools) when is_list(build_tools) do
    cond do
      "mix" in build_tools       -> "mix.exs"
      "rebar" in build_tools     -> "rebar.config"
      "rebar3" in build_tools    -> "rebar.config"
      "erlang.mk" in build_tools -> "Makefile"
      true                       -> "TOP CONFIG"
    end
  end
  defp guess_config(_), do: "TOP CONFIG"

  ### Hex.Registry callbacks ###

  def open(_opts \\ []) do
    tid = :ets.new(__MODULE__, [])
    Process.put(__MODULE__, tid)
    {:ok, tid}
  end

  def close(name \\ Process.get(__MODULE__)) do
    Process.delete(__MODULE__)
    if :ets.info(name) == :undefined do
      false
    else
      :ets.delete(name)
    end
  end

  def versions("hexpm", package_name), do: get_versions(Process.get(__MODULE__), package_name)
  def versions(name, package_name), do: get_versions(name, package_name)
  def deps("hexpm", package, version), do: get_deps_new(Process.get(__MODULE__), package, version)
  def deps(name, package, version), do: get_deps_old(name, package, version)
  def checksum(_name, _package, _version), do: raise "not implemented"

  def prefetch(packages) do
    packages = Enum.map(packages, fn {"hexpm", name} -> name end)
    prefetch(Process.get(__MODULE__), packages)
  end
  def prefetch(name, packages) do
    packages =
      packages
      |> Enum.uniq
      |> Enum.reject(&:ets.member(name, {:versions, &1}))

    packages =
      from(p in HexWeb.Package,
           where: p.name in ^packages,
           select: {p.id, p.name})
      |> HexWeb.Repo.all
      |> Map.new

    releases =
      from(r in HexWeb.Release,
           where: r.package_id in ^Map.keys(packages),
           select: {r.package_id, {r.id, r.version}})
      |> HexWeb.Repo.all
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    versions =
      Enum.map(packages, fn {id, name} ->
        {{:versions, name}, Enum.map(releases[id], &elem(&1, 1))}
      end)

    releases =
      Enum.flat_map(releases, fn {pid, versions} ->
        Enum.map(versions, fn {rid, vsn} ->
          {{:release, packages[pid], vsn}, rid}
        end)
      end)

    :ets.insert(name, versions ++ releases)
  end

  defp get_versions(name, package) do
    :ets.lookup_element(name, {:versions, package}, 2)
  end

  defp get_deps_new(name, package, version) do
    get_deps_old(name, package, version)
    |> Enum.map(fn {name, app, req, optional} ->
      {"hexpm", name, app, req, optional}
    end)
  end

  defp get_deps_old(name, package, version) do
    case :ets.lookup(name, {:deps, package, version}) do
      [{_, deps}] ->
        deps
      [] ->
        # TODO: Preload requirements in prefetch, maybe?
        release_id = :ets.lookup_element(name, {:release, package, version}, 2)

        deps =
          from(r in HexWeb.Requirement,
               join: p in assoc(r, :dependency),
               where: r.release_id == ^release_id,
               select: {p.name, r.app, r.requirement, r.optional})
          |> HexWeb.Repo.all

        :ets.insert(name, {{:deps, package, version}, deps})
        deps
    end
  end

  def version(_name),
    do: raise "not implemented"

  def installs(_name),
    do: raise "not implemented"

  def stat(_name),
    do: raise "not implemented"

  def search(_name, _term),
    do: raise "not implemented"

  def all_packages(_name),
    do: raise "not implemented"

  def get_checksum(_name, _package, _version),
    do: raise "not implemented"

  def get_build_tools(_name, _package, _version),
    do: raise "not implemented"

  def retired(_name, _package, _version),
    do: raise "not implemented"

  def tarball_etag(_name, _package, _version),
    do: raise "not implemented"

  def tarball_etag(_name, _package, _version, _String_t),
    do: raise "not implemented"
end
