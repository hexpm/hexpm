defmodule HexWeb.Requirement do
  use HexWeb.Web, :model
  require Logger

  schema "requirements" do
    field :app, :string
    field :requirement, :string
    field :optional, :boolean

    # The name of the dependency used to find the package
    field :name, :string, virtual: true

    belongs_to :release, Release
    belongs_to :dependency, Package
  end

  def changeset(requirement, params, dependencies) do
    cast(requirement, params, ~w(name app requirement optional))
    |> put_assoc(:dependency, dependencies[params["name"]])
    |> validate_required(~w(name app requirement optional)a)
    |> validate_required(:dependency, message: "package does not exist")
    |> validate_requirement(:requirement)
  end

  defp validate_requirement(changeset, field) do
    validate_change(changeset, field, fn key, req ->
      cond do
        is_nil(req) ->
          # Temporary friendly error message until people update to hex 0.9.1
          [{key, {"invalid requirement: #{inspect req}, use \">= 0.0.0\" instead", []}}]
        not valid?(req) ->
          [{key, {"invalid requirement: #{inspect req}", []}}]
        true ->
          []
      end
    end)
  end

  # TODO: Raise validation error if field is not set
  def build_all(release_changeset) do
    dependencies = preload_dependencies(release_changeset.params["requirements"])

    release_changeset =
      release_changeset
      |> cast_assoc(:requirements, with: &changeset(&1, &2, dependencies))

    if release_changeset.valid? do
      requirements =
        get_change(release_changeset, :requirements, [])
        |> Enum.map(&Ecto.Changeset.apply_changes/1)

      build_tools = get_field(release_changeset, :meta).build_tools

      {time, result} = :timer.tc(fn ->
        case resolve(requirements, guess_config(build_tools)) do
          :ok ->
            release_changeset
          {:error, reason} ->
            release_changeset = update_in(release_changeset.changes.requirements, fn req_changesets ->
              Enum.map(req_changesets, fn req_changeset ->
                add_error(req_changeset, :requirement, reason)
              end)
            end)
            %{release_changeset | valid?: false}
        end
      end)

      Logger.warn "DEPENDENCY_RESOLUTION_COMPLETED (#{div time, 1000}ms)"
      result
    else
      release_changeset
    end

    # TODO: Remap requirements errors to hex http spec
  end

  defp valid?(req) do
    is_binary(req) and match?({:ok, _}, Version.parse_requirement(req))
  end

  defp resolve(requirements, config) do
    Hex.Registry.open!(HexWeb.RegistryDB)

    deps      = resolve_deps(requirements)
    top_level = Enum.map(deps, &elem(&1, 0))
    requests  = resolve_requests(requirements, config)

    # TODO: Remove function_exported? on Hex 0.14+
    #       Also remove the xref exclude
    if function_exported?(Hex.Registry, :prefetch, 1) do
      requests |> Enum.map(&elem(&1, 0)) |> Hex.Registry.prefetch
    end

    case Hex.Resolver.resolve(requests, deps, top_level, []) do
      {:ok, _} ->
        :ok
      {:error, messages} ->
        # Remove ANSI escape sequences
        messages = String.replace(messages, ~r"\e\[[0-9]+[a-zA-Z]", "")
        {:error, messages}
    end
  after
    Hex.Registry.close
  end

  defp resolve_deps(requirements) do
    Enum.map(requirements, fn %{app: app} ->
      {app, false, []}
    end)
  end

  defp resolve_requests(requirements, config) do
    Enum.map(requirements, fn %{name: name, app: app, requirement: req} ->
      {name, app, req, config}
    end)
  end

  defp preload_dependencies(requirements)  do
    names = requirement_names(requirements)
    from(p in Package, where: p.name in ^names, select: {p.name, p})
    |> HexWeb.Repo.all
    |> Enum.into(%{})
  end

  defp requirement_names(requirements) when is_list(requirements) do
    Enum.flat_map(requirements, fn
      req when is_map(req) -> [req["name"]]
      _ -> []
    end)
    |> Enum.filter(&is_binary/1)
  end
  defp requirement_names(_requirements), do: []

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
end
