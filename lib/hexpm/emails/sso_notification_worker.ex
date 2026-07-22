defmodule Hexpm.Emails.SSONotificationWorker do
  use Oban.Worker,
    queue: :periodic,
    max_attempts: 10,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  import Ecto.Query, only: [from: 2]
  alias Hexpm.Emails
  alias Hexpm.Emails.Delivery
  alias Hexpm.Accounts.SSO.Notification
  alias Hexpm.Repo

  def enqueue!(notification_id) do
    %{notification_id: notification_id}
    |> new()
    |> Oban.insert!()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => notification_id}}) do
    Repo.transaction(fn ->
      case Repo.get(Notification, notification_id) do
        nil ->
          :ok

        target ->
          notification =
            from(notification in Notification,
              where: notification.connection_id == ^target.connection_id,
              where: notification.user_id == ^target.user_id,
              order_by: [asc: notification.inserted_at, asc: notification.id],
              limit: 1,
              lock: "FOR UPDATE"
            )
            |> Repo.one()

          if notification do
            deliver!(notification)
            Repo.delete!(notification)

            if notification.id == target.id, do: :ok, else: :more_pending
          else
            :ok
          end
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:ok, :more_pending} -> {:snooze, 1}
      {:error, reason} -> {:error, reason}
    end
  end

  defp deliver!(notification) do
    recipients = Map.fetch!(notification.recipients, "emails")

    notification.kind
    |> build_email(
      notification.organization_name,
      notification.username,
      recipients,
      notification.provider_email
    )
    |> Delivery.impl().deliver!()
  end

  defp build_email("identity_linked", organization, username, recipients, _provider_email) do
    Emails.sso_identity_linked(organization, username, recipients)
  end

  defp build_email("identity_unlinked", organization, username, recipients, _provider_email) do
    Emails.sso_identity_unlinked(organization, username, recipients)
  end

  defp build_email("email_mismatch", organization, username, recipients, provider_email) do
    Emails.sso_email_mismatch(organization, username, recipients, provider_email)
  end
end
