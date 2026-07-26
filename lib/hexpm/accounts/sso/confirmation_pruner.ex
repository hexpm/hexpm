defmodule Hexpm.Accounts.SSO.ConfirmationPruner do
  use Oban.Worker,
    queue: :periodic,
    max_attempts: 5,
    unique: [period: 10 * 60, fields: [:worker], states: :incomplete]

  import Ecto.Query

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.Transaction
  alias Hexpm.Repo

  @pending_login_limit 5

  @impl Oban.Worker
  def timeout(%Oban.Job{}), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) when map_size(args) == 0 do
    SSO.expire_confirmations()
    expire_pending_logins()
    :ok
  end

  def perform(%Oban.Job{args: args}), do: {:cancel, {:invalid_args, args}}

  @doc false
  def expire_pending_logins(opts \\ []) do
    limit = opts |> Keyword.get(:limit, @pending_login_limit) |> min(@pending_login_limit)
    now = DateTime.utc_now()
    query = pending_login_query(now)
    due_count = Repo.aggregate(query, :count)

    ids =
      from(transaction in query,
        order_by: [asc: transaction.expires_at, asc: transaction.id],
        select: transaction.id,
        limit: ^limit
      )
      |> Repo.all(log: false)

    expired_count = Enum.count(ids, &expire_pending_login(&1, now))
    remaining_count = Repo.aggregate(pending_login_query(DateTime.utc_now()), :count)

    :telemetry.execute(
      [:hexpm, :sso, :pending_login_pruning, :batch],
      %{
        due_count: due_count,
        selected_count: length(ids),
        expired_count: expired_count,
        remaining_count: remaining_count
      },
      %{limit: limit}
    )

    expired_count
  end

  defp expire_pending_login(transaction_id, now) do
    {:ok, expired?} =
      Repo.transaction(fn ->
        transaction =
          from(transaction in Transaction,
            where: transaction.id == ^transaction_id,
            lock: "FOR UPDATE"
          )
          |> Repo.one(log: false)

        if pending_login?(transaction, now) do
          transaction
          |> Ecto.Changeset.change(
            user_id: nil,
            issuer: nil,
            subject: nil,
            provider_email: nil,
            link_token_hash: nil,
            cancelled_at: now
          )
          |> Repo.update!(log: false)

          true
        else
          false
        end
      end)

    expired?
  end

  defp pending_login_query(now) do
    from(transaction in Transaction,
      where: transaction.kind == "login",
      where: not is_nil(transaction.consumed_at),
      where: is_nil(transaction.link_method),
      where: not is_nil(transaction.user_id),
      where: not is_nil(transaction.link_token_hash),
      where: is_nil(transaction.linked_at),
      where: is_nil(transaction.cancelled_at),
      where: transaction.expires_at <= ^now
    )
  end

  defp pending_login?(nil, _now), do: false

  defp pending_login?(transaction, now) do
    transaction.kind == "login" and not is_nil(transaction.consumed_at) and
      is_nil(transaction.link_method) and not is_nil(transaction.user_id) and
      not is_nil(transaction.link_token_hash) and is_nil(transaction.linked_at) and
      is_nil(transaction.cancelled_at) and
      DateTime.compare(transaction.expires_at, now) != :gt
  end
end
