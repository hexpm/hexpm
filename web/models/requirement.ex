defmodule HexWeb.Requirement do
  use HexWeb.Web, :model

  schema "requirements" do
    field :app, :string
    field :requirement, :string
    field :optional, :boolean

    # The name of the dependency
    field :name, :string, virtual: true

    belongs_to :release, Release
    belongs_to :dependency, Package
  end

  # TODO: Clean this up after with lands in ecto

  def create_all(release, requirements) do
    requirements = normalize(requirements)
    deps = deps(requirements)

    errors = Enum.map(requirements, &validate(deps, &1))
             |> Enum.filter(&match?({:error, _}, &1))

    if errors == [] do
      case resolve(requirements, guess_config(release)) do
        :ok ->
          Enum.each(requirements, &insert(release, deps, &1))
          {:ok, requirements}
        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, Enum.map(errors, &elem(&1, 1))}
    end
  end

  defp deps(requirements) do
    deps = Enum.map(requirements, & &1.name)

    from(p in Package,
         where: p.name in ^deps,
         select: {p.name, p.id})
    |> HexWeb.Repo.all
    |> Enum.into(%{})
  end

  defp normalize(requirements) do
    Enum.map(requirements, fn
      {dep, map} when is_map(map) ->
        %{name: to_string(dep), app: map["app"], requirement: map["requirement"], optional: map["optional"] || false}
      {dep, {req, app}} ->
        %{name: to_string(dep), app: to_string(app), requirement: req, optional: false}
      {dep, req} ->
        %{name: to_string(dep), app: to_string(dep), requirement: req, optional: false}
    end)
  end

  defp validate(deps, %{name: dep, requirement: req}) do
    cond do
      is_nil(req) ->
        # Temporary friendly error message until people update to hex 0.9.1
        {:error, {dep, "invalid requirement: #{inspect req}, use \">= 0.0.0\" instead"}}
      not valid?(req) ->
        {:error, {dep, "invalid requirement: #{inspect req}"}}
      !deps[dep] ->
        {:error, {dep, "unknown package"}}
      true ->
        :ok
    end
  end

  defp insert(release, deps, %{name: dep, app: app, requirement: req, optional: optional}) do
    build_assoc(release, :requirements)
    |> struct(requirement: req,
              app: app,
              optional: optional,
              dependency_id: deps[dep])
    |> HexWeb.Repo.insert!
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
      {:ok, _} -> :ok
      {:error, messages} -> {:error, messages}
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

  defp guess_config(release) do
    build_tools = release.meta.build_tools || []
    cond do
      "mix" in build_tools       -> "mix.exs"
      "rebar" in build_tools     -> "rebar.config"
      "rebar3" in build_tools    -> "rebar.config"
      "erlang.mk" in build_tools -> "Makefile"
      true                       -> "TOP CONFIG"
    end
  end
end
