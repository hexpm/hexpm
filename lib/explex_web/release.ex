defmodule ExplexWeb.Release do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  import ExplexWeb.Util.Validation

  queryable "releases" do
    belongs_to :package, ExplexWeb.Package
    field :version, :string
    field :git_url, :string
    field :git_ref, :string
    has_many :requirements, ExplexWeb.Requirement
    field :created, :datetime
  end

  validate release,
    version: present() and type(:string) and valid_version(),
    git_url: present() and type(:string),
    git_ref: present() and type(:string),
    also: unique([:version], scope: [:package_id], on: ExplexWeb.Repo)

  # TODO: Extract validation of requirements

  def create(package, version, url, ref, requirements) do
    release = package.releases.new(version: version, git_url: url, git_ref: ref)

    case validate(release) do
      [] ->
        ExplexWeb.Repo.transaction(fn ->
          release = ExplexWeb.Repo.create(release)
          deps = Dict.keys(requirements) |> Enum.filter(&is_binary/1)

          deps_query =
               from p in ExplexWeb.Package,
             where: p.name in array(^deps, ^:string),
            select: { p.name, p.id }
          deps = ExplexWeb.Repo.all(deps_query) |> HashDict.new

          requirements =
            Enum.map(requirements, fn { dep, req } ->
              cond do
                not is_binary(req) or match?(:error, Version.parse_requirement(req)) ->
                  { :error, { dep, "invalid requirement: #{inspect req}" } }

                id = deps[dep] ->
                  release.requirements.new(requirement: req, dependency_id: id)
                  |> ExplexWeb.Repo.create()
                  { dep, req }

                true ->
                  { :error, { dep, "unknown package" } }
              end
            end)

          errors = Enum.filter_map(requirements, &match?({ :error, _ }, &1), &elem(&1, 1))
          if errors == [] do
            release.package(package)
                   .requirements(requirements)
          else
            ExplexWeb.Repo.rollback(deps: errors)
          end
        end)
      errors ->
        { :error, errors }
    end
  end

  def all(package) do
    ExplexWeb.Repo.all(package.releases)
    |> Enum.map(&(&1.package(package)))
  end

  def get(package, version) do
    release =
      from(r in package.releases, where: r.version == ^version)
      |> ExplexWeb.Repo.all
      |> List.first

    if release do
      reqs =
        from(req in release.requirements,
             join: p in req.dependency,
             select: { p.name, req.requirement })
        |> ExplexWeb.Repo.all

      release.package(package)
             .requirements(reqs)
    end
  end
end

defimpl ExplexWeb.Render, for: ExplexWeb.Release.Entity do
  import ExplexWeb.Util

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
