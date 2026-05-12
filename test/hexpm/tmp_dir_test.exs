defmodule Hexpm.TmpDirTest do
  use ExUnit.Case, async: true

  test "tmp_file/1 creates a file" do
    path = Hexpm.TmpDir.tmp_file("test")
    assert File.exists?(path)
    assert File.regular?(path)
  end

  test "tmp_dir/1 creates a directory" do
    path = Hexpm.TmpDir.tmp_dir("test")
    assert File.dir?(path)
  end

  test "cleanup on normal process exit" do
    test_pid = self()

    {:ok, task_pid} =
      Task.start(fn ->
        file = Hexpm.TmpDir.tmp_file("test")
        dir = Hexpm.TmpDir.tmp_dir("test")
        send(test_pid, {:paths, file, dir})
      end)

    assert_receive {:paths, file, dir}
    Hexpm.TmpDir.await_cleanup(task_pid)

    refute File.exists?(file)
    refute File.exists?(dir)
  end

  @tag :capture_log
  test "cleanup on process crash" do
    test_pid = self()

    {:ok, task_pid} =
      Task.start(fn ->
        file = Hexpm.TmpDir.tmp_file("test")
        dir = Hexpm.TmpDir.tmp_dir("test")
        send(test_pid, {:paths, file, dir})
        raise "crash"
      end)

    assert_receive {:paths, file, dir}
    Hexpm.TmpDir.await_cleanup(task_pid)

    refute File.exists?(file)
    refute File.exists?(dir)
  end

  test "multiple paths for one process" do
    test_pid = self()

    {:ok, task_pid} =
      Task.start(fn ->
        paths =
          for i <- 1..5 do
            file = Hexpm.TmpDir.tmp_file("test-#{i}")
            dir = Hexpm.TmpDir.tmp_dir("test-#{i}")
            {file, dir}
          end

        send(test_pid, {:paths, paths})
      end)

    assert_receive {:paths, paths}
    Hexpm.TmpDir.await_cleanup(task_pid)

    for {file, dir} <- paths do
      refute File.exists?(file)
      refute File.exists?(dir)
    end
  end

  test "cleanup removes paths for calling process" do
    file = Hexpm.TmpDir.tmp_file("test")
    dir = Hexpm.TmpDir.tmp_dir("test")

    assert File.exists?(file)
    assert File.dir?(dir)

    Hexpm.TmpDir.cleanup()

    refute File.exists?(file)
    refute File.exists?(dir)
  end

  test "cleanup only removes paths for calling process" do
    test_pid = self()

    Task.start(fn ->
      other_file = Hexpm.TmpDir.tmp_file("other")
      send(test_pid, {:other_path, other_file})
      Process.sleep(:infinity)
    end)

    assert_receive {:other_path, other_file}

    file = Hexpm.TmpDir.tmp_file("test")
    Hexpm.TmpDir.cleanup()

    refute File.exists?(file)
    assert File.exists?(other_file)
  end

  test "paths persist while process is alive" do
    file = Hexpm.TmpDir.tmp_file("test")
    dir = Hexpm.TmpDir.tmp_dir("test")

    assert File.exists?(file)
    assert File.dir?(dir)
  end
end
