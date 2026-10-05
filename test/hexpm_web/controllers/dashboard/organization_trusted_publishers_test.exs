defmodule HexpmWeb.Dashboard.OrganizationTrustedPublishersTest do
  use HexpmWeb.ConnCase, async: false

  import Mox

  alias Hexpm.Accounts.AuditLog
  alias Hexpm.TrustedPublishers
  alias Hexpm.TrustedPublishers.TrustedPublisher

  setup :verify_on_exit!

  setup do
    admin = insert(:user_with_tfa)
    writer = insert(:user)
    reader = insert(:user)

    repository =
      insert(:repository,
        organization:
          build(:organization,
            organization_users: [
              build(:organization_user, user: admin, role: "admin"),
              build(:organization_user, user: writer, role: "write"),
              build(:organization_user, user: reader, role: "read")
            ]
          )
      )

    %{admin: admin, writer: writer, reader: reader, organization: repository.organization}
  end

  defp path(organization), do: "/dashboard/orgs/#{organization.name}/trusted-publishers"

  defp publisher_params(params) do
    %{
      "trusted_publisher" =>
        Map.merge(
          %{"provider" => "github", "repository_owner" => "acme", "repository" => "widget"},
          params
        )
    }
  end

  describe "GET /dashboard/orgs/:dashboard_org/trusted-publishers" do
    test "shows the publishers and the form to an admin", %{
      admin: admin,
      organization: organization
    } do
      insert(:organization_trusted_publisher,
        organization: organization,
        role: "write",
        repository: "acme/widget",
        workflow: "release.yml",
        packages: ["widget", "gadget"]
      )

      body =
        build_conn()
        |> test_login(admin)
        |> get(path(organization))
        |> html_response(200)

      assert body =~ "acme/widget"
      assert body =~ "release.yml"
      assert body =~ "widget, gadget"
      assert body =~ "add-trusted-publisher-form"
    end

    test "shows the publishers without the form to a write member", %{
      writer: writer,
      organization: organization
    } do
      insert(:organization_trusted_publisher,
        organization: organization,
        repository: "acme/widget"
      )

      body =
        build_conn()
        |> test_login(writer)
        |> get(path(organization))
        |> html_response(200)

      assert body =~ "acme/widget"
      assert body =~ "Only organization admins can add and remove trusted publishers."
      refute body =~ "add-trusted-publisher-form"
    end

    test "refuses a read member", %{reader: reader, organization: organization} do
      conn =
        build_conn()
        |> test_login(reader)
        |> get(path(organization))

      assert conn.status == 400
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "permission"
    end

    test "requires sudo", %{admin: admin, organization: organization} do
      conn =
        build_conn()
        |> test_login(admin, sudo: false)
        |> get(path(organization))

      assert redirected_to(conn) =~ "/sudo"
    end

    test "returns 404 and hides the tab when the feature is disabled", %{
      admin: admin,
      organization: organization
    } do
      previous = Application.get_env(:hexpm, :features)
      Application.put_env(:hexpm, :features, trusted_publishers: false)
      on_exit(fn -> Application.put_env(:hexpm, :features, previous) end)

      conn = build_conn() |> test_login(admin) |> get(path(organization))
      assert conn.status == 404

      body =
        build_conn()
        |> test_login(admin)
        |> get("/dashboard/orgs/#{organization.name}")
        |> html_response(200)

      refute body =~ path(organization)
    end
  end

  describe "POST /dashboard/orgs/:dashboard_org/trusted-publishers" do
    test "adds a publisher", %{admin: admin, organization: organization} do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 22, "owner" => %{"id" => 11}}}
      end)

      conn =
        build_conn()
        |> test_login(admin)
        |> post(path(organization), publisher_params(%{"role" => "read", "workflow" => ""}))

      assert redirected_to(conn) == path(organization)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "added"

      assert [publisher] = TrustedPublishers.list(organization)
      assert publisher.role == "read"
      assert publisher.workflow == ""
      assert Repo.get_by(AuditLog, action: "organization.trusted_publisher.add")
    end

    test "adds a publisher for every repository of the owner", %{
      admin: admin,
      organization: organization
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 200, [], %{"id" => 11}}
      end)

      conn =
        build_conn()
        |> test_login(admin)
        |> post(path(organization), publisher_params(%{"role" => "read", "repository" => ""}))

      assert redirected_to(conn) == path(organization)

      body =
        build_conn()
        |> test_login(admin)
        |> get(path(organization))
        |> html_response(200)

      assert body =~ "Any repository owned by acme"
    end

    test "renders errors for an invalid publisher", %{admin: admin, organization: organization} do
      conn =
        build_conn()
        |> test_login(admin)
        |> post(
          path(organization),
          publisher_params(%{"role" => "write", "packages" => "widget"})
        )

      body = html_response(conn, 400)
      assert body =~ "is required for the write role"
      assert body =~ ~s(value="widget")
      assert TrustedPublishers.list(organization) == []
    end

    test "refuses a write member", %{writer: writer, organization: organization} do
      conn =
        build_conn()
        |> test_login(writer)
        |> post(path(organization), publisher_params(%{"role" => "read"}))

      assert conn.status == 400
      assert TrustedPublishers.list(organization) == []
    end

    test "requires 2FA on the admin's account", %{organization: organization} do
      admin = insert(:user)
      insert(:organization_user, organization: organization, user: admin, role: "admin")

      conn =
        build_conn()
        |> test_login(admin)
        |> post(path(organization), publisher_params(%{"role" => "read"}))

      assert redirected_to(conn) == "/dashboard/security"
      assert get_session(conn, :tfa_return_to) == path(organization)
      assert TrustedPublishers.list(organization) == []
    end

    test "refuses an organization without active billing", %{
      admin: admin,
      organization: organization
    } do
      organization
      |> Ecto.Changeset.change(billing_active: false)
      |> Repo.update!()

      conn =
        build_conn()
        |> test_login(admin)
        |> post(path(organization), publisher_params(%{"role" => "read"}))

      assert redirected_to(conn) == path(organization)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "no active billing subscription"
      assert TrustedPublishers.list(organization) == []
    end
  end

  describe "DELETE /dashboard/orgs/:dashboard_org/trusted-publishers/:id" do
    test "removes a publisher", %{admin: admin, organization: organization} do
      publisher = insert(:organization_trusted_publisher, organization: organization)

      conn =
        build_conn()
        |> test_login(admin)
        |> delete("#{path(organization)}/#{publisher.id}")

      assert redirected_to(conn) == path(organization)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "removed"
      refute Repo.get(TrustedPublisher, publisher.id)
    end

    test "refuses another organization's publisher", %{admin: admin, organization: organization} do
      publisher = insert(:organization_trusted_publisher)

      conn =
        build_conn()
        |> test_login(admin)
        |> delete("#{path(organization)}/#{publisher.id}")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not found"
      assert Repo.get(TrustedPublisher, publisher.id)
    end

    test "refuses a write member", %{writer: writer, organization: organization} do
      publisher = insert(:organization_trusted_publisher, organization: organization)

      conn =
        build_conn()
        |> test_login(writer)
        |> delete("#{path(organization)}/#{publisher.id}")

      assert conn.status == 400
      assert Repo.get(TrustedPublisher, publisher.id)
    end
  end
end
