defmodule HexpmWeb.BasicAuthTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.BasicAuth

  test "disables the schedule in the Hex integration environment" do
    config = Config.Reader.read!("config/hex.exs", env: :hex)

    refute config[:hexpm][BasicAuth][:schedule_enabled]
  end

  test "allows Basic authentication before the first brownout" do
    refute BasicAuth.disabled?(~U[2026-09-30 23:59:59.999999Z])
  end

  test "uses inclusive starts and exclusive ends" do
    assert BasicAuth.disabled?(~U[2026-10-01 00:00:00Z])
    assert BasicAuth.disabled?(~U[2026-10-01 00:59:59.999999Z])
    refute BasicAuth.disabled?(~U[2026-10-01 01:00:00Z])
    refute BasicAuth.disabled?(~U[2026-10-01 11:59:59.999999Z])
    assert BasicAuth.disabled?(~U[2026-10-01 12:00:00Z])
  end

  test "handles windows ending at midnight" do
    refute BasicAuth.disabled?(~U[2026-10-10 21:59:59.999999Z])
    assert BasicAuth.disabled?(~U[2026-10-10 22:00:00Z])
    assert BasicAuth.disabled?(~U[2026-10-10 23:59:59.999999Z])
    refute BasicAuth.disabled?(~U[2026-10-11 00:00:00Z])
  end

  test "applies the longer windows later in the month" do
    assert BasicAuth.disabled?(~U[2026-10-18 13:00:00Z])
    refute BasicAuth.disabled?(~U[2026-10-18 17:00:00Z])
    assert BasicAuth.disabled?(~U[2026-10-25 16:00:00Z])
    assert BasicAuth.disabled?(~U[2026-10-30 23:59:59.999999Z])
    refute BasicAuth.disabled?(~U[2026-10-31 00:00:00Z])
    assert BasicAuth.disabled?(~U[2026-10-31 13:00:00Z])
    refute BasicAuth.disabled?(~U[2026-10-31 23:00:00Z])
  end

  test "disables Basic authentication permanently after the brownouts" do
    refute BasicAuth.disabled?(~U[2026-10-31 23:59:59.999999Z])
    assert BasicAuth.disabled?(~U[2026-11-01 00:00:00Z])
    assert BasicAuth.disabled?(~U[2027-01-01 00:00:00Z])
  end
end
