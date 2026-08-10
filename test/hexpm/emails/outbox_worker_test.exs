defmodule Hexpm.Emails.OutboxWorkerTest do
  use Hexpm.DataCase
  use Oban.Testing, repo: Hexpm.RepoBase

  import Swoosh.Email, except: [from: 2]
  import Swoosh.TestAssertions

  alias Hexpm.Emails
  alias Hexpm.Emails.{Outbox, OutboxEntry, OutboxEnvelope, OutboxReconciler, OutboxWorker}

  # The producers report in from a task that checks out a connection and takes
  # an advisory lock first, which the 100ms default does not cover.
  @receive_timeout 10_000

  setup do
    mailer_config = Application.fetch_env!(:hexpm, Emails.Mailer)
    on_exit(fn -> Application.put_env(:hexpm, Emails.Mailer, mailer_config) end)
    %{mailer_config: mailer_config}
  end

  test "delivers a rendered email through Swoosh.Adapters.Test and deletes it" do
    assert Application.fetch_env!(:hexpm, Emails.Mailer)[:adapter] == Swoosh.Adapters.Test

    email = rendered_email("Rendered email")
    entry = Outbox.enqueue!(email, category: "test.rendered")
    persisted_email = OutboxEnvelope.load!(entry.email)

    assert persisted_email == %{email | private: %{}, assigns: %{}}
    assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: entry.id})
    assert_email_sent(delivered(persisted_email, entry))
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
      entry = Outbox.enqueue!(email, category: category, group_key: "sso:1:2")

      assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: entry.id})

      assert_email_sent(
        subject: subject,
        to: ["one@example.com", "two@example.com"]
      )

      refute Repo.get(OutboxEntry, entry.id)
    end
  end

  test "a retry repeats the delivery under the same Message-ID", context do
    email = rendered_email("Retry this email")
    entry = Outbox.enqueue!(email, category: "test.retry")
    delivered_email = delivered(OutboxEnvelope.load!(entry.email), entry)

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

    assert_receive {:delivery_attempt, ^delivered_email}
    assert Repo.get!(OutboxEntry, entry.id)

    Application.put_env(:hexpm, Emails.Mailer, context.mailer_config)

    assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: entry.id})
    assert_email_sent(delivered_email)
    assert delivered_email.headers["Message-ID"] == "<outbox-#{entry.id}@hex.pm>"
    refute Repo.get(OutboxEntry, entry.id)
  end

  test "a failing entry does not hold up another entry in its group", context do
    linked =
      Outbox.enqueue!(rendered_email("Linked"),
        category: "sso.identity_linked",
        group_key: "sso:1:2"
      )

    unlinked =
      Outbox.enqueue!(rendered_email("Unlinked"),
        category: "sso.identity_unlinked",
        group_key: "sso:1:2"
      )

    assert delivery_job(linked)
    assert delivery_job(unlinked)

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

    Application.put_env(:hexpm, Emails.Mailer, context.mailer_config)

    assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: unlinked.id})
    assert_email_sent(subject: "Unlinked")
    refute Repo.get(OutboxEntry, unlinked.id)

    assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: linked.id})
    assert_email_sent(subject: "Linked")
    refute Repo.get(OutboxEntry, linked.id)
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

  test "reconciliation purges an expired entry and leaves its group alone" do
    live =
      Outbox.enqueue!(rendered_email("Live"),
        category: "test.live",
        group_key: "purged:1"
      )

    expired =
      Outbox.enqueue!(rendered_email("Expired later"),
        category: "test.expired",
        group_key: "purged:1",
        expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
      )

    assert Repo.get(OutboxEntry, live.id)
    assert Repo.get(OutboxEntry, expired.id)

    assert :ok = perform_job(OutboxReconciler, %{})

    assert Repo.get(OutboxEntry, live.id)
    refute Repo.get(OutboxEntry, expired.id)
  end

  test "the final failed attempt discards the entry", context do
    permanent =
      Outbox.enqueue!(rendered_email("Permanent failure"),
        category: "test.permanent",
        group_key: "failed:1"
      )

    next =
      Outbox.enqueue!(rendered_email("Next"),
        category: "test.next",
        group_key: "failed:1"
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
        %{outbox_entry_id: permanent.id},
        attempt: OutboxWorker.__opts__()[:max_attempts]
      )
    end

    refute Repo.get(OutboxEntry, permanent.id)
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

  test "reconciliation discards a terminal entry" do
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
        group_key: "terminal:1"
      )

    next =
      Outbox.enqueue!(rendered_email("After terminal"),
        category: "test.after_terminal",
        group_key: "terminal:1"
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

  test "suspended jobs do not starve entries with missing jobs during reconciliation" do
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

  test "serializes producers that share a group key" do
    original = Application.fetch_env!(:hexpm, :skip_advisory_locks)
    Application.put_env(:hexpm, :skip_advisory_locks, false)
    on_exit(fn -> Application.put_env(:hexpm, :skip_advisory_locks, original) end)
    parent = self()

    first =
      Task.async(fn ->
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Hexpm.RepoBase)

        Outbox.enqueue!(rendered_email("First producer"),
          category: "test.first",
          group_key: "shared"
        )

        send(parent, :first_enqueued)

        receive do
          :release -> :ok
        end

        Ecto.Adapters.SQL.Sandbox.checkin(Hexpm.RepoBase)
      end)

    assert_receive :first_enqueued, @receive_timeout

    second =
      Task.async(fn ->
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Hexpm.RepoBase)
        send(parent, :second_started)

        Outbox.enqueue!(rendered_email("Second producer"),
          category: "test.second",
          group_key: "shared"
        )

        send(parent, :second_enqueued)
        Ecto.Adapters.SQL.Sandbox.checkin(Hexpm.RepoBase)
      end)

    assert_receive :second_started, @receive_timeout
    refute_receive :second_enqueued, 100

    send(first.pid, :release)
    assert :ok = Task.await(first)
    assert_receive :second_enqueued, @receive_timeout
    assert :ok = Task.await(second)
  end

  test "an outbox snapshot remains deliverable after its source record is deleted" do
    user = insert(:user)
    email = Emails.account_deleted(user)
    entry = Outbox.enqueue!(email, category: "account.deleted")
    persisted_email = OutboxEnvelope.load!(entry.email)
    recipient = Hexpm.Accounts.User.email(user, :primary)

    Repo.delete!(user)

    assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: entry.id})
    assert_email_sent(delivered(persisted_email, entry))
    assert {_name, ^recipient} = List.first(persisted_email.to)
    refute Repo.get(OutboxEntry, entry.id)
  end

  test "rejects emails that are not safely deliverable and redacts the persisted envelope" do
    email =
      rendered_email("Attachment")
      |> attachment(%Swoosh.Attachment{filename: "secret.txt", data: "secret"})

    for {email, message} <- [
          {email, "email outbox does not support attachments"},
          {%{rendered_email("Sender") | from: nil}, "email outbox requires a sender"},
          {%{rendered_email("Recipient") | to: [], cc: [], bcc: []},
           "email outbox requires a recipient"},
          {%{rendered_email("Rendering") | text_body: nil, html_body: nil},
           "email outbox requires a rendered body"},
          {%{rendered_email("Private") | private: %{client_options: [receive_timeout: 10_000]}},
           "email outbox does not support private delivery options"},
          {%{rendered_email("Provider") | provider_options: %{unknown: true}},
           "email outbox does not support these provider options"}
        ] do
      assert_raise ArgumentError, message, fn ->
        Outbox.enqueue!(email, category: "test.invalid")
      end
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

  defp delivered(email, entry) do
    header(email, "Message-ID", "<outbox-#{entry.id}@hex.pm>")
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
