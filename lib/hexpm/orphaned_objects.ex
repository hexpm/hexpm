defmodule Hexpm.OrphanedObjects do
  @moduledoc """
  Finds and deletes objects in the buckets that no repository, package, release
  or policy accounts for.

  Most of these objects go as a side effect of the row going: a reverted
  release deletes its tarball, and the `ObjectRemoved` event that causes
  deletes the unpacked docs pages and the preview files. An event that never
  arrives leaves its objects in the bucket for good, and that is what this
  sweeps up.

  ## What is deleted

  A key is deleted only when it parses into something the database can be
  asked about and the answer is no. Keys that parse into nothing known are
  counted as unrecognised and reported, never deleted, so an object shape
  added since this module was written survives the sweep.

      Hexpm.OrphanedObjects.scan()
      Hexpm.OrphanedObjects.delete(buckets: [:diff_bucket])

  ## Why it does not delete live objects

  A publish writes its database row before it writes any object, so an object
  in a listing whose row is missing from a database read taken after that
  listing has no row at all. `delete/1` reads the packages twice for this:
  once to pick candidates out of the listing, and again, after the listing has
  finished, to decide what to delete. Objects written in the last
  `:older_than` days are left alone regardless, which covers a republish of a
  version between the second read and the delete.
  """

  import Ecto.Query, only: [from: 2]

  alias Hexpm.Repo
  alias Hexpm.Repository.{Package, Policy, Repository}

  require Logger

  @buckets [:repo_bucket, :preview_bucket, :docs_bucket, :docs_private_bucket, :diff_bucket]
  @special_packages Map.keys(Application.compile_env!(:hexpm, :hexdocs_special_packages))
  @default_older_than 7
  @default_limit 100_000
  @samples 20
  @delete_batch 1000

  @type report :: %{
          scanned: non_neg_integer(),
          orphaned: non_neg_integer(),
          unrecognised: non_neg_integer(),
          too_recent: non_neg_integer(),
          truncated: boolean(),
          orphaned_sample: [String.t()],
          unrecognised_sample: [String.t()]
        }

  @doc """
  Reports what each bucket holds that nothing accounts for, without deleting.

  ## Options

  - `:buckets` - which buckets to look at (default: all five)
  - `:prefix` - only objects under this key prefix (default: everything)
  - `:older_than` - ignore objects written in the last so many days
    (default: #{@default_older_than})
  - `:limit` - stop collecting candidates per bucket after this many, the
    report then says `truncated: true` (default: #{@default_limit})

  ## Examples

      iex> Hexpm.OrphanedObjects.scan(buckets: [:diff_bucket])
      %{diff_bucket: %{scanned: 812, orphaned: 40, unrecognised: 0, ...}}
  """
  @spec scan(keyword()) :: %{atom() => report()}
  def scan(opts \\ []) do
    index = index()

    Map.new(buckets(opts), fn bucket ->
      {bucket, report(collect(bucket, index, opts))}
    end)
  end

  @doc """
  Deletes what `scan/1` reports as orphaned, and returns the same report with
  the number actually deleted.

  Takes the same options as `scan/1`. Candidates are checked against a second
  read of the packages before anything is deleted, so a release published
  while the bucket was being listed keeps its objects.

  ## Examples

      iex> Hexpm.OrphanedObjects.delete(buckets: [:diff_bucket], older_than: 30)
      %{diff_bucket: %{deleted: 40, orphaned: 40, ...}}
  """
  @spec delete(keyword()) :: %{atom() => report()}
  def delete(opts \\ []) do
    Repo.write_mode!()
    index = index()

    Map.new(buckets(opts), fn bucket ->
      collected = collect(bucket, index, opts)
      deleted = delete_collected(bucket, collected.orphaned)
      {bucket, Map.put(report(collected), :deleted, deleted)}
    end)
  end

  defp buckets(opts) do
    buckets = Keyword.get(opts, :buckets, @buckets)

    case buckets -- @buckets do
      [] -> buckets
      unknown -> raise ArgumentError, "not a bucket this sweeps: #{inspect(unknown)}"
    end
  end

  # The second read of the packages. Everything in `keys` was listed before it
  # ran, and an object is written after the row it belongs to, so a key still
  # orphaned here has no row.
  defp delete_collected(_bucket, []), do: 0

  defp delete_collected(bucket, keys) do
    index = index()

    keys =
      Enum.filter(keys, fn {_key, classification} -> orphaned?(classification, index) end)
      |> Enum.map(&elem(&1, 0))

    keys
    |> Stream.chunk_every(@delete_batch)
    |> Enum.each(fn batch ->
      Hexpm.Store.delete_many(bucket, batch)

      Logger.info(%{
        message: "Deleted orphaned objects",
        event: "orphaned_objects.delete",
        bucket: bucket,
        count: length(batch)
      })
    end)

    length(keys)
  end

  defp collect(bucket, index, opts) do
    prefix = Keyword.get(opts, :prefix, "")
    limit = Keyword.get(opts, :limit, @default_limit)
    cutoff = DateTime.add(DateTime.utc_now(), -older_than(opts), :day)

    empty = %{
      scanned: 0,
      orphaned: [],
      orphaned_count: 0,
      unrecognised: [],
      unrecognised_count: 0,
      too_recent: 0,
      truncated: false
    }

    Hexpm.Store.list_objects(bucket, prefix)
    |> Enum.reduce(empty, fn object, acc ->
      acc = %{acc | scanned: acc.scanned + 1}

      case classify(bucket, object.key) do
        :keep ->
          acc

        :unrecognised ->
          %{
            acc
            | unrecognised_count: acc.unrecognised_count + 1,
              unrecognised: sample(acc.unrecognised, object.key)
          }

        classification ->
          cond do
            not orphaned?(classification, index) ->
              acc

            DateTime.after?(object.last_modified, cutoff) ->
              %{acc | too_recent: acc.too_recent + 1}

            acc.orphaned_count >= limit ->
              %{acc | truncated: true}

            true ->
              %{
                acc
                | orphaned_count: acc.orphaned_count + 1,
                  orphaned: [{object.key, classification} | acc.orphaned]
              }
          end
      end
    end)
  end

  defp older_than(opts) do
    case Keyword.get(opts, :older_than, @default_older_than) do
      days when is_integer(days) and days >= 0 -> days
      other -> raise ArgumentError, ":older_than takes a number of days, got #{inspect(other)}"
    end
  end

  defp sample(taken, _key) when length(taken) >= @samples, do: taken
  defp sample(taken, key), do: [key | taken]

  defp report(collected) do
    %{
      scanned: collected.scanned,
      orphaned: collected.orphaned_count,
      unrecognised: collected.unrecognised_count,
      too_recent: collected.too_recent,
      truncated: collected.truncated,
      orphaned_sample:
        collected.orphaned |> Enum.reverse() |> Enum.take(@samples) |> Enum.map(&elem(&1, 0)),
      unrecognised_sample: Enum.reverse(collected.unrecognised)
    }
  end

  ## What the database says exists

  defp index() do
    packages =
      from(p in Package,
        join: repository in assoc(p, :repository),
        left_join: release in assoc(p, :releases),
        select: {repository.name, p.name, release.version}
      )
      |> Repo.all()
      |> Enum.reduce(%{}, fn {repository, package, version}, acc ->
        versions = if version, do: [to_string(version)], else: []
        Map.update(acc, {repository, package}, MapSet.new(versions), &union(&1, versions))
      end)

    repositories =
      from(r in Repository, select: r.name)
      |> Repo.all()
      |> MapSet.new()

    policies =
      from(p in Policy, join: o in assoc(p, :organization), select: {o.name, p.name})
      |> Repo.all()
      |> MapSet.new()

    %{packages: packages, repositories: repositories, policies: policies}
  end

  defp union(set, []), do: set
  defp union(set, [version]), do: MapSet.put(set, version)

  defp orphaned?({:repository, repository}, index) do
    not MapSet.member?(index.repositories, repository)
  end

  defp orphaned?({:package, repository, package}, index) do
    not Map.has_key?(index.packages, {repository, package})
  end

  defp orphaned?({:release, repository, package, version}, index) do
    case Map.fetch(index.packages, {repository, package}) do
      {:ok, versions} -> not MapSet.member?(versions, version)
      :error -> true
    end
  end

  defp orphaned?({:policy, repository, name}, index) do
    not MapSet.member?(index.policies, {repository, name})
  end

  # A cached diff names the two versions it compares, so it is live only while
  # both are still releases of the package.
  defp orphaned?({:diff, repository, package, pair}, index) do
    case Map.fetch(index.packages, {repository, package}) do
      {:ok, versions} -> not version_pair?(pair, versions)
      :error -> true
    end
  end

  # `pair` is "<from>-<to>" and a version can hold hyphens of its own, so the
  # split is the one that leaves a release on each side.
  defp version_pair?(pair, versions) do
    size = byte_size(pair)

    Enum.any?(1..(size - 1)//1, fn index ->
      binary_part(pair, index, 1) == "-" and
        MapSet.member?(versions, binary_part(pair, 0, index)) and
        MapSet.member?(versions, binary_part(pair, index + 1, size - index - 1))
    end)
  end

  ## What each key is

  defp classify(:repo_bucket, key) do
    with {repository, rest} <- split_repository(key) do
      classify_repo(repository, rest)
    end
  end

  defp classify(:preview_bucket, key) do
    with {repository, rest} <- split_repository(key) do
      classify_preview(repository, rest)
    end
  end

  defp classify(:diff_bucket, key) do
    with {repository, rest} <- split_repository(key) do
      classify_diff(repository, rest)
    end
  end

  defp classify(:docs_bucket, key) when key in ~w(sitemap.xml package_names.csv org_names.csv) do
    :keep
  end

  defp classify(:docs_bucket, key) do
    classify_docs("hexpm", String.split(key, "/"))
  end

  defp classify(:docs_private_bucket, key) do
    case String.split(key, "/") do
      [repository | rest] when rest != [] -> classify_docs(repository, rest)
      _ -> :unrecognised
    end
  end

  defp classify_repo(repository, rest) when rest in ~w(names versions) do
    {:repository, repository}
  end

  defp classify_repo("hexpm", "installs/list.csv"), do: :keep
  defp classify_repo("hexpm", "debug/" <> _rest), do: :keep

  defp classify_repo(repository, "packages/" <> package) do
    if String.contains?(package, "/"), do: :unrecognised, else: {:package, repository, package}
  end

  defp classify_repo(repository, "tarballs/" <> file) do
    release(repository, file, ".tar")
  end

  defp classify_repo(repository, "docs/" <> file) do
    release(repository, file, ".tar.gz")
  end

  defp classify_repo(repository, "policies/" <> name) do
    if String.contains?(name, "/"), do: :unrecognised, else: {:policy, repository, name}
  end

  defp classify_repo(_repository, _rest), do: :unrecognised

  defp classify_preview(repository, "files/" <> rest) do
    case String.split(rest, "/", parts: 3) do
      [package, version, _path] -> {:release, repository, package, version}
      _ -> :unrecognised
    end
  end

  defp classify_preview(repository, "file_lists/" <> file) do
    release(repository, file, ".json")
  end

  defp classify_preview(repository, "latest_versions/" <> package) do
    if String.contains?(package, "/"), do: :unrecognised, else: {:package, repository, package}
  end

  defp classify_preview(_repository, _rest), do: :unrecognised

  defp classify_docs(_repository, [package | _rest]) when package in @special_packages do
    :keep
  end

  defp classify_docs(repository, [package, segment | _rest]) do
    case Version.parse(segment) do
      {:ok, _version} -> {:release, repository, package, segment}
      :error -> {:package, repository, package}
    end
  end

  defp classify_docs(_repository, _segments), do: :unrecognised

  defp classify_diff(repository, "metadata/" <> file) do
    diff(repository, file, ".json")
  end

  defp classify_diff(repository, "diffs/" <> file) do
    with {:ok, base} <- strip_suffix(file, ".json"),
         [rest, _index] <- String.split(base, "-diff-") do
      diff(repository, rest, "")
    else
      _ -> :unrecognised
    end
  end

  defp classify_diff(_repository, _rest), do: :unrecognised

  # "<package>-<from>-<to>-<hash>": a package name holds no hyphen and the hash
  # is `:erlang.phash2/1`, so both ends come off and the versions are left.
  defp diff(repository, file, suffix) do
    with {:ok, base} <- strip_suffix(file, suffix),
         [package, rest] <- String.split(base, "-", parts: 2),
         [_, pair] <- Regex.run(~r/\A(.+)-\d+\z/, rest) do
      {:diff, repository, package, pair}
    else
      _ -> :unrecognised
    end
  end

  # "<package>-<version><suffix>", the same way round.
  defp release(repository, file, suffix) do
    with {:ok, base} <- strip_suffix(file, suffix),
         false <- String.contains?(base, "/"),
         [package, version] <- String.split(base, "-", parts: 2) do
      {:release, repository, package, version}
    else
      _ -> :unrecognised
    end
  end

  defp strip_suffix(string, "") do
    {:ok, string}
  end

  defp strip_suffix(string, suffix) do
    if String.ends_with?(string, suffix) do
      {:ok, binary_part(string, 0, byte_size(string) - byte_size(suffix))}
    else
      :error
    end
  end

  defp split_repository("repos/" <> rest) do
    case String.split(rest, "/", parts: 2) do
      [repository, rest] when rest != "" -> {repository, rest}
      _ -> :unrecognised
    end
  end

  defp split_repository(key), do: {"hexpm", key}
end
