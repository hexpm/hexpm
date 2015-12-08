defmodule HexWeb.RegistryBuilderTest do
  use HexWebTest.Case

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.Install
  alias HexWeb.RegistryBuilder

  @ets_table :hex_registry

  setup do
    {:ok, user} = User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
    {:ok, _} = Package.create(user, pkg_meta(%{name: "postgrex", description: "PostgreSQL driver for Elixir."}))
    {:ok, _} = Package.create(user, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal arithmetic for Elixir."}))
    {:ok, _} = Package.create(user, pkg_meta(%{name: "ex_doc", description: "ExDoc"}))
    {:ok, _} = Install.create("0.0.1", ["0.13.0-dev"])
    {:ok, _} = Install.create("0.1.0", ["0.13.1-dev", "0.13.1"])
    :ok
  end

  defp open_table do
    {:ok, tid} = :ets.file2tab('tmp/registry.ets')
    tid
  end

  defp close_table(tid) do
    :ets.delete(tid)
  end

  defp test_data do
    postgrex = Package.get("postgrex")
    decimal = Package.get("decimal")

    Release.create(decimal, rel_meta(%{version: "0.0.1", app: "decimal"}), "")
    Release.create(decimal, rel_meta(%{version: "0.0.2", app: "decimal", requirements: %{ex_doc: "0.0.0"}}), "")
    Release.create(postgrex, rel_meta(%{version: "0.0.2", app: "postgrex", requirements: %{decimal: "~> 0.0.1", ex_doc: "0.1.0"}}), "")
  end

  test "registry is versioned" do
    RegistryBuilder.rebuild()
    tid = open_table()

    try do
      assert [{:"$$version$$", 4}] = :ets.lookup(tid, :"$$version$$")
    after
      close_table(tid)
    end
  end

  test "registry is in correct format" do
    test_data()

    RegistryBuilder.rebuild()
    tid = open_table()

    try do
      assert length(:ets.match_object(tid, :_)) == 7

      assert [ {"decimal", [["0.0.1", "0.0.2"]]} ] = :ets.lookup(tid, "decimal")

      assert [ {{"decimal", "0.0.1"}, [[], "", ["mix"]]} ] =
             :ets.lookup(tid, {"decimal", "0.0.1"})

      assert [{"postgrex", [["0.0.2"]]}] =
             :ets.lookup(tid, "postgrex")

      reqs = :ets.lookup(tid, {"postgrex", "0.0.2"}) |> List.first |> elem(1) |> List.first
      assert length(reqs) == 2
      assert Enum.find(reqs, &(&1 == ["decimal", "~> 0.0.1", false, "decimal"]))
      assert Enum.find(reqs, &(&1 == ["ex_doc", "0.1.0", false, "ex_doc"]))

      assert [] = :ets.lookup(tid, "ex_doc")
    after
      close_table(tid)
    end
  end

  test "registry is uploaded alongside signature" do
    keypath  = Path.join([__DIR__, "..", "fixtures"])
    key      = File.read!(Path.join(keypath, "testkey.pem"))
    Application.put_env(:hex_web, :signing_key, key)

    test_data()
    RegistryBuilder.rebuild()

    tmp = Application.get_env(:hex_web, :tmp)
    reg = File.read!(Path.join(tmp, "store/registry.ets.gz")) |> :zlib.gunzip
    sig = File.read!(Path.join(tmp, "store/registry.ets.gz.signed"))

    checksum = :crypto.hash(:sha512, reg)

    assert HexWeb.Util.sign(checksum, key) == sig
  end

  test "integration fetch registry" do
    if Application.get_env(:hex_web, :s3_bucket) do
      Application.put_env(:hex_web, :store, HexWeb.Store.S3)
    end

    keypath  = Path.join([__DIR__, "..", "fixtures"])
    key      = File.read!(Path.join(keypath, "testkey.pem"))
    Application.put_env(:hex_web, :signing_key, key)

    test_data()
    RegistryBuilder.rebuild()

    :inets.start

    # fetch registry
    url = HexWeb.Util.cdn_url("registry.ets.gz") |> String.to_char_list
    assert {:ok, response} = :httpc.request(:get, {url, []}, [], [])
    assert {{_version, 200, _reason}, _headers, body} = response

    # convert body to binary and unzip registry
    body = body
           |> :erlang.list_to_binary
           |> :zlib.gunzip

    # sign registry
    checksum = :crypto.hash(:sha512, body)
    signature = HexWeb.Util.sign(checksum, key)
                |> :erlang.binary_to_list

    # fetch generated signature
    url = HexWeb.Util.cdn_url("registry.ets.gz.signed") |> String.to_char_list
    assert {:ok, response} = :httpc.request(:get, {url, []}, [], [])

    # compare signatures
    {{_version, 200, _reason}, _headers, ^signature} = response

  after
    Application.put_env(:hex_web, :store, HexWeb.Store.Local)
  end

  # test "building is blocking" do
  #   postgrex = Package.get("postgrex")
  #   decimal = Package.get("decimal")

  #   Release.create(decimal, %{version: "0.0.1", app: "decimal"}, "")
  #   Release.create(decimal, %{version: "0.0.2", app: "decimal", requirements: %{ex_doc: "0.0.0"}}, "")
  #   Release.create(postgrex, %{version: "0.0.2", app: "postgrex", requirements: %{decimal: "~> 0.0.1", ex_doc: "0.1.0"}}, "")

  #   pid = self

  #   Task.start_link(fn ->
  #     RegistryBuilder.rebuild
  #     send pid, :done
  #   end)
  #   Task.start_link(fn ->
  #     RegistryBuilder.rebuild
  #     send pid, :done
  #   end)

  #   RegistryBuilder.rebuild

  #   receive do: (:done -> :ok)
  #   receive do: (:done -> :ok)

  #   tid = open_table()
  #   close_table(tid)
  # end
end
