defmodule HexWeb.AuditLogTest do
  use HexWeb.ModelCase, async: true

  test "build" do
    actor = %HexWeb.User{id: 1}
    package = %HexWeb.Package{id: 2, name: "ecto", meta: %HexWeb.PackageMetadata{description: "some description"}}
    user = %HexWeb.User{id: 3, username: "eric", handles: %HexWeb.UserHandles{github: "ericmj"}}

    assert HexWeb.AuditLog.build(actor, "Hex/0.12.1", "owner.add", {package, user}) ==
      %HexWeb.AuditLog{
        actor_id: 1,
        user_agent: "Hex/0.12.1",
        action: "owner.add",
        params: %{
          package: %{id: 2, name: "ecto",
                     meta: %{maintainers: nil, description: "some description", licenses: nil, links: nil, maintainers: nil, extra: nil}},
          user: %{id: 3, username: "eric", handles: %{github: "ericmj", freenode: nil, twitter: nil}}}}
  end
end
