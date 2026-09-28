defmodule Hexpm.Accounts.SSO.OIDC.IssuerTest do
  use ExUnit.Case, async: true

  alias Hexpm.Accounts.SSO.Error
  alias Hexpm.Accounts.SSO.OIDC.Issuer

  test "accepts an exact HTTPS issuer with an optional port and path" do
    assert {:ok, %URI{query: nil, fragment: nil}} =
             Issuer.validate_syntax("https://identity.example.com:8443/tenant/v2.0")
  end

  test "rejects query and fragment components" do
    assert {:error, %Error{stage: :url_validation, code: :query_not_allowed}} =
             Issuer.validate_syntax("https://identity.example.com/tenant?configuration=other")

    assert {:error, %Error{stage: :url_validation, code: :query_not_allowed}} =
             Issuer.validate_syntax("https://identity.example.com/tenant?")

    assert {:error, %Error{stage: :url_validation, code: :fragment_not_allowed}} =
             Issuer.validate_syntax("https://identity.example.com/tenant#other")
  end

  test "preserves HTTPS and public-network validation" do
    assert {:error, %Error{stage: :url_validation, code: :https_required}} =
             Issuer.validate_syntax("http://identity.example.com/tenant")

    assert {:error, %Error{stage: :url_validation, code: :private_address_not_allowed}} =
             Issuer.validate("https://127.0.0.1/tenant")
  end

  test "recognizes a Microsoft Entra issuer by its host" do
    assert Issuer.entra?(
             "https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555/v2.0"
           )

    refute Issuer.entra?("https://example.okta.com")
    refute Issuer.entra?("https://login.microsoftonline.com.example.com/tenant/v2.0")
    refute Issuer.entra?("https://example.com/login.microsoftonline.com/tenant/v2.0")
  end
end
