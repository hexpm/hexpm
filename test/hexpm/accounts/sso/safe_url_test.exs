defmodule Hexpm.Accounts.SSO.SafeURLTest do
  use ExUnit.Case, async: false

  alias Hexpm.Accounts.SSO.Error
  alias Hexpm.Accounts.SSO.SafeURL

  defp exempt(hosts) do
    previous = Application.get_env(:hexpm, :sso_exempt_issuer_hosts, [])
    Application.put_env(:hexpm, :sso_exempt_issuer_hosts, hosts)
    on_exit(fn -> Application.put_env(:hexpm, :sso_exempt_issuer_hosts, previous) end)
  end

  test "requires HTTPS and a public address when no host is exempt" do
    assert {:error, %Error{stage: :url_validation, code: :https_required}} =
             SafeURL.validate_syntax("http://localhost:4443/mock")

    assert {:error, %Error{stage: :url_validation, code: :private_address_not_allowed}} =
             SafeURL.validate("https://127.0.0.1/mock")
  end

  test "allows plain HTTP on an exempt host" do
    exempt(["localhost"])

    assert {:ok, %URI{scheme: "http", host: "localhost", port: 4443}} =
             SafeURL.validate("http://localhost:4443/mock")
  end

  test "allows a loopback address on an exempt host" do
    exempt(["127.0.0.1"])

    assert {:ok, %URI{}, [{127, 0, 0, 1}]} = SafeURL.resolve("http://127.0.0.1:4443/mock")
  end

  test "exempting one host does not exempt any other" do
    exempt(["localhost"])

    assert {:error, %Error{stage: :url_validation, code: :https_required}} =
             SafeURL.validate_syntax("http://identity.example.com/tenant")

    assert {:error, %Error{stage: :url_validation, code: :private_address_not_allowed}} =
             SafeURL.validate("https://127.0.0.1/mock")
  end
end
