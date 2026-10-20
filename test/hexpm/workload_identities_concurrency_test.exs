defmodule Hexpm.WorkloadIdentitiesConcurrencyTest do
  use Hexpm.DataCase
  import Hexpm.ConcurrencyCase
  import Mox

  alias Hexpm.OAuth.Token
  alias Hexpm.WorkloadIdentities
  alias Hexpm.WorkloadIdentities.{TrustedRepository, WorkloadIdentity}
  alias Hexpm.WorkloadIdentityHelpers

  setup :verify_on_exit!

  # Fails if minting stops matching the workload identity again under a lock
  # on its row: the exchange matched before the change committed and inserts
  # a token the change never sees to revoke.
  test "an exchange that matched before a change commits gets no token" do
    committed(&build_context/0, fn %{package: package, workload_identity: workload_identity} =
                                     context ->
      parent = self()
      WorkloadIdentityHelpers.stub_oidc_discovery()

      oidc_token =
        WorkloadIdentityHelpers.github_claims()
        |> WorkloadIdentityHelpers.sign_oidc_claims()

      # Holds the row the way WorkloadIdentities.update does, with the workflow
      # the token names already replaced, until the exchange waits on it.
      change =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            Repo.update_all(
              from(wi in WorkloadIdentity, where: wi.id == ^workload_identity.id),
              set: [workflow: "other.yml"]
            )

            send(parent, :changed)

            receive do
              :commit -> :ok
            end
          end)
        end)

      assert_receive :changed, 15_000

      exchange =
        unboxed_task(fn ->
          WorkloadIdentities.verify_and_mint(oidc_token,
            repository: "hexpm",
            package: package.name
          )
        end)

      assert await_lock_wait() == :waiting
      send(change.pid, :commit)
      Task.await(change, 15_000)

      assert Task.await(exchange, 15_000) == {:error, :no_matching_identity}
      assert committed_count(context, Token) == 0
    end)
  end

  # Fails if a change stops locking the workload identity's row before
  # comparing it with the version its form was loaded with: the waiting change
  # reads the row before the other one commits and overwrites it.
  test "a change that waits on another change is refused once that one commits" do
    committed(&build_context/0, fn %{user: user, workload_identity: workload_identity} ->
      parent = self()

      other_change =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            lock_row(workload_identity, "FOR NO KEY UPDATE")

            Repo.update_all(
              from(wi in WorkloadIdentity, where: wi.id == ^workload_identity.id),
              set: [workflow: "other.yml"]
            )

            send(parent, :locked)

            receive do
              :commit -> :ok
            end
          end)
        end)

      assert_receive :locked, 15_000

      change =
        unboxed_task(fn ->
          WorkloadIdentities.update(
            workload_identity,
            %{
              "repositories" => "widget",
              "workflow" => "publish.yml",
              "version" => WorkloadIdentities.version(workload_identity)
            },
            audit: audit_data(user)
          )
        end)

      assert await_lock_wait() == :waiting
      send(other_change.pid, :commit)
      Task.await(other_change, 15_000)

      assert Task.await(change, 15_000) == {:error, :changed}
      assert Repo.get!(WorkloadIdentity, workload_identity.id).workflow == "other.yml"
    end)
  end

  # Fails if a change revokes the workload identity's tokens before it holds
  # the row: an exchange holding the row's shared lock commits its token after
  # the revocation and keeps a token the change meant to revoke.
  test "a change revokes the token an exchange inserted while the change waited" do
    committed(&build_context/0, fn %{user: user, workload_identity: workload_identity} ->
      parent = self()

      workload_identity =
        workload_identity
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_embed(:repositories, [
          %TrustedRepository{name: "acme/widget", id: "67890"},
          %TrustedRepository{name: "acme/gadget", id: "70001"}
        ])
        |> Repo.update!()

      # Holds the row the way minting does while it inserts the token.
      exchange =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            lock_row(workload_identity, "FOR SHARE")
            token = insert_token(workload_identity)
            send(parent, :inserted)

            receive do
              :commit -> token
            end
          end)
        end)

      assert_receive :inserted, 15_000

      change =
        unboxed_task(fn ->
          WorkloadIdentities.update(
            workload_identity,
            %{"repositories" => "widget", "workflow" => "release.yml"},
            audit: audit_data(user)
          )
        end)

      assert await_lock_wait() == :waiting
      send(exchange.pid, :commit)
      assert {:ok, token} = Task.await(exchange, 15_000)

      assert {:ok, updated} = Task.await(change, 15_000)
      assert updated.repositories == [%TrustedRepository{name: "acme/widget", id: "67890"}]
      assert Repo.get!(Token, token.id).revoked_at
    end)
  end

  # Fails if removal revokes the tokens before it locks the workload
  # identity's row, the opposite order of a change: each holds what the other
  # waits for, and Postgres aborts one of them.
  test "removing a workload identity while a change holds it doesn't deadlock" do
    committed(&build_context/0, fn %{user: user, workload_identity: workload_identity} ->
      parent = self()
      token = insert_token(workload_identity)

      # Holds the row the way a change does, then revokes the tokens.
      change =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            lock_row(workload_identity, "FOR NO KEY UPDATE")
            send(parent, :locked)

            receive do
              :revoke -> :ok
            end

            Repo.update_all(WorkloadIdentities.revoke_tokens_query([workload_identity.id]), [])
          end)
        end)

      assert_receive :locked, 15_000

      removal =
        unboxed_task(fn ->
          WorkloadIdentities.delete(workload_identity, audit: audit_data(user))
        end)

      assert await_lock_wait() == :waiting
      send(change.pid, :revoke)

      assert {:ok, _revoked} = Task.await(change, 15_000)
      assert {:ok, _deleted} = Task.await(removal, 15_000)
      refute Repo.get(WorkloadIdentity, workload_identity.id)
      assert Repo.get!(Token, token.id).revoked_at
    end)
  end

  defp lock_row(workload_identity, "FOR SHARE") do
    Repo.one!(
      from(wi in WorkloadIdentity, where: wi.id == ^workload_identity.id, lock: "FOR SHARE")
    )
  end

  defp lock_row(workload_identity, "FOR NO KEY UPDATE") do
    Repo.one!(
      from(wi in WorkloadIdentity,
        where: wi.id == ^workload_identity.id,
        lock: "FOR NO KEY UPDATE"
      )
    )
  end

  # A token the way minting inserts one, unrevoked.
  defp insert_token(workload_identity) do
    scope = "package:hexpm/#{workload_identity.package.name}"

    {:ok, access_token, jti} =
      Hexpm.OAuth.JWT.generate_access_token(
        to_string(workload_identity.id),
        "workload_identity",
        [scope],
        expires_in: 900
      )

    %{
      jti: jti,
      access_token: access_token,
      scopes: [scope],
      granted_scopes: [scope],
      expires_at: DateTime.add(DateTime.utc_now(), 900, :second),
      grant_type: "workload_identity",
      grant_reference: "oidc-jti-#{System.unique_integer([:positive])}",
      workload_identity_id: workload_identity.id,
      oidc_claims: %{}
    }
    |> Token.build()
    |> Repo.insert!()
  end

  defp build_context do
    user = insert(:user)

    package =
      insert(:package, package_owners: [build(:package_owner, user: user, level: "full")])

    workload_identity =
      insert(:workload_identity,
        package: package,
        repository_owner: "acme",
        repository_owner_id: "12345",
        repositories: [%TrustedRepository{name: "acme/widget", id: "67890"}],
        workflow: "release.yml"
      )

    %{user: user, package: package, workload_identity: workload_identity}
  end
end
