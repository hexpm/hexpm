defmodule Hexpm.Accounts.SSO.ConfirmationPrunerTest do
  use Hexpm.DataCase

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.{ConfirmationPruner, Transaction}

  setup do
    organization = insert(:organization)
    user = insert(:user)

    connection =
      insert(:organization_sso_connection,
        organization: organization,
        tested_at: DateTime.utc_now(),
        enabled_at: DateTime.utc_now()
      )

    %{connection: connection, user: user}
  end

  test "confirmation pruning is capped at five and reports the backlog", context do
    now = DateTime.utc_now()

    transactions =
      for offset <- 7..1//-1 do
        insert_transaction(context.connection,
          link_method: "confirmed_primary_email",
          confirmation_code_hash: :crypto.strong_rand_bytes(32),
          confirmation_expires_at: DateTime.add(now, -offset, :second)
        )
      end

    handler_id = attach_batch_handler([:hexpm, :sso, :confirmation_pruning, :batch])

    assert SSO.expire_confirmations() == 5

    assert_receive {:pruner_batch, %{due_count: 7, selected_count: 5, remaining_count: 2},
                    %{limit: 5}}

    assert Enum.all?(Enum.take(transactions, 5), fn transaction ->
             transaction = Repo.get!(Transaction, transaction.id)
             transaction.cancelled_at && is_nil(transaction.confirmation_code_hash)
           end)

    assert Enum.all?(Enum.drop(transactions, 5), fn transaction ->
             transaction = Repo.get!(Transaction, transaction.id)
             is_nil(transaction.cancelled_at) && transaction.confirmation_code_hash
           end)

    :telemetry.detach(handler_id)
  end

  test "pending-login pruning is capped at five, scrubs secrets, and reports the backlog",
       context do
    now = DateTime.utc_now()

    transactions =
      for offset <- 7..1//-1 do
        insert_pending_login(context.connection, context.user,
          expires_at: DateTime.add(now, -offset, :second)
        )
      end

    unexpired =
      insert_pending_login(context.connection, context.user,
        expires_at: DateTime.add(now, 60, :second)
      )

    conventional =
      insert_pending_login(context.connection, context.user,
        expires_at: DateTime.add(now, -60, :second),
        link_method: "conventional"
      )

    handler_id = attach_batch_handler([:hexpm, :sso, :pending_login_pruning, :batch])

    assert ConfirmationPruner.expire_pending_logins() == 5

    assert_receive {:pruner_batch,
                    %{
                      due_count: 7,
                      selected_count: 5,
                      expired_count: 5,
                      remaining_count: 2
                    }, %{limit: 5}}

    assert Enum.all?(Enum.take(transactions, 5), &pending_login_scrubbed?/1)

    assert Enum.all?(Enum.drop(transactions, 5), fn transaction ->
             transaction = Repo.get!(Transaction, transaction.id)
             is_nil(transaction.cancelled_at) && transaction.link_token_hash
           end)

    refute pending_login_scrubbed?(unexpired)
    refute pending_login_scrubbed?(conventional)

    :telemetry.detach(handler_id)
  end

  test "pending-login completion and pruning serialize without retaining proof material",
       context do
    capability = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    transaction =
      insert_pending_login(context.connection, context.user,
        expires_at: DateTime.add(DateTime.utc_now(), -1, :second),
        link_token_hash: pending_login_capability_hash(capability)
      )

    parent = self()

    prune_task =
      Task.async(fn ->
        send(parent, {:ready, self()})

        receive do
          :go -> {:prune, ConfirmationPruner.expire_pending_logins(limit: 1)}
        end
      end)

    complete_task =
      Task.async(fn ->
        send(parent, {:ready, self()})

        receive do
          :go ->
            {:complete,
             SSO.complete_pending_login(
               transaction.id,
               capability,
               nil,
               audit_data(context.user)
             )}
        end
      end)

    pids =
      for _task <- 1..2 do
        assert_receive {:ready, pid}
        pid
      end

    Enum.each(pids, &send(&1, :go))

    results = [Task.await(prune_task, 5_000), Task.await(complete_task, 5_000)]

    assert {:prune, pruned} = List.keyfind(results, :prune, 0)
    assert pruned in [0, 1]

    assert {:complete, {:error, reason}} = List.keyfind(results, :complete, 0)
    assert reason in [:invalid_pending_login, :pending_login_cancelled, :pending_login_expired]
    assert pending_login_scrubbed?(transaction)
  end

  defp attach_batch_handler(event) do
    handler_id = {__MODULE__, self(), make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        fn _event, measurements, metadata, pid ->
          send(pid, {:pruner_batch, measurements, metadata})
        end,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    handler_id
  end

  defp insert_pending_login(connection, user, attrs) do
    capability_hash = :crypto.strong_rand_bytes(32)

    insert_transaction(
      connection,
      Keyword.merge(
        [
          user_id: user.id,
          consumed_at: DateTime.utc_now(),
          issuer: connection.issuer,
          subject: "subject-#{System.unique_integer([:positive])}",
          provider_email: primary_email(user).email,
          link_token_hash: capability_hash
        ],
        attrs
      )
    )
  end

  defp insert_transaction(connection, attrs) do
    defaults = %{
      connection_id: connection.id,
      state_hash: :crypto.strong_rand_bytes(32),
      kind: "login",
      secret_slot: "active",
      connection_version: connection.version,
      secret_version: connection.version,
      redirect_uri: "http://localhost:5000/sso/callback",
      expires_at: DateTime.add(DateTime.utc_now(), 60, :second)
    }

    %Transaction{}
    |> Ecto.Changeset.change(Map.merge(defaults, Map.new(attrs)))
    |> Repo.insert!()
  end

  defp pending_login_scrubbed?(transaction) do
    transaction = Repo.get!(Transaction, transaction.id)

    transaction.cancelled_at &&
      is_nil(transaction.user_id) &&
      is_nil(transaction.issuer) &&
      is_nil(transaction.subject) &&
      is_nil(transaction.provider_email) &&
      is_nil(transaction.link_token_hash)
  end

  defp pending_login_capability_hash(capability) do
    :crypto.mac(
      :hmac,
      :sha256,
      Application.fetch_env!(:hexpm, :secret),
      "sso-login-capability:" <> capability
    )
  end

  defp primary_email(user) do
    user
    |> Repo.preload(:emails)
    |> Map.fetch!(:emails)
    |> Enum.find(& &1.primary)
  end
end
