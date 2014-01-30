defmodule ExplexWeb.Package do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  require Ecto.Validator
  import ExplexWeb.Util.Validation

  queryable "packages" do
    field :name, :string
    belongs_to :owner, ExplexWeb.User
    field :meta, :string
    field :created, :datetime
  end

  validate package,
    name: type(:string) and present(),
    meta: validate_meta()

  defp validate_meta(field, arg) do
    errors =
      Ecto.Validator.bin_dict(arg,
        contributors: type({ :array, :string }),
        licenses:     type({ :array, :string }),
        links:        type({ :dict, :string, :string }),
        description:  type(:string))
    if errors == [], do: [], else: [meta: errors]
  end

  @meta_fields ["contributors", "description", "links", "licenses"]

  def create(name, owner, meta) do
    meta = Dict.take(meta, @meta_fields)
    package = owner.packages.new(name: name, meta: meta)

    case validate(package) do
      [] ->
        package = package.meta(JSON.encode!(meta))
        { :ok, ExplexWeb.Repo.create(package).update_meta(&JSON.decode!(&1)) }
      errors ->
        { :error, errors }
    end
  end

  def get(name) do
    package =
      from(p in ExplexWeb.Package, where: p.name == ^name)
      |> ExplexWeb.Repo.all
      |> List.first

    if package do
      package.update_meta(&JSON.decode!(&1))
    end
  end
end
