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

  def get_versions(name, package_name) do
    case :ets.lookup(name, {:versions, package_name}) do
      [{_, versions}] ->
        versions
      [] ->
        package_id = from(p in HexWeb.Package, where: p.name == ^package_name, select: p.id)
                     |> HexWeb.Repo.one!
        releases = from(r in HexWeb.Release, where: r.package_id == ^package_id, select: {r.id, r.version})
                   |> HexWeb.Repo.all

        versions = Enum.map(releases, &elem(&1, 1))
        releases = Enum.map(releases, fn {id, vsn} -> {{:release, package_name, vsn}, id} end)

        :ets.insert(name, {{:versions, package_name}, versions})
        :ets.insert(name, releases)

        versions
    end
  end

  def get_deps(name, package, version) do
    case :ets.lookup(name, {:deps, package, version}) do
      [{_, versions}] ->
        versions
      [] ->
        release_id = :ets.lookup_element(name, {:release, package, version}, 2)
        requirements = from(r in HexWeb.Requirement,
                            join: p in assoc(r, :dependency),
                            where: r.release_id == ^release_id,
                            select: {p.name, r.app, r.requirement, r.optional})
                       |> HexWeb.Repo.all

        :ets.insert(name, {{:deps, package, version}, requirements})
        requirements
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
