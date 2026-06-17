defmodule Hexpm.Repository.Policy.OverrideTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Repository.Policy.Override

  defp changeset(attrs) do
    Override.changeset(%Override{}, attrs)
  end

  test "requires action and package" do
    refute changeset(%{}).valid?
    errors = errors_on(changeset(%{}))
    assert errors.action == "can't be blank"
    assert errors.package == "can't be blank"
  end

  test "validates action inclusion" do
    refute changeset(%{"action" => "maybe", "package" => "phoenix"}).valid?
    assert changeset(%{"action" => "allow", "package" => "phoenix"}).valid?
    assert changeset(%{"action" => "deny", "package" => "phoenix"}).valid?
  end

  test "validates package format" do
    cs = changeset(%{"action" => "allow", "package" => "Bad Name"})
    refute cs.valid?
    assert errors_on(cs).package == "has invalid format"
  end

  test "accepts a valid version requirement" do
    assert changeset(%{"action" => "allow", "package" => "phoenix", "requirement" => "~> 1.7"}).valid?
  end

  test "rejects an invalid version requirement" do
    cs = changeset(%{"action" => "allow", "package" => "phoenix", "requirement" => "nonsense"})
    refute cs.valid?
    assert errors_on(cs).requirement == "is invalid"
  end

  test "blank requirement is nilified" do
    cs = changeset(%{"action" => "allow", "package" => "phoenix", "requirement" => "  "})
    assert cs.valid?
    assert Ecto.Changeset.apply_changes(cs).requirement == nil
  end
end
