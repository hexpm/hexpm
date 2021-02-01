defmodule Hexpm.Repository.PackageMetadata do
  use Hexpm.Schema

  @derive HexpmWeb.Stale

  embedded_schema do
    field :description, :string
    field :licenses, {:array, :string}
    field :keywords, {:array, :string}
    field :links, {:map, :string}
    field :maintainers, {:array, :string}
    field :extra, :map
  end

  def changeset(meta, params, package) do
    cast(meta, params, ~w(description licenses keywords links maintainers extra)a)
    |> validate_required_meta(package)
    |> validate_length(:keywords, max: 10)
    |> validate_keywords()
    |> validate_links()
  end

  defp validate_required_meta(changeset, package) do
    if package.repository.public do
      validate_required(changeset, ~w(description licenses)a)
    else
      changeset
    end
  end

  defp validate_keywords(changeset) do
    changeset
    |> update_change(:keywords, fn keywords -> Enum.map(keywords, &String.downcase/1) end)
    |> validate_change(:keywords, fn _, keywords ->
      keywords
      |> Enum.reject(&(String.length(&1) < 30))
      |> Enum.map(&{:keywords, "invalid keyword #{inspect(&1)}"})
    end)
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
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] and !!uri.host
  end
end
