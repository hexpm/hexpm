defmodule Hexpm.Repository.Packages do
  use Hexpm.Context
  import Ecto.Query

  def count() do
    Repo.one!(Package.count())
  end

  def count(repositories, filter) do
    Repo.one!(Package.count(repositories, filter))
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
    |> Repo.preload(:repository)
  end

  def get(repository, name) do
    package = Repo.get_by(assoc(repository, :packages), name: name)
    package && %{package | repository: repository}
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
    Package.all(repositories, page, packages_per_page, query, sort, fields)
    |> Repo.all()
    |> attach_repositories(repositories)
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
      [
        %{
          id: _,
          name: "ecto",
          repository_id: _,
          repository_name: "hexpm",
          href: "/packages/ecto",
          name_html: "ecto",
          description_html: _,
          recent_downloads: _,
          latest_version: _
        },
        ...
      ]

      iex> Packages.suggest(repository, "")
      []
  """
  def suggest(repository, term, limit \\ 8)

  def suggest(_repository, "", _limit), do: []

  def suggest(repository, term, limit) when is_binary(term) do
    term = String.trim(term)
    do_suggest(repository, term, limit)
  end

  defp do_suggest(_repository, "", _limit), do: []

  defp do_suggest(repository, term, limit) do
    {_repo_part, pkg_part} = split_repo_term(term)
    pkg_part = String.downcase(pkg_part)

    escaped = escape_like(pkg_part)
    prefix = escaped <> "%"
    substr = "%" <> escaped <> "%"
    tsquery = build_tsquery(term)

    package_results =
      Package
      |> where([p], p.repository_id == ^repository.id)
      |> add_suggest_joins()
      |> add_suggest_search_where(substr, tsquery)
      |> add_suggest_order_by(pkg_part, prefix, substr, tsquery)
      |> add_suggest_select(tsquery)
      |> limit(^limit)
      |> Repo.all()

    package_ids =
      Enum.map(package_results, fn {id, _name, _repo_id, _repo_name, _desc, _recent} -> id end)

    versions_map =
      from(r in Hexpm.Repository.Release,
        where: r.package_id in ^package_ids,
        group_by: r.package_id,
        select: {r.package_id, fragment("array_agg(?)", r.version)}
      )
      |> Repo.all()
      |> Map.new()

    package_results
    |> Enum.map(fn {id, name, repo_id, repo_name, description_html, recent_downloads} ->
      href = package_href(repo_name, name)
      name_html = highlight_name(name, pkg_part)

      latest_version = get_latest_version_string(versions_map, id)

      %{
        id: id,
        name: name,
        repository_id: repo_id,
        repository_name: repo_name,
        href: href,
        name_html: name_html,
        description_html: empty_to_nil(description_html),
        recent_downloads: recent_downloads,
        latest_version: latest_version
      }
    end)
  end

  defp get_latest_version_string(versions_map, id) do
    case Map.get(versions_map, id) do
      nil ->
        nil

      versions ->
        versions
        |> Enum.map(&%Hexpm.Repository.Release{version: &1})
        |> Hexpm.Repository.Release.latest_version(
          only_stable: true,
          unstable_fallback: true
        )
        |> case do
          nil -> nil
          %Hexpm.Repository.Release{version: v} -> to_string(v)
        end
    end
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
    # The GIN index packages_description_text will be used automatically by PostgreSQL
    # when the expression matches exactly: to_tsvector('english', regexp_replace((meta->'description')::text, '/', ' '))
    where(
      query,
      [p],
      fragment("lower(?) LIKE ?", p.name, ^substr) or
        fragment(
          "to_tsvector('english', regexp_replace((?->'description')::text, '/', ' ')) @@ to_tsquery('english', ?)",
          p.meta,
          ^tsquery
        )
    )
  end

  defp add_suggest_order_by(query, pkg_part, prefix, substr, tsquery) do
    # Note: The tsvector is recomputed here for ranking, but PostgreSQL's query planner
    # will optimize this. The WHERE clause uses the GIN index, and ORDER BY only runs
    # on the filtered result set. For further optimization, consider using a CTE
    # to compute the tsvector once (see add_suggest_order_by_with_cte/5 for example).
    order_by(
      query,
      [p, r, d],
      desc:
        fragment(
          """
          (CASE WHEN lower(?) = ? THEN 3.0 ELSE 0 END) +
          (CASE WHEN lower(?) LIKE ? THEN 2.0 ELSE 0 END) +
          (CASE WHEN lower(?) LIKE ? THEN 1.0 ELSE 0 END) +
          (LEAST(5.0, ln(1 + COALESCE(?, 0))) * 0.2) +
          (COALESCE(
            ts_rank_cd(
              to_tsvector('english', regexp_replace((?->'description')::text, '/', ' ')),
              to_tsquery('english', ?)
            ),
            0.0
          ) * 0.4)
          """,
          p.name,
          ^pkg_part,
          p.name,
          ^prefix,
          p.name,
          ^substr,
          d.downloads,
          p.meta,
          ^tsquery
        ),
      asc: p.name
    )
  end

  # Use PostgreSQL's ts_headline to extract and highlight matching text from the description.
  # The fragment below does the following:
  # - Extracts the description from the JSONB meta field
  # - Replaces '/' with spaces (to improve word boundary detection)
  # - Searches for matches using the tsquery (built from the search term)
  # - Returns a highlighted excerpt with matching words wrapped in <strong> tags
  # - Limits to 1 fragment, 5-15 words for a concise preview
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
    search
    |> String.replace(~r/(%|_|\\)/u, "\\\\\\1")
  end

  defp build_tsquery(search) do
    search
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/u, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.slice(&1, 0, 50))
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&(&1 <> ":*"))
    |> Enum.join(" & ")
  end

  defp package_href(repo_name, name) do
    if repo_name == "hexpm" do
      "/packages/#{name}"
    else
      "/packages/#{repo_name}/#{name}"
    end
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(str) when is_binary(str), do: if(String.trim(str) == "", do: nil, else: str)
  defp empty_to_nil(other), do: other

  defp highlight_name(name, term) when is_binary(term) and term != "" do
    dn = String.downcase(name)
    dt = String.downcase(term)

    case :binary.match(dn, dt) do
      {pos, len} ->
        {pre, rest} = String.split_at(name, pos)
        {mid, post} = String.split_at(rest, len)
        pre_e = pre |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        mid_e = mid |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        post_e = post |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        pre_e <> "<strong>" <> mid_e <> "</strong>" <> post_e

      :nomatch ->
        name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    end
  end

  defp highlight_name(name, _term) do
    name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end
end
