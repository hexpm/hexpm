defmodule ExplexWeb.Package do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]

  queryable "packages" do
    field :name, :string
    belongs_to :owner, ExplexWeb.User
    field :meta, :string
    field :created, :datetime
  end

  validate package,
    name: present(),
    meta: validate_meta()

  defp validate_meta(:meta, meta) do
    errors = []

    unless list_of_strings?(Dict.get(meta, "contributors")) do
      errors = errors ++ [contributors: "should be a list of strings"]
    end

    unless list_of_strings?(Dict.get(meta, "licenses")) do
      errors = errors ++ [licenses: "should be a list of strings"]
    end

    unless dict_of_strings?(Dict.get(meta, "links")) do
      errors = errors ++ [links: "should be a dictionary of strings"]
    end

    description = Dict.get(meta, "description")
    unless nil?(description) or is_binary(description) do
      errors = errors ++ [description: "should be a string"]
    end

    errors
  end

  defp list_of_strings?(arg) do
    nil?(arg) or (is_list(arg) and Enum.all?(arg, &is_binary/1))
  end

  defp dict_of_strings?(arg) do
    nil?(arg) or (is_list(arg) and
                  Enum.all?(arg, fn { k, v } -> is_binary(k) and is_binary(v) end))
  end

  @meta_fields ["contributors", "description", "links", "licenses"]

  def create(name, owner, meta) do
    meta = Dict.take(meta, @meta_fields)
    package = owner.packages.new(name: name, meta: meta)

    case validate(package) do
      [] ->
        package = package.update_meta(&JSON.encode!(&1))
        { :ok, ExplexWeb.Repo.create(package) }
      errors ->
        { :error, errors }
    end
  end

  def get(name) do
    from(p in ExplexWeb.Package, where: p.name == ^name)
    |> ExplexWeb.Repo.all
    |> List.first
  end
end
