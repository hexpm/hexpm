defmodule Hexpm.Repository.Requirement do
  use Hexpm.Web, :schema
  require Logger

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

  def changeset(requirement, params, dependencies, release_changeset) do
    cast(requirement, params, ~w(name app requirement optional))
    |> put_assoc(:dependency, dependencies[params["name"]])
    |> validate_required(~w(name app requirement optional)a)
    |> validate_required(:dependency, message: "package does not exist")
    |> validate_requirement(:requirement, pre: get_field(release_changeset, :version).pre != [])
  end

  def build_all(release_changeset) do
    dependencies = preload_dependencies(release_changeset.params["requirements"])

    release_changeset = cast_assoc(
      release_changeset,
      :requirements,
      with: &changeset(&1, &2, dependencies, release_changeset)
    )

    if release_changeset.valid? do
      requirements =
        get_change(release_changeset, :requirements, [])
        |> Enum.map(&apply_changes/1)

      validate_resolver(release_changeset, requirements)
    else
      release_changeset
    end
  end

  defp validate_resolver(release_changeset, requirements) do
    build_tools = get_field(release_changeset, :meta).build_tools

    {time, release_changeset} = :timer.tc(fn ->
      case Resolver.run(requirements, build_tools) do
        :ok ->
          release_changeset
        {:error, reason} ->
          release_changeset = update_in(release_changeset.changes.requirements, fn req_changesets ->
            Enum.map(req_changesets, &add_error(&1, :requirement, reason))
          end)
          %{release_changeset | valid?: false}
      end
    end)

    Logger.warn "DEPENDENCY_RESOLUTION_COMPLETED (#{div time, 1000}ms)"
    release_changeset
  end

  defp preload_dependencies(requirements)  do
    names = requirement_names(requirements)
    from(p in Package, where: p.name in ^names, select: {p.name, p})
    |> Hexpm.Repo.all
    |> Enum.into(%{})
  end

  defp requirement_names(requirements) when is_list(requirements) do
    Enum.flat_map(requirements, fn
      req when is_map(req) ->
        [req["name"]]
      _ ->
        []
    end)
    |> Enum.filter(&is_binary/1)
  end
  defp requirement_names(_requirements), do: []
end
