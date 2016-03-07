defmodule HexWeb.Package do
  use HexWeb.Web, :model
  import Ecto.Query, only: [from: 2]

  @derive {Phoenix.Param, key: :name}

  @timestamps_opts [usec: true]

  schema "packages" do
    field :name, :string
    field :docs_updated_at, Ecto.DateTime
    timestamps

    has_many :releases, Release
    has_many :package_owners, PackageOwner
    has_many :owners, through: [:package_owners, :owner]
    has_many :downloads, PackageDownload
    embeds_one :meta, PackageMetadata, on_replace: :delete
  end

  @elixir_names ~w(eex elixir ex_unit iex logger mix)
  @tool_names ~w(rebar rebar3 hex)
  @otp_names ~w(
    appmon asn1 common_test compiler cosEvent cosEventDomain cosFileTransfer
    cosNotification cosProperty cosTime cosTransactions crypto debugger
    dialyzer diameter edoc eldap erl_docgen erl_interface et eunit gs hipe
    ic inets jinterface kernel Makefile megaco mnesia observer odbc orber
    os_mon ose otp_mibs parsetools percept pman public_key reltool runtime_tools
    sasl snmp ssh ssl stdlib syntax_tools test_server toolbar tools tv typer
    webtool wx xmerl)

  @reserved_names @elixir_names ++ @otp_names ++ @tool_names

  defp changeset(package, :create, params) do
    changeset(package, :update, params)
    |> unique_constraint(:name, name: "packages_name_idx")
  end

  defp changeset(package, :update, params) do
    cast(package, params, ~w(name), [])
    |> cast_embed(:meta, required: true)
    |> validate_format(:name, ~r"^[a-z]\w*$")
    |> validate_exclusion(:name, @reserved_names)
  end

  # TODO: Leave this in until we have multi
  def create(owner, params) do
    changeset = changeset(%Package{}, :create, params)

    HexWeb.Repo.transaction(fn ->
      case HexWeb.Repo.insert(changeset) do
        {:ok, package} ->
          %PackageOwner{package_id: package.id, owner_id: owner.id}
          |> HexWeb.Repo.insert!

          package
        {:error, changeset} ->
          HexWeb.Repo.rollback(changeset)
      end
    end)
  end

  def update(package, params) do
    changeset(package, :update, params)
  end

  def is_owner(package, user) do
    from(o in PackageOwner,
         where: o.package_id == ^package.id,
         where: o.owner_id == ^user.id,
         select: count(o.id) >= 1)
  end

  def docs_sitemap do
    from(p in Package,
         order_by: p.name,
         where: not is_nil(p.docs_updated_at),
         select: {p.name, p.docs_updated_at})
  end

  def packages_sitemap do
    from(p in Package,
         order_by: p.name,
         select: {p.name, p.updated_at})
  end

  def create_owner(package, user) do
    change(%PackageOwner{}, package_id: package.id, owner_id: user.id)
    |> unique_constraint(:owner_id, name: "package_owners_unique", message: "is already owner")
  end

  def owner(package, user) do
    from(p in HexWeb.PackageOwner,
         where: p.package_id == ^package.id,
         where: p.owner_id == ^user.id)
  end

  def all(page, count, search \\ nil, sort \\ :name) do
    from(p in Package,
         preload: :downloads)
    |> sort(sort)
    |> HexWeb.Utils.paginate(page, count)
    |> search(search)
  end

  def recent(count) do
    from(p in Package,
         order_by: [desc: p.inserted_at],
         limit: ^count,
         select: {p.name, p.inserted_at})
  end

  def count(search \\ nil) do
    from(p in Package, select: count(p.id))
    |> search(search)
  end

  defp search(query, nil) do
    query
  end

  defp search(query, search) do
    name_search = escape_search(search)
    name_search = if String.length(search) >= 3, do: "%" <> name_search <> "%", else: name_search

    desc_search = String.replace(search, ~r"\s+"u, " | ")

    # without fragment("?::text", var.name) the gin_trgm_ops index will not be used
      from var in query,
    where: ilike(fragment("?::text", var.name), ^name_search) or
           fragment("to_tsvector('english', regexp_replace((?->'description')::text, '/', ' ')) @@ to_tsquery('english', ?)",
                    var.meta, ^desc_search)
  end

  defp escape_search(search) do
    String.replace(search, ~r"(%|_)"u, "\\\\\\1")
  end

  defp sort(query, :name) do
    from d in query, order_by: :name
  end

  defp sort(query, :inserted_at) do
    from d in query, order_by: [desc: :inserted_at, desc: :id]
  end

  defp sort(query, :updated_at) do
    from d in query, order_by: [desc: :updated_at, desc: :id]
  end

  defp sort(query, :downloads) do
    from(p in query,
      left_join: d in PackageDownload,
        on: p.id == d.package_id and d.view == "all",
      order_by: [asc: is_nil(d.downloads),
                 desc: d.downloads,
                 desc: p.id])
  end

  defp sort(query, nil) do
    query
  end
end
