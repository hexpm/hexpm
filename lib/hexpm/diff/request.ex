defmodule Hexpm.Diff.Request do
  @enforce_keys [
    :package,
    :from,
    :to,
    :from_release,
    :to_release,
    :from_checksum,
    :to_checksum,
    :cache_version,
    :ignore_whitespace,
    :canonical_hash,
    :legacy_hash,
    :versions
  ]
  defstruct @enforce_keys

  alias Hexpm.Repository.{Package, Packages, Release, Releases, Repository}

  def prepare(package_name, from, to, opts) when is_binary(package_name) and is_list(opts) do
    cache_version = Application.fetch_env!(:hexpm, :diff_cache_version)
    prepare(package_name, from, to, opts, cache_version)
  end

  def prepare(_, _, _, _), do: {:error, :invalid_request}

  defp prepare(package_name, from, to, opts, cache_version) do
    with {:ok, from} <- parse_version(from),
         {:ok, to} <- parse_optional_version(to),
         {:ok, package} <- fetch_package(package_name),
         {:ok, releases} <- fetch_releases(package),
         {:ok, to} <- resolve_to(to, releases),
         :ok <- ensure_distinct(from, to),
         {:ok, from_release} <- find_release(releases, from),
         {:ok, to_release} <- find_release(releases, to) do
      ignore_whitespace = Keyword.get(opts, :ignore_whitespace, false)
      from_checksum = from_release.outer_checksum
      to_checksum = to_release.outer_checksum

      {:ok,
       %__MODULE__{
         package: package.name,
         from: from,
         to: to,
         from_release: %{from_release | package: package},
         to_release: %{to_release | package: package},
         from_checksum: from_checksum,
         to_checksum: to_checksum,
         cache_version: cache_version,
         ignore_whitespace: ignore_whitespace,
         canonical_hash:
           cache_hash(cache_version, [from_checksum, to_checksum], ignore_whitespace),
         legacy_hash: cache_hash(cache_version, [to_checksum, from_checksum], ignore_whitespace),
         versions: Enum.map(releases, &to_string(&1.version))
       }}
    else
      {:error, _} = error -> error
    end
  end

  def from_args(%{
        "package" => package,
        "from" => from,
        "to" => to,
        "from_checksum" => from_checksum,
        "to_checksum" => to_checksum,
        "cache_version" => cache_version,
        "ignore_whitespace" => ignore_whitespace
      })
      when is_binary(package) and is_binary(from) and is_binary(to) and
             is_binary(from_checksum) and is_binary(to_checksum) and is_integer(cache_version) and
             is_boolean(ignore_whitespace) do
    with {:ok, decoded_from} <- Base.decode16(from_checksum, case: :mixed),
         {:ok, decoded_to} <- Base.decode16(to_checksum, case: :mixed),
         {:ok, request} <-
           prepare(
             package,
             from,
             to,
             [ignore_whitespace: ignore_whitespace],
             cache_version
           ) do
      {:ok,
       %{
         request
         | from_checksum: decoded_from,
           to_checksum: decoded_to,
           cache_version: cache_version,
           canonical_hash:
             cache_hash(cache_version, [decoded_from, decoded_to], ignore_whitespace),
           legacy_hash: cache_hash(cache_version, [decoded_to, decoded_from], ignore_whitespace)
       }}
    else
      _ -> {:error, :invalid_args}
    end
  end

  def from_args(_), do: {:error, :invalid_args}

  def to_args(%__MODULE__{} = request) do
    %{
      package: request.package,
      from: request.from,
      to: request.to,
      from_checksum: Base.encode16(request.from_checksum, case: :lower),
      to_checksum: Base.encode16(request.to_checksum, case: :lower),
      cache_version: request.cache_version,
      ignore_whitespace: request.ignore_whitespace
    }
  end

  def cache_hash(cache_version, checksums, ignore_whitespace) do
    base = {cache_version, checksums}
    key = if ignore_whitespace, do: {base, [ignore_whitespace: true]}, else: base
    :erlang.phash2(key)
  end

  defp parse_version(version) when is_binary(version) do
    case Version.parse(version) do
      {:ok, version} -> {:ok, to_string(version)}
      :error -> {:error, :invalid_version}
    end
  end

  defp parse_version(_), do: {:error, :invalid_version}

  defp parse_optional_version(version) when version in [nil, "", :latest], do: {:ok, :latest}
  defp parse_optional_version(version), do: parse_version(version)

  defp resolve_to(:latest, releases) do
    case Release.latest_version(releases, only_stable: true, unstable_fallback: true) do
      nil -> {:error, :no_releases}
      release -> {:ok, to_string(release.version)}
    end
  end

  defp resolve_to(version, _releases), do: {:ok, version}

  defp ensure_distinct(version, version), do: {:error, :identical_versions}
  defp ensure_distinct(_, _), do: :ok

  defp fetch_package(package_name) do
    case Packages.get(Repository.hexpm(), package_name) do
      %Package{} = package -> {:ok, package}
      nil -> {:error, :package_not_found}
    end
  end

  defp fetch_releases(package) do
    case Releases.all(package) do
      [] -> {:error, :no_releases}
      releases -> {:ok, releases}
    end
  end

  defp find_release(releases, version) do
    case Enum.find(releases, &(to_string(&1.version) == version)) do
      %Release{} = release -> {:ok, release}
      nil -> {:error, :release_not_found}
    end
  end
end
