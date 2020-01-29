releases =
  Hexpm.Repository.Release
  |> Hexpm.Repo.all()
  |> Hexpm.Repo.preload(package: :repository)
  |> Enum.with_index()

num = length(releases)

Task.async_stream(
  releases,
  fn {release, ix} ->
    key = "tarballs/#{release.package.name}-#{release.version}.tar"

    key =
      if release.package.repository_id == 1 do
        key
      else
        "repos/#{release.package.repository.name}/#{key}"
      end

    object = Hexpm.Store.S3.get(:repo_bucket, key, [])
    checksum = :crypto.hash(:sha256, object)

    release
    |> Ecto.Changeset.change(outer_checksum: checksum)
    |> Hexpm.Repo.update!()

    IO.puts("#{ix + 1}/#{num}")
  end,
  ordered: false,
  max_concurrency: 10,
  on_timeout: :kill_task
)
|> Stream.run()
