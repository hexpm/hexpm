defmodule Hexpm.Repository.PackageMetadata do
  use Hexpm.Web, :schema

  @derive Hexpm.Web.Stale

  embedded_schema do
    field :description, :string
    field :licenses, {:array, :string}
    field :links, {:map, :string}
    field :maintainers, {:array, :string}
    field :extra, :map
  end

  def changeset(meta, params, package) do
    cast(meta, params, ~w(description licenses links maintainers extra))
    |> validate_required_meta(package)
    |> validate_links()
  end

  defp validate_required_meta(changeset, package) do
    if package.repository_id == 1 do
      validate_required(changeset, ~w(description licenses)a)
    else
      changeset
    end
  end

  defp validate_links(changeset) do
    validate_change(changeset, :links, fn _, links ->
      links
      |> Map.values()
      |> Enum.reject(&valid_url?/1)
      |> Enum.map(&{:links, "invalid link #{inspect(&1)}"})
    end)
  end

  defp valid_url?(url) do
    case :http_uri.parse(to_charlist(url)) do
      {:ok, _} -> true
      _ -> false
    end
  end
end
