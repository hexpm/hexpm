defmodule Hexpm.Repository.RegistryBuilderTest do
  use Hexpm.ModelCase

  alias Hexpm.Repository.Package
  alias Hexpm.Repository.Release
  alias Hexpm.Repository.Install
  alias Hexpm.Repository.RegistryBuilder

  setup do
    user = create_user("eric", "eric@mail.com", "ericeric")
    postgrex = Package.build(user, pkg_meta(%{name: "postgrex", description: "PostgreSQL driver for Elixir."})) |> Hexpm.Repo.insert!
    decimal = Package.build(user, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal arithmetic for Elixir."})) |> Hexpm.Repo.insert!
    ex_doc = Package.build(user, pkg_meta(%{name: "ex_doc", description: "ExDoc"})) |> Hexpm.Repo.insert!
    Install.build("0.0.1", ["0.13.0-dev"]) |> Hexpm.Repo.insert!
    Install.build("0.1.0", ["0.13.1-dev", "0.13.1"]) |> Hexpm.Repo.insert!

    %{user: user, postgrex: postgrex, decimal: decimal, ex_doc: ex_doc}
  end

  defp open_table do
    contents = Hexpm.Store.get(nil, :s3_bucket, "registry.ets.gz", []) |> :zlib.gunzip
    File.write!("tmp/registry_builder_test.ets", contents)
    {:ok, tid} = :ets.file2tab('tmp/registry_builder_test.ets')
    tid
  end

  defp v2_map(path) do
    {module, message} = path_to_protobuf(path)
    if contents = Hexpm.Store.get(nil, :s3_bucket, path, []) do
      %{payload: payload, signature: signature} =
        contents
        |> :zlib.gunzip
        |> :hex_pb_signed.decode_msg(:Signed)

      public_key = Application.fetch_env!(:hexpm, :public_key)
      assert Hexpm.Utils.verify(payload, signature, public_key)
      module.decode_msg(payload, message)
    end
  end
  defp path_to_protobuf("names"), do: {:hex_pb_names, :Names}
  defp path_to_protobuf("versions"), do: {:hex_pb_versions, :Versions}
  defp path_to_protobuf("packages/" <> _), do: {:hex_pb_package, :Package}

  defp test_data(context) do
    ex_doc1 = Release.build(context.ex_doc, rel_meta(%{version: "0.0.1", app: "ex_doc"}), "") |> Hexpm.Repo.insert!
    decimal1 = Release.build(context.decimal, rel_meta(%{version: "0.0.1", app: "decimal"}), "") |> Hexpm.Repo.insert!
    reqs = [%{name: "ex_doc", app: "ex_doc", requirement: "0.0.1", optional: false}]
    decimal2 = Release.build(context.decimal, rel_meta(%{version: "0.0.2", app: "decimal", requirements: reqs}), "") |> Hexpm.Repo.insert!
    reqs = [%{name: "decimal", app: "decimal", requirement: "~> 0.0.1", optional: false},
            %{name: "ex_doc", app: "ex_doc", requirement: "0.0.1", optional: false}]
    meta = rel_meta(%{requirements: reqs, app: "postgrex", version: "0.0.2"})
    postgrex1 = Release.build(context.postgrex, meta, "") |> Hexpm.Repo.insert!

    %{ex_doc1: ex_doc1, decimal1: decimal1, decimal2: decimal2, postgrex1: postgrex1}
  end

  test "registry is versioned" do
    RegistryBuilder.full_build()
    tid = open_table()

    assert [{:"$$version$$", 4}] = :ets.lookup(tid, :"$$version$$")
  end

  test "registry is in correct format", context do
    test_data(context)
    RegistryBuilder.full_build()
    tid = open_table()

    assert length(:ets.match_object(tid, :_)) == 9

    assert [{"decimal", [["0.0.1", "0.0.2"]]}] = :ets.lookup(tid, "decimal")

    assert [{{"decimal", "0.0.1"}, [[], "", ["mix"]]}] =
           :ets.lookup(tid, {"decimal", "0.0.1"})

    assert [{"postgrex", [["0.0.2"]]}] =
           :ets.lookup(tid, "postgrex")

    reqs = :ets.lookup(tid, {"postgrex", "0.0.2"}) |> List.first |> elem(1) |> List.first
    assert length(reqs) == 2
    assert Enum.find(reqs, &(&1 == ["decimal", "~> 0.0.1", false, "decimal"]))
    assert Enum.find(reqs, &(&1 == ["ex_doc", "0.0.1", false, "ex_doc"]))

    assert [] = :ets.lookup(tid, "non_existant")
  end

  test "registry is uploaded alongside signature", context do
    test_data(context)
    RegistryBuilder.full_build()

    registry = Hexpm.Store.get(nil, :s3_bucket, "registry.ets.gz", [])
    signature = Hexpm.Store.get(nil, :s3_bucket, "registry.ets.gz.signed", [])

    public_key = Application.fetch_env!(:hexpm, :public_key)
    signature = Base.decode16!(signature, case: :lower)
    assert Hexpm.Utils.verify(registry, signature, public_key)
  end

  test "registry v2 is in correct format", context do
    test_data(context)
    RegistryBuilder.full_build()

    names = v2_map("names")
    assert length(names.packages) == 3
    assert [%{name: "decimal"} | _] = names.packages

    versions = v2_map("versions")
    assert length(versions.packages) == 3
    assert [%{name: "decimal", versions: ["0.0.1", "0.0.2"]} | _] = versions.packages

    decimal = v2_map("packages/decimal")
    assert length(decimal.releases) == 2
    assert [%{version: "0.0.1", checksum: checksum, dependencies: []} | _] = decimal.releases
    assert is_binary(checksum)

    postgrex = v2_map("packages/postgrex")
    assert [%{version: "0.0.2", dependencies: deps}] = postgrex.releases
    assert deps == [%{package: "decimal", requirement: "~> 0.0.1"}, %{package: "ex_doc", requirement: "0.0.1"}]
  end

  test "partial build add release", context do
    test_data(context)
    RegistryBuilder.full_build()

    release = Release.build(context.decimal, rel_meta(%{version: "0.0.3", app: "decimal", requirements: []}), "") |> Hexpm.Repo.insert!
    Release.retire(release, %{retirement: %{reason: "invalid", message: "message"}}) |> Hexpm.Repo.update!
    RegistryBuilder.partial_build({:publish, "decimal"})

    tid = open_table()
    assert length(:ets.match_object(tid, :_)) == 10

    versions = v2_map("versions")
    assert [%{name: "decimal", versions: ["0.0.1", "0.0.2", "0.0.3"]} | _] = versions.packages

    decimal = v2_map("packages/decimal")
    assert length(decimal.releases) == 3
    release = List.last(decimal.releases)
    assert release.version == "0.0.3"
    assert release.retired.reason == :RETIRED_INVALID
    assert release.retired.message == "message"
  end

  test "partial build remove release", context do
    %{decimal2: decimal2} = test_data(context)
    RegistryBuilder.full_build()

    Release.delete(decimal2) |> Hexpm.Repo.delete!
    RegistryBuilder.partial_build({:publish, "decimal"})

    tid = open_table()
    assert length(:ets.match_object(tid, :_)) == 8

    versions = v2_map("versions")
    assert [%{name: "decimal", versions: ["0.0.1"]} | _] = versions.packages

    decimal = v2_map("packages/decimal")
    assert length(decimal.releases) == 1
  end

  test "partial build add package", context do
    test_data(context)
    RegistryBuilder.full_build()

    ecto = Package.build(context.user, pkg_meta(%{name: "ecto", description: "..."})) |> Hexpm.Repo.insert!
    Release.build(ecto, rel_meta(%{version: "0.0.1", app: "ecto", requirements: []}), "") |> Hexpm.Repo.insert!
    RegistryBuilder.partial_build({:publish, "ecto"})

    tid = open_table()
    assert length(:ets.match_object(tid, :_)) == 11

    assert length(v2_map("names").packages) == 4

    versions = v2_map("versions")
    assert [_, %{name: "ecto", versions: ["0.0.1"]} | _] = versions.packages

    ecto = v2_map("packages/ecto")
    assert length(ecto.releases) == 1
  end

  test "partial build remove package", context do
    %{postgrex1: postgrex1} = test_data(context)
    RegistryBuilder.full_build()

    Release.delete(postgrex1) |> Hexpm.Repo.delete!
    Hexpm.Repo.delete!(context.postgrex)
    RegistryBuilder.partial_build({:publish, "postgrex"})

    tid = open_table()
    assert length(:ets.match_object(tid, :_)) == 7

    assert length(v2_map("names").packages) == 2
    assert length(v2_map("versions").packages) == 2

    refute v2_map("packages/postgrex")
  end

  test "full build remove package", context do
    %{postgrex1: postgrex1} = test_data(context)
    RegistryBuilder.full_build()

    Release.delete(postgrex1) |> Hexpm.Repo.delete!
    Hexpm.Repo.delete!(context.postgrex)
    RegistryBuilder.full_build

    assert length(v2_map("names").packages) == 2
    assert v2_map("packages/ex_doc")
    assert v2_map("packages/decimal")
    refute v2_map("packages/postgrex")
  end
end
