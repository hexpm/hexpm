defmodule Hexpm.Repository.Package do
  use Hexpm.Schema
  import Ecto.Query, only: [from: 2]

  @derive {HexpmWeb.Stale, assocs: [:releases, :owners]}
  @derive {Phoenix.Param, key: :name}

  schema "packages" do
    field :name, :string
    field :docs_updated_at, :utc_datetime_usec
    field :latest_release, :map, virtual: true
    timestamps()

    belongs_to :repository, Repository
    has_many :releases, Release
    has_many :package_owners, PackageOwner
    has_many :owners, through: [:package_owners, :user]
    has_many :downloads, PackageDownload
    has_many :package_reports, PackageReport
    embeds_one :meta, PackageMetadata, on_replace: :delete
  end

  @elixir_names ~w(eex elixir elixirc ex_unit iex logger mix)
  @tool_names ~w(erlang typer to_erl run_erl escript erlc erl epmd dialyzer ct_run rebar rebar3 hex hexpm mix_hex)
  @otp_names ~w(
    otp asn1 common_test compiler crypto debugger dialyzer diameter
    edoc eldap erl_docgen erl_interface erts et eunit ftp hipe
    inets jinterface kernel megaco mnesia observer odbc os_mon
    parsetools public_key reltool runtime_tools sasl snmp ssh
    ssl stdlib syntax_tools toolbar tools typer wx xmerl
  )
  @inets_names ~w(tftp httpc httpd)
  @app_names ~w(toucan net http net_http)
  @windows_names ~w(
    nul con prn aux com1 com2 com3 com4 com5 com6 com7 com8 com9 lpt1 lpt2
    lpt3 lpt4 lpt5 lpt6 lpt7 lpt8 lpt9
  )
  @generic_names ~w(package organization www myapp lock locked)

  @reserved_names Enum.concat([
                    @elixir_names,
                    @otp_names,
                    @inets_names,
                    @tool_names,
                    @app_names,
                    @windows_names,
                    @generic_names
                  ])

  def build(repository, user, params) do
    package =
      build_assoc(repository, :packages)
      |> Map.put(:repository, repository)

    package
    |> cast(params, ~w(name)a)
    |> unique_constraint(:name, name: :packages_repository_id_name_text_pattern_ops_index)
    |> validate_required(:name)
    |> validate_length(:name, min: 2)
    |> validate_format(:name, ~r"^[a-z]\w*$")
    |> validate_exclusion(:name, @reserved_names)
    |> cast_embed(:meta, with: &PackageMetadata.changeset(&1, &2, package), required: true)
    |> put_first_owner(user, repository)
  end

  @spec delete({map, any} | %{__struct__: atom | %{__changeset__: any}}) :: Ecto.Changeset.t()
  def delete(package) do
    foreign_key_constraint(
      change(package),
      :name,
      name: "requirements_dependency_id_fkey",
      message: "you cannot delete this package because other packages depend on it"
    )
  end

  defp put_first_owner(changeset, user, repository) do
    if repository.id == 1 do
      put_assoc(changeset, :package_owners, [%PackageOwner{user_id: user.id}])
    else
      changeset
    end
  end

  def update(package, params) do
    cast(package, params, [])
    # A release publish should always update the package's updated_at
    |> force_change(:updated_at, DateTime.utc_now())
    |> cast_embed(:meta, with: &PackageMetadata.changeset(&1, &2, package), required: true)
    |> validate_metadata_name()
  end

  def package_owner(package, user, level \\ "maintainer") do
    levels = PackageOwner.level_or_higher(level)

    from(
      po in PackageOwner,
      left_join: ou in OrganizationUser,
      on: ou.organization_id == ^package.repository.organization_id,
      where: ou.user_id == ^user.id or ^(package.repository.id == 1),
      where: po.package_id == ^package.id,
      where: po.user_id == ^user.id,
      where: po.level in ^levels,
      select: count() >= 1
    )
  end

  def organization_owner(package, user, level \\ "maintainer") do
    role = PackageOwner.level_to_organization_role(level)
    roles = Organization.role_or_higher(role)

    from(
      po in PackageOwner,
      join: u in assoc(po, :user),
      join: ou in OrganizationUser,
      on: u.organization_id == ou.organization_id,
      where: po.package_id == ^package.id,
      where: ou.user_id == ^user.id,
      where: ou.role in ^roles,
      select: count() >= 1
    )
  end

  def all(repositories, page, count, search, sort, fields) do
    from(
      p in assoc(repositories, :packages),
      join: r in assoc(p, :repository),
      preload: :downloads
    )
    |> sort(sort)
    |> Hexpm.Utils.paginate(page, count)
    |> search(search)
    |> fields(fields)
  end

  def recent(repository, count) do
    from(
      p in assoc(repository, :packages),
      order_by: [desc: p.inserted_at],
      limit: ^count,
      select: {p.name, p.inserted_at, p.meta}
    )
  end

  def count() do
    from(Package, select: count())
  end

  def count(repositories, search) do
    from(
      p in assoc(repositories, :packages),
      join: r in assoc(p, :repository),
      select: count()
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
      like(unquote(p).name, fragment("lower(?)", ^unquote(search)))
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
    {repository, package} = name_search(search)
    description = description_search(search)

    if repository do
      from(
        [p, r] in query,
        where:
          (name_query(p, package) and name_query(r, repository)) or
            description_query(p, description)
      )
    else
      from(p in query, where: name_query(p, package) or description_query(p, description))
    end
  end

  # TODO: add repository param
  defp search_param("name", search, query) do
    case String.split(search, "/", parts: 2) do
      [repository, package] ->
        from(
          [p, r] in query,
          where: name_query(p, extra_name_search(package)),
          where: name_query(r, extra_name_search(repository))
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

  defp search_param("updated_after", search, query) do
    case DateTime.from_iso8601(search) do
      {:ok, updated_after, 0} -> from(p in query, where: p.updated_at >= ^updated_after)
      # invalid date, ignore the filter
      _ -> query
    end
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
    case String.split(search, ":", parts: 2) do
      [repository, package] ->
        from(
          p in query,
          join: pd in Hexpm.Repository.PackageDependant,
          on: p.id == pd.dependant_id,
          where: pd.name == ^package,
          where: pd.repo == ^repository
        )

      _ ->
        from(
          p in query,
          join: pd in Hexpm.Repository.PackageDependant,
          on: p.id == pd.dependant_id,
          where: pd.name == ^search
        )
    end
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
      [repository, package] ->
        {do_name_search(repository), do_name_search(package)}

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
      on: p.id == d.package_id and d.view == "all",
      order_by: [fragment("? DESC NULLS LAST", d.downloads)]
    )
  end

  defp sort(query, :recent_downloads) do
    from(
      p in query,
      left_join: d in PackageDownload,
      on: p.id == d.package_id and d.view == "recent",
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

  def downloads_for_last_n_days(package_id, num_of_days) do
    date_start = Date.add(Date.utc_today(), -1 * num_of_days)
    from(d in downloads_by_period(package_id, :day), where: d.day >= ^date_start)
  end

  def downloads_by_period(package_id, filter) do
    from(d in Download, where: d.package_id == ^package_id)
    |> Download.query_filter(filter)
  end
end
