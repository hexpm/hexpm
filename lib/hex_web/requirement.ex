defmodule HexWeb.Requirement do
  use Ecto.Model

  schema "requirements" do
    field :app, :string
    field :requirement, :string
    field :optional, :boolean

    belongs_to :release, HexWeb.Release
    belongs_to :dependency, HexWeb.Package
  end

  def create_all(release, requirements) do
    requirements = normalize(requirements)
    results = insert_all(release, requirements)

    {_ok, errors} = Enum.partition(results, &match?({:ok, _}, &1))
    if errors == [] do
      {:ok, requirements}
    else
      {:error, Enum.map(errors, &elem(&1, 1))}
    end
  end

  defp insert_all(release, requirements) do
    deps = Enum.map(requirements, &elem(&1, 0))

    deps_query =
         from p in HexWeb.Package,
       where: p.name in ^deps,
      select: {p.name, p.id}
    deps = HexWeb.Repo.all(deps_query) |> Enum.into(%{})

    Enum.map(requirements, fn {dep, app, req, optional} ->
      insert(release, deps, dep, app, req, optional || false)
    end)
  end

  defp normalize(requirements) do
    Enum.map(requirements, fn
      {dep, map} when is_map(map) ->
        {to_string(dep), map["app"], map["requirement"], map["optional"] || false}
      {dep, {req, app}} ->
        {to_string(dep), to_string(app), req, false}
      {dep, req} ->
        {to_string(dep), to_string(dep), req, false}
    end)
  end

  defp insert(release, deps, dep, app, req, optional) do
    cond do
      is_nil(req) ->
        # Temporary friendly error message until people update to hex 0.9.1
        {:error, {dep, "invalid requirement: #{inspect req}, use \">= 0.0.0\" instead"}}

      not valid?(req) ->
        {:error, {dep, "invalid requirement: #{inspect req}"}}

      id = deps[dep] ->
        {:ok, build(release, :requirements)
              |> struct(requirement: req,
                        app: app,
                        optional: optional,
                        dependency_id: id)
              |> HexWeb.Repo.insert}

      true ->
        {:error, {dep, "unknown package"}}
    end
  end

  defp valid?(req) do
    is_binary(req) and match?({:ok, _}, Version.parse_requirement(req))
  end
end
