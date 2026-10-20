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

    %{package: package, workload_identity: workload_identity}
  end
end
