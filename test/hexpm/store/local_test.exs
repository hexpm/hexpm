defmodule Hexpm.Store.LocalTest do
  use ExUnit.Case, async: false

  alias Hexpm.Store.Local

  setup context do
    if tmp_dir = context[:tmp_dir] do
      original_tmp_dir = Application.get_env(:hexpm, :tmp_dir)
      Application.put_env(:hexpm, :tmp_dir, tmp_dir)

      on_exit(fn ->
        Application.put_env(:hexpm, :tmp_dir, original_tmp_dir)
      end)
    end

    :ok
  end

  describe "get/3" do
    @tag :tmp_dir
    test "works for valid paths", %{tmp_dir: tmp_dir} do
      bucket_dir = Path.join([tmp_dir, "store", "bucket"])
      File.mkdir_p!(bucket_dir)
      File.write!(Path.join(bucket_dir, "file.txt"), "content")

      assert Local.get("bucket", "file.txt", []) == "content"
    end

    @tag :tmp_dir
    test "raises on path traversal attempt", %{tmp_dir: tmp_dir} do
      bucket_dir = Path.join([tmp_dir, "store", "bucket"])
      File.mkdir_p!(bucket_dir)

      secret_file = Path.join([tmp_dir, "store", "secret.txt"])
      File.write!(secret_file, "secret content")

      assert_raise ArgumentError, fn ->
        Local.get("bucket", "../secret.txt", [])
      end
    end
  end

  describe "put/4" do
    @tag :tmp_dir
    test "works for valid paths", %{tmp_dir: tmp_dir} do
      bucket_dir = Path.join([tmp_dir, "store", "bucket"])
      File.mkdir_p!(bucket_dir)

      Local.put("bucket", "file.txt", "content", [])

      assert File.read!(Path.join(bucket_dir, "file.txt")) == "content"
    end

    @tag :tmp_dir
    test "raises on path traversal attempt", %{tmp_dir: tmp_dir} do
      bucket_dir = Path.join([tmp_dir, "store", "bucket"])
      File.mkdir_p!(bucket_dir)

      assert_raise ArgumentError, fn ->
        Local.put("bucket", "../evil.txt", "malicious", [])
      end
    end
  end

  describe "delete/2" do
    @tag :tmp_dir
    test "works for valid paths", %{tmp_dir: tmp_dir} do
      bucket_dir = Path.join([tmp_dir, "store", "bucket"])
      File.mkdir_p!(bucket_dir)
      file_path = Path.join(bucket_dir, "file.txt")
      File.write!(file_path, "content")

      Local.delete("bucket", "file.txt")

      refute File.exists?(file_path)
    end

    @tag :tmp_dir
    test "raises on path traversal attempt", %{tmp_dir: tmp_dir} do
      bucket_dir = Path.join([tmp_dir, "store", "bucket"])
      File.mkdir_p!(bucket_dir)

      secret_file = Path.join([tmp_dir, "store", "secret.txt"])
      File.write!(secret_file, "secret content")

      assert_raise ArgumentError, fn ->
        Local.delete("bucket", "../secret.txt")
      end
    end
  end

  describe "delete_many/2" do
    @tag :tmp_dir
    test "works for valid paths", %{tmp_dir: tmp_dir} do
      bucket_dir = Path.join([tmp_dir, "store", "bucket"])
      File.mkdir_p!(bucket_dir)
      file1 = Path.join(bucket_dir, "file1.txt")
      file2 = Path.join(bucket_dir, "file2.txt")
      File.write!(file1, "content1")
      File.write!(file2, "content2")

      Local.delete_many("bucket", ["file1.txt", "file2.txt"])

      refute File.exists?(file1)
      refute File.exists?(file2)
    end

    @tag :tmp_dir
    test "raises on path traversal attempt", %{tmp_dir: tmp_dir} do
      bucket_dir = Path.join([tmp_dir, "store", "bucket"])
      File.mkdir_p!(bucket_dir)

      secret_file = Path.join([tmp_dir, "store", "secret.txt"])
      File.write!(secret_file, "secret content")

      assert_raise ArgumentError, fn ->
        Local.delete_many("bucket", ["file.txt", "../secret.txt"])
      end
    end
  end

  describe "list/2" do
    @tag :tmp_dir
    test "works for valid paths", %{tmp_dir: tmp_dir} do
      bucket_dir = Path.join([tmp_dir, "store", "bucket"])
      File.mkdir_p!(bucket_dir)
      File.write!(Path.join(bucket_dir, "prefix_file1.txt"), "content1")
      File.write!(Path.join(bucket_dir, "prefix_file2.txt"), "content2")
      File.write!(Path.join(bucket_dir, "other.txt"), "content3")

      result = Local.list("bucket", "prefix_")

      assert Enum.sort(result) == ["prefix_file1.txt", "prefix_file2.txt"]
    end
  end
end
