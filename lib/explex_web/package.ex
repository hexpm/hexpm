defmodule ExplexWeb.Package do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  require Ecto.Validator
  import ExplexWeb.Util.Validation

  queryable "packages" do
    field :name, :string
    belongs_to :owner, ExplexWeb.User
    field :meta, :string
    has_many :releases, ExplexWeb.Release
    field :created, :datetime
  end

  validatep validate_create(package),
    also: validate(),
    also: unique([:name], on: ExplexWeb.Repo)

  validatep validate(package),
    name: present() and type(:string),
    meta: validate_meta()

  defp validate_meta(field, arg) do
    errors =
      Ecto.Validator.bin_dict(arg,
        contributors: type({ :array, :string }),
        licenses:     type({ :array, :string }),
        links:        type({ :dict, :string, :string }),
        description:  type(:string))
    if errors == [], do: [], else: [{ field, errors }]
  end

  @meta_fields ["contributors", "description", "links", "licenses"]

  def create(name, owner, meta) do
    meta = Dict.take(meta, @meta_fields)
    package = owner.packages.new(name: name, meta: meta)

    case validate_create(package) do
      [] ->
        package = package.meta(JSON.encode!(meta))
        { :ok, ExplexWeb.Repo.create(package).meta(meta).releases([]) }
      errors ->
        { :error, errors }
    end
  end

  def update(package) do
    meta = Dict.take(package.meta, @meta_fields)

    case validate(package) do
      [] ->
        ExplexWeb.Repo.update(package.meta(JSON.encode!(meta)))
        { :ok, package.meta(meta) }
      errors ->
        { :error, errors }
    end
  end

  def get(name) do
    package =
      from(p in ExplexWeb.Package,
           where: p.name == ^name,
           preload: [:releases])
      |> ExplexWeb.Repo.all
      |> List.first

    if package do
      package.update_meta(&JSON.decode!(&1))
             .releases(ExplexWeb.Release.all(package))
    end
  end
end

defimpl ExplexWeb.Render, for: ExplexWeb.Package.Entity do
  import ExplexWeb.Util

  def render(package) do
    releases =
      Enum.map(package.releases, fn release ->
        release.__entity__(:keywords)
        |> Dict.take([:version, :git_url, :git_ref, :created])
        |> Dict.update!(:created, &to_iso8601/1)
        |> Dict.put(:url, url(["packages", package.name, "releases", release.version]))
      end)

    package.__entity__(:keywords)
    |> Dict.take([:name, :meta, :created])
    |> Dict.update!(:created, &to_iso8601/1)
    |> Dict.put(:url, url(["packages", package.name]))
    |> Dict.put(:releases, releases)
  end
end
