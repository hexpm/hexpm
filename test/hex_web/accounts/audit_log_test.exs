defmodule HexWeb.Accounts.AuditLogTest do
  use HexWeb.ModelCase, async: true

  alias HexWeb.Accounts.AuditLog

  test "build" do
    actor = %HexWeb.Accounts.User{id: 1}
    package = %HexWeb.Repository.Package{id: 2, name: "ecto", meta: %HexWeb.Repository.PackageMetadata{description: "some description"}}
    user = %HexWeb.Accounts.User{id: 3, username: "eric", handles: %HexWeb.Accounts.UserHandles{github: "ericmj"}}

    assert AuditLog.build(actor, "Hex/0.12.1", "owner.add", {package, user}) ==
      %AuditLog{
        actor_id: 1,
        user_agent: "Hex/0.12.1",
        action: "owner.add",
        params: %{
          package: %{id: 2, name: "ecto",
                     meta: %{maintainers: nil, description: "some description", licenses: nil, links: nil, maintainers: nil, extra: nil}},
          user: %{id: 3, username: "eric", handles: %{github: "ericmj", freenode: nil, twitter: nil}}}}
  end
end
