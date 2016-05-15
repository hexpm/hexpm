defmodule HexWeb.Requirement do
  use HexWeb.Web, :model

  schema "requirements" do
    field :app, :string
    field :requirement, :string
    field :optional, :boolean, default: false

    # The name of the dependency used to find the package
    field :name, :string, virtual: true

    belongs_to :release, Release
    belongs_to :dependency, Package
  end

  def changeset(requirement, params \\ %{}) do
    changeset = cast(requirement, params, ~w(name app requirement optional))

    name = changeset.changes.name
    app = Map.get(changeset.changes, :app, name)
    dep = HexWeb.Repo.get_by(Package, name: name)

    changeset
    |> put_change(:app, app)
    |> put_assoc(:dependency, dep)
    |> validate_requirement(dep)
  end

  defp validate_requirement(changeset, dep) do
    validate_change(changeset, :requirement, fn key, req ->
      cond do
        is_nil(req) ->
          # Temporary friendly error message until people update to hex 0.9.1
          [{key, {"invalid requirement: #{inspect req}, use \">= 0.0.0\" instead", []}}]
        not valid?(req) ->
          [{key, {"invalid requirement: #{inspect req}", []}}]
        !dep ->
          [{key, {"invalid package", []}}]
        true ->
          []
      end
    end)
  end

  def create_all(release_changeset) do
    release_changeset =
      release_changeset
      |> cast_assoc(:requirements)

    requirements =
      get_change(release_changeset, :requirements, [])
      |> Enum.filter(& &1.changes != %{})
      |> normalize

    if release_changeset.valid? do
      build_tools = get_field(release_changeset, :meta).build_tools

      case resolve(requirements, guess_config(build_tools)) do
        :ok ->
          release_changeset
        {:error, reason} ->
          %{release_changeset | valid?: false, changes:
            Map.put(release_changeset.changes, :requirements,
              Enum.map(release_changeset.changes.requirements, fn req_changeset ->
                add_error(req_changeset, :requirement, reason)
              end))}
      end
    else
      release_changeset
    end
  end

  defp normalize(requirements) do
    Enum.map(requirements, fn
      %{changes: %{} = req} ->
        req
    end)
  end

  defp valid?(req) do
    is_binary(req) and match?({:ok, _}, Version.parse_requirement(req))
  end

  defp resolve(requirements, config) do
    Hex.Registry.open!(HexWeb.RegistryDB)

    deps      = resolve_deps(requirements)
    top_level = Enum.map(deps, &elem(&1, 0))
    requests  = resolve_requests(requirements, config)

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

  defp guess_config(build_tools) do
    cond do
      "mix" in build_tools       -> "mix.exs"
      "rebar" in build_tools     -> "rebar.config"
      "rebar3" in build_tools    -> "rebar.config"
      "erlang.mk" in build_tools -> "Makefile"
      true                       -> "TOP CONFIG"
    end
  end
end
