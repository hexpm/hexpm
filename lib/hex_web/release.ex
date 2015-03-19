defmodule HexWeb.Release do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  import HexWeb.Validation
  alias HexWeb.Util

  schema "releases" do
    field :app, :string
    field :version, :string
    field :checksum, :string
    field :has_docs, :boolean
    field :created_at, :datetime
    field :updated_at, :datetime

    belongs_to :package, HexWeb.Package
    has_many :requirements, HexWeb.Requirement
    has_many :daily_downloads, HexWeb.Stats.Download
    has_one :downloads, HexWeb.Stats.ReleaseDownload
  end

  validatep validate(release),
    # app: present() and type(:string),
    # version: present() and type(:string) and valid_version()
    app: present(),
    version: present() and valid_version()

  validatep validate_create(release),
    also: validate(),
    also: unique(:version, scope: [:package_id], on: HexWeb.Repo)

  def create(package, version, app, requirements, checksum, created_at \\ nil) do
    now = Util.ecto_now
    release =
      build(package, :releases)
      |> struct(app: app,
                version: version,
                updated_at: now,
                checksum: String.upcase(checksum),
                created_at: created_at || now)

    if errors = validate_create(release) do
      {:error, errors}
    else
      HexWeb.Repo.transaction(fn ->
        HexWeb.Repo.insert(release)
        |> update_requirements(requirements)
        |> Util.maybe(& %{&1 | package: package})
      end)
    end
  end

  def update(release, app, requirements, checksum) do
    if editable?(release) do
      if errors = validate(release) do
        {:error, errors}
      else
        HexWeb.Repo.transaction(fn ->
          downloads = HexWeb.Repo.all(assoc(release, :daily_downloads))
          HexWeb.Repo.delete_all(assoc(release, :daily_downloads))
          HexWeb.Repo.delete_all(assoc(release, :requirements))
          HexWeb.Repo.delete(release)

          {:ok, new_release} =
            create(release.package, release.version, app, requirements,
                   checksum, release.created_at)

          Enum.each(downloads, fn download ->
            download = %{download | release_id: new_release.id}
            HexWeb.Repo.insert(download)
          end)

          new_release
        end)
      end

    else
      {:error, %{created_at: "can only modify a release up to one hour after creation"}}
    end
  end

  def delete(release, opts \\ []) do
    force? = Keyword.get(opts, :force, false)
    if editable?(release) or force? do
      HexWeb.Repo.transaction(fn ->
        HexWeb.Repo.delete_all(assoc(release, :requirements))
        HexWeb.Repo.delete(release)
      end)

      :ok
    else
      {:error, %{created_at: "can only delete a release up to one hour after creation"}}
    end
  end

  defp editable?(release) do
    created_at = Ecto.DateTime.to_erl(release.created_at)
                 |> :calendar.datetime_to_gregorian_seconds
    now = :calendar.universal_time
          |> :calendar.datetime_to_gregorian_seconds

    now - created_at <= 3600
  end

  defp update_requirements(release, requirements) do
    requirements = normalize_requirements(requirements)
    results = create_requirements(release, requirements)

    errors = Enum.filter_map(results, &match?({:error, _}, &1), &elem(&1, 1))
    if errors == [] do
      %{release | requirements: requirements}
    else
      HexWeb.Repo.rollback(%{deps: Enum.into(errors, %{})})
    end
  end

  defp create_requirements(release, requirements) do
    deps = Enum.map(requirements, &elem(&1, 0))

    deps_query =
         from p in HexWeb.Package,
       where: p.name in ^deps,
      select: {p.name, p.id}
    deps = HexWeb.Repo.all(deps_query) |> Enum.into(HashDict.new)

    Enum.map(requirements, fn {dep, app, req, optional} ->
      add_requirement(release, deps, dep, app, req, optional || false)
    end)
  end

  defp normalize_requirements(requirements) do
    Enum.map(requirements, fn
      {dep, map} when is_map(map) ->
        {to_string(dep), map["app"], map["requirement"], map["optional"] || false}
      {dep, {req, app}} ->
        {to_string(dep), to_string(app), req, false}
      {dep, req} ->
        {to_string(dep), to_string(dep), req, false}
    end)
  end

  def latest_versions(packages) when is_list(packages) do
    package_ids = Enum.map(packages, & &1.id)

    query =
           from r in HexWeb.Release,
         where: r.package_id in ^package_ids,
      group_by: r.package_id,
        select: {r.package_id, fragment("array_agg(?)", r.version)}

    HexWeb.Repo.all(query)
    |> Enum.map(fn {id, versions} ->
         {id, Enum.sort(versions, &(Version.compare(&1, &2) == :gt)) |> List.first}
       end)
    |> Enum.into(HashDict.new)
  end

  def all(package) do
    HexWeb.Repo.all(assoc(package, :releases))
    |> Enum.map(& %{&1 | package: package})
    |> sort
  end

  def sort(releases) do
    releases
    |> Enum.sort(&(Version.compare(&1.version, &2.version) == :gt))
  end

  def get(package, version) do
    from(r in assoc(package, :releases), where: r.version == ^version, limit: 1)
    |> HexWeb.Repo.one
    |> Util.maybe(& %{&1 | package: package})
    |> Util.maybe(& %{&1 | requirements: requirements(&1)})
  end

  def requirements(release) do
    from(req in assoc(release, :requirements),
         join: p in assoc(req, :dependency),
         select: {p.name, req.app, req.requirement, req.optional})
    |> HexWeb.Repo.all
  end

  def count do
    HexWeb.Repo.all(from(r in HexWeb.Release, select: fragment("count(?)", r.id)))
    |> List.first
  end

  def recent(count) do
    from(r in HexWeb.Release,
         order_by: [desc: r.created_at],
         join: p in assoc(r, :package),
         limit: ^count,
         select: {r.version, p.name})
    |> HexWeb.Repo.all
  end

  def docs_url(release) do
    HexWeb.Util.docs_url([release.package.name, release.version])
  end

  defp add_requirement(release, deps, dep, app, req, optional) do
    cond do
      not valid_requirement?(req) ->
        {:error, {dep, "invalid requirement: #{inspect req}"}}

      id = deps[dep] ->
        build(release, :requirements)
        |> struct(requirement: req,
                  app: app,
                  optional: optional,
                  dependency_id: id)
        |> HexWeb.Repo.insert()
        :ok

      true ->
        {:error, {dep, "unknown package"}}
    end
  end

  defp valid_requirement?(req) do
    is_nil(req) or (is_binary(req) and match?({:ok, _}, Version.parse_requirement(req)))
  end
end

defimpl HexWeb.Render, for: HexWeb.Release do
  import HexWeb.Util

  def render(release) do
    package = release.package

    reqs = for {name, app, req, optional} <- release.requirements, into: %{} do
      {name, %{app: app, requirement: req, optional: optional}}
    end

    entity =
      release
      |> Map.take([:app, :version, :has_docs, :created_at, :updated_at])
      |> Map.update!(:created_at, &to_iso8601/1)
      |> Map.update!(:updated_at, &to_iso8601/1)
      |> Map.put(:url, api_url(["packages", package.name, "releases", release.version]))
      |> Map.put(:package_url, api_url(["packages", package.name]))
      |> Map.put(:requirements, reqs)
      |> Enum.into(%{})

    if release.has_docs do
      entity = Dict.put(entity, :docs_url, HexWeb.Release.docs_url(release))
    end

    if association_loaded?(release.downloads) do
      entity = Dict.put(entity, :downloads, release.downloads)
    end

    entity
  end
end
