defmodule Hexpm.Repository.Resolver do
  import Ecto.Query, only: [from: 2, or_where: 3]

  @behaviour Hex.Registry

  def run(requirements, build_tools) do
    config = guess_config(build_tools)
    resolve(requirements, config)
  end

  defp resolve(requirements, config) do
    {:ok, _name} = open()

    deps = resolve_deps(requirements)
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
  defp resolve_result({:error, {:repo, messages}}), do: {:error, remove_ansi_escapes(messages)}
  defp resolve_result({:error, messages}), do: {:error, remove_ansi_escapes(messages)}

  defp remove_ansi_escapes(string) do
    String.replace(string, ~r"\e\[[0-9]+[a-zA-Z]", "")
  end

  defp resolve_deps(requirements) do
    if Version.compare(Hex.version(), "0.18.0-dev") in [:eq, :gt] do
      Map.new(requirements, fn %{app: app} ->
        {app, {false, %{}}}
      end)
    else
      Enum.map(requirements, fn %{repository: repository, app: app} ->
        {repository || "hexpm", app, false, []}
      end)
    end
  end

  defp resolve_new_requests(requirements, config) do
    Enum.map(requirements, fn %{repository: repository, name: name, app: app, requirement: req} ->
      {repository || "hexpm", name, app, req, config}
    end)
  end

  defp guess_config(build_tools) when is_list(build_tools) do
    cond do
      "mix" in build_tools -> "mix.exs"
      "rebar" in build_tools -> "rebar.config"
      "rebar3" in build_tools -> "rebar.config"
      "erlang.mk" in build_tools -> "Makefile"
      true -> "TOP CONFIG"
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

  def versions(name \\ Process.get(__MODULE__), repository, package) do
    :ets.lookup_element(name, {:versions, repository, package}, 2)
  end

  def deps(name \\ Process.get(__MODULE__), repository, package, version) do
    case :ets.lookup(name, {:deps, repository, package, version}) do
      [{_, deps}] ->
        deps

      [] ->
        release_id = :ets.lookup_element(name, {:release, repository, package, version}, 2)

        deps =
          from(
            r in Hexpm.Repository.Requirement,
            join: p in assoc(r, :dependency),
            join: repo in assoc(p, :repository),
            where: r.release_id == ^release_id,
            select: {repo.name, p.name, r.app, r.requirement, r.optional}
          )
          |> Hexpm.Repo.all()

        :ets.insert(name, {{:deps, repository, package, version}, deps})
        deps
    end
  end

  def prefetch(name \\ Process.get(__MODULE__), packages) do
    packages =
      packages
      |> Enum.uniq()
      |> Enum.reject(fn {repo, package} -> :ets.member(name, {:versions, repo, package}) end)

    load_prefetch(name, packages)
  end

  defp load_prefetch(_name, []), do: :ok

  defp load_prefetch(name, packages) do
    packages_query =
      from(
        p in Hexpm.Repository.Package,
        join: r in assoc(p, :repository),
        select: {p.id, {r.name, p.name}}
      )

    packages =
      Enum.reduce(packages, packages_query, fn {repository, package}, query ->
        or_where(query, [p, r], r.name == ^repository and p.name == ^package)
      end)
      |> Hexpm.Repo.all()
      |> Map.new()

    releases =
      from(
        r in Hexpm.Repository.Release,
        where: r.package_id in ^Map.keys(packages),
        select: {r.package_id, {r.id, r.version}}
      )
      |> Hexpm.Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    versions =
      Enum.map(packages, fn {id, {repo, package}} ->
        versions =
          releases[id]
          |> Enum.map(&elem(&1, 1))
          |> Enum.sort(&(Version.compare(&1, &2) != :gt))

        {{:versions, repo, package}, versions}
      end)

    releases =
      Enum.flat_map(releases, fn {pid, versions} ->
        Enum.map(versions, fn {rid, vsn} ->
          {repo, package} = packages[pid]
          {{:release, repo, package, vsn}, rid}
        end)
      end)

    :ets.insert(name, versions ++ releases)
  end
end
