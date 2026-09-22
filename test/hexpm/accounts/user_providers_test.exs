defmodule Hexpm.Accounts.UserProvidersTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.UserProviders

  describe "create/6" do
    test "refuses a second account for a provider the user already linked" do
      user = insert(:user)
      insert(:user_provider, user: user, provider: "github", provider_uid: "11111")

      assert {:error, changeset} =
               UserProviders.create(user, "github", "22222", "attacker@example.com", %{},
                 audit: audit_data(user)
               )

      assert %{user_id: "has already been taken"} = errors_on(changeset)
      assert UserProviders.get_for_user(user, "github").provider_uid == "11111"
    end
  end
end
