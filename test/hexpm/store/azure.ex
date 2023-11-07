defmodule Hexpm.Store.AzureTest do
  @moduledoc """
  Note that these are integration tests that run against azurite.
  Probably not a good idea to run them unless you have to. 
  """
  use ExUnit.Case
  @moduletag :integration

  alias Azurex.Blob
  alias Hexpm.Store.Azure

  @num_blobs 10
  setup_all do
    bucket = random_string(10)

    Blob.Container.create(bucket)
    %{bucket: bucket}
  end

  describe "list/2" do
    setup do
      bucket = random_string(10)
      seed_bucket(bucket, @num_blobs)

      # Override bucket to not clobber other tests
      %{bucket: bucket}
    end

    test "lists all blobs in the container, even if there are more than the maximum for one request", %{bucket: bucket} do
      assert bucket
        |> Azure.list(nil)
        |> Enum.to_list()
        |> length() == @num_blobs
    end
  end

  describe "get/3" do
    test "gets a blob", %{bucket: bucket} do
      key = random_string(10)
      Blob.put_blob(key, "test", nil, bucket)
      assert {:ok, "test"} = Azurex.Blob.get_blob(key, bucket)
    end
  end

  describe "put/4" do
  	test "puts a blob", %{bucket: bucket} do
      key = random_string(10)
    	Azure.put(bucket, key, "test", [])
      assert {:ok, "test"} = Azurex.Blob.get_blob(key, bucket)
    end
  end

  describe "delete/2" do
    test "deletes a blob", %{bucket: bucket} do
      key = random_string(10)
      Blob.put_blob(key, "test", nil, bucket)
      assert {:ok, [_ | _]} = Blob.head_blob(key, bucket)
      Azure.delete(bucket, key)
      assert {:error, :not_found} = Blob.head_blob(key, bucket)
    end
  end


  describe "delete_many/2" do
    setup do
      bucket = random_string(10)
      key_names = seed_bucket(bucket, @num_blobs)

      # Override bucket to not clobber other tests
      %{bucket: bucket, key_names: key_names}
    end

    test "deletes all keys given, leaves others untouched", %{bucket: bucket, key_names: key_names} do
      num_blobs = fn -> bucket |> Azure.list(nil) |> Enum.to_list() |> length() end
      assert num_blobs.() == @num_blobs
      extra_key = random_string(10) 
      :ok = Blob.put_blob(extra_key, random_string(10), nil, bucket)
      Azure.delete_many(bucket, key_names)
      assert num_blobs.() == 1
      assert {:ok, _meta} = Blob.head_blob(extra_key, bucket)
    end
  end

  defp random_string(len) do
    ?a..?z
    |> Enum.to_list()
    |> Enum.concat('-')
    |> Enum.take_random(len)
    |> IO.chardata_to_string()
    |> String.trim("-")
  end

  defp seed_bucket(bucket, num_seeds) do
      Blob.Container.create(bucket)
      key_names = for _ <- 1..num_seeds, do: random_string(5)
      Enum.each(key_names, &Blob.put_blob(&1, random_string(10), nil, bucket))
      key_names
  end
end
