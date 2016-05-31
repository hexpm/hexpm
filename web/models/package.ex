defmodule HexWeb.Package do
  use HexWeb.Web, :model
  import Ecto.Query, only: [from: 2]
  alias HexWeb.Utils
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
  @search_keys ~w(name: description: extra:)

  defp changeset(package, :create, params) do
    changeset(package, :update, params)
    |> unique_constraint(:name, name: "packages_name_idx")
  end

  defp changeset(package, :update, params) do
    cast(package, params, ~w(name))
    |> cast_embed(:meta, required: true)
    |> validate_required(:name)
    |> validate_format(:name, ~r"^[a-z]\w*$")
    |> validate_exclusion(:name, @reserved_names)
  end

  def build(owner, params) do
    changeset(%Package{}, :create, params)
    |> put_assoc(:package_owners, [%PackageOwner{owner_id: owner.id}])
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

  def build_owner(package, user) do
    change(%PackageOwner{}, package_id: package.id, owner_id: user.id)
    |> unique_constraint(:owner_id, name: "package_owners_unique", message: "is already owner")
  end

  def owner(package, user) do
    from(p in HexWeb.PackageOwner,
         where: p.package_id == ^package.id,
         where: p.owner_id == ^user.id)
  end

  def all(page, count, search \\ nil, sort \\ :name) do
    from(p in Package, preload: :downloads)
    |> sort(sort)
    |> HexWeb.Utils.paginate(page, count)
    |> search(search)
  end

  def recent(count) do
    from(p in Package,
         order_by: [desc: p.inserted_at],
         limit: ^count,
         select: {p.name, p.inserted_at, p.meta})
  end

  def count(search \\ nil) do
    from(p in Package, select: count(p.id))
    |> search(search)
  end

  defp search(query, nil) do
    query
  end

  defp search(query, {:letter, letter}) do
    name_search = letter <> "%"

    from var in query,
    where: ilike(fragment("?::text", var.name), ^name_search)
  end

  defp search(query, search) when is_binary(search) do
    if Enum.any?(@search_keys, & String.starts_with?(search, &1)) do
      Enum.reduce(parse_search(search), query, fn({k, v}, q) ->
        search(k, q, v)
      end)
    else
      search = Utils.safe_search(search)
      filter =
        if String.length(search) >= 3 do
          :contains
        else
          :equals
        end
      name_search =
        search
        |> escape_search
        |> like_search(filter)

      desc_search = String.replace(search, ~r"\s+"u, " | ")

      from p in query,
      where: ilike(fragment("?::text", p.name), ^name_search) or
             fragment("to_tsvector('english', regexp_replace((?->'description')::text, '/', ' ')) @@ to_tsquery('english', ?)", p.meta, ^desc_search)
    end
  end

  defp search(:name, query, search) do
    from(p in query,
      where: ilike(fragment("?::text", p.name), ^search))
  end

  defp search(:description, query, search) do
    desc_search = String.replace(search, ~r"\s+"u, " | ")
    from(p in query,
      where: fragment("to_tsvector('english', regexp_replace((?->'description')::text, '/', ' ')) @@ to_tsquery('english', ?)", p.meta, ^desc_search))
  end

  defp search(:extra, query, search) do
    [v | p] =
      search
      |> String.split(",")
      |> Enum.reverse
    [h | t] = p

    value = extra_value(v)
    extra = extra(t, Map.put(%{}, h, value))

    from(p in query,
      where: fragment("?->'extra' @> ?", p.meta, ^extra))
  end

  defp extra_value(<<"[", value :: binary>>) do
    value
    |> String.rstrip(?])
    |> String.split(",")
    |> Enum.map(fn(v) ->
      case Integer.parse(v) do
        {int, ""} -> int
        _ -> Utils.safe_search(v)
      end
    end)
  end
  defp extra_value(v),
    do: Utils.safe_search(v)

  defp extra([], m), do: m
  defp extra([h | t], m) do
    extra(t, Map.put(%{}, h, m))
  end

  defp like_search(search, :contains),
    do: "%" <> search <> "%"
  defp like_search(search, :equals),
    do: search

  defp escape_search(search) do
    String.replace(search, ~r"(%|_)"u, "\\\\\\1")
  end

  defp sort(query, :name) do
    from p in query, order_by: p.name
  end

  defp sort(query, :inserted_at) do
    from p in query, order_by: [desc: p.inserted_at]
  end

  defp sort(query, :updated_at) do
    from p in query, order_by: [desc: p.updated_at]
  end

  defp sort(query, :downloads) do
    from(p in query,
      left_join: d in PackageDownload,
        on: p.id == d.package_id,
      order_by: [fragment("? DESC NULLS LAST", d.downloads)],
      where: d.view == "all")
  end

  defp sort(query, nil) do
    query
  end

  defp parse_search(_, _ \\ [])
  defp parse_search("", keys), do: Enum.reverse(keys)
  defp parse_search(search, keys) do
    {filter, tail} = parse_key(search, keys)
    tail
    |> String.strip
    |> parse_search(filter)
  end

  defp parse_key(string, search) do
    [k, v] = String.split(string, ":", parts: 2)
    {v, tail} = parse_value(v)
    {add_param({String.to_existing_atom(k), v}, search), tail}
  end

  defp parse_value(input) do
    {rest, delim} =
      case input do
        "\"" <> rest -> {rest, "\""}
        _ -> {input, " "}
      end

    case String.split(rest, delim, parts: 2) do
      [value] -> {value, ""}
      [value, tail] -> {value, tail}
    end
  end

  defp add_param(param, []),
    do: [param]
  defp add_param(param, [scope | tail]),
    do: [param | [scope | tail]]
end
