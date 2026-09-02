defmodule Hexpm.Emails.OutboxTest do
  use Hexpm.DataCase
  use Oban.Testing, repo: Hexpm.RepoBase

  import Swoosh.Email, except: [from: 2]

  alias Hexpm.Emails.{Outbox, OutboxEntry, OutboxWorker}

  describe "insert_all!/1" do
    test "inserts the entries and one delivery job per entry" do
      attrs =
        for n <- 1..3 do
          prepared_entry("Bulk #{n}", category: "test.bulk", group_key: "bulk:1", priority: 3)
        end

      assert Outbox.insert_all!(attrs) == 3

      entries = Repo.all(from(entry in OutboxEntry, order_by: entry.id))
      assert Enum.map(entries, & &1.subject) == ["Bulk 1", "Bulk 2", "Bulk 3"]
      assert Enum.map(entries, & &1.category) == ["test.bulk", "test.bulk", "test.bulk"]
      assert Enum.map(entries, & &1.recipients) == List.duplicate(["bob@example.com"], 3)
      assert Enum.all?(entries, & &1.inserted_at)

      jobs = all_enqueued(worker: OutboxWorker)

      assert Enum.sort(Enum.map(jobs, & &1.args["outbox_entry_id"])) ==
               Enum.map(entries, & &1.id)

      assert Enum.map(jobs, & &1.priority) == [3, 3, 3]
    end

    test "inserts more entries than one chunk holds" do
      attrs = List.duplicate(prepared_entry("Bulk", category: "test.bulk"), 1_001)

      assert Outbox.insert_all!(attrs) == 1_001
      assert Repo.aggregate(OutboxEntry, :count) == 1_001
      assert length(all_enqueued(worker: OutboxWorker)) == 1_001
    end

    test "inserts nothing when an entry is invalid" do
      attrs = [
        prepared_entry("Valid", category: "test.bulk"),
        prepared_entry("Invalid", category: "Not A Category")
      ]

      assert_raise Ecto.InvalidChangesetError, fn -> Outbox.insert_all!(attrs) end
      assert Repo.all(OutboxEntry) == []
      assert all_enqueued(worker: OutboxWorker) == []
    end

    test "inserts nothing for an empty list" do
      assert Outbox.insert_all!([]) == 0
      assert Repo.all(OutboxEntry) == []
    end
  end

  describe "insert_all!/1 locking" do
    setup do
      skip = Application.fetch_env!(:hexpm, :skip_advisory_locks)
      Application.put_env(:hexpm, :skip_advisory_locks, false)
      on_exit(fn -> Application.put_env(:hexpm, :skip_advisory_locks, skip) end)
      :ok
    end

    test "takes one advisory lock per group" do
      attrs = [
        prepared_entry("One", category: "test.bulk", group_key: "bulk:1"),
        prepared_entry("Two", category: "test.bulk", group_key: "bulk:1"),
        prepared_entry("Three", category: "test.bulk", group_key: "bulk:2")
      ]

      assert held_outbox_locks() == 0
      Outbox.insert_all!(attrs)
      assert held_outbox_locks() == 2
    end
  end

  describe "cancel!/1 by group key" do
    test "deletes only the named categories in that group" do
      cancelled =
        insert(:email_outbox_entry, group_key: "sso:1:2", category: "sso.identity_linked")

      kept = insert(:email_outbox_entry, group_key: "sso:1:2", category: "sso.identity_unlinked")

      other_group =
        insert(:email_outbox_entry, group_key: "sso:1:3", category: "sso.identity_linked")

      assert Outbox.cancel!(group_key: "sso:1:2", categories: ["sso.identity_linked"]) == 1

      refute Repo.get(OutboxEntry, cancelled.id)
      assert Repo.get(OutboxEntry, kept.id)
      assert Repo.get(OutboxEntry, other_group.id)
    end

    test "leaves a delivered entry in place" do
      delivered =
        insert(:email_outbox_entry,
          group_key: "sso:1:2",
          category: "sso.identity_linked",
          delivered_at: DateTime.utc_now()
        )

      assert Outbox.cancel!(group_key: "sso:1:2", categories: ["sso.identity_linked"]) == 0
      assert Repo.get(OutboxEntry, delivered.id)
    end

    test "deletes nothing when the group has no matching category" do
      entry = insert(:email_outbox_entry, group_key: "sso:1:2", category: "sso.identity_unlinked")

      assert Outbox.cancel!(group_key: "sso:1:2", categories: ["sso.identity_linked"]) == 0
      assert Repo.get(OutboxEntry, entry.id)
    end
  end

  describe "cancel!/1 by scope key" do
    test "spans every group under the scope" do
      first =
        insert(:email_outbox_entry,
          scope_key: "sso:user:7",
          group_key: "sso:1:7",
          category: "sso.identity_linked"
        )

      second =
        insert(:email_outbox_entry,
          scope_key: "sso:user:7",
          group_key: "sso:2:7",
          category: "sso.email_mismatch"
        )

      kept_category =
        insert(:email_outbox_entry,
          scope_key: "sso:user:7",
          group_key: "sso:3:7",
          category: "account.deleted"
        )

      other_scope =
        insert(:email_outbox_entry,
          scope_key: "sso:user:8",
          group_key: "sso:1:8",
          category: "sso.identity_linked"
        )

      assert Outbox.cancel!(
               scope_key: "sso:user:7",
               categories: ["sso.identity_linked", "sso.email_mismatch"]
             ) == 2

      refute Repo.get(OutboxEntry, first.id)
      refute Repo.get(OutboxEntry, second.id)
      assert Repo.get(OutboxEntry, kept_category.id)
      assert Repo.get(OutboxEntry, other_scope.id)
    end

    # Lock ordering across concurrent cancellations is a deadlock property, so
    # it is asserted on real connections in Hexpm.Accounts.SSOConcurrencyTest.
    test "clears every group under the scope" do
      for group <- ["sso:3:9", "sso:1:9", "sso:2:9"] do
        insert(:email_outbox_entry,
          scope_key: "sso:user:9",
          group_key: group,
          category: "sso.identity_linked"
        )
      end

      assert Outbox.cancel!(scope_key: "sso:user:9", categories: ["sso.identity_linked"]) == 3
      refute Repo.exists?(from(entry in OutboxEntry, where: entry.scope_key == "sso:user:9"))
    end
  end

  describe "cancel!/1 locking" do
    setup do
      skip = Application.fetch_env!(:hexpm, :skip_advisory_locks)
      Application.put_env(:hexpm, :skip_advisory_locks, false)
      on_exit(fn -> Application.put_env(:hexpm, :skip_advisory_locks, skip) end)
      :ok
    end

    # The rest of the suite runs with skip_advisory_locks, so without this the
    # lock acquisition could be deleted outright and nothing would notice.
    test "takes one advisory lock per group the scope reaches" do
      for group <- ["sso:1:9", "sso:2:9", "sso:3:9"] do
        insert(:email_outbox_entry,
          scope_key: "sso:user:9",
          group_key: group,
          category: "sso.identity_linked"
        )
      end

      assert held_outbox_locks() == 0
      Outbox.cancel!(scope_key: "sso:user:9", categories: ["sso.identity_linked"])
      assert held_outbox_locks() == 3
    end

    test "takes exactly one advisory lock for a group cancellation" do
      insert(:email_outbox_entry, group_key: "sso:1:2", category: "sso.identity_linked")

      Outbox.cancel!(group_key: "sso:1:2", categories: ["sso.identity_linked"])
      assert held_outbox_locks() == 1
    end

    test "takes no lock for a group whose only entries were delivered" do
      insert(:email_outbox_entry,
        scope_key: "sso:user:9",
        group_key: "sso:1:9",
        category: "sso.identity_linked",
        delivered_at: DateTime.utc_now()
      )

      Outbox.cancel!(scope_key: "sso:user:9", categories: ["sso.identity_linked"])
      assert held_outbox_locks() == 0
    end

    test "takes no lock for a group the categories do not reach" do
      insert(:email_outbox_entry,
        scope_key: "sso:user:9",
        group_key: "sso:1:9",
        category: "account.deleted"
      )

      Outbox.cancel!(scope_key: "sso:user:9", categories: ["sso.identity_linked"])
      assert held_outbox_locks() == 0
    end

    # classid 5 is the :email_outbox advisory lock class in Hexpm.Repo. pg_locks
    # is cluster-wide, so this has to be scoped to our own backend: a dev server
    # on the same cluster mid-cancellation would otherwise be counted, and so
    # would a sibling database under `mix test --partitions`.
    defp held_outbox_locks do
      %{rows: [[count]]} =
        Repo.query!(
          """
          SELECT count(*) FROM pg_locks
          WHERE locktype = 'advisory'
            AND classid = 5
            AND pid = pg_backend_pid()
            AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
          """,
          []
        )

      count
    end
  end

  describe "cancel!/1 argument handling" do
    test "requires exactly one of group key and scope key" do
      assert_raise ArgumentError, ~r/requires group_key or scope_key/, fn ->
        Outbox.cancel!(categories: ["sso.identity_linked"])
      end

      assert_raise ArgumentError, ~r/not both/, fn ->
        Outbox.cancel!(
          group_key: "sso:1:2",
          scope_key: "sso:user:2",
          categories: ["sso.identity_linked"]
        )
      end
    end

    test "requires categories" do
      assert_raise ArgumentError, ~r/requires categories/, fn ->
        Outbox.cancel!(group_key: "sso:1:2")
      end
    end

    test "rejects unknown options" do
      assert_raise ArgumentError, ~r/unknown email outbox options/, fn ->
        Outbox.cancel!(group_key: "sso:1:2", categories: [], expires_at: nil)
      end
    end
  end

  describe "cancel/3" do
    test "runs as a step on the caller's multi and reports the count" do
      entry = insert(:email_outbox_entry, group_key: "sso:1:2", category: "sso.identity_linked")

      assert {:ok, changes} =
               Ecto.Multi.new()
               |> Outbox.cancel(:cancelled,
                 group_key: "sso:1:2",
                 categories: ["sso.identity_linked"]
               )
               |> Repo.transaction()

      assert changes.cancelled == 1
      refute Repo.get(OutboxEntry, entry.id)
    end

    test "a later failing step puts the cancelled mail back" do
      entry = insert(:email_outbox_entry, group_key: "sso:1:2", category: "sso.identity_linked")

      assert {:error, :boom, _value, _changes} =
               Ecto.Multi.new()
               |> Outbox.cancel(:cancelled,
                 group_key: "sso:1:2",
                 categories: ["sso.identity_linked"]
               )
               |> Ecto.Multi.run(:boom, fn _repo, _changes -> {:error, :boom} end)
               |> Repo.transaction()

      assert Repo.get(OutboxEntry, entry.id)
    end
  end

  defp prepared_entry(subject, opts) do
    new()
    |> Swoosh.Email.from({"Hex.pm", "noreply@hex.pm"})
    |> to("bob@example.com")
    |> subject(subject)
    |> text_body("Body")
    |> Outbox.prepare!(opts)
  end
end
