defmodule HexpmWeb.Dashboard.SecurityView do
  use HexpmWeb, :view
  alias HexpmWeb.DashboardView
  alias Hexpm.Accounts.User

  defp show_recovery_codes?(user) do
    User.tfa_enabled?(user) && user.tfa.recovery_codes
  end

  defp class_for_code(code) do
    case code.used_at do
      nil -> "recovery-code-unused"
      _ -> "recovery-code-used"
    end
  end

  defp aggregate_recovery_codes(codes) do
    Enum.map(codes, & &1.code)
    |> Enum.reduce(fn code, acc -> acc <> "\n" <> code end)
  end
end
