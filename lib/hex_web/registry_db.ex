defmodule HexWeb.RegistryDB do
  import Ecto.Query, only: [from: 2]

  @behaviour Hex.Registry

  def open([]) do
    {:ok, :ets.new(__MODULE__, [])}
  end

  def close(name) do
    if :ets.info(name) == :undefined do
      false
    else
      :ets.delete(name)
    end
  end

  def versions(name, package_name), do: get_versions(name, package_name)
  def deps(name, package, version), do: get_deps(name, package, version)
  def checksum(_name, _package, _version), do: raise "not implemented"

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

  def get_versions(name, package) do
    case :ets.lookup(name, {:versions, package}) do
      [{_, versions}] ->
        versions
      [] ->
        # TODO: Not needed in Hex 0.14+
        package_id = from(p in HexWeb.Package, where: p.name == ^package, select: p.id)
                     |> HexWeb.Repo.one!
        releases = from(r in HexWeb.Release, where: r.package_id == ^package_id, select: {r.id, r.version})
                   |> HexWeb.Repo.all

        versions = Enum.map(releases, &elem(&1, 1))
        releases = Enum.map(releases, fn {id, vsn} -> {{:release, package, vsn}, id} end)

        :ets.insert(name, {{:versions, package}, versions})
        :ets.insert(name, releases)

        versions
    end
  end

  def get_deps(name, package, version) do
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
end
