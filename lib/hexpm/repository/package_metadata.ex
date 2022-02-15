defmodule Hexpm.Repository.PackageMetadata do
  use Hexpm.Schema

  @derive HexpmWeb.Stale

  embedded_schema do
    field :description, :string
    field :licenses, {:array, :string}
    field :links, {:map, :string}
    field :maintainers, {:array, :string}
    field :extra, :map
  end

  def changeset(meta, params, package) do
    cast(meta, params, ~w(description licenses links maintainers extra)a)
    |> validate_required_meta(package)
    |> validate_links()
    |> validate_licenses(package)
  end

  def update_changeset(meta, params, package) do
    cast(meta, params, ~w(description licenses links maintainers extra)a)
    |> validate_required_meta(package)
    |> validate_links()
  end

  defp validate_required_meta(changeset, package) do
    if package.repository.public do
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

  defp validate_licenses(changeset, package) do
    if package.repository.public do
      validate_change(changeset, :licenses, fn _, licenses ->
        licenses
        |> Enum.reject(&valid_license?/1)
        |> Enum.map(&{:licenses, "invalid license #{inspect(&1)}"})
      end)
    else
      changeset
    end
  end

  defp valid_url?(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] and !!uri.host
  end

  defp valid_license?(license) do
    :hex_licenses.valid(license)
  end
end
