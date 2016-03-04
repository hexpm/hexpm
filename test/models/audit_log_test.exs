defmodule HexWeb.AuditLogTest do
  use HexWeb.ModelCase

  test "create" do
    actor = %HexWeb.User{id: 1}
    package = %HexWeb.Package{id: 2, name: "ecto", meta: %{}}
    user = %HexWeb.User{id: 3, username: "eric", email: "eric@mail.com", confirmed: true}

    assert HexWeb.AuditLog.create(actor, "owner.add", {package, user}) ==
      %HexWeb.AuditLog{
        actor_id: 1,
        action: "owner.add",
        params: %{
          package: %{id: 2, name: "ecto", meta: %{}},
          user: %{id: 3, username: "eric", email: "eric@mail.com", confirmed: true}}}
  end
end
