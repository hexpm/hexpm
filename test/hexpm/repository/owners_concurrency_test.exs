defmodule Hexpm.Repository.OwnersConcurrencyTest do
  use Hexpm.DataCase
  import Hexpm.ConcurrencyCase

  alias Hexpm.Repository.{Owners, Package, PackageOwner}

  # Each of these fails if Owners stops taking the package lock before its
  # last-owner checks: both racers read two owners and both succeed.

  test "two removals cannot leave a public package without owners" do
    committed(&build_context/0, fn context ->
      results =
        race([context.first, context.second], fn user ->
          Owners.remove(context.package, user, audit: audit_data(user))
        end)

      assert Enum.sort(results) == [:ok, {:error, :last_owner}]
      assert length(owners(context.package)) == 1
    end)
  end

  test "a removal and a demotion cannot leave a public package without a full owner" do
    committed(&build_context/0, fn context ->
      results =
        race([
          fn ->
            Owners.remove(context.package, context.first, audit: audit_data(context.first))
          end,
          fn ->
            Owners.update_level(context.package, context.second, "maintainer",
              audit: audit_data(context.second)
            )
          end
        ])

      assert Enum.count(results, &(&1 == {:error, :last_full_owner})) == 1
      assert Enum.count(owners(context.package), &(&1.level == "full")) == 1
    end)
  end

  test "two demotions cannot leave a package without a full owner" do
    committed(&build_context/0, fn context ->
      results =
        race([context.first, context.second], fn user ->
          Owners.update_level(context.package, user, "maintainer", audit: audit_data(user))
        end)

      assert Enum.count(results, &match?({:ok, %PackageOwner{}}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :last_full_owner})) == 1
      assert Enum.count(owners(context.package), &(&1.level == "full")) == 1
    end)
  end

  test "an owner removed while their transfer waits on the lock can't take the package" do
    committed(&build_context/0, fn %{package: package, first: first, second: second} ->
      parent = self()

      # Holds the lock the way Owners.remove does, with first's row already
      # deleted, until the transfer is waiting on it.
      removal =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            Repo.one!(from(p in Package, where: p.id == ^package.id, lock: "FOR NO KEY UPDATE"))

            Repo.delete_all(
              from(owner in PackageOwner,
                where: owner.package_id == ^package.id and owner.user_id == ^first.id
              )
            )

            send(parent, :removed)

            receive do
              :commit -> :ok
            end
          end)
        end)

      assert_receive :removed, 15_000

      # Authorized while first was still a full owner.
      transfer =
        unboxed_task(fn ->
          Owners.add(package, first, %{"transfer" => true}, audit: audit_data(first))
        end)

      assert await_lock_wait() == :waiting
      send(removal.pid, :commit)
      Task.await(removal, 15_000)

      assert Task.await(transfer, 15_000) == {:error, :not_full_owner}
      assert [%{user_id: user_id}] = owners(package)
      assert user_id == second.id
    end)
  end

  defp build_context do
    first = insert(:user)
    second = insert(:user)

    package =
      insert(:package,
        package_owners: [
          build(:package_owner, user: first, level: "full"),
          build(:package_owner, user: second, level: "full")
        ]
      )
      |> Repo.preload(repository: :organization)

    %{package: package, first: first, second: second}
  end

  defp owners(package) do
    Repo.all(from(owner in PackageOwner, where: owner.package_id == ^package.id))
  end
end
