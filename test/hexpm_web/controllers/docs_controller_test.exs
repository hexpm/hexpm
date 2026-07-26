defmodule HexpmWeb.DocsControllerTest do
  use HexpmWeb.ConnCase

  test "renders the organization SSO setup guide in the docs navigation" do
    enable_sso_docs()

    html =
      build_conn()
      |> get("/docs/organization-sso")
      |> html_response(200)

    assert html =~ "Organization single sign-on"
    assert html =~ "Create the Okta application"
    assert html =~ "existing Hexpm account"
    assert html =~ "Custom Okta dashboard tiles"
    assert html =~ "remain unavailable until their external validation"
    assert html =~ "tenant-specific v2 issuer"
    assert html =~ "organization access session"
    assert html =~ "never suppresses a personal Hexpm two-factor prompt"

    {:ok, document} = Floki.parse_document(html)
    assert [link] = Floki.find(document, ~s(a[href="/docs/organization-sso"]))
    assert Floki.text(link) =~ "Organization SSO"
    assert Floki.attribute(link, "class") |> List.first() =~ "bg-blue-50"
  end

  test "hides the organization SSO guide and navigation when SSO is off" do
    config = Application.fetch_env!(:hexpm, :organization_sso)
    app_env(:hexpm, :organization_sso, Keyword.put(config, :mode, :off))
    assert_sso_docs_hidden()
  end

  test "hides the organization SSO guide and navigation for an empty beta allowlist" do
    config = Application.fetch_env!(:hexpm, :organization_sso)

    app_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, mode: :beta, beta_organizations: [])
    )

    assert_sso_docs_hidden()
  end

  defp assert_sso_docs_hidden do
    build_conn()
    |> get("/docs/organization-sso")
    |> response(404)

    html =
      build_conn()
      |> get("/docs/usage")
      |> html_response(200)

    refute html =~ ~s(href="/docs/organization-sso")
  end

  defp enable_sso_docs do
    config = Application.fetch_env!(:hexpm, :organization_sso)

    app_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, mode: :beta, beta_organizations: ["pilot"])
    )
  end
end
