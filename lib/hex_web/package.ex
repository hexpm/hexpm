defmodule HexWeb.Package do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  import HexWeb.Validation
  require Ecto.Validator
  alias HexWeb.Util

  schema "packages" do
    field :name, :string
    has_many :owners, HexWeb.User
    field :meta, :string
    has_many :releases, HexWeb.Release
    field :created_at, :datetime
    field :updated_at, :datetime
    has_many :downloads, HexWeb.Stats.PackageDownload
  end

  validatep validate_create(package),
    also: validate(),
    also: unique([:name], case_sensitive: false, on: HexWeb.Repo)

  validatep validate(package),
    name: present() and type(:string) and has_format(~r"^[a-z]\w*$"),
    meta: validate_meta()

  defp validate_meta(field, arg) do
    errors =
      Ecto.Validator.bin_dict(arg,
        contributors: type({:array, :string}),
        licenses:     type({:array, :string}),
        links:        type({:dict, :string, :string}),
        description:  type(:string))

    if errors == [], do: [], else: [{field, errors}]
  end

  @meta_fields [:contributors, :description, :links, :licenses]
  @meta_fields @meta_fields ++ Enum.map(@meta_fields, &Atom.to_string/1)

  def create(name, owner, meta) do
    now = Util.ecto_now
    meta = Dict.take(meta, @meta_fields)
    package = %HexWeb.Package{name: name, meta: meta, created_at: now,
                              updated_at: now}

    case validate_create(package) do
      [] ->
        package = %{package | meta: Jazz.encode!(package.meta)}

        {:ok, package} = HexWeb.Repo.transaction(fn ->
          package = HexWeb.Repo.insert(package)

          %HexWeb.PackageOwner{package_id: package.id, owner_id: owner.id}
          |> HexWeb.Repo.insert
          package
        end)

        {:ok, %{package | meta: meta}}
      errors ->
        {:error, errors_to_map(errors)}
    end
  end

  def update(package, meta) do
    meta = Dict.take(meta, @meta_fields)

    case validate(%{package | meta: meta}) do
      [] ->
        package = %{package | updated_at: Util.ecto_now, meta: Jazz.encode!(meta)}
        HexWeb.Repo.update(package)
        {:ok, %{package | meta: meta}}
      errors ->
        {:error, errors_to_map(errors)}
    end
  end

  def get(name) do
    package =
      from(p in HexWeb.Package,
           where: p.name == ^name,
           limit: 1)
      |> HexWeb.Repo.one

    if package do
      %{package | meta: Jazz.decode!(package.meta)}
    end
  end

  def owners(package) do
    from(p in HexWeb.PackageOwner,
         where: p.package_id == ^package.id,
         join: u in HexWeb.User, on: u.id == p.owner_id,
         select: u)
    |> HexWeb.Repo.all
  end

  def owner?(package, user) do
    from(p in HexWeb.PackageOwner,
         where: p.package_id == ^package.id,
         where: p.owner_id == ^user.id,
         select: true)
    |> HexWeb.Repo.all
    |> Enum.any?
  end

  def add_owner(package, user) do
    %HexWeb.PackageOwner{package_id: package.id, owner_id: user.id}
    |> HexWeb.Repo.insert
  end

  def delete_owner(package, user) do
    from(p in HexWeb.PackageOwner,
         where: p.package_id == ^package.id,
         where: p.owner_id == ^user.id)
    |> HexWeb.Repo.delete_all
  end

  def all(page, count, search \\ nil) do
    from(p in HexWeb.Package,
         order_by: p.name)
    |> Util.paginate(page, count)
    |> search(search, true)
    |> HexWeb.Repo.all
    |> Enum.map(& %{&1 | meta: Jazz.decode!(&1.meta)})
  end

  def recent(count) do
    from(p in HexWeb.Package,
         order_by: [desc: p.created_at],
         limit: count,
         select: {p.name, p.created_at})
    |> HexWeb.Repo.all
  end

  def count(search \\ nil) do
    from(p in HexWeb.Package, select: count(p.id))
    |> search(search, false)
    |> HexWeb.Repo.one!
  end

  defp search(query, nil, _order?) do
    query
  end

  defp search(query, search, order?) do
    name_search = "%" <> like_escape(search, ~r"(%|_)") <> "%"
    desc_search = String.replace(search, ~r"\s+", " & ")

    query = from(var in query,
         where: ilike(var.name, ^name_search) or
                text_match(to_tsvector("english", json_access(var.meta, "description")),
                           to_tsquery("english", ^desc_search)))
    if order? do
      query = from(var in query, order_by: ilike(var.name, ^name_search))
    end

    query
  end

  defp like_escape(string, escape) do
    String.replace(string, escape, "\\\\\\1")
  end

  defp errors_to_map(errors) do
    if meta = errors[:meta] do
      errors = Dict.put(errors, :meta, Enum.into(meta, %{}))
    end
    Enum.into(errors, %{})
  end
end

defimpl HexWeb.Render, for: HexWeb.Package do
  import HexWeb.Util

  def render(package) do
    dict =
      HexWeb.Package.__schema__(:keywords, package)
      |> Dict.take([:name, :meta, :created_at, :updated_at])
      |> Dict.update!(:created_at, &to_iso8601/1)
      |> Dict.update!(:updated_at, &to_iso8601/1)
      |> Dict.put(:url, api_url(["packages", package.name]))
      |> Enum.into(%{})

    if package.releases.loaded? do
      releases =
        Enum.map(package.releases.all, fn release ->
          HexWeb.Release.__schema__(:keywords, release)
          |> Dict.take([:version, :created_at, :updated_at])
          |> Dict.update!(:created_at, &to_iso8601/1)
          |> Dict.update!(:updated_at, &to_iso8601/1)
          |> Dict.put(:url, api_url(["packages", package.name, "releases", release.version]))
          |> Enum.into(%{})
        end)
      dict = Dict.put(dict, :releases, releases)
    end

    if package.downloads.loaded? do
      downloads = Enum.into(package.downloads.all, %{})
      dict = Dict.put(dict, :downloads, downloads)
    end

    dict
  end
end
