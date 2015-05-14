defmodule HexWeb.Package do
  use Ecto.Model
  import HexWeb.Validation
  import Ecto.Changeset, except: [validate_unique: 3]
  alias HexWeb.Util

  @timestamps_opts [usec: true]

  schema "packages" do
    field :name, :string
    field :meta, HexWeb.JSON
    timestamps

    has_many :releases, HexWeb.Release
    has_many :owners, HexWeb.PackageOwner
    has_many :downloads, HexWeb.Stats.PackageDownload
  end

  @elixir_names ~w(eex elixir ex_unit gettext iex logger mix hex)
  @otp_names ~w(
    appmon asn1 common_test compiler cosEvent cosEventDomain cosFileTransfer
    cosNotification cosProperty cosTime cosTransactions crypto debugger
    dialyzer diameter edoc eldap erl_docgen erl_interface et eunit gs hipe
    ic inets jinterface kernel Makefile megaco mnesia observer odbc orber
    os_mon ose otp_mibs parsetools percept pman public_key reltool runtime_tools
    sasl snmp ssh ssl stdlib syntax_tools test_server toolbar tools tv typer
    webtool wx xmerl)

  @reserved_names @elixir_names ++ @otp_names

  @meta_types %{
    "contributors" => {:array, :string},
    "licenses"     => {:array, :string},
    "links"        => {:dict, :string, :string},
    "description"  => :string
  }

  @meta_fields Map.keys(@meta_types)

  before_delete :delete_owners

  defp validate_meta(changeset, field) do
    validate_change(changeset, field, fn _field, meta ->
      errors =
        Enum.flat_map(@meta_types, fn {sub_field, type} ->
          type(sub_field, Map.get(meta, sub_field), type)
        end)

      if errors == [],
          do: [],
        else: [{field, errors}]
    end)
  end

  defp changeset(package, :create, params) do
    changeset(package, :update, params)
    |> validate_unique(:name, on: HexWeb.Repo)
  end

  defp changeset(package, :update, params) do
    cast(package, params, ~w(name meta), [])
    |> update_change(:meta, &Map.take(&1, @meta_fields))
    |> validate_format(:name, ~r"^[a-z]\w*$")
    |> validate_exclusion(:name, @reserved_names)
    |> validate_meta(:meta)
  end

  def create(owner, params) do
    changeset = changeset(%HexWeb.Package{}, :create, params)

    if changeset.valid? do
      {:ok, package} =
        HexWeb.Repo.transaction(fn ->
          package = HexWeb.Repo.insert(changeset)

          %HexWeb.PackageOwner{package_id: package.id, owner_id: owner.id}
          |> HexWeb.Repo.insert

          package
        end)

      {:ok, package}
    else
      {:error, changeset.errors}
    end
  end

  def update(package, params) do
    changeset = changeset(package, :update, params)

    if changeset.valid? do
      {:ok, HexWeb.Repo.update(changeset)}
    else
      {:error, changeset.errors}
    end
  end

  def get(name) do
    from(p in HexWeb.Package,
         where: p.name == ^name,
         limit: 1)
    |> HexWeb.Repo.one
  end

  def delete(package) do
    HexWeb.Repo.delete(package)
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

  def all(page, count, search \\ nil, sort \\ :name) do
    from(p in HexWeb.Package,
         preload: :downloads)
    |> sort(sort)
    |> Util.paginate(page, count)
    |> search(search, true)
    |> HexWeb.Repo.all
  end

  def recent(count) do
    from(p in HexWeb.Package,
         order_by: [desc: p.inserted_at],
         limit: ^count,
         select: {p.name, p.inserted_at})
    |> HexWeb.Repo.all
  end

  def recent_full(count) do
    from(p in HexWeb.Package,
         order_by: [desc: p.inserted_at],
         limit: ^count)
    |> HexWeb.Repo.all
  end

  def count(search \\ nil) do
    from(p in HexWeb.Package, select: count(p.id))
    |> search(search, false)
    |> HexWeb.Repo.one!
  end

  def versions(package) do
    from(r in HexWeb.Release, where: r.package_id == ^package.id, select: r.version)
    |> HexWeb.Repo.all
  end

  defp delete_owners(changeset) do
    assoc(changeset.model, :owners)
    |> HexWeb.Repo.delete_all
    changeset
  end

  defp search(query, nil, _order?) do
    query
  end

  defp search(query, search, order?) do
    name_search = like_escape(search, ~r"(%|_)")
    if String.length(search) >= 3 do
      name_search = "%" <> name_search <> "%"
    end

    desc_search = String.replace(search, ~r"\s+", " & ")

    query =
      from var in query,
    where: ilike(var.name, ^name_search) or
           fragment("to_tsvector('english', (?->'description')::text) @@ to_tsquery('english', ?)",
                    var.meta, ^desc_search)
    if order? do
      query = from(var in query, order_by: ilike(var.name, ^name_search))
    end

    query
  end

  defp like_escape(string, escape) do
    String.replace(string, escape, "\\\\\\1")
  end

  defp sort(query, :name) do
    from d in query, order_by: :name
  end

  defp sort(query, :downloads) do
    from p in query,
    left_join: d in HexWeb.Stats.PackageDownload, on: p.id == d.package_id and d.view == "all",
    order_by: [asc: is_nil(d.downloads), desc: d.downloads]
  end
end

defimpl HexWeb.Render, for: HexWeb.Package do
  import HexWeb.Util

  def render(package) do
    entity =
      package
      |> Map.take([:name, :meta, :inserted_at, :updated_at])
      |> Map.update!(:inserted_at, &to_iso8601/1)
      |> Map.update!(:updated_at, &to_iso8601/1)
      |> Map.put(:url, api_url(["packages", package.name]))

    if association_loaded?(package.releases) do
      releases =
        Enum.map(package.releases, fn release ->
          release
          |> Map.take([:version, :inserted_at, :updated_at])
          |> Map.update!(:inserted_at, &to_iso8601/1)
          |> Map.update!(:updated_at, &to_iso8601/1)
          |> Map.put(:url, api_url(["packages", package.name, "releases", to_string(release.version)]))
        end)
      entity = Map.put(entity, :releases, releases)
    end

    if association_loaded?(package.downloads) do
      downloads = Enum.into(package.downloads, %{})
      entity = Map.put(entity, :downloads, downloads)
    end

    entity
  end
end
