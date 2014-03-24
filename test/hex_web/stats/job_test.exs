defmodule HexWeb.Stats.JobTest do
  use HexWebTest.Case

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release

  @logfile_1 """
  79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be mybucket [06/Feb/2014:00:00:38 +0000] 192.0.2.3 79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be 3E57427F3EXAMPLE REST.GET.VERSIONING - "GET /mybucket?versioning HTTP/1.1" 200 - 113 - 7 - "-" "S3Console/0.4" -
  79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be mybucket [06/Feb/2014:00:00:38 +0000] 192.0.2.3 79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be 891CE47D2EXAMPLE REST.GET.OBJECT - "GET /tarballs/foo-0.0.1.tar HTTP/1.1" 200 - 242 - 11 - "-" "S3Console/0.4" -
  79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be mybucket [06/Feb/2014:00:00:38 +0000] 192.0.2.3 79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be A1206F460EXAMPLE REST.GET.OBJECT - "GET /tarballs/foo-0.0.1.tar?key=value HTTP/1.1" 200 297 - 38 - "-" "S3Console/0.4" -
  79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be mybucket [06/Feb/2014:00:01:00 +0000] 192.0.2.3 79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be 7B4A0FABBEXAMPLE REST.GET.OBJECT - "GET /some/other/thing HTTP/1.1" 200 - 113 - 33 - "-" "S3Console/0.4" -
  79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be mybucket [06/Feb/2014:00:01:57 +0000] 192.0.2.3 79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be DD6CC733AEXAMPLE REST.PUT.OBJECT s3-dg.pdf "PUT /tarballs/foo-0.0.1.tar HTTP/1.1" 200 - - 4406583 41754 28 "-" "S3Console/0.4" -
  79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be mybucket [06/Feb/2014:00:03:21 +0000] 192.0.2.3 79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be BC3C074D0EXAMPLE REST.GET.OBJECT - "GET /tarballs/bar-0.0.2.tar?versioning HTTP/1.1" 200 - 113 - 28 - "-" "S3Console/0.4" -
  """

  @logfile_2 """
  79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be mybucket [06/Feb/2014:00:00:38 +0000] 192.0.2.3 79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be 3E57427F3EXAMPLE REST.GET.OBJECT - "GET /tarballs/foo.tar HTTP/1.1" 200 - 113 - 7 - "-" "S3Console/0.4" -
  79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be mybucket [06/Feb/2014:00:00:38 +0000] 192.0.2.3 79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be 891CE47D2EXAMPLE REST.GET.OBJECT - "GET /tarballs/foobar-0.0.1.tar HTTP/1.1" 200 - 242 - 11 - "-" "S3Console/0.4" -
  79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be mybucket [06/Feb/2014:00:00:38 +0000] 192.0.2.3 79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be A1206F460EXAMPLE REST.GET.OBJECT - "GET /tarballs/foo-0.0.1.tar?key=value HTTP/1.1" 200 297 - 38 - "-" "S3Console/0.4" -
  79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be mybucket [06/Feb/2014:00:01:00 +0000] 192.0.2.3 79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be 7B4A0FABBEXAMPLE REST.GET.OBJECT - "GET /some/other/thing HTTP/1.1" 200 - 113 - 33 - "-" "S3Console/0.4" -
  79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be mybucket [06/Feb/2014:00:01:57 +0000] 192.0.2.3 79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be DD6CC733AEXAMPLE REST.GET.OBJECT - "GET /tarballs/foo-0.0.1.tar HTTP/1.1" 200 - - 4406583 41754 28 "-" "S3Console/0.4" -
  79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be mybucket [06/Feb/2014:00:01:57 +0000] 192.0.2.3 79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be DD6CC733AEXAMPLE REST.GET.OBJECT - "GET /tarballs/foo-0.0.1.tar HTTP/1.1" 200 - - 4406583 41754 28 "-" "S3Console/0.4" -
  79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be mybucket [06/Feb/2014:00:01:57 +0000] 192.0.2.3 79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be DD6CC733AEXAMPLE REST.GET.OBJECT - "GET /tarballs/foo-0.0.2.tar HTTP/1.1" 200 - - 4406583 41754 28 "-" "S3Console/0.4" -
  79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be mybucket [06/Feb/2014:00:03:21 +0000] 192.0.2.3 79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be BC3C074D0EXAMPLE REST.GET.OBJECT - "GET /tarballs/bar-0.0.2.tar?versioning HTTP/1.1" 200 - 113 - 28 - "-" "S3Console/0.4" -
  79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be mybucket [06/Feb/2014:00:01:57 +0000] 192.0.2.3 79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be DD6CC733AEXAMPLE REST.GET.OBJECT - "GET /tarballs/foo-0.0.2.tar HTTP/1.1" 200 - - 4406583 41754 28 "-" "S3Console/0.4" -
  """

  @moduletag :integration

  setup do
    { :ok, user } = User.create("eric", "eric@mail.com", "eric")
    { :ok, foo } = Package.create("foo", user, [])
    { :ok, bar } = Package.create("bar", user, [])
    { :ok, other } = Package.create("other", user, [])

    { :ok, _ } = Release.create(foo, "0.0.1", [])
    { :ok, _ } = Release.create(foo, "0.0.2", [])
    { :ok, _ } = Release.create(foo, "0.1.0", [])
    { :ok, _ } = Release.create(bar, "0.0.1", [])
    { :ok, _ } = Release.create(bar, "0.0.2", [])
    { :ok, _ } = Release.create(other, "0.0.1", [])

    :ok
  end

  test "counts all downloads" do
    HexWeb.Config.store.put("logs/2013-11-01-21-32-16-E568B2907131C0C0", @logfile_1)
    HexWeb.Config.store.put("logs/2013-11-02-21-32-17-E568B2907131C0C0", @logfile_1)
    HexWeb.Config.store.put("logs/2013-11-03-21-32-18-E568B2907131C0C0", @logfile_1)
    HexWeb.Config.store.put("logs/2013-11-01-21-32-19-E568B2907131C0C0", @logfile_2)

    HexWeb.Stats.Job.run({ 2013, 11, 1 })

    rel1 = Release.get(Package.get("foo"), "0.0.1")
    rel2 = Release.get(Package.get("foo"), "0.0.2")
    rel3 = Release.get(Package.get("bar"), "0.0.2")

    downloads = HexWeb.Repo.all(HexWeb.Stats.Download)
    assert length(downloads) == 3

    assert Enum.find(downloads, &(&1.release_id == rel1.id)).downloads == 5
    assert Enum.find(downloads, &(&1.release_id == rel2.id)).downloads == 2
    assert Enum.find(downloads, &(&1.release_id == rel3.id)).downloads == 2
  end
end
