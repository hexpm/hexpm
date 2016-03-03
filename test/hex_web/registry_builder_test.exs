defmodule HexWeb.RegistryBuilderTest do
  use HexWeb.ModelCase

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.Install
  alias HexWeb.RegistryBuilder

  @ets_table :hex_registry
  @endpoint HexWeb.Endpoint

  setup do
    user = User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true) |> HexWeb.Repo.insert!
    Package.create(user, pkg_meta(%{name: "postgrex", description: "PostgreSQL driver for Elixir."}))
    Package.create(user, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal arithmetic for Elixir."}))
    Package.create(user, pkg_meta(%{name: "ex_doc", description: "ExDoc"}))
    Install.create("0.0.1", ["0.13.0-dev"]) |> HexWeb.Repo.insert!
    Install.create("0.1.0", ["0.13.1-dev", "0.13.1"]) |> HexWeb.Repo.insert!
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
    ex_doc = HexWeb.Repo.get_by(Package, name: "ex_doc")
    postgrex = HexWeb.Repo.get_by(Package, name: "postgrex")
    decimal = HexWeb.Repo.get_by(Package, name: "decimal")

    {:ok, _} = Release.create(ex_doc, rel_meta(%{version: "0.0.1", app: "ex_doc"}), "")
    {:ok, _} = Release.create(decimal, rel_meta(%{version: "0.0.1", app: "decimal"}), "")
    {:ok, _} = Release.create(decimal, rel_meta(%{version: "0.0.2", app: "decimal", requirements: %{ex_doc: "0.0.1"}}), "")
    {:ok, _} = Release.create(postgrex, rel_meta(%{version: "0.0.2", app: "postgrex", requirements: %{decimal: "~> 0.0.1", ex_doc: "0.0.1"}}), "")
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
      assert length(:ets.match_object(tid, :_)) == 9

      assert [ {"decimal", [["0.0.1", "0.0.2"]]} ] = :ets.lookup(tid, "decimal")

      assert [ {{"decimal", "0.0.1"}, [[], "", ["mix"]]} ] =
             :ets.lookup(tid, {"decimal", "0.0.1"})

      assert [{"postgrex", [["0.0.2"]]}] =
             :ets.lookup(tid, "postgrex")

      reqs = :ets.lookup(tid, {"postgrex", "0.0.2"}) |> List.first |> elem(1) |> List.first
      assert length(reqs) == 2
      assert Enum.find(reqs, &(&1 == ["decimal", "~> 0.0.1", false, "decimal"]))
      assert Enum.find(reqs, &(&1 == ["ex_doc", "0.0.1", false, "ex_doc"]))

      assert [] = :ets.lookup(tid, "non_existant")
    after
      close_table(tid)
    end
  end

  test "registry is uploaded alongside signature" do
    keypath       = Path.join([__DIR__, "..", "fixtures"])
    priv_key      = File.read!(Path.join(keypath, "test_priv.pem"))
    pub_key       = File.read!(Path.join(keypath, "test_pub.pem"))

    Application.put_env(:hex_web, :signing_key, priv_key)

    test_data()

    try do
      RegistryBuilder.rebuild()

      tmp = Application.get_env(:hex_web, :tmp_dir)
      reg = File.read!(Path.join(tmp, "store/registry.ets.gz"))
      sig = File.read!(Path.join(tmp, "store/registry.ets.gz.signed"))

      assert HexWeb.Utils.verify(reg, sig, pub_key) == true
    after
      Application.delete_env(:hex_web, :signing_key)
    end
  end

  # test "building is blocking" do
  #   postgrex = HexWeb.Repo.get_by(Package, name: "postgrex")
  #   decimal = HexWeb.Repo.get_by(Package, name: "decimal")

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
