defmodule Hexpm.Emails.OutboxEntryTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Emails.OutboxEntry

  test "bounds the keys in bytes" do
    attrs = %{category: "notice", email: %{}}

    assert OutboxEntry.changeset(
             %OutboxEntry{},
             Map.put(attrs, :group_key, combining_string(255))
           ).valid?

    changeset =
      OutboxEntry.changeset(%OutboxEntry{}, Map.put(attrs, :group_key, combining_string(256)))

    assert errors_on(changeset).group_key == "should be at most 255 byte(s)"

    changeset =
      OutboxEntry.changeset(%OutboxEntry{}, Map.put(attrs, :scope_key, combining_string(256)))

    assert errors_on(changeset).scope_key == "should be at most 255 byte(s)"

    changeset =
      OutboxEntry.changeset(%OutboxEntry{}, Map.put(attrs, :type, combining_string(101)))

    assert errors_on(changeset).type == "should be at most 100 byte(s)"
  end
end
