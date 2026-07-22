defmodule Hexpm.Emails.SSONotificationWorkerTest do
  use Hexpm.DataCase
  use Oban.Testing, repo: Hexpm.RepoBase

  import Swoosh.TestAssertions

  alias Hexpm.Accounts.SSO.Notification
  alias Hexpm.Emails.Delivery
  alias Hexpm.Emails.SSONotificationReconciler
  alias Hexpm.Emails.SSONotificationWorker

  setup :verify_on_exit!

  test "delivers each SSO security notification and deletes its outbox record" do
    context = notification_context()

    for {kind, provider_email, subject} <- [
          {"identity_linked", nil, "Hex.pm - Organization SSO connected"},
          {"identity_unlinked", nil, "Hex.pm - Organization SSO disconnected"},
          {"email_mismatch", "person@idp.example", "Hex.pm - Organization SSO email differs"}
        ] do
      notification = insert_notification(context, kind, provider_email)

      assert :ok =
               perform_job(SSONotificationWorker, %{notification_id: notification.id})

      refute Repo.get(Notification, notification.id)
      assert_email_sent(subject: subject)
    end
  end

  test "keeps notification data and its job retryable after delivery fails" do
    original = Application.get_env(:hexpm, :sso_mailer_impl)
    Application.put_env(:hexpm, :sso_mailer_impl, Delivery.Mock)

    on_exit(fn ->
      if original do
        Application.put_env(:hexpm, :sso_mailer_impl, original)
      else
        Application.delete_env(:hexpm, :sso_mailer_impl)
      end
    end)

    notification = notification_context() |> insert_notification("identity_linked", nil)

    job =
      %{notification_id: notification.id}
      |> SSONotificationWorker.new()
      |> Oban.insert!()

    expect(Delivery.Mock, :deliver!, fn _email -> raise "mail unavailable" end)

    assert_raise RuntimeError, "mail unavailable", fn ->
      perform_job(SSONotificationWorker, %{notification_id: notification.id})
    end

    assert Repo.get!(Notification, notification.id)
    assert Repo.get!(Oban.Job, job.id).state == "available"

    expect(Delivery.Mock, :deliver!, fn _email -> :ok end)
    assert :ok = perform_job(SSONotificationWorker, %{notification_id: notification.id})
    refute Repo.get(Notification, notification.id)
  end

  test "delivers lifecycle notifications in creation order" do
    original = Application.get_env(:hexpm, :sso_mailer_impl)
    Application.put_env(:hexpm, :sso_mailer_impl, Delivery.Mock)

    on_exit(fn ->
      if original do
        Application.put_env(:hexpm, :sso_mailer_impl, original)
      else
        Application.delete_env(:hexpm, :sso_mailer_impl)
      end
    end)

    context = notification_context()
    linked = insert_notification(context, "identity_linked", nil)
    unlinked = insert_notification(context, "identity_unlinked", nil)
    parent = self()

    expect(Delivery.Mock, :deliver!, fn email ->
      send(parent, {:delivered, email.subject})
      :ok
    end)

    assert {:snooze, 1} =
             perform_job(SSONotificationWorker, %{notification_id: unlinked.id})

    assert_receive {:delivered, "Hex.pm - Organization SSO connected"}
    refute Repo.get(Notification, linked.id)
    assert Repo.get(Notification, unlinked.id)

    expect(Delivery.Mock, :deliver!, fn email ->
      send(parent, {:delivered, email.subject})
      :ok
    end)

    assert :ok = perform_job(SSONotificationWorker, %{notification_id: unlinked.id})
    assert_receive {:delivered, "Hex.pm - Organization SSO disconnected"}
    refute Repo.get(Notification, unlinked.id)
  end

  test "reconciles a discarded delivery job while its outbox record remains" do
    notification = notification_context() |> insert_notification("identity_linked", nil)

    discarded =
      %{notification_id: notification.id}
      |> SSONotificationWorker.new()
      |> Oban.insert!()
      |> Ecto.Changeset.change(state: "discarded")
      |> Repo.update!()

    assert :ok = perform_job(SSONotificationReconciler, %{})

    replacement_jobs =
      Oban.Job
      |> Repo.all()
      |> Enum.filter(fn job ->
        job.worker == inspect(SSONotificationWorker) and
          job.args == %{"notification_id" => notification.id} and
          job.id != discarded.id
      end)

    assert [%Oban.Job{state: "available"}] = replacement_jobs
    assert Repo.get(Notification, notification.id)
  end

  test "does not enqueue duplicate incomplete jobs for one notification" do
    notification = notification_context() |> insert_notification("identity_linked", nil)

    first = SSONotificationWorker.enqueue!(notification.id)
    duplicate = SSONotificationWorker.enqueue!(notification.id)

    assert duplicate.conflict?
    assert duplicate.id == first.id

    jobs =
      Oban.Job
      |> Repo.all()
      |> Enum.filter(fn job ->
        job.worker == inspect(SSONotificationWorker) and
          job.args == %{"notification_id" => notification.id}
      end)

    assert [%Oban.Job{id: job_id}] = jobs
    assert job_id == first.id
  end

  defp notification_context do
    organization = insert(:organization)
    user = insert(:user)
    connection = insert(:organization_sso_connection, organization: organization)
    %{connection: connection, organization: organization, user: user}
  end

  defp insert_notification(context, kind, provider_email) do
    %Notification{}
    |> Notification.changeset(%{
      connection_id: context.connection.id,
      user_id: context.user.id,
      kind: kind,
      organization_name: context.organization.name,
      username: context.user.username,
      recipients: %{emails: [Hexpm.Accounts.User.email(context.user, :primary)]},
      provider_email: provider_email
    })
    |> Repo.insert!()
  end
end
