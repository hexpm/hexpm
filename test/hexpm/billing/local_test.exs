defmodule Hexpm.Billing.LocalTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.Organizations
  alias Hexpm.Billing.Local

  test "reads a seat count persisted by an earlier server process" do
    organization = insert(:organization, billing_seats: 4)

    assert %{"quantity" => 4} = Local.get(organization.name)
  end

  test "persists seat updates per organization" do
    organization = insert(:organization, billing_seats: nil)
    other_organization = insert(:organization, billing_seats: nil)

    assert %{"quantity" => 1} = Local.get(organization.name)
    assert %{"quantity" => 1} = Local.get(other_organization.name)

    assert {:ok, %{"quantity" => 3}} = Local.update(organization.name, %{"quantity" => 3})
    assert %{"quantity" => 3} = Local.get(organization.name)
    assert %{"quantity" => 1} = Local.get(other_organization.name)
    assert Organizations.get(organization.name).billing_seats == 3
  end
end
