defmodule ExplexWeb.Release do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  import ExplexWeb.Util.Validation

  queryable "releases" do
    belongs_to :package, ExplexWeb.Package
    field :version, :string
    has_many :requirements, ExplexWeb.Requirement
    field :created, :datetime
  end

  validate release,
    version: present() and type(:string) and valid_version()

  # TODO: Extract validation of requirements

  def create(package, version, requirements) do
    release = package.releases.new(version: version)

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

                true ->
                  { :error, { dep, "unknown package" } }
              end
            end)

          errors = Enum.filter_map(requirements, &match?({ :error, _ }, &1), &elem(&1, 1))
          if errors == [] do
            release
            release.requirements(requirements)
          else
            ExplexWeb.Repo.rollback(deps: errors)
          end
        end)
      errors ->
        { :error, errors }
    end
  end

  def all(package) do
    from(r in package.releases,
         preload: [:requirements])
    |> ExplexWeb.Repo.all
  end

  def get(package, version) do
    from(r in package.releases,
         where: r.version == ^version,
         preload: [:requirements])
    |> ExplexWeb.Repo.all
    |> List.first
  end
end
