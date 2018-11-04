defmodule Hexpm.Repository.Package do
  use HexpmWeb, :schema
  import Ecto.Query, only: [from: 2, where: 3]

  @derive {HexpmWeb.Stale, assocs: [:releases, :owners, :downloads]}
  @derive {Phoenix.Param, key: :name}

  schema "packages" do
    field :name, :string
    field :docs_updated_at, :utc_datetime_usec
    field :latest_version, Hexpm.Version, virtual: true
    timestamps()

    belongs_to :organization, Organization
    has_many :releases, Release
    has_many :package_owners, PackageOwner
    has_many :owners, through: [:package_owners, :user]
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
  @inets_names ~w(ftp tftp httpc httpd http_uri)
  @app_names ~w(firenest toucan net http net_http gen_http xhttp)
  @windows_names ~w(
    nul con prn aux com1 com2 com3 com4 com5 com6 com7 com8 com9 lpt1 lpt2
    lpt3 lpt4 lpt5 lpt6 lpt7 lpt8 lpt9
  )

  # Backwards compatible for tests, fixed in Hex at 2017-07-29
  if Mix.env() == :hex do
    @generic_names []
  else
    @generic_names ~w(package organization www)
  end

  @reserved_names Enum.concat([
                    @elixir_names,
                    @otp_names,
                    @inets_names,
                    @tool_names,
                    @app_names,
                    @windows_names,
                    @generic_names
                  ])

  def build(organization, user, params) do
    package =
      build_assoc(organization, :packages)
      |> Map.put(:organization, organization)

    package
    |> cast(params, ~w(name)a)
    |> unique_constraint(:name, name: "packages_organization_id_name_index")
    |> validate_required(:name)
    |> validate_length(:name, min: 2)
    |> validate_format(:name, ~r"^[a-z]\w*$")
    |> validate_exclusion(:name, @reserved_names)
    |> cast_embed(:meta, with: &PackageMetadata.changeset(&1, &2, package), required: true)
    |> put_first_owner(user, organization)
  end

  def delete(package) do
    foreign_key_constraint(
      change(package),
      :name,
      name: "requirements_dependency_id_fkey",
      message: "you cannot delete this package because other packages depend on it"
    )
  end

  defp put_first_owner(changeset, %User{id: id}, _organization) do
    put_assoc(changeset, :package_owners, [%PackageOwner{user_id: id}])
  end

  defp put_first_owner(changeset, nil, %Organization{id: id}) when id != 1 do
    changeset
  end

  def update(package, params) do
    cast(package, params, [])
    |> cast_embed(:meta, with: &PackageMetadata.changeset(&1, &2, package), required: true)
    |> validate_metadata_name()
  end

  def owner(package, user) do
    from(
      o in PackageOwner,
      where: o.package_id == ^package.id,
      where: o.user_id == ^user.id,
      select: count(o.id) >= 1
    )
  end

  def owner(package, user, level) do
    owner(package, user)
    |> where([o], o.level == ^level)
  end

  def owner_with_access(package, user) do
    from(
      po in PackageOwner,
      left_join: ru in OrganizationUser,
      on: ru.organization_id == ^package.organization_id,
      where: ru.user_id == ^user.id or ^package.organization.public,
      where: po.package_id == ^package.id,
      where: po.user_id == ^user.id,
      select: count(po.id) >= 1
    )
  end

  def owner_with_access(package, user, level) do
    owner_with_access(package, user)
    |> where([o], o.level == ^level)
  end

  def all(organizations, page, count, search, sort, fields) do
    from(
      p in assoc(organizations, :packages),
      join: r in assoc(p, :organization),
      preload: :downloads
    )
    |> sort(sort)
    |> Hexpm.Utils.paginate(page, count)
    |> search(search)
    |> fields(fields)
  end

  def recent(organization, count) do
    from(
      p in assoc(organization, :packages),
      order_by: [desc: p.inserted_at],
      limit: ^count,
      select: {p.name, p.inserted_at, p.meta}
    )
  end

  def count() do
    from(p in Package, select: count(p.id))
  end

  def count(organizations, search) do
    from(
      p in assoc(organizations, :packages),
      join: r in assoc(p, :organization),
      select: count(p.id)
    )
    |> search(search)
  end

  defp validate_metadata_name(changeset) do
    name = get_field(changeset, :name)
    meta_name = changeset.params["meta"]["name"]

    if !meta_name || name == meta_name do
      changeset
    else
      add_error(changeset, :name, "metadata does not match package name")
    end
  end

  defp fields(query, nil) do
    query
  end

  defp fields(query, fields) do
    from(p in query, select: ^fields)
  end

  defmacrop description_query(p, search) do
    quote do
      fragment(
        "to_tsvector('english', regexp_replace((?->'description')::text, '/', ' ')) @@ to_tsquery('english', ?)",
        unquote(p).meta,
        ^unquote(search)
      )
    end
  end

  defmacrop name_query(p, search) do
    quote do
      ilike(fragment("?::text", unquote(p).name), ^unquote(search))
    end
  end

  defp search(query, nil) do
    query
  end

  defp search(query, {:letter, letter}) do
    search = letter <> "%"
    from(p in query, where: name_query(p, search))
  end

  defp search(query, search) when is_binary(search) do
    case parse_search(search) do
      {:ok, params} ->
        Enum.reduce(params, query, fn {k, v}, q -> search_param(k, v, q) end)

      :error ->
        basic_search(query, search)
    end
  end

  defp basic_search(query, search) do
    {organization, package} = name_search(search)
    description = description_search(search)

    if organization do
      from(
        [p, r] in query,
        where:
          (name_query(p, package) and name_query(r, organization)) or
            description_query(p, description)
      )
    else
      from(p in query, where: name_query(p, package) or description_query(p, description))
    end
  end

  # TODO: add organization param
  defp search_param("name", search, query) do
    case String.split(search, "/", parts: 2) do
      [organization, package] ->
        from(
          [p, r] in query,
          where: name_query(p, extra_name_search(package)),
          where: name_query(r, extra_name_search(organization))
        )

      _ ->
        search = extra_name_search(search)
        from(p in query, where: name_query(p, search))
    end
  end

  defp search_param("description", search, query) do
    search = description_search(search)
    from(p in query, where: description_query(p, search))
  end

  defp search_param("extra", search, query) do
    [value | keys] =
      search
      |> String.split(",")
      |> Enum.reverse()

    extra = extra_map(keys, extra_value(value))

    from(p in query, where: fragment("?->'extra' @> ?", p.meta, ^extra))
  end

  defp search_param("depends", search, query) do
    from(
      p in query,
      join: pd in Hexpm.Repository.PackageDependant,
      on: p.id == pd.dependant_id,
      where: pd.name == ^search
    )
  end

  defp search_param(_, _, query) do
    query
  end

  defp extra_value(<<"[", value::binary>>) do
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

  defp like_search(search, :contains), do: "%" <> search <> "%"
  defp like_search(search, :equals), do: search

  defp escape_search(search) do
    String.replace(search, ~r"(%|_|\\)"u, "\\\\\\1")
  end

  defp name_search(search) do
    case String.split(search, "/", parts: 2) do
      [organization, package] ->
        {do_name_search(organization), do_name_search(package)}

      _ ->
        {nil, do_name_search(search)}
    end
  end

  defp do_name_search(search) do
    search
    |> escape_search()
    |> like_search(search_filter(search))
  end

  defp search_filter(search) do
    if String.length(search) >= 3 do
      :contains
    else
      :equals
    end
  end

  defp description_search(search) do
    search
    |> String.replace(~r/\//u, " ")
    |> String.replace(~r/[^\w\s]/u, "")
    |> String.trim()
    |> String.replace(~r"\s+"u, " | ")
  end

  def extra_name_search(search) do
    search
    |> escape_search()
    |> String.replace(~r/(^\*)|(\*$)/u, "%")
  end

  defp sort(query, :name) do
    from(p in query, order_by: p.name)
  end

  defp sort(query, :inserted_at) do
    from(p in query, order_by: [desc: p.inserted_at])
  end

  defp sort(query, :updated_at) do
    from(p in query, order_by: [desc: p.updated_at])
  end

  defp sort(query, :total_downloads) do
    from(
      p in query,
      left_join: d in PackageDownload,
      on: p.id == d.package_id and (d.view == "all" or is_nil(d.view)),
      order_by: [fragment("? DESC NULLS LAST", d.downloads)]
    )
  end

  defp sort(query, :recent_downloads) do
    from(
      p in query,
      left_join: d in PackageDownload,
      on: p.id == d.package_id and (d.view == "recent" or is_nil(d.view)),
      order_by: [fragment("? DESC NULLS LAST", d.downloads)]
    )
  end

  defp sort(query, nil) do
    query
  end

  defp parse_search(search) do
    search
    |> String.trim_leading()
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
    with [k, tail] when k != "" <- String.split(string, ":", parts: 2) do
      {:ok, k, String.trim_leading(tail)}
    end
  end

  defp parse_value(string) do
    case string do
      "\"" <> rest ->
        with [v, tail] <- String.split(rest, "\"", parts: 2) do
          {:ok, v, String.trim_leading(tail)}
        end

      _ ->
        case String.split(string, " ", parts: 2) do
          [value] -> {:ok, value, ""}
          [value, tail] -> {:ok, value, String.trim_leading(tail)}
        end
    end
  end
end
