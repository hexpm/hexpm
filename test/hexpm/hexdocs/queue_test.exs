defmodule Hexpm.Hexdocs.QueueTest do
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Hexdocs.Queue
  alias Hexpm.Hexdocs.Workers

  test "acknowledges S3 test events without inserting jobs" do
    assert %{status: :ok} = handle(%{"Event" => "s3:TestEvent"})
    assert all_enqueued() == []
  end

  test "inserts public create jobs transactionally" do
    data = %{
      "Records" => [created("docs%2Fdemo-1.0.0.tar.gz")]
    }

    assert %{status: :ok} = handle(data)

    assert_enqueued(
      worker: Workers.Upload,
      args: %{key: "docs/demo-1.0.0.tar.gz", generation: "0001"}
    )

    assert_enqueued(
      worker: Workers.Search,
      args: %{key: "docs/demo-1.0.0.tar.gz", generation: "0001"}
    )
  end

  test "inserts private uploads without search and removal jobs" do
    key = "repos/org/docs/demo-1.0.0.tar.gz"
    assert %{status: :ok} = handle(%{"Records" => [created(key)]})

    assert_enqueued(worker: Workers.Upload, args: %{key: key, generation: "0001"})
    refute_enqueued(worker: Workers.Search)

    assert %{status: :ok} = handle(%{"Records" => [removed("docs/demo-1.0.0.tar.gz")]})

    assert_enqueued(
      worker: Workers.Delete,
      args: %{key: "docs/demo-1.0.0.tar.gz", generation: "0001"}
    )
  end

  test "keeps distinct object generations for the same key" do
    key = "docs/demo-1.0.0.tar.gz"

    assert %{status: :ok} = handle(%{"Records" => [created(key, "0001")]})
    assert %{status: :ok} = handle(%{"Records" => [created(key, "0002")]})

    assert_enqueued(worker: Workers.Upload, args: %{key: key, generation: "0001"})
    assert_enqueued(worker: Workers.Upload, args: %{key: key, generation: "0002"})
    assert_enqueued(worker: Workers.Search, args: %{key: key, generation: "0001"})
    assert_enqueued(worker: Workers.Search, args: %{key: key, generation: "0002"})
    assert length(all_enqueued()) == 4
  end

  test "uses each available object generation field before the message id" do
    records = [
      record("ObjectCreated:Put", %{
        "key" => "docs/demo-1.0.0.tar.gz",
        "versionId" => "version-id"
      }),
      record("ObjectCreated:Put", %{"key" => "docs/demo-2.0.0.tar.gz", "eTag" => "etag"}),
      record("ObjectCreated:Put", %{"key" => "docs/demo-3.0.0.tar.gz"})
    ]

    assert %{status: :ok} = handle(%{"Records" => records})

    assert_enqueued(
      worker: Workers.Upload,
      args: %{key: "docs/demo-1.0.0.tar.gz", generation: "version-id"}
    )

    assert_enqueued(
      worker: Workers.Upload,
      args: %{key: "docs/demo-2.0.0.tar.gz", generation: "etag"}
    )

    assert_enqueued(
      worker: Workers.Upload,
      args: %{key: "docs/demo-3.0.0.tar.gz", generation: "message-1"}
    )
  end

  test "supports custom upload, search, and sitemap messages" do
    for {event, worker} <- [
          {"hexdocs:upload", Workers.Upload},
          {"hexdocs:search", Workers.Search},
          {"hexdocs:sitemap", Workers.Sitemap}
        ] do
      assert %{status: :ok} = handle(%{event => "docs/demo-1.0.0.tar.gz"})
      assert [%{args: args}] = all_enqueued(worker: worker)
      assert args == %{"key" => "docs/demo-1.0.0.tar.gz"}
    end
  end

  test "fails the whole message before inserting any jobs when a record is invalid" do
    data = %{"Records" => [created("docs/demo-1.0.0.tar.gz"), %{"eventName" => "unknown"}]}
    assert %{status: {:failed, {:unsupported_s3_record, _record}}} = handle(data)
    assert all_enqueued() == []
  end

  test "fails malformed S3 object payloads" do
    data = %{"Records" => [%{"eventName" => "ObjectCreated:Put", "s3" => %{"object" => %{}}}]}

    assert %{status: {:failed, {:malformed_s3_object, _s3}}} = handle(data)
    assert all_enqueued() == []
  end

  test "redelivery reuses unique incomplete jobs" do
    data = %{"Records" => [created("docs/demo-1.0.0.tar.gz")]}
    assert %{status: :ok} = handle(data)
    assert %{status: :ok} = handle(data)
    assert length(all_enqueued()) == 2
  end

  defp handle(data) do
    message = %Broadway.Message{
      data: JSON.encode!(data),
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
    %{"eventName" => event, "s3" => %{"object" => object}}
  end
end
