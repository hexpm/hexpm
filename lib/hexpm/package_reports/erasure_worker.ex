defmodule Hexpm.PackageReports.ErasureWorker do
  @moduledoc """
  Tells the CNA that a user it holds personal data about has deleted their
  account, so it can erase what hex.pm sent it.

  Inserted in the transaction that deletes the user, carrying the username and
  primary email address, since neither exists in hex.pm once it commits. It
  runs ten minutes later, after any report or contact lookup that was sending
  the user's details to the CNA when the deletion started has finished, so the
  notice can't arrive ahead of the data it erases.
  """

  use Oban.Worker, queue: :heavy, max_attempts: 20

  alias Hexpm.Accounts.User

  @delay 10 * 60
  alias Hexpm.PackageReports.Varsel

  def new_job(%User{} = user) do
    new(%{"username" => user.username, "email" => User.email(user, :primary)},
      schedule_in: @delay
    )
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"username" => username, "email" => email}}) do
    Varsel.erase(%{username: username, email: email})
  end
end
