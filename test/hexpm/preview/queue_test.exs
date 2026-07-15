defmodule Hexpm.Preview.QueueTest do
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Preview.Queue
  alias Hexpm.Preview.Workers

  test "acknowledges S3 test events without inserting jobs" do
    assert %{status: :ok} = handle(%{"Event" => "s3:TestEvent"})
    assert all_enqueued() == []
  end

  test "inserts create and removal jobs" do
    assert %{status: :ok} = handle(%{"Records" => [created("tarballs%2Fdemo-1.0.0.tar")]})

    assert_enqueued(
      worker: Workers.Upload,
      args: %{key: "tarballs/demo-1.0.0.tar", generation: "0001"}
    )

    assert %{status: :ok} = handle(%{"Records" => [removed("tarballs/demo-1.0.0.tar")]})

    assert_enqueued(
      worker: Workers.Delete,
      args: %{key: "tarballs/demo-1.0.0.tar", generation: "0001"}
    )
  end

  test "inserts every record in one transaction and reuses unique incomplete jobs" do
    data = %{
      "Records" => [
        created("tarballs/demo-1.0.0.tar"),
        created("tarballs/demo-2.0.0.tar")
      ]
    }

    assert %{status: :ok} = handle(data)
    assert %{status: :ok} = handle(data)
    assert length(all_enqueued()) == 2
  end

  test "keeps distinct object generations for the same key" do
    key = "tarballs/demo-1.0.0.tar"

    assert %{status: :ok} = handle(%{"Records" => [created(key, "0001")]})
    assert %{status: :ok} = handle(%{"Records" => [created(key, "0002")]})

    assert_enqueued(worker: Workers.Upload, args: %{key: key, generation: "0001"})
    assert_enqueued(worker: Workers.Upload, args: %{key: key, generation: "0002"})
    assert length(all_enqueued()) == 2
  end

  test "uses each available object generation field before the message id" do
    records = [
      record("ObjectCreated:Put", %{
        "key" => "tarballs/demo-1.0.0.tar",
        "versionId" => "version-id"
      }),
      record("ObjectCreated:Put", %{
        "key" => "tarballs/demo-2.0.0.tar",
        "eTag" => "etag"
      }),
      record("ObjectCreated:Put", %{"key" => "tarballs/demo-3.0.0.tar"})
    ]

    assert %{status: :ok} = handle(%{"Records" => records})

    assert_enqueued(
      worker: Workers.Upload,
      args: %{key: "tarballs/demo-1.0.0.tar", generation: "version-id"}
    )

    assert_enqueued(
      worker: Workers.Upload,
      args: %{key: "tarballs/demo-2.0.0.tar", generation: "etag"}
    )

    assert_enqueued(
      worker: Workers.Upload,
      args: %{key: "tarballs/demo-3.0.0.tar", generation: "message-1"}
    )
  end

  test "does not insert any jobs when one record is malformed" do
    data = %{"Records" => [created("tarballs/demo-1.0.0.tar"), %{"eventName" => "unknown"}]}

    assert %{status: {:failed, {:unsupported_s3_record, _record}}} = handle(data)
    assert all_enqueued() == []
  end

  test "leaves the message retryable when the insertion transaction fails" do
    original = Application.get_env(:hexpm, :read_only_mode, false)
    Application.put_env(:hexpm, :read_only_mode, true)
    on_exit(fn -> Application.put_env(:hexpm, :read_only_mode, original) end)

    assert %{status: {:failed, %Hexpm.WriteInReadOnlyMode{}}} =
             handle(%{"Records" => [created("tarballs/demo-1.0.0.tar")]})

    assert all_enqueued() == []
  end

  test "acknowledges unrelated object keys without inserting jobs" do
    assert %{status: :ok} = handle(%{"Records" => [created("docs/demo-1.0.0.tar.gz")]})
    assert all_enqueued() == []
  end

  test "fails malformed S3 object payloads" do
    data = %{"Records" => [%{"eventName" => "ObjectCreated:Put", "s3" => %{"object" => %{}}}]}

    assert %{status: {:failed, {:malformed_s3_object, _s3}}} = handle(data)
    assert all_enqueued() == []
  end

  test "fails malformed JSON and unsupported messages" do
    assert %{status: {:failed, %Jason.DecodeError{}}} = handle_raw("not-json")
    assert %{status: {:failed, {:unsupported_preview_message, %{}}}} = handle(%{})

    assert %{status: {:failed, {:unsupported_preview_message, _message}}} =
             handle(%{"preview:sitemap" => "tarballs/demo-1.0.0.tar"})
  end

  defp handle(data), do: data |> Jason.encode!() |> handle_raw()

  defp handle_raw(data) do
    message = %Broadway.Message{
      data: data,
      metadata: %{message_id: "message-1"},
      acknowledger: {Broadway.NoopAcknowledger, nil, nil}
    }

    Queue.handle_message(:default, message, %{})
  end

  defp created(key, generation \\ "0001"), do: record("ObjectCreated:Put", key, generation)
  defp removed(key, generation \\ "0001"), do: record("ObjectRemoved:Delete", key, generation)

  defp record(event, key, generation) do
    record(event, %{"key" => key, "sequencer" => generation})
  end

  defp record(event, object) do
    %{
      "eventName" => event,
      "s3" => %{"object" => object}
    }
  end
end
