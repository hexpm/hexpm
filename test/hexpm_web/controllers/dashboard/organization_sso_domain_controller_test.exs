defmodule HexpmWeb.Dashboard.OrganizationSSODomainControllerTest do
  use HexpmWeb.ConnCase

  alias Hexpm.Accounts.SSO.Domain

  setup :verify_on_exit!

  setup do
    organization = insert(:organization)
    admin = insert(:user)
    member = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")
    insert(:organization_user, organization: organization, user: member, role: "read")
    enable_beta_for(organization)
    stub(Hexpm.Billing.Mock, :get, fn _organization, _opts -> nil end)

    %{admin: admin, member: member, organization: organization}
  end

  test "renders domain controls without exposing other SSO secrets", context do
    domain =
      insert(:organization_sso_domain,
        organization: context.organization,
        state: "verified",
        verified_at: DateTime.utc_now(),
        valid_until: DateTime.add(DateTime.utc_now(), 86_400, :second)
      )

    html =
      build_conn()
      |> test_login(context.admin)
      |> get("/dashboard/orgs/#{context.organization.name}/sso")
      |> html_response(200)

    assert html =~ "Verified domains"
    assert html =~ domain.domain
    assert html =~ "_hexpm-sso.#{domain.domain}"
    assert html =~ domain.challenge
    assert html =~ "Email discovery"
    assert html =~ "Confirmed account linking"
  end

  test "adds, verifies, and updates a domain through admin routes", context do
    path = "/dashboard/orgs/#{context.organization.name}/sso"

    conn =
      build_conn()
      |> test_login(context.admin)
      |> post(path <> "/domains", %{"domain" => %{"domain" => "Example.COM."}})

    assert redirected_to(conn) == path
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "domain was added"

    domain = Repo.get_by!(Domain, organization_id: context.organization.id)
    assert domain.domain == "example.com"

    expect(Hexpm.Accounts.SSO.DomainResolver.Mock, :lookup_txt, fn _name ->
      {:ok, [domain.challenge]}
    end)

    conn =
      build_conn()
      |> test_login(context.admin)
      |> post(path <> "/domains/#{domain.id}/verify")

    assert redirected_to(conn) == path
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "The domain was verified."

    conn =
      build_conn()
      |> test_login(context.admin)
      |> post(path <> "/domains/#{domain.id}/policy", %{
        "domain" => %{
          "discovery_enabled" => "true",
          "discovery_disclosure_acknowledged" => "true",
          "automatic_linking_enabled" => "true"
        }
      })

    assert redirected_to(conn) == path
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "The domain policy was updated."
    assert Repo.get!(Domain, domain.id).discovery_enabled
    assert Repo.get!(Domain, domain.id).automatic_linking_enabled
  end

  test "reverification rotates an invalid challenge", context do
    domain =
      insert(:organization_sso_domain,
        organization: context.organization,
        state: "invalid",
        invalidated_at: DateTime.utc_now()
      )

    conn =
      build_conn()
      |> test_login(context.admin)
      |> post("/dashboard/orgs/#{context.organization.name}/sso/domains/#{domain.id}/reverify")

    assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}/sso"
    rotated = Repo.get!(Domain, domain.id)
    assert rotated.state == "pending"
    assert rotated.challenge_generation == domain.challenge_generation + 1
    assert rotated.challenge != domain.challenge
  end

  test "non-admins and feature-off requests cannot change domains", context do
    path = "/dashboard/orgs/#{context.organization.name}/sso/domains"

    conn =
      build_conn()
      |> test_login(context.member)
      |> post(path, %{"domain" => %{"domain" => "example.com"}})

    assert redirected_to(conn) == "/dashboard/orgs/#{context.organization.name}"
    refute Repo.exists?(Domain)

    disable_sso()

    conn =
      build_conn()
      |> test_login(context.admin)
      |> post(path, %{"domain" => %{"domain" => "example.com"}})

    assert response(conn, 404)
    refute Repo.exists?(Domain)
  end

  defp enable_beta_for(organization) do
    config = Application.fetch_env!(:hexpm, :organization_sso)

    Application.put_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, mode: :beta, beta_organizations: [organization.name])
    )

    on_exit(fn -> Application.put_env(:hexpm, :organization_sso, config) end)
  end

  defp disable_sso do
    config = Application.fetch_env!(:hexpm, :organization_sso)
    Application.put_env(:hexpm, :organization_sso, Keyword.put(config, :mode, :off))
  end
end
