defmodule Hexpm.Emails.SSONotificationReconciler do
  use Oban.Worker,
    queue: :periodic,
    max_attempts: 10,
    unique: [period: :infinity, states: :incomplete]

  import Ecto.Query, only: [from: 2]

  alias Hexpm.Accounts.SSO.Notification
  alias Hexpm.Emails.SSONotificationWorker
  alias Hexpm.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    from(notification in Notification,
      order_by: [asc: notification.inserted_at, asc: notification.id],
      select: notification.id
    )
    |> Repo.all()
    |> Enum.each(&SSONotificationWorker.enqueue!/1)

    :ok
  end
end
