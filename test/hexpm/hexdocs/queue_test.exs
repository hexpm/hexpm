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
    assert_enqueued(worker: Workers.Upload, args: %{key: "docs/demo-1.0.0.tar.gz"})
    assert_enqueued(worker: Workers.Search, args: %{key: "docs/demo-1.0.0.tar.gz"})
  end

  test "inserts private uploads without search and removal jobs" do
    assert %{status: :ok} =
             handle(%{"Records" => [created("repos/org/docs/demo-1.0.0.tar.gz")]})

    assert_enqueued(worker: Workers.Upload)
    refute_enqueued(worker: Workers.Search)

    assert %{status: :ok} = handle(%{"Records" => [removed("docs/demo-1.0.0.tar.gz")]})
    assert_enqueued(worker: Workers.Delete)
  end

  test "supports custom upload, search, and sitemap messages" do
    for {event, worker} <- [
          {"hexdocs:upload", Workers.Upload},
          {"hexdocs:search", Workers.Search},
          {"hexdocs:sitemap", Workers.Sitemap}
        ] do
      assert %{status: :ok} = handle(%{event => "docs/demo-1.0.0.tar.gz"})
      assert_enqueued(worker: worker)
    end
  end

  test "fails the whole message before inserting any jobs when a record is invalid" do
    data = %{"Records" => [created("docs/demo-1.0.0.tar.gz"), %{"eventName" => "unknown"}]}
    assert %{status: {:failed, {:unsupported_s3_record, _record}}} = handle(data)
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
      acknowledger: {Broadway.NoopAcknowledger, nil, nil}
    }

    Queue.handle_message(:default, message, %{})
  end

  defp created(key), do: record("ObjectCreated:Put", key)
  defp removed(key), do: record("ObjectRemoved:Delete", key)
  defp record(event, key), do: %{"eventName" => event, "s3" => %{"object" => %{"key" => key}}}
end
