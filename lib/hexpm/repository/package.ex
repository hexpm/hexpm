defmodule Hexpm.Repository.Package do
  use Hexpm.Web, :schema
  @derive {Phoenix.Param, key: :name}

  schema "packages" do
    field :name, :string
    field :docs_updated_at, :naive_datetime
    field :latest_version, Hexpm.Version, virtual: true
    timestamps()

    belongs_to :repository, Repository
    has_many :releases, Release
    has_many :package_owners, PackageOwner
    has_many :owners, through: [:package_owners, :owner]
    has_many :downloads, PackageDownload
    embeds_one :meta, PackageMetadata, on_replace: :delete
  end

  @elixir_names ~w(eex elixir ex_unit iex logger mix)
  @tool_names ~w(rebar rebar3 hex hexpm)
  @otp_names ~w(
    appmon asn1 common_test compiler cosEvent cosEventDomain cosFileTransfer
    cosNotification cosProperty cosTime cosTransactions crypto debugger
    dialyzer diameter edoc eldap erl_docgen erl_interface et eunit gs hipe
    ic inets jinterface kernel Makefile megaco mnesia observer odbc orber
    os_mon ose otp_mibs parsetools percept pman public_key reltool runtime_tools
    sasl snmp ssh ssl stdlib syntax_tools test_server toolbar tools tv typer
    webtool wx xmerl
  )
  @app_names ~w(firenest toucan net)
  @windows_names ~w(
    nul con prn aux com1 com2 com3 com4 com5 com6 com7 com8 com9lpt1 lpt2
    lpt3 lpt4 lpt5 lpt6 lpt7 lpt8 lpt9
  )

  @reserved_names Enum.concat [
    @elixir_names,
    @otp_names,
    @tool_names,
    @app_names,
    @windows_names
  ]

  defp changeset(package, :create, params) do
    changeset(package, :update, params)
    |> unique_constraint(:name, name: "packages_repository_id_name_index")
  end

  defp changeset(package, :update, params) do
    cast(package, params, ~w(name))
    |> cast_embed(:meta, required: true)
    |> validate_required(:name)
    |> validate_length(:name, min: 2)
    |> validate_format(:name, ~r"^[a-z]\w*$")
    |> validate_exclusion(:name, @reserved_names)
  end

  def build(repository, owner, params) do
    changeset(build_assoc(repository, :packages), :create, params)
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

  def build_owner(package, user) do
    change(%PackageOwner{}, package_id: package.id, owner_id: user.id)
    |> unique_constraint(:owner_id, name: "package_owners_unique", message: "is already owner")
  end

  def owner(package, user) do
    from(p in Hexpm.Repository.PackageOwner,
         where: p.package_id == ^package.id,
         where: p.owner_id == ^user.id)
  end

  def all(page, count, search \\ nil, sort \\ :name) do
    from(p in Package, preload: :downloads)
    |> sort(sort)
    |> Hexpm.Utils.paginate(page, count)
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
    case parse_search(search) do
      {:ok, params} ->
        Enum.reduce(params, query, fn {k, v}, q -> search_param(k, v, q) end)
      :error ->
        name_search = name_search(search)
        desc_search = description_search(search)

        from(p in query,
          where: ilike(fragment("?::text", p.name), ^name_search) or
                 fragment("to_tsvector('english', regexp_replace((?->'description')::text, '/', ' ')) @@ to_tsquery('english', ?)", p.meta, ^desc_search))
    end
  end

  defp search_param("name", search, query) do
    search = extra_name_search(search)
    from(p in query,
      where: ilike(fragment("?::text", p.name), ^search))
  end

  defp search_param("description", search, query) do
    search = description_search(search)
    from(p in query,
      where: fragment("to_tsvector('english', regexp_replace((?->'description')::text, '/', ' ')) @@ to_tsquery('english', ?)", p.meta, ^search))
  end

  defp search_param("extra", search, query) do
    [value | keys] =
      search
      |> String.split(",")
      |> Enum.reverse

    extra = extra_map(keys, extra_value(value))

    from(p in query,
      where: fragment("?->'extra' @> ?", p.meta, ^extra))
  end

  defp search_param("depends", search, query) do
    from(p in query,
         join: pd in Hexpm.Repository.PackageDependant,
         on: p.id == pd.dependant_id,
         where: pd.name == ^search)
  end

  defp search_param(_, _, query) do
    query
  end

  defp extra_value(<<"[", value :: binary>>) do
    value
    |> String.trim_trailing("]")
    |> String.split(",")
    |> Enum.map(&try_integer/1)
  end
  defp extra_value(value), do: try_integer(value)

  defp try_integer(string) do
    case Integer.parse(string) do
      {int, ""} -> int
      _ -> string
    end
  end

  defp extra_map([], m), do: m
  defp extra_map([h | t], m) do
    extra_map(t, %{h => m})
  end

  defp like_search(search, :contains),
    do: "%" <> search <> "%"
  defp like_search(search, :equals),
    do: search

  defp escape_search(search) do
    String.replace(search, ~r"(%|_|\\)"u, "\\\\\\1")
  end

  defp name_search(search) do
    filter = search_filter(search)

    search
    |> escape_search
    |> like_search(filter)
  end

  defp search_filter(search) do
    if String.length(search) >= 3,
      do: :contains,
    else: :equals
  end

  defp description_search(search) do
    search
    |> String.replace(~r/\//u, " ")
    |> String.replace(~r/[^\w\s]/u, "")
    |> String.trim
    |> String.replace(~r"\s+"u, " | ")
  end

  def extra_name_search(search) do
    search
    |> escape_search
    |> String.replace(~r/(^\*)|(\*$)/u, "%")
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
      where: d.view == "all" or is_nil(d.view))
  end

  defp sort(query, nil) do
    query
  end

  defp parse_search(search) do
    search
    |> String.trim_leading
    |> parse_params([])
  end

  defp parse_params("", params), do: {:ok, Enum.reverse(params)}
  defp parse_params(tail, params) do
    with {:ok, key, tail} <- parse_key(tail),
         {:ok, value, tail} <- parse_value(tail) do
      parse_params(tail, [{key, value} | params])
    else
      _ -> :error
    end
  end

  defp parse_key(string) do
    with [k, tail] when k != "" <- String.split(string, ":", parts: 2),
         do: {:ok, k, String.trim_leading(tail)}
  end

  defp parse_value(string) do
    case string do
      "\"" <> rest ->
        with [v, tail] <- String.split(rest, "\"", parts: 2),
             do: {:ok, v, String.trim_leading(tail)}
      _ ->
        case String.split(string, " ", parts: 2) do
          [value] -> {:ok, value, ""}
          [value, tail] -> {:ok, value, String.trim_leading(tail)}
        end
    end
  end
end
