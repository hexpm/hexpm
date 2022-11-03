defmodule Hexpm.Repository.Requirement do
  use Hexpm.Schema
  require Logger

  @derive {HexpmWeb.Stale, last_modified: nil}

  schema "requirements" do
    field :app, :string
    field :requirement, :string
    field :optional, :boolean, default: false

    # The repository and name of the dependency used to find the package
    field :repository, :string, virtual: true
    field :name, :string, virtual: true

    belongs_to :release, Release
    belongs_to :dependency, Package
  end

  def changeset(requirement, params, dependencies, package) do
    repository = params["repository"] || "hexpm"

    cast(requirement, params, ~w(repository name app requirement optional)a)
    |> put_assoc(:dependency, dependencies[{repository, params["name"]}])
    |> validate_required(~w(name app requirement optional)a)
    |> validate_required(
      :dependency,
      message: "package does not exist in repository \"#{repository}\""
    )
    |> validate_requirement(:requirement)
    |> validate_repository(:repository, repository: package.repository)
  end

  def build_all(release_changeset, package) do
    dependencies = preload_dependencies(release_changeset.params["requirements"])

    cast_assoc(
      release_changeset,
      :requirements,
      with: &changeset(&1, &2, dependencies, package)
    )
  end

  defp preload_dependencies(requirements) do
    names = requirement_names(requirements)

    from(
      p in Package,
      join: r in assoc(p, :repository),
      select: {{r.name, p.name}, %{p | repository: r}}
    )
    |> filter_dependencies(names)
  end

  defp filter_dependencies(_query, []) do
    %{}
  end

  defp filter_dependencies(query, names) do
    import Ecto.Query, only: [or_where: 3]

    Enum.reduce(names, query, fn {repository, package}, query ->
      or_where(query, [p, r], r.name == ^repository and p.name == ^package)
    end)
    |> Hexpm.Repo.all()
    |> Map.new()
  end

  defp requirement_names(requirements) when is_list(requirements) do
    Enum.flat_map(requirements, fn
      req when is_map(req) ->
        name = req["name"]
        repository = req["repository"] || "hexpm"

        if is_binary(name) and is_binary(repository) do
          [{repository, name}]
        else
          []
        end

      _ ->
        []
    end)
  end

  defp requirement_names(_requirements), do: []
end
