defmodule Hexpm.Accounts.SeatsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.{Organization, Seats}

  describe "limit/1" do
    test "reports the paid seat count" do
      assert Seats.limit(%Organization{billing_active: true, billing_seats: 5}) == {:limited, 5}
    end

    test "treats an organization without a live subscription as unlimited" do
      assert Seats.limit(%Organization{billing_active: false}) == :unlimited
    end

    test "treats a comped organization as unlimited even though it is active" do
      # Hexpm.Billing.Report marks an overridden organization active without
      # giving it a seat count, so the override has to be read before the count.
      organization = %Organization{billing_active: true, billing_override: true}
      assert Seats.limit(organization) == :unlimited
    end

    test "reports an active organization with no known seat count as unknown" do
      assert Seats.limit(%Organization{billing_active: true}) == :unknown
      assert Seats.limit(%Organization{billing_active: true, billing_seats: 0}) == :unknown
    end
  end

  describe "claim/2" do
    test "allows a claim while seats remain" do
      organization = insert(:organization, billing_seats: 2)
      insert(:organization_user, organization: organization, user: insert(:user))

      assert {:ok, usage} = Repo.transaction(fn -> Seats.claim(organization) end) |> unwrap()
      assert usage.used == 1
      assert usage.limit == {:limited, 2}
    end

    test "refuses a claim once the seats are taken" do
      organization = insert(:organization, billing_seats: 1)
      insert(:organization_user, organization: organization, user: insert(:user))

      assert {:error, :seats_exhausted} =
               Repo.transaction(fn -> Seats.claim(organization) end) |> unwrap()
    end

    test "allows an unknown seat count by default and refuses it on request" do
      organization = insert(:organization)

      assert {:ok, _usage} = Repo.transaction(fn -> Seats.claim(organization) end) |> unwrap()

      assert {:error, :seat_limit_unknown} =
               Repo.transaction(fn -> Seats.claim(organization, unknown: :deny) end) |> unwrap()
    end

    test "refuses to run outside a transaction, where its lock would buy nothing" do
      organization = insert(:organization, billing_seats: 2)

      assert_raise ArgumentError, ~r/must run inside a transaction/, fn ->
        Seats.claim(organization)
      end
    end
  end

  describe "update_quantity/3" do
    test "writes back the quantity the billing service confirmed" do
      organization = insert(:organization, billing_seats: 2)

      assert {:ok, _customer} =
               Seats.update_quantity(organization, 5, fn quantity ->
                 assert quantity == 5
                 {:ok, %{"quantity" => quantity}}
               end)

      assert reload(organization).billing_seats == 5
    end

    test "subscribes to exactly the current members" do
      organization = insert(:organization)
      insert(:organization_user, organization: organization, user: insert(:user))
      insert(:organization_user, organization: organization, user: insert(:user))

      assert {:ok, _customer} =
               Seats.update_quantity(organization, :member_count, fn quantity ->
                 assert quantity == 2
                 {:ok, %{"quantity" => quantity}}
               end)

      assert reload(organization).billing_seats == 2
    end

    test "refuses a negative quantity rather than raising" do
      organization = insert(:organization, billing_seats: 3)

      assert {:error, {:seats_below_members, 0}} =
               Seats.update_quantity(organization, -1, fn _quantity ->
                 flunk("billing must not be called for a negative quantity")
               end)

      assert reload(organization).billing_seats == 3
    end

    test "refuses to drop below the current members" do
      organization = insert(:organization, billing_seats: 3)
      insert(:organization_user, organization: organization, user: insert(:user))
      insert(:organization_user, organization: organization, user: insert(:user))

      assert {:error, {:seats_below_members, 2}} =
               Seats.update_quantity(organization, 1, fn _quantity ->
                 flunk("billing must not be called when the reduction is invalid")
               end)

      assert reload(organization).billing_seats == 3
    end

    test "holds a reduction while the call is in flight so nothing spends a seat that is going away" do
      organization = insert(:organization, billing_seats: 5)

      assert {:ok, _customer} =
               Seats.update_quantity(organization, 2, fn quantity ->
                 assert reload(organization).billing_seats == 2
                 {:ok, %{"quantity" => quantity}}
               end)

      assert reload(organization).billing_seats == 2
    end

    test "does not raise the limit until the call has succeeded" do
      organization = insert(:organization, billing_seats: 2)

      assert {:ok, _customer} =
               Seats.update_quantity(organization, 9, fn quantity ->
                 assert reload(organization).billing_seats == 2
                 {:ok, %{"quantity" => quantity}}
               end)

      assert reload(organization).billing_seats == 9
    end

    test "puts a held reduction back when the call fails" do
      organization = insert(:organization, billing_seats: 5)

      assert {:error, :nope} =
               Seats.update_quantity(organization, 2, fn _quantity -> {:error, :nope} end)

      assert reload(organization).billing_seats == 5
    end

    test "leaves a payment that still needs confirming unapplied" do
      organization = insert(:organization, billing_seats: 5)

      assert {:requires_action, %{}} =
               Seats.update_quantity(organization, 2, fn _quantity ->
                 {:requires_action, %{}}
               end)

      assert reload(organization).billing_seats == 5
    end
  end

  defp unwrap({:ok, result}), do: result
  defp unwrap({:error, reason}), do: {:error, reason}

  defp reload(organization), do: Repo.get!(Organization, organization.id)
end
