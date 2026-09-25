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

    document = LazyHTML.from_document(html)

    assert [link] =
             LazyHTML.query(document, ~s(#docs-nav a[href="/docs/organization-sso"]))
             |> Enum.to_list()

    assert LazyHTML.text(link) =~ "Organization SSO"
    assert LazyHTML.attribute(link, "class") |> List.first() =~ "bg-blue-50"
  end

  test "renders the navigation as a sidebar on desktop and a collapsed accordion below it" do
    html =
      build_conn()
      |> get("/docs/rebar3-usage")
      |> html_response(200)

    document = LazyHTML.from_document(html)

    assert [sidebar] = LazyHTML.query(document, "nav#docs-nav") |> Enum.to_list()
    assert LazyHTML.attribute(sidebar, "class") |> List.first() =~ "hidden lg:block"

    assert [accordion] = LazyHTML.query(document, "details#docs-nav-mobile") |> Enum.to_list()
    assert LazyHTML.attribute(accordion, "class") |> List.first() =~ "lg:hidden"
    assert LazyHTML.attribute(accordion, "open") == []
    assert LazyHTML.query(accordion, "summary") |> LazyHTML.text() =~ "Rebar3 usage"

    for nav <- [sidebar, accordion] do
      assert [link] = LazyHTML.query(nav, ~s(a[href="/docs/rebar3-usage"])) |> Enum.to_list()
      assert LazyHTML.attribute(link, "class") |> List.first() =~ "bg-blue-50"
      assert [_] = LazyHTML.query(nav, ~s(a[href="/docs/public-keys"])) |> Enum.to_list()
      assert [tasks] = LazyHTML.query(nav, ~s(a[href="https://hexdocs.pm/hex"])) |> Enum.to_list()
      assert LazyHTML.attribute(tasks, "target") == ["_blank"]
    end
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
    assert html =~ "urn:ietf:params:oauth:grant-type:jwt-bearer"
    assert html =~ "id-token: write"
    assert html =~ "Cannot create a package"

    document = LazyHTML.from_document(html)

    assert [link] =
             LazyHTML.query(document, ~s(#docs-nav a[href="/docs/trusted-publishers"]))
             |> Enum.to_list()

    assert LazyHTML.text(link) =~ "Trusted publishers"
    assert [class] = LazyHTML.attribute(link, "class")
    assert class =~ "bg-blue-50"
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

  test "2FA documentation and navigation follow their own rollout availability" do
    app_env(:hexpm, :organization_sso, mode: :off, beta_organizations: [])

    for {config, visible?} <- [
          {[mode: :off, beta_organizations: ["pilot"]], false},
          {[mode: :beta, beta_organizations: []], false},
          {[mode: :beta, beta_organizations: ["pilot"]], true},
          {[mode: :enabled, beta_organizations: []], true}
        ] do
      app_env(:hexpm, :organization_tfa, config)
      html = build_conn() |> get("/docs/usage") |> html_response(200)
      assert html =~ ~s(href="/docs/organization-tfa") == visible?
      refute html =~ ~s(href="/docs/organization-sso")

      assert build_conn()
             |> get("/docs/organization-tfa")
             |> response(if visible?, do: 200, else: 404)
    end
  end

  test "usage guide code blocks have a copy control" do
    html =
      build_conn()
      |> get("/docs/usage")
      |> html_response(200)

    document = LazyHTML.from_document(html)

    assert [button | _] =
             LazyHTML.query(document, ~s(.docs-content button[phx-hook="CopyButton"]))
             |> Enum.to_list()

    assert [target_id] = LazyHTML.attribute(button, "data-copy-target")
    assert [target] = LazyHTML.query(document, "##{target_id}") |> Enum.to_list()
    assert [value] = LazyHTML.attribute(target, "data-value")
    assert value =~ "defmodule MyProject.MixProject"
    refute value =~ "```"
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
