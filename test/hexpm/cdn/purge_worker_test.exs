defmodule Hexpm.CDN.PurgeWorkerTest do
  # Swaps the global CDN implementation for a mock.
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.CDN
  alias Hexpm.CDN.PurgeWorker

  setup :verify_on_exit!

  setup do
    original = Application.fetch_env!(:hexpm, :cdn_impl)
    Application.put_env(:hexpm, :cdn_impl, Hexpm.CDN.Mock)
    on_exit(fn -> Application.put_env(:hexpm, :cdn_impl, original) end)
    :ok
  end

  defp target(url, etag \\ "abc", write \\ 1),
    do: %{"url" => url, "etag" => etag, "write" => write}

  describe "purge/3" do
    test "enqueues a purge job with the keys and verification targets" do
      CDN.purge(:fastly_hexrepo, ["a", "b", "a"], verify: [%{url: "https://r/x", etag: "e"}])

      assert_enqueued(
        worker: PurgeWorker,
        queue: :purge,
        args: %{
          "service" => "fastly_hexrepo",
          "keys" => ["a", "b"],
          "verify" => [%{"url" => "https://r/x", "etag" => "e"}]
        }
      )
    end
  end

  describe "perform/1" do
    test "purges twice and verifies every target" do
      expect(Hexpm.CDN.Mock, :purge_key, 2, fn :fastly_hexrepo, ["k"] -> :ok end)

      expect(Hexpm.CDN.Mock, :verify, fn :fastly_hexrepo,
                                         [
                                           %{url: "https://r/a", etag: "abc"} = a,
                                           %{url: "https://r/b", etag: nil} = b
                                         ] ->
        [{a, :ok}, {b, :ok}]
      end)

      args = %{
        "service" => "fastly_hexrepo",
        "keys" => ["k"],
        "verify" => [target("https://r/a"), target("https://r/b", nil)]
      }

      assert :ok = perform_job(PurgeWorker, args)
    end

    test "purges again while a target still serves the old object" do
      expect(Hexpm.CDN.Mock, :purge_key, 4, fn :fastly_hexrepo, ["k"] -> :ok end)

      expect(Hexpm.CDN.Mock, :verify, fn _service, [%{url: "https://r/a"} = a] ->
        [{a, {:error, {:stale, [%{pop: :nearest, served: {:write, 0}, cache: "x-cache: HIT"}]}}}]
      end)

      expect(Hexpm.CDN.Mock, :verify, fn _service, [%{url: "https://r/a"} = a] -> [{a, :ok}] end)

      args = %{
        "service" => "fastly_hexrepo",
        "keys" => ["k"],
        "verify" => [target("https://r/a")]
      }

      assert :ok = perform_job(PurgeWorker, args)
    end

    test "raises after the configured rounds so the job retries and Sentry hears of it" do
      expect(Hexpm.CDN.Mock, :purge_key, 6, fn :fastly_hexrepo, ["k"] -> :ok end)

      expect(Hexpm.CDN.Mock, :verify, 3, fn _service, [%{url: "https://r/a"} = a] ->
        [{a, {:error, {:stale, [%{pop: :nearest, served: {:write, 0}, cache: "x-cache: HIT"}]}}}]
      end)

      args = %{
        "service" => "fastly_hexrepo",
        "keys" => ["k"],
        "verify" => [target("https://r/a")]
      }

      assert_raise Hexpm.CDN.PurgeVerificationError,
                   ~r/https:\/\/r\/a expected write 1: nearest serves write 0 \(x-cache: HIT\)/,
                   fn -> perform_job(PurgeWorker, args) end
    end

    test "returns the purge error so the job retries" do
      expect(Hexpm.CDN.Mock, :purge_key, fn :fastly_hexrepo, ["k"] ->
        {:error, {:status, 503, "unavailable"}}
      end)

      args = %{"service" => "fastly_hexrepo", "keys" => ["k"], "verify" => []}
      assert {:error, {:status, 503, "unavailable"}} = perform_job(PurgeWorker, args)
    end

    test "absorbs the queued jobs for the same service" do
      CDN.purge(:fastly_hexrepo, ["a"], verify: [%{url: "https://r/a", etag: "1"}])
      CDN.purge(:fastly_hexrepo, ["b"], verify: [%{url: "https://r/b", etag: "2"}])
      CDN.purge(:fastly_hexdocs, ["c"])

      expect(Hexpm.CDN.Mock, :purge_key, 2, fn :fastly_hexrepo, ["a", "b"] -> :ok end)

      expect(Hexpm.CDN.Mock, :verify, fn _service,
                                         [
                                           %{url: "https://r/a", etag: "1"} = a,
                                           %{url: "https://r/b", etag: "2"} = b
                                         ] ->
        [{a, :ok}, {b, :ok}]
      end)

      expect(Hexpm.CDN.Mock, :purge_key, 2, fn :fastly_hexdocs, ["c"] -> :ok end)

      assert %{success: 2, failure: 0} =
               Oban.drain_queue(queue: :purge, with_limit: 1, with_recursion: true)

      assert [%{args: %{"keys" => ["b"]}}] = jobs("cancelled")

      assert [%{args: %{"keys" => ["a", "b"], "absorbed" => 1}}, %{args: %{"keys" => ["c"]}}] =
               jobs("completed")
    end

    test "keeps the latest write when absorbed jobs wrote the same object" do
      CDN.purge(:fastly_hexrepo, ["a"], verify: [%{url: "https://r/a", etag: "1", write: 1}])
      CDN.purge(:fastly_hexrepo, ["a"], verify: [%{url: "https://r/a", etag: "2", write: 2}])

      expect(Hexpm.CDN.Mock, :purge_key, 2, fn :fastly_hexrepo, ["a"] -> :ok end)

      expect(Hexpm.CDN.Mock, :verify, fn _service, [%{url: "https://r/a", write: 2} = a] ->
        [{a, :ok}]
      end)

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(queue: :purge, with_limit: 1, with_recursion: true)

      assert [%{args: %{"verify" => [%{"url" => "https://r/a", "etag" => "2", "write" => 2}]}}] =
               jobs("completed")
    end

    test "keeps its own target over an absorbed older write of the same object" do
      # A retried job comes back available behind newer ones, so the newer
      # job absorbs it although its write is older.
      CDN.purge(:fastly_hexrepo, ["a"], verify: [%{url: "https://r/a", etag: "2", write: 2}])
      CDN.purge(:fastly_hexrepo, ["a"], verify: [%{url: "https://r/a", etag: "1", write: 1}])

      expect(Hexpm.CDN.Mock, :purge_key, 2, fn :fastly_hexrepo, ["a"] -> :ok end)

      expect(Hexpm.CDN.Mock, :verify, fn _service, [%{url: "https://r/a", write: 2} = a] ->
        [{a, :ok}]
      end)

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(queue: :purge, with_limit: 1, with_recursion: true)

      assert [%{args: %{"verify" => [%{"url" => "https://r/a", "etag" => "2", "write" => 2}]}}] =
               jobs("completed")
    end

    test "drops a content target answered 404 when a newer deletion job exists" do
      {:ok, older} =
        Repo.insert(
          PurgeWorker.new(%{
            "service" => "fastly_hexrepo",
            "keys" => ["a"],
            "verify" => [target("https://r/a", "abc", 1)]
          })
        )

      Oban.insert!(
        PurgeWorker.new(
          %{
            "service" => "fastly_hexrepo",
            "keys" => ["a"],
            "verify" => [target("https://r/a", nil, 2)]
          },
          schedule_in: 60
        )
      )

      expect(Hexpm.CDN.Mock, :purge_key, 2, fn :fastly_hexrepo, ["a"] -> :ok end)

      expect(Hexpm.CDN.Mock, :verify, fn _service, [%{url: "https://r/a", write: 1} = a] ->
        [{a, {:error, {:status, 404, nil}}}]
      end)

      assert :ok = PurgeWorker.perform(older)
    end

    test "drops a stale target judged by ETag when a newer job for its URL exists" do
      {:ok, older} =
        Repo.insert(
          PurgeWorker.new(%{
            "service" => "fastly_hexrepo",
            "keys" => ["a"],
            "verify" => [target("https://r/a", "1", 1)]
          })
        )

      Oban.insert!(
        PurgeWorker.new(
          %{
            "service" => "fastly_hexrepo",
            "keys" => ["a"],
            "verify" => [target("https://r/a", "2", 2)]
          },
          schedule_in: 60
        )
      )

      expect(Hexpm.CDN.Mock, :purge_key, 2, fn :fastly_hexrepo, ["a"] -> :ok end)

      expect(Hexpm.CDN.Mock, :verify, fn _service, [%{url: "https://r/a", write: 1} = a] ->
        [{a, {:error, {:stale, [%{pop: :nearest, served: {:etag, "2"}, cache: nil}]}}}]
      end)

      assert :ok = PurgeWorker.perform(older)
    end

    test "purges again on a 404 that no newer job explains" do
      expect(Hexpm.CDN.Mock, :purge_key, 4, fn :fastly_hexrepo, ["k"] -> :ok end)

      expect(Hexpm.CDN.Mock, :verify, fn _service, [%{url: "https://r/a"} = a] ->
        [{a, {:error, {:status, 404, "x-cache: HIT"}}}]
      end)

      expect(Hexpm.CDN.Mock, :verify, fn _service, [%{url: "https://r/a"} = a] -> [{a, :ok}] end)

      args = %{
        "service" => "fastly_hexrepo",
        "keys" => ["k"],
        "verify" => [target("https://r/a")]
      }

      assert :ok = perform_job(PurgeWorker, args)
    end

    test "checks its target even when a newer job for the same URL is queued" do
      {:ok, older} =
        Repo.insert(
          PurgeWorker.new(%{
            "service" => "fastly_hexrepo",
            "keys" => ["a"],
            "verify" => [target("https://r/a", "1", 1)]
          })
        )

      Oban.insert!(
        PurgeWorker.new(
          %{
            "service" => "fastly_hexrepo",
            "keys" => ["a"],
            "verify" => [target("https://r/a", "2", 2)]
          },
          schedule_in: 60
        )
      )

      expect(Hexpm.CDN.Mock, :purge_key, 2, fn :fastly_hexrepo, ["a"] -> :ok end)

      expect(Hexpm.CDN.Mock, :verify, fn _service, [%{url: "https://r/a", write: 1} = a] ->
        [{a, :ok}]
      end)

      assert :ok = PurgeWorker.perform(older)
    end
  end

  describe "next_write/0" do
    test "increases with every call" do
      first = CDN.next_write()
      assert is_integer(first)
      assert CDN.next_write() > first
    end
  end

  defp jobs(state) do
    Repo.all(
      from(j in Oban.Job,
        where: j.worker == "Hexpm.CDN.PurgeWorker" and j.state == ^state,
        order_by: j.id
      )
    )
  end
end
