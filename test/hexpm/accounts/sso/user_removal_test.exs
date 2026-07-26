defmodule Hexpm.Accounts.SSO.UserRemovalTest do
  use Hexpm.DataCase, async: true

  alias Ecto.Multi
  alias Hexpm.Accounts.SSO

  test "user deletion locks memberships before deleting SSO transactions" do
    user = insert(:user)

    operations =
      Multi.new()
      |> SSO.lock_user_removal(user)
      |> SSO.delete_user_transactions(user)
      |> Multi.to_list()
      |> Enum.map(&elem(&1, 0))

    assert operations == [
             :organization_sso_user_removal_locks,
             :organization_sso_user_transactions
           ]
  end
end
