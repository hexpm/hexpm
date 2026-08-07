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

    # The load-bearing fact about the OIN listing, rather than the sentence
    # carrying it. An earlier version asserted the exact wording and refuted two
    # phrasings that no longer exist anywhere, which breaks on a copy edit and
    # catches nothing.
    assert html =~ "never submitted for review"
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

  test "renders the trusted publishers guide in the docs navigation" do
    enable_trusted_publisher_docs()

    html =
      build_conn()
      |> get("/docs/trusted-publishers")
      |> html_response(200)

    assert html =~ "Trusted publishers"
    assert html =~ "Configure a trusted publisher"
    assert html =~ "/api/oidc/mint-token"
    assert html =~ "id-token: write"
    assert html =~ "Cannot create a package"

    {:ok, document} = Floki.parse_document(html)
    assert [link] = Floki.find(document, ~s(a[href="/docs/trusted-publishers"]))
    assert Floki.text(link) =~ "Trusted publishers"
    assert Floki.attribute(link, "class") |> List.first() =~ "bg-blue-50"
  end

  test "hides the trusted publishers guide and navigation when the feature is off" do
    app_env(:hexpm, :features, trusted_publishers: false)

    build_conn()
    |> get("/docs/trusted-publishers")
    |> response(404)

    html =
      build_conn()
      |> get("/docs/usage")
      |> html_response(200)

    refute html =~ ~s(href="/docs/trusted-publishers")
  end

  test "publish docs link to trusted publishers when the feature is on" do
    enable_trusted_publisher_docs()

    html =
      build_conn()
      |> get("/docs/publish")
      |> html_response(200)

    assert html =~ ~s(href="/docs/trusted-publishers")
    assert html =~ "trusted publishers"
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

  defp enable_trusted_publisher_docs do
    app_env(:hexpm, :features, trusted_publishers: true)
  end
end
