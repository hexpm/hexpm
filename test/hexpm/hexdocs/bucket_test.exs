defmodule Hexpm.Hexdocs.BucketTest do
  use Hexpm.DataCase, async: false

  alias Hexpm.Hexdocs.Bucket

  test "uploads versioned and current private docs" do
    version = Version.parse!("1.0.0")
    {dir, files} = create_files([{"index.html", "1.0.0"}])

    assert :ok = Bucket.upload("acme", "package", version, [], MapSet.new(), dir, files)

    assert Hexpm.Store.get(:docs_private_bucket, "acme/package/1.0.0/index.html") == "1.0.0"
    assert Hexpm.Store.get(:docs_private_bucket, "acme/package/index.html") == "1.0.0"
  end

  test "an older version does not replace current docs" do
    latest = Version.parse!("2.0.0")
    older = Version.parse!("1.0.0")
    {latest_dir, latest_files} = create_files([{"index.html", "latest"}])
    {older_dir, older_files} = create_files([{"index.html", "older"}])

    Bucket.upload("acme", "package", latest, [], MapSet.new(), latest_dir, latest_files)
    Bucket.upload("acme", "package", older, [latest], MapSet.new(), older_dir, older_files)

    assert Hexpm.Store.get(:docs_private_bucket, "acme/package/index.html") == "latest"
    assert Hexpm.Store.get(:docs_private_bucket, "acme/package/1.0.0/index.html") == "older"
  end

  test "replacing docs removes stale files without affecting prefix-matching packages" do
    version = Version.parse!("1.0.0")

    {first_dir, first_files} =
      create_files([{"index.html", "first"}, {"removed.html", "removed"}])

    {prefix_dir, prefix_files} = create_files([{"index.html", "prefix"}])
    {second_dir, second_files} = create_files([{"index.html", "second"}])

    Bucket.upload("acme", "package_extra", version, [], MapSet.new(), prefix_dir, prefix_files)
    Bucket.upload("acme", "package", version, [], MapSet.new(), first_dir, first_files)
    Bucket.upload("acme", "package", version, [], MapSet.new(), second_dir, second_files)

    assert Hexpm.Store.get(:docs_private_bucket, "acme/package/index.html") == "second"
    refute Hexpm.Store.get(:docs_private_bucket, "acme/package/removed.html")
    assert Hexpm.Store.get(:docs_private_bucket, "acme/package_extra/index.html") == "prefix"
  end

  test "writes public docs to the existing docs bucket" do
    version = Version.parse!("1.0.0")
    {dir, files} = create_files([{"index.html", "public"}])

    Bucket.upload("hexpm", "package", version, [], MapSet.new(), dir, files)

    assert Hexpm.Store.get(:docs_bucket, "package/index.html") == "public"

    docs_config = Hexpm.Store.get(:docs_bucket, "package/docs_config.js")

    assert IO.iodata_to_binary(docs_config) =~ "http://package.localhost:5002/1.0.0"
  end

  defp create_files(entries) do
    dir = Hexpm.TmpDir.tmp_dir("hexdocs-bucket")

    files =
      Enum.map(entries, fn {path, contents} ->
        full_path = Path.join(dir, path)
        File.mkdir_p!(Path.dirname(full_path))
        File.write!(full_path, contents)
        path
      end)

    {dir, files}
  end
end
