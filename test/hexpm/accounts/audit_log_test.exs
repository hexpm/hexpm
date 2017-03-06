defmodule Hexpm.Accounts.AuditLogTest do
  use Hexpm.ModelCase, async: true

  alias Hexpm.Accounts.AuditLog

  test "build" do
    actor = %Hexpm.Accounts.User{id: 1}
    package = %Hexpm.Repository.Package{id: 2, name: "ecto", meta: %Hexpm.Repository.PackageMetadata{description: "some description"}}
    user = %Hexpm.Accounts.User{id: 3, username: "eric", handles: %Hexpm.Accounts.UserHandles{github: "ericmj"}}

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
