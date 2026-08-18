defmodule Hexpm.Repository.Assets do
  alias Hexpm.Repository.Repository

  def push_release(release, body_path) do
    meta = [
      {"surrogate-key", tarball_cdn_key(release)},
      {"surrogate-control", "public, max-age=604800"}
    ]

    cache_control = tarball_cache_control(release.package.repository)
    opts = [cache_control: cache_control, meta: meta]
    key = tarball_store_key(release)

    {:ok, %{etag: etag}} = Hexpm.Store.put_file(:repo_bucket, key, body_path, opts)
    purge(release, tarball_cdn_key(release), key, etag)
  end

  def revert_release(release) do
    key = tarball_store_key(release)
    Hexpm.Store.delete(:repo_bucket, key)
    purge(release, tarball_cdn_key(release), key, nil)
    revert_docs(release)
  end

  def push_docs(release, body_path) do
    meta = [
      {"surrogate-key", docs_cdn_key(release)},
      {"surrogate-control", "public, max-age=604800"}
    ]

    cache_control = docs_cache_control(release.package.repository)
    opts = [cache_control: cache_control, meta: meta]
    key = docs_store_key(release)

    {:ok, %{etag: etag}} = Hexpm.Store.put_file(:repo_bucket, key, body_path, opts)
    purge(release, docs_cdn_key(release), key, etag)
  end

  def revert_docs(release) do
    if release.has_docs do
      key = docs_store_key(release)
      Hexpm.Store.delete(:repo_bucket, key)
      purge(release, docs_cdn_key(release), key, nil)
    end
  end

  defp purge(release, cdn_key, store_key, etag) do
    repository = release.package.repository
    target = %{url: Hexpm.Utils.cdn_url(store_key), etag: etag}

    target =
      if repository.id == 1, do: target, else: Map.put(target, :repository, repository.name)

    Hexpm.CDN.purge(:fastly_hexrepo, cdn_key, verify: [target])
    :ok
  end

  defp tarball_cache_control(%Repository{id: 1}), do: "public, max-age=604800"
  defp tarball_cache_control(%Repository{}), do: "private, max-age=86400"

  defp docs_cache_control(%Repository{id: 1}), do: "public, max-age=86400"
  defp docs_cache_control(%Repository{}), do: "private, max-age=86400"

  def tarball_cdn_key(release) do
    "tarballs/#{repository_cdn_key(release)}#{release.package.name}-#{release.version}"
  end

  def tarball_store_key(release) do
    "#{repository_store_key(release)}tarballs/#{release.package.name}-#{release.version}.tar"
  end

  def file_checksum(path) do
    hash =
      path
      |> File.stream!(64 * 1024, [])
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))

    :crypto.hash_final(hash)
  end

  def docs_cdn_key(release) do
    "docs/#{repository_cdn_key(release)}#{release.package.name}-#{release.version}"
  end

  def docs_store_key(release) do
    "#{repository_store_key(release)}docs/#{release.package.name}-#{release.version}.tar.gz"
  end

  defp repository_cdn_key(release) do
    repository = release.package.repository

    if repository.id == 1 do
      ""
    else
      "#{repository.name}-"
    end
  end

  defp repository_store_key(release) do
    repository = release.package.repository

    if repository.id == 1 do
      ""
    else
      "repos/#{repository.name}/"
    end
  end
end
