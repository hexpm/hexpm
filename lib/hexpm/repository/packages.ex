defmodule Hexpm.Repository.Packages do
  use Hexpm.Context
  import Ecto.Query
  import HexpmWeb.ViewHelpers, only: [path_for_package: 2]

  @max_word_length 50

  def count() do
    Repo.one!(Package.count())
  end

  def count(repositories, filter) do
    Repo.one!(Package.count(repositories, filter))
  end

  def count_dependants(repositories, dependency) do
    Repo.one!(Package.count_dependants(repositories, dependency))
  end

  def diff(packages, nil), do: packages

  def diff(packages, remove) do
    names = Enum.map(List.wrap(remove), & &1.name)

    packages
    |> Enum.reject(&(&1.name in names))
  end

  def get(repository, name) when is_binary(repository) do
    repository = Repositories.get(repository)
    repository && get(repository, name)
  end

  def get(repositories, name) when is_list(repositories) do
    Repo.get_by(assoc(repositories, :packages), name: name)
    |> Repo.preload([:repository, security_advisories: active_advisories_preload()])
  end

  def get(repository, name) do
    package = Repo.get_by(assoc(repository, :packages), name: name)

    package &&
      Repo.preload(%{package | repository: repository},
        security_advisories: active_advisories_preload()
      )
  end

  defp active_advisories_preload do
    from a in Hexpm.Security.Advisory,
      where: is_nil(a.withdrawn_at),
      order_by: [desc: a.published_at],
      preload: [:references, :affected_versions]
  end

  def owner_with_access?(package, user, level \\ "maintainer") do
    repository = package.repository
    role = PackageOwner.level_to_organization_role(level)

    Repo.one!(Package.package_owner(package, user, level)) or
      Repo.one!(Package.organization_owner(package, user, level)) or
      (repository.id != 1 and Organizations.access?(repository.organization, user, role))
  end

  def preload(package) do
    package = Repo.preload(package, [:downloads, :releases])
    update_in(package.releases, &Release.sort/1)
  end

  def attach_latest_releases(packages) do
    package_ids = Enum.map(packages, & &1.id)

    releases =
      from(
        r in Release,
        where: r.package_id in ^package_ids,
        group_by: r.package_id,
        select:
          {r.package_id,
           {fragment("array_agg(?)", r.version), fragment("array_agg(?)", r.inserted_at)}}
      )
      |> Repo.all()
      |> Map.new(fn {package_id, {versions, inserted_ats}} ->
        {package_id,
         Enum.zip_with(versions, inserted_ats, fn version, inserted_at ->
           %Release{version: version, inserted_at: inserted_at}
         end)}
      end)

    Enum.map(packages, fn package ->
      release =
        Release.latest_version(releases[package.id], only_stable: true, unstable_fallback: true)

      %{package | latest_release: release}
    end)
  end

  def search(repositories, page, packages_per_page, query, sort, fields) do
    if query == nil and sort in [:recent_downloads, :total_downloads] do
      packages_by_downloads(repositories, page, packages_per_page, sort, fields)
    else
      Package.all(repositories, page, packages_per_page, query, sort, fields)
      |> Repo.all()
      |> attach_repositories(repositories)
    end
  end

  def dependants(repositories, dependency, page, packages_per_page, sort, fields \\ nil) do
    if sort in [:recent_downloads, :total_downloads] do
      dependants_by_downloads(repositories, dependency, page, packages_per_page, sort, fields)
    else
      Package.dependants(repositories, dependency, page, packages_per_page, sort, fields)
      |> Repo.all()
      |> attach_repositories(repositories)
    end
  end

  def search_with_versions(repositories, page, packages_per_page, query, sort) do
    Package.all(repositories, page, packages_per_page, query, sort, nil)
    |> Ecto.Query.preload(
      releases:
        ^from(r in Release,
          select: struct(r, [:id, :version, :inserted_at, :updated_at, :has_docs, :retirement])
        )
    )
    |> Repo.all()
    |> Enum.map(fn package -> update_in(package.releases, &Release.sort/1) end)
    |> attach_repositories(repositories)
  end

  defp attach_repositories(packages, repositories) do
    repositories = Map.new(repositories, &{&1.id, &1})

    Enum.map(packages, fn package ->
      repository = Map.fetch!(repositories, package.repository_id)
      %{package | repository: repository}
    end)
  end

  defp dependants_by_downloads(repositories, dependency, page, packages_per_page, sort, fields) do
    view = download_view(sort)

    paginate_by_downloads(repositories, page, packages_per_page, fields,
      downloaded: &Package.downloaded_dependant_ids(repositories, dependency, view, &1, &2),
      count: fn -> Package.count_downloaded_dependants(repositories, dependency, view) end,
      undownloaded: &Package.undownloaded_dependant_ids(repositories, dependency, view, &1, &2)
    )
  end

  defp packages_by_downloads(repositories, page, packages_per_page, sort, fields) do
    view = download_view(sort)

    paginate_by_downloads(repositories, page, packages_per_page, fields,
      downloaded: &Package.downloaded_package_ids(repositories, view, &1, &2),
      count: fn -> Package.count_downloaded_packages(repositories, view) end,
      undownloaded: &Package.undownloaded_package_ids(repositories, view, &1, &2)
    )
  end

  defp paginate_by_downloads(repositories, page, packages_per_page, fields, queries) do
    offset = (page - 1) * packages_per_page

    downloaded_ids = Repo.all(queries[:downloaded].(packages_per_page, offset))
    remaining = packages_per_page - length(downloaded_ids)

    package_ids =
      if remaining > 0 do
        downloaded_count =
          if downloaded_ids == [] and offset > 0 do
            Repo.one!(queries[:count].())
          else
            offset + length(downloaded_ids)
          end

        zero_download_offset = max(offset - downloaded_count, 0)
        zero_download_ids = Repo.all(queries[:undownloaded].(remaining, zero_download_offset))
        downloaded_ids ++ zero_download_ids
      else
        downloaded_ids
      end

    load_packages(repositories, package_ids, fields)
  end

  defp load_packages(_repositories, [], _fields), do: []

  defp load_packages(repositories, package_ids, fields) do
    packages =
      package_ids
      |> Package.by_ids(fields)
      |> Repo.all()
      |> attach_repositories(repositories)

    packages_by_id = Map.new(packages, &{&1.id, &1})

    Enum.map(package_ids, &Map.fetch!(packages_by_id, &1))
  end

  defp download_view(:recent_downloads), do: "recent"
  defp download_view(:total_downloads), do: "all"

  def recent(repository, count) do
    Repo.all(Package.recent(repository, count))
  end

  def accessible_user_owned_packages(nil, _) do
    []
  end

  def accessible_user_owned_packages(user, for_user) do
    repositories = Enum.map(Users.all_organizations(for_user), & &1.repository)
    repository_ids = Enum.map(repositories, & &1.id)

    # Atoms sort before strings
    sorter = fn repo -> if(repo.id == 1, do: :first, else: repo.name) end

    user.owned_packages
    |> Enum.filter(&(&1.repository_id in repository_ids))
    |> Enum.sort_by(&[sorter.(&1.repository), &1.name])
  end

  @doc """
  Suggest packages by term with weighted ranking.

  - Case-insensitive
  - Treat '_' literally (escaped in LIKE)
  - Prefer name exact > prefix > substring; include description matches
  - Weight by recent downloads and text relevance
  - Only searches within the given repository

  ## Examples

      iex> repository = Hexpm.Repository.Repository.hexpm()
      iex> Packages.suggest(repository, "ecto")
      [%{id: _, name: "ecto", ...}, ...]

      iex> Packages.suggest(repository, "")
      []
  """
  def suggest(repository, term, limit \\ 8)

  def suggest(_repository, "", _limit), do: []

  def suggest(repository, term, limit) when is_binary(term) do
    term
    |> String.trim()
    |> case do
      term when byte_size(term) < 3 -> []
      term -> do_suggest(repository, term, limit)
    end
  end

  defp do_suggest(_repository, "", _limit), do: []

  defp do_suggest(repository, term, limit) do
    {_repo_part, pkg_part} = split_repo_term(term)
    pkg_part = String.downcase(pkg_part)

    escaped = escape_like(pkg_part)
    prefix = escaped <> "%"
    substr = "%" <> escaped <> "%"
    tsquery = build_tsquery(term)

    Package
    |> where([p], p.repository_id == ^repository.id)
    |> add_suggest_joins()
    |> add_suggest_search_where(substr, tsquery)
    |> add_suggest_order_by(pkg_part, prefix, substr)
    |> add_suggest_select(tsquery)
    |> limit(^limit)
    |> Repo.all()
    |> then(fn packages ->
      packages_with_releases =
        packages
        |> Enum.map(fn {id, _, _, _, _, _} -> %Package{id: id} end)
        |> attach_latest_releases()

      packages
      |> Enum.zip(packages_with_releases)
      |> Enum.map(fn {{id, name, repo_id, repo_name, description_html, recent_downloads},
                      package_with_release} ->
        href = path_for_package(repo_name, name)
        name_html = highlight_name(name, pkg_part)
        latest_release = Map.get(package_with_release, :latest_release)
        latest_version = if latest_release, do: latest_release.version, else: nil

        %{
          id: id,
          name: name,
          repository_id: repo_id,
          repository_name: repo_name,
          href: href,
          name_html: name_html,
          description_html: safe_description_html(description_html),
          recent_downloads: recent_downloads,
          latest_version: latest_version
        }
      end)
    end)
  end

  defp add_suggest_joins(query) do
    query
    |> join(:inner, [p], r in assoc(p, :repository))
    |> then(fn q ->
      from([p, r] in q,
        left_join: d in PackageDownload,
        on: d.package_id == p.id and d.view == "recent"
      )
    end)
  end

  defp add_suggest_search_where(query, substr, tsquery) do
    where(
      query,
      [p],
      like(p.name, ^substr) or
        fragment(
          "to_tsvector('english', regexp_replace((?->'description')::text, '/', ' ')) @@ to_tsquery('english', ?)",
          p.meta,
          ^tsquery
        )
    )
  end

  defp add_suggest_order_by(query, pkg_part, prefix, substr) do
    # Name-match tiers are exclusive so each package falls into exactly one band:
    #   exact       → 3.0  (name LIKE term)
    #   prefix      → 2.0  (name LIKE term%)
    #   substr      → 1.0  (name LIKE %term%)
    #   desc-only   → 0.5  (matched via full-text search, not name)
    # Downloads use an uncapped logarithm so popular packages rank higher within
    # each tier (e.g. "ecto" surfaces above other "ect*" prefix matches).
    order_by(
      query,
      [p, r, d],
      desc:
        fragment(
          """
          (CASE
            WHEN ? LIKE ?           THEN 3.0
            WHEN ? LIKE ?           THEN 2.0
            WHEN ? LIKE ?           THEN 1.0
            ELSE 0.5
          END) +
          (ln(1 + COALESCE(?, 0)) * 0.1)
          """,
          p.name,
          ^pkg_part,
          p.name,
          ^prefix,
          p.name,
          ^substr,
          d.downloads
        ),
      asc: p.name
    )
  end

  defp add_suggest_select(query, tsquery) do
    select(query, [p, r, d], {
      p.id,
      p.name,
      p.repository_id,
      r.name,
      fragment(
        """
        ts_headline('english',
          regexp_replace((?->'description')::text, '/', ' '),
          to_tsquery('english', ?),
          'StartSel=<strong>, StopSel=</strong>, MaxFragments=1, MinWords=5, MaxWords=15'
        )
        """,
        p.meta,
        ^tsquery
      ),
      coalesce(d.downloads, 0)
    })
  end

  defp split_repo_term(term) do
    case String.split(term, "/", parts: 2) do
      [repo, pkg] -> {String.downcase(repo), pkg}
      [pkg] -> {nil, pkg}
      _ -> {nil, term}
    end
  end

  defp escape_like(search) do
    String.replace(search, ~r/(%|_|\\)/u, "\\\\\\1")
  end

  defp build_tsquery(search) do
    search
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/u, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.slice(&1, 0, @max_word_length))
    |> Enum.map(&(&1 <> ":*"))
    |> Enum.join(" & ")
  end

  defp highlight_name(name, term) when is_binary(term) and term != "" do
    escaped_name = Phoenix.HTML.html_escape(name) |> Phoenix.HTML.safe_to_string()
    escaped_term = Regex.escape(Phoenix.HTML.html_escape(term) |> Phoenix.HTML.safe_to_string())
    pattern = Regex.compile!(escaped_term, "i")
    highlighted = Regex.replace(pattern, escaped_name, fn match -> "<mark>#{match}</mark>" end)
    Phoenix.HTML.raw(highlighted)
  end

  defp highlight_name(name, _term) do
    Phoenix.HTML.html_escape(name)
  end

  defp safe_description_html(nil), do: nil

  defp safe_description_html(description) when is_binary(description) do
    parts = String.split(description, ~r{</?strong>})

    safe =
      parts
      |> Enum.with_index()
      |> Enum.map_join(fn {part, idx} ->
        escaped = part |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        if rem(idx, 2) == 0, do: escaped, else: "<strong>#{escaped}</strong>"
      end)

    Phoenix.HTML.raw(safe)
  end

  @spec resolve_hexpm_package_ids(package_names :: [name]) :: %{optional(name) => pos_integer()}
        when name: String.t()
  def resolve_hexpm_package_ids(package_names) do
    from(package in Package,
      join: repository in assoc(package, :repository),
      where: repository.name == "hexpm" and package.name in ^package_names,
      select: {package.name, package.id}
    )
    |> Repo.all()
    |> Map.new()
  end
end
