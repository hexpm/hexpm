defmodule HexWeb.Release do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  import HexWeb.Validation

  queryable "releases" do
    belongs_to :package, HexWeb.Package
    field :version, :string
    field :git_url, :string
    field :git_ref, :string
    has_many :requirements, HexWeb.Requirement
    field :created, :datetime
  end

  validate release,
    version: present() and type(:string) and valid_version(),
    git_url: present() and type(:string),
    git_ref: present() and type(:string),
    also: unique([:version], scope: [:package_id], on: HexWeb.Repo)

  # TODO: Extract validation of requirements

  def create(package, version, url, ref, requirements) do
    release = package.releases.new(version: version, git_url: url, git_ref: ref)

    case validate(release) do
      [] ->
        HexWeb.Repo.transaction(fn ->
          release = HexWeb.Repo.create(release)
          requirements = create_requirements(release, requirements)

          errors = Enum.filter_map(requirements, &match?({ :error, _ }, &1), &elem(&1, 1))
          if errors == [] do
            release.package(package).requirements(requirements)
          else
            HexWeb.Repo.rollback(deps: errors)
          end
        end)
      errors ->
        { :error, errors }
    end
  end

  defp create_requirements(release, requirements) do
    deps = Dict.keys(requirements) |> Enum.filter(&is_binary/1)

    deps_query =
         from p in HexWeb.Package,
       where: p.name in array(^deps, ^:string),
      select: { p.name, p.id }
    deps = HexWeb.Repo.all(deps_query) |> HashDict.new

    Enum.map(requirements, fn { dep, req } ->
      cond do
        not is_binary(req) or match?(:error, Version.parse_requirement(req)) ->
          { :error, { dep, "invalid requirement: #{inspect req}" } }

        id = deps[dep] ->
          release.requirements.new(requirement: req, dependency_id: id)
          |> HexWeb.Repo.create()
          { dep, req }

        true ->
          { :error, { dep, "unknown package" } }
      end
    end)
  end

  def all(package) do
    # TODO: Sort releases by Version.compare/2
    HexWeb.Repo.all(package.releases)
    |> Enum.map(&(&1.package(package)))
  end

  def get(package, version) do
    release =
      from(r in package.releases, where: r.version == ^version)
      |> HexWeb.Repo.all
      |> List.first

    if release do
      reqs =
        from(req in release.requirements,
             join: p in req.dependency,
             select: { p.name, req.requirement })
        |> HexWeb.Repo.all

      release.package(package)
             .requirements(reqs)
    end
  end
end

defimpl HexWeb.Render, for: HexWeb.Release.Entity do
  import HexWeb.Util

  def render(release) do
    package = release.package.get
    reqs    = release.requirements.to_list

    release.__entity__(:keywords)
    |> Dict.take([:version, :git_url, :git_ref, :created])
    |> Dict.update!(:created, &to_iso8601/1)
    |> Dict.put(:url, url(["packages", package.name, "releases", release.version]))
    |> Dict.put(:package_url, url(["packages", package.name]))
    |> Dict.put(:requirements, reqs)
  end
end
