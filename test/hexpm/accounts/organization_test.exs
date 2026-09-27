defmodule Hexpm.Accounts.OrganizationTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.Organization

  describe "changeset/2 name validation" do
    test "accepts underscores" do
      assert Organization.changeset(%Organization{}, %{name: "foo_bar"}).valid?
    end

    test "accepts plain alphanumeric names" do
      assert Organization.changeset(%Organization{}, %{name: "globex"}).valid?
    end

    test "rejects hyphens" do
      refute Organization.changeset(%Organization{}, %{name: "foo-bar"}).valid?
    end

    test "rejects dots" do
      refute Organization.changeset(%Organization{}, %{name: "foo.bar"}).valid?
    end

    test "bounds the name in bytes" do
      assert Organization.changeset(%Organization{}, %{name: String.duplicate("a", 255)}).valid?

      changeset = Organization.changeset(%Organization{}, %{name: String.duplicate("a", 256)})
      assert errors_on(changeset).name == "should be at most 255 byte(s)"
    end
  end

  describe "trial" do
    test "a new organization has not started its trial" do
      changeset = Organization.changeset(%Organization{}, %{name: "globex"})
      assert Ecto.Changeset.get_field(changeset, :trial_end) == nil
      refute Organization.trialing?(%Organization{trial_end: nil})
      refute Organization.billing_active?(%Organization{billing_active: false, trial_end: nil})
    end

    test "start_trial/1 starts a month-long trial" do
      for trial_end <- [nil, ~U[2020-01-01 00:00:00Z], DateTime.add(DateTime.utc_now(), 5, :day)] do
        changeset = Organization.start_trial(%Organization{trial_end: trial_end})
        new_trial_end = Ecto.Changeset.get_change(changeset, :trial_end)
        assert DateTime.diff(new_trial_end, DateTime.utc_now(), :day) in 29..31
      end
    end

    test "start_trial/1 keeps a longer trial" do
      trial_end = DateTime.add(DateTime.utc_now(), 60, :day)
      changeset = Organization.start_trial(%Organization{trial_end: trial_end})
      assert changeset.changes == %{}
      assert Ecto.Changeset.get_field(changeset, :trial_end) == trial_end
    end
  end
end
