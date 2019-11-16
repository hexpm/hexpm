defmodule Hexpm.Accounts.RecoveryCodeTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.RecoveryCode

  setup do
    %{user: create_user("starbelly", "starbelly@mail.com", "hunter42")}
  end

  test "create recovery code and get", %{user: user} do
    recovery_code = %RecoveryCode{user_id: user.id, code_digest: "1234"} |> Hexpm.Repo.insert!()
    assert Hexpm.Repo.get(RecoveryCode, recovery_code.id).user_id == user.id
  end

  test "create unique key name", %{user: user} do
    assert %RecoveryCode{} = %RecoveryCode{user_id: user.id, code_digest: "1234"} |> Hexpm.Repo.insert!()
    assert %RecoveryCode{} = %RecoveryCode{user_id: user.id, code_digest: "12345"} |> Hexpm.Repo.insert!()
    assert_raise Ecto.ConstraintError, fn -> %RecoveryCode{user_id: user.id, code_digest: "1234"} |> Hexpm.Repo.insert!() end
  end

end
