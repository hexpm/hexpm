defmodule Hexpm.Repository.Assets do
  alias Hexpm.Repository.Repository

  def push_release(release, body) do
    meta = [
      {"surrogate-key", tarball_cdn_key(release)},
      {"surrogate-control", "public, max-age=604800"}
    ]

    cache_control = tarball_cache_control(release.package.repository)
    opts = [cache_control: cache_control, meta: meta]

    Hexpm.Store.put(:repo_bucket, tarball_store_key(release), body, opts)
    Hexpm.CDN.purge_key(:fastly_hexrepo, tarball_cdn_key(release))
  end

  def revert_release(release) do
    Hexpm.CDN.purge_key(:fastly_hexrepo, tarball_cdn_key(release))
    Hexpm.Store.delete(:repo_bucket, tarball_store_key(release))
    revert_docs(release)
  end

  def push_docs(release, body) do
    meta = [
      {"surrogate-key", docs_cdn_key(release)},
      {"surrogate-control", "public, max-age=604800"}
    ]

    cache_control = docs_cache_control(release.package.repository)
    opts = [cache_control: cache_control, meta: meta]

    Hexpm.Store.put(:repo_bucket, docs_store_key(release), body, opts)
    Hexpm.CDN.purge_key(:fastly_hexrepo, docs_cdn_key(release))
  end

  def revert_docs(release) do
    if release.has_docs do
      Hexpm.Store.delete(:repo_bucket, docs_store_key(release))
      Hexpm.CDN.purge_key(:fastly_hexrepo, docs_cdn_key(release))
    end
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
