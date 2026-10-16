defmodule Hexpm.Accounts.OrganizationsConcurrencyTest do
  use Hexpm.DataCase
  import Hexpm.ConcurrencyCase

  alias Hexpm.Accounts.{OrganizationInvitations, Organizations, OrganizationUser, Seats}

  # Every assertion here fails if the seat lock in Hexpm.Accounts.Seats stops
  # being taken. Deleting `lock: "FOR NO KEY UPDATE"` from Seats.lock!/1 is the
  # check that these are contending on real connections and not quietly boxed.

  test "two acceptances cannot spend the same last seat" do
    committed(&build_context/0, fn context ->
      newcomers = [insert(:user), insert(:user)]
      invitations = Enum.map(newcomers, &invite(context, &1))

      results =
        race(Enum.zip(invitations, newcomers), fn {invitation, user} ->
          OrganizationInvitations.accept(invitation, user, audit: audit_data(user))
        end)

      assert Enum.count(results, &match?({:ok, %OrganizationUser{}}, &1)) == 1
      assert Enum.count(results, &match?({:error, :seats_exhausted}, &1)) == 1
      assert Seats.used(context.organization) == 3
    end)
  end

  test "two removals cannot empty the organization" do
    committed(&build_context/0, fn context ->
      results =
        race([context.admin, context.other_admin], fn user ->
          Organizations.remove_member(context.organization, user,
            audit: audit_data(context.admin)
          )
        end)

      assert Enum.count(results, &(&1 == :ok)) == 1
      assert Enum.count(results, &(&1 == {:error, :last_member})) == 1
      assert Seats.used(context.organization) == 1
    end)
  end

  test "two demotions cannot leave the organization without an admin" do
    committed(&build_context/0, fn context ->
      results =
        race([context.admin, context.other_admin], fn user ->
          Organizations.change_role(context.organization, user, %{"role" => "read"},
            audit: audit_data(context.admin)
          )
        end)

      assert Enum.count(results, &match?({:ok, %OrganizationUser{}}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :last_admin})) == 1
      assert admin_count(context.organization) == 1
    end)
  end

  test "an acceptance and a reduction cannot both take the last seat" do
    committed(&build_context/0, fn context ->
      newcomer = insert(:user)
      invitation = invite(context, newcomer)

      results =
        race([
          fn ->
            OrganizationInvitations.accept(invitation, newcomer, audit: audit_data(newcomer))
          end,
          fn ->
            Seats.update_quantity(context.organization, 2, fn quantity ->
              {:ok, %{"quantity" => quantity}}
            end)
          end
        ])

      successes =
        Enum.count(results, fn
          {:ok, %OrganizationUser{}} -> true
          {:ok, %{"quantity" => _}} -> true
          _other -> false
        end)

      assert successes == 1
      assert Seats.used(context.organization) <= paid_seats(context.organization)
    end)
  end

  test "concurrent resends send one invitation per account and organization" do
    committed(&build_context/0, fn context ->
      user = insert(:user)
      invitation = invite(context, user)

      {:ok, _declined} =
        OrganizationInvitations.decline(invitation, user, audit: audit_data(user))

      invitation
      |> Ecto.Changeset.change(sent_at: DateTime.add(DateTime.utc_now(), -25 * 60 * 60))
      |> Repo.update!()

      results =
        race([user, user], fn user ->
          OrganizationInvitations.invite_user(
            context.organization,
            user,
            %{"role" => "read"},
            context.admin,
            audit: audit_data(context.admin)
          )
        end)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :invitation_cooldown})) == 1
      assert [_pending] = OrganizationInvitations.all_pending_for_user(user)
    end)
  end

  test "blocking and resending can't leave a pending invitation" do
    committed(&build_context/0, fn context ->
      user = insert(:user)
      invitation = invite(context, user)

      {:ok, _declined} =
        OrganizationInvitations.decline(invitation, user, audit: audit_data(user))

      invitation
      |> Ecto.Changeset.change(sent_at: DateTime.add(DateTime.utc_now(), -25 * 60 * 60))
      |> Repo.update!()

      results =
        race([
          fn ->
            OrganizationInvitations.invite_user(
              context.organization,
              user,
              %{"role" => "read"},
              context.admin,
              audit: audit_data(context.admin)
            )
          end,
          fn -> OrganizationInvitations.block(invitation, user, audit: audit_data(user)) end
        ])

      assert Enum.any?(results, &match?({:ok, _}, &1))
      assert [_block] = OrganizationInvitations.all_blocks_for_user(user)
      assert OrganizationInvitations.all_pending_for_user(user) == []

      assert {:error, :blocked} =
               OrganizationInvitations.invite_user(
                 context.organization,
                 user,
                 %{"role" => "read"},
                 context.admin,
                 audit: audit_data(context.admin)
               )
    end)
  end

  defp invite(context, user) do
    {:ok, invitation} =
      OrganizationInvitations.invite_user(
        context.organization,
        user,
        %{"role" => "read"},
        context.admin,
        audit: audit_data(context.admin)
      )

    Repo.preload(invitation, :organization)
  end

  defp build_context do
    # Three paid seats and two members, so exactly one seat is free and the
    # membership set is one removal away from its last member.
    organization = insert(:organization, billing_seats: 3)
    admin = insert(:user)
    other_admin = insert(:user)

    insert(:organization_user, organization: organization, user: admin, role: "admin")
    insert(:organization_user, organization: organization, user: other_admin, role: "admin")

    %{organization: organization, admin: admin, other_admin: other_admin}
  end

  defp admin_count(organization) do
    Hexpm.RepoBase.aggregate(
      from(organization_user in OrganizationUser,
        where: organization_user.organization_id == ^organization.id,
        where: organization_user.role == "admin"
      ),
      :count
    )
  end

  defp paid_seats(organization) do
    Hexpm.RepoBase.get!(Hexpm.Accounts.Organization, organization.id).billing_seats
  end
end
