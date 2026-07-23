defmodule Hexpm.Emails.OutboxWorkerTest do
  use Hexpm.DataCase
  use Oban.Testing, repo: Hexpm.RepoBase

  import Swoosh.Email, except: [from: 2]
  import Swoosh.TestAssertions

  alias Hexpm.Emails
  alias Hexpm.Emails.{Outbox, OutboxEntry, OutboxReconciler, OutboxWorker}

  setup do
    mailer_config = Application.fetch_env!(:hexpm, Emails.Mailer)
    on_exit(fn -> Application.put_env(:hexpm, Emails.Mailer, mailer_config) end)
    %{mailer_config: mailer_config}
  end

  test "delivers a rendered email through Swoosh.Adapters.Test and deletes it" do
    assert Application.fetch_env!(:hexpm, Emails.Mailer)[:adapter] == Swoosh.Adapters.Test

    email = rendered_email("Rendered email")
    entry = Outbox.enqueue!(email, category: "test.rendered")
    persisted_email = OutboxEntry.to_email(entry)

    assert persisted_email == %{email | private: %{}, assigns: %{}}
    assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: entry.id})
    assert_email_sent(persisted_email)
    refute Repo.get(OutboxEntry, entry.id)
  end

  test "delivers each SSO security notification to every snapshotted address" do
    for {email, category, subject} <- [
          {Emails.sso_identity_linked("acme", "user", ["one@example.com", "two@example.com"]),
           "sso.identity_linked", "Hex.pm - Organization SSO connected"},
          {Emails.sso_identity_unlinked("acme", "user", ["one@example.com", "two@example.com"]),
           "sso.identity_unlinked", "Hex.pm - Organization SSO disconnected"},
          {Emails.sso_email_mismatch(
             "acme",
             "user",
             ["one@example.com", "two@example.com"],
             "person@idp.example"
           ), "sso.email_mismatch", "Hex.pm - Organization SSO email differs"}
        ] do
      entry = Outbox.enqueue!(email, category: category, ordering_key: "sso:1:2")

      assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: entry.id})

      assert_email_sent(
        subject: subject,
        to: ["one@example.com", "two@example.com"]
      )

      refute Repo.get(OutboxEntry, entry.id)
    end
  end

  test "a Swoosh adapter error keeps the rendered email retryable", context do
    email = rendered_email("Retry this email")
    entry = Outbox.enqueue!(email, category: "test.retry")
    persisted_email = OutboxEntry.to_email(entry)

    Application.put_env(
      :hexpm,
      Emails.Mailer,
      context.mailer_config
      |> Keyword.put(:adapter, Emails.FailingAdapter)
      |> Keyword.put(:test_pid, self())
    )

    assert_raise Swoosh.DeliveryError, "delivery error: :mail_unavailable", fn ->
      perform_job(OutboxWorker, %{outbox_entry_id: entry.id})
    end

    assert_receive {:delivery_attempt, ^persisted_email}
    assert Repo.get!(OutboxEntry, entry.id)

    Application.put_env(:hexpm, Emails.Mailer, context.mailer_config)

    assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: entry.id})
    assert_email_sent(persisted_email)
    refute Repo.get(OutboxEntry, entry.id)
  end

  test "only the stream head has a job and failures never skip it", context do
    linked =
      Outbox.enqueue!(rendered_email("Linked"),
        category: "sso.identity_linked",
        ordering_key: "sso:1:2"
      )

    unlinked =
      Outbox.enqueue!(rendered_email("Unlinked"),
        category: "sso.identity_unlinked",
        ordering_key: "sso:1:2"
      )

    refute delivery_job(unlinked)

    assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: unlinked.id})
    refute_email_sent()

    Application.put_env(
      :hexpm,
      Emails.Mailer,
      context.mailer_config
      |> Keyword.put(:adapter, Emails.FailingAdapter)
      |> Keyword.put(:test_pid, self())
    )

    assert_raise Swoosh.DeliveryError, fn ->
      perform_job(OutboxWorker, %{outbox_entry_id: linked.id})
    end

    assert_receive {:delivery_attempt, %Swoosh.Email{subject: "Linked"}}
    assert Repo.get(OutboxEntry, linked.id)
    assert Repo.get(OutboxEntry, unlinked.id)
    refute_receive {:delivery_attempt, %Swoosh.Email{subject: "Unlinked"}}

    Application.put_env(:hexpm, Emails.Mailer, context.mailer_config)

    assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: linked.id})
    assert_email_sent(subject: "Linked")
    refute Repo.get(OutboxEntry, linked.id)
    assert Repo.get(OutboxEntry, unlinked.id)
    assert delivery_job(unlinked)

    assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: unlinked.id})
    assert_email_sent(subject: "Unlinked")
    refute Repo.get(OutboxEntry, unlinked.id)
  end

  test "missing and expired entries are harmless" do
    assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: -1})
    refute_email_sent()

    expired =
      Outbox.enqueue!(rendered_email("Expired"),
        category: "test.expired",
        expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
      )

    assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: expired.id})
    refute Repo.get(OutboxEntry, expired.id)
    refute_email_sent()
  end

  test "reconciliation purges an expired entry behind a blocked head" do
    head =
      Outbox.enqueue!(rendered_email("Blocked"),
        category: "test.blocked",
        ordering_key: "blocked:1"
      )

    expired =
      Outbox.enqueue!(rendered_email("Expired later"),
        category: "test.expired",
        ordering_key: "blocked:1",
        expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
      )

    assert Repo.get(OutboxEntry, head.id)
    assert Repo.get(OutboxEntry, expired.id)

    assert :ok = perform_job(OutboxReconciler, %{})

    assert Repo.get(OutboxEntry, head.id)
    refute Repo.get(OutboxEntry, expired.id)
  end

  test "the final failed attempt discards the head and unblocks the stream", context do
    head =
      Outbox.enqueue!(rendered_email("Permanent failure"),
        category: "test.permanent",
        ordering_key: "failed:1"
      )

    next =
      Outbox.enqueue!(rendered_email("Next"),
        category: "test.next",
        ordering_key: "failed:1"
      )

    Application.put_env(
      :hexpm,
      Emails.Mailer,
      context.mailer_config
      |> Keyword.put(:adapter, Emails.FailingAdapter)
      |> Keyword.put(:test_pid, self())
    )

    assert_raise Swoosh.DeliveryError, fn ->
      perform_job(
        OutboxWorker,
        %{outbox_entry_id: head.id},
        attempt: OutboxWorker.__opts__()[:max_attempts]
      )
    end

    refute Repo.get(OutboxEntry, head.id)
    assert Repo.get(OutboxEntry, next.id)
    assert delivery_job(next)

    Application.put_env(:hexpm, Emails.Mailer, context.mailer_config)

    assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: next.id})
    assert_email_sent(subject: "Next")
    refute Repo.get(OutboxEntry, next.id)
  end

  test "reconciles a discarded delivery job while its outbox entry remains" do
    entry = Outbox.enqueue!(rendered_email("Reconcile"), category: "test.reconcile")

    discarded =
      Oban.Job
      |> Repo.get_by!(worker: inspect(OutboxWorker), args: %{"outbox_entry_id" => entry.id})
      |> Ecto.Changeset.change(state: "discarded")
      |> Repo.update!()

    assert :ok = perform_job(OutboxReconciler, %{})

    replacement_jobs =
      Oban.Job
      |> Repo.all()
      |> Enum.filter(fn job ->
        job.worker == inspect(OutboxWorker) and
          job.args == %{"outbox_entry_id" => entry.id} and
          job.id != discarded.id
      end)

    assert [%Oban.Job{state: "available"}] = replacement_jobs
    assert Repo.get(OutboxEntry, entry.id)
  end

  test "reconciliation discards a terminal entry and enqueues the next stream entry" do
    for id <- 1..500 do
      job =
        %{outbox_entry_id: -id}
        |> OutboxWorker.new()
        |> Oban.insert!()

      job
      |> Ecto.Changeset.change(
        state: "discarded",
        attempt: job.max_attempts,
        discarded_at: DateTime.utc_now()
      )
      |> Repo.update!()
    end

    terminal =
      Outbox.enqueue!(rendered_email("Terminal"),
        category: "test.terminal",
        ordering_key: "terminal:1"
      )

    next =
      Outbox.enqueue!(rendered_email("After terminal"),
        category: "test.after_terminal",
        ordering_key: "terminal:1"
      )

    terminal_job = delivery_job(terminal)

    terminal_job
    |> Ecto.Changeset.change(
      state: "discarded",
      attempt: terminal_job.max_attempts,
      discarded_at: DateTime.utc_now()
    )
    |> Repo.update!()

    assert :ok = perform_job(OutboxReconciler, %{})

    refute Repo.get(OutboxEntry, terminal.id)
    assert Repo.get(OutboxEntry, next.id)
    assert delivery_job(next)
  end

  test "reconciliation preserves an existing incomplete delivery job" do
    entry = Outbox.enqueue!(rendered_email("Existing"), category: "test.existing")
    existing = delivery_job(entry)

    assert :ok = perform_job(OutboxReconciler, %{})
    assert delivery_job(entry).id == existing.id
  end

  test "suspended jobs do not starve heads with missing jobs during reconciliation" do
    for id <- 1..500 do
      entry = Outbox.enqueue!(rendered_email("Suspended #{id}"), category: "test.suspended")

      entry
      |> delivery_job()
      |> Ecto.Changeset.change(state: "suspended")
      |> Repo.update!()
    end

    missing = Outbox.enqueue!(rendered_email("Missing"), category: "test.missing")
    missing |> delivery_job() |> Repo.delete!()

    assert :ok = perform_job(OutboxReconciler, %{})
    assert %Oban.Job{state: "available"} = delivery_job(missing)
  end

  test "does not enqueue duplicate incomplete jobs for one entry" do
    entry = Outbox.enqueue!(rendered_email("Unique"), category: "test.unique")
    first = delivery_job(entry)
    duplicate = OutboxWorker.enqueue!(entry.id)

    assert duplicate.conflict?
    assert duplicate.id == first.id

    assert [job] =
             Oban.Job
             |> Repo.all()
             |> Enum.filter(fn job ->
               job.worker == inspect(OutboxWorker) and
                 job.args == %{"outbox_entry_id" => entry.id}
             end)

    assert job.id == first.id
  end

  test "enqueue rolls back the outbox entry and delivery job together" do
    parent = self()

    assert {:error, :forced} =
             Repo.transaction(fn ->
               entry = Outbox.enqueue!(rendered_email("Rollback"), category: "test.rollback")
               send(parent, {:rolled_back_entry, entry.id})
               Repo.rollback(:forced)
             end)

    assert_receive {:rolled_back_entry, entry_id}
    refute Repo.get(OutboxEntry, entry_id)

    refute Repo.exists?(
             Ecto.Query.from(job in Oban.Job,
               where: job.worker == ^inspect(OutboxWorker),
               where: job.args == ^%{"outbox_entry_id" => entry_id}
             )
           )
  end

  test "serializes producers that share an ordering key" do
    original = Application.fetch_env!(:hexpm, :skip_advisory_locks)
    Application.put_env(:hexpm, :skip_advisory_locks, false)
    on_exit(fn -> Application.put_env(:hexpm, :skip_advisory_locks, original) end)
    parent = self()

    first =
      Task.async(fn ->
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Hexpm.RepoBase)

        Outbox.enqueue!(rendered_email("First producer"),
          category: "test.first",
          ordering_key: "shared"
        )

        send(parent, :first_enqueued)

        receive do
          :release -> :ok
        end

        Ecto.Adapters.SQL.Sandbox.checkin(Hexpm.RepoBase)
      end)

    assert_receive :first_enqueued

    second =
      Task.async(fn ->
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Hexpm.RepoBase)
        send(parent, :second_started)

        Outbox.enqueue!(rendered_email("Second producer"),
          category: "test.second",
          ordering_key: "shared"
        )

        send(parent, :second_enqueued)
        Ecto.Adapters.SQL.Sandbox.checkin(Hexpm.RepoBase)
      end)

    assert_receive :second_started
    refute_receive :second_enqueued, 100

    send(first.pid, :release)
    assert :ok = Task.await(first)
    assert_receive :second_enqueued
    assert :ok = Task.await(second)
  end

  test "an outbox snapshot remains deliverable after its source record is deleted" do
    user = insert(:user)
    email = Emails.account_deleted(user)
    entry = Outbox.enqueue!(email, category: "account.deleted")
    persisted_email = OutboxEntry.to_email(entry)
    recipient = Hexpm.Accounts.User.email(user, :primary)

    Repo.delete!(user)

    assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: entry.id})
    assert_email_sent(persisted_email)
    assert {_name, ^recipient} = List.first(persisted_email.to)
    refute Repo.get(OutboxEntry, entry.id)
  end

  test "rejects unsupported or malformed email fields and redacts the persisted envelope" do
    email =
      rendered_email("Attachment")
      |> attachment(%Swoosh.Attachment{filename: "secret.txt", data: "secret"})

    changeset =
      OutboxEntry.changeset(%OutboxEntry{}, email, %{
        category: "test.attachment"
      })

    refute changeset.valid?
    assert {"attachments are not supported", _} = changeset.errors[:email]

    invalid_email =
      new()
      |> Swoosh.Email.from("noreply@hex.pm")
      |> text_body("No recipients")

    invalid_changeset =
      OutboxEntry.changeset(%OutboxEntry{}, invalid_email, %{category: "test.invalid"})

    refute invalid_changeset.valid?
    assert {"requires at least one valid recipient", _} = invalid_changeset.errors[:email]

    for {email, message} <- [
          {%{rendered_email("Subject") | subject: nil}, "requires a valid subject"},
          {%{rendered_email("Body") | html_body: %{invalid: true}}, "contains an invalid body"},
          {%{rendered_email("Headers") | headers: [:invalid]}, "contains invalid headers"},
          {%{rendered_email("Private") | private: %{client_options: [receive_timeout: 10_000]}},
           "contains unsupported private delivery options"}
        ] do
      changeset = OutboxEntry.changeset(%OutboxEntry{}, email, %{category: "test.invalid"})
      refute changeset.valid?
      assert {^message, _} = changeset.errors[:email]
    end

    assert :email in OutboxEntry.__schema__(:redact_fields)

    entry = Outbox.enqueue!(rendered_email("Private body"), category: "test.redaction")
    refute inspect(entry) =~ "Private body"
    refute inspect(entry) =~ "recipient@example.com"
  end

  test "rejects unknown enqueue options" do
    assert_raise ArgumentError, "unknown email outbox options: [:order_key]", fn ->
      Outbox.enqueue!(rendered_email("Typo"),
        category: "test.typo",
        order_key: "misspelled"
      )
    end
  end

  defp delivery_job(entry) do
    Repo.get_by(Oban.Job,
      worker: inspect(OutboxWorker),
      args: %{"outbox_entry_id" => entry.id}
    )
  end

  defp rendered_email(subject) do
    new()
    |> Swoosh.Email.from({"Hex.pm", "noreply@hex.pm"})
    |> to([{"Recipient", "recipient@example.com"}, "second@example.com"])
    |> cc({"Carbon Copy", "cc@example.com"})
    |> bcc("bcc@example.com")
    |> reply_to([{"Support", "support@example.com"}, "other@example.com"])
    |> header("X-Test", "outbox")
    |> subject(subject)
    |> text_body("Private body")
    |> html_body("<p>Private body</p>")
    |> put_provider_option(:click_tracking, %{enable: false})
    |> Map.put(:assigns, %{not_persisted: "rendered"})
    |> Map.put(:private, %{
      phoenix_layout: {HexpmWeb.EmailView, :layout},
      phoenix_template: "test.text",
      phoenix_view: HexpmWeb.EmailView
    })
  end
end
