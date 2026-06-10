defmodule HexpmWeb.Dashboard.OrganizationController.PolicyTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Repository.{OrganizationPolicy, Policies}

  defp mock_customer() do
    stub(Hexpm.Billing.Mock, :get, fn _token, _opts ->
      %{"checkout_html" => "", "invoices" => []}
    end)
  end

  setup do
    user = insert(:user)
    organization = insert(:organization, billing_active: true)
    insert(:organization_user, organization: organization, user: user, role: "admin")
    mock_customer()
    %{user: user, organization: organization}
  end

  describe "index" do
    test "renders the policies page", %{user: user, organization: org} do
      conn = build_conn() |> test_login(user)
      conn = get(conn, "/dashboard/orgs/#{org.name}/policies")

      response = html_response(conn, 200)
      assert response =~ "Policies"
      assert response =~ "Policies define dependency resolution rules that projects can opt into"
      assert response =~ "Rules are evaluated separately for each repository"
      assert response =~ "Documentation"
      assert response =~ "No policies yet"
      assert response =~ "Create policy"
      refute response =~ "Dependency policies are in preview"
      refute response =~ "Hex v2.5.0"
    end

    test "renders repository summaries for policies", %{user: user, organization: org} do
      {:ok, %{policy: policy}} =
        Policies.create(
          org,
          %{
            "name" => "strict-prod",
            "visibility" => "private",
            "repositories" => [%{"repository" => "hexpm", "cooldown" => "14d"}]
          },
          audit: audit_data(user)
        )

      conn = build_conn() |> test_login(user)
      conn = get(conn, "/dashboard/orgs/#{org.name}/policies")

      response = html_response(conn, 200)
      assert response =~ policy.name
      assert response =~ "#{org.name}/#{policy.name}"
      assert response =~ "14d"
      refute response =~ "Allow all"
    end

    test "reader role can view", %{organization: org} do
      reader = insert(:user)
      insert(:organization_user, organization: org, user: reader, role: "read")
      conn = build_conn() |> test_login(reader)
      conn = get(conn, "/dashboard/orgs/#{org.name}/policies")

      assert html_response(conn, 200) =~ "Policies"
    end
  end

  describe "create" do
    test "renders the new policy form", %{user: user, organization: org} do
      conn = build_conn() |> test_login(user)
      conn = get(conn, "/dashboard/orgs/#{org.name}/policies/new")

      response = html_response(conn, 200)
      assert response =~ "New policy"
      assert response =~ "e.g. production-baseline"
      assert response =~ "What is this policy for?"
      assert response =~ "Create policy"
    end

    test "creates a public policy", %{user: user, organization: org} do
      conn = build_conn() |> test_login(user)
      params = %{"policy" => %{"name" => "strict-prod", "visibility" => "public"}}

      conn = post(conn, "/dashboard/orgs/#{org.name}/policies", params)

      assert redirected_to(conn) =~ "/dashboard/orgs/#{org.name}/policies/strict-prod"
      assert Policies.get(org, "strict-prod")
    end

    test "renders errors for invalid params", %{user: user, organization: org} do
      conn = build_conn() |> test_login(user)
      params = %{"policy" => %{"name" => "ab", "visibility" => "public"}}

      conn = post(conn, "/dashboard/orgs/#{org.name}/policies", params)

      assert html_response(conn, 400) =~ "at least 3"
      refute Policies.get(org, "ab")
    end

    test "rejects a reserved name", %{user: user, organization: org} do
      conn = build_conn() |> test_login(user)
      params = %{"policy" => %{"name" => "new", "visibility" => "public"}}

      conn = post(conn, "/dashboard/orgs/#{org.name}/policies", params)

      assert html_response(conn, 400) =~ "is reserved"
      refute Policies.get(org, "new")
    end
  end

  describe "update" do
    test "updates a repository tab's restriction", %{user: user, organization: org} do
      {:ok, %{policy: policy}} =
        Policies.create(org, %{"name" => "polone", "visibility" => "private"},
          audit: audit_data(user)
        )

      conn = build_conn() |> test_login(user)

      params = %{
        "policy" => %{
          "visibility" => "private",
          "repositories" => repository_params(policy, "hexpm", %{"cooldown" => "7d"})
        }
      }

      conn = post(conn, "/dashboard/orgs/#{org.name}/policies/#{policy.name}", params)

      assert redirected_to(conn) =~ "/dashboard/orgs/#{org.name}/policies/polone"

      updated = Policies.get(org, "polone")
      hexpm = Enum.find(updated.repositories, &(&1.repository == "hexpm"))
      assert hexpm.cooldown == "7d"
      # the org tab survives the round-trip
      assert Enum.any?(updated.repositories, &(&1.repository == org.name))
    end

    test "ignores an attempt to rename the policy", %{user: user, organization: org} do
      {:ok, %{policy: policy}} =
        Policies.create(org, %{"name" => "polone", "visibility" => "public"},
          audit: audit_data(user)
        )

      conn = build_conn() |> test_login(user)

      params = %{
        "policy" => %{
          "name" => "renamed",
          "visibility" => "public",
          "repositories" => repository_params(policy, "hexpm", %{})
        }
      }

      conn = post(conn, "/dashboard/orgs/#{org.name}/policies/#{policy.name}", params)

      assert redirected_to(conn) =~ "/dashboard/orgs/#{org.name}/policies/polone"
      assert Policies.get(org, "polone")
      refute Policies.get(org, "renamed")
    end
  end

  # Builds the nested repositories params the edit form submits: every existing
  # tab (matched by id) with `extra` merged into the named one.
  defp repository_params(policy, repository, extra) do
    policy.repositories
    |> Enum.with_index()
    |> Map.new(fn {repo, index} ->
      base = %{"id" => repo.id, "repository" => repo.repository}
      base = if repo.repository == repository, do: Map.merge(base, extra), else: base
      {to_string(index), base}
    end)
  end

  describe "edit" do
    test "renders the edit page with repository tabs", %{user: user, organization: org} do
      {:ok, %{policy: policy}} =
        Policies.create(org, %{"name" => "strict-prod", "visibility" => "private"},
          audit: audit_data(user)
        )

      conn = build_conn() |> test_login(user)
      conn = get(conn, "/dashboard/orgs/#{org.name}/policies/#{policy.name}")

      response = html_response(conn, 200)
      assert response =~ "Repository rules"
      assert response =~ "How resolution works"
      assert response =~ "Overrides"
      assert response =~ "hexpm"
      assert response =~ org.name
      refute response =~ "Allowed packages"
      refute response =~ "Allow all"
    end

    test "admin sees the save and delete affordances", %{user: user, organization: org} do
      {:ok, %{policy: policy}} =
        Policies.create(org, %{"name" => "strict-prod", "visibility" => "private"},
          audit: audit_data(user)
        )

      conn = build_conn() |> test_login(user)
      conn = get(conn, "/dashboard/orgs/#{org.name}/policies/#{policy.name}")

      response = html_response(conn, 200)
      assert response =~ "Save policy"
      assert response =~ "delete-policy-header-btn"
      refute response =~ "You need the admin role to edit this policy"
    end

    test "reader sees a read-only notice without save or delete", %{organization: org} do
      reader = insert(:user)
      insert(:organization_user, organization: org, user: reader, role: "read")

      {:ok, %{policy: policy}} =
        Policies.create(org, %{"name" => "strict-prod", "visibility" => "private"},
          audit: audit_data(reader)
        )

      conn = build_conn() |> test_login(reader)
      conn = get(conn, "/dashboard/orgs/#{org.name}/policies/#{policy.name}")

      response = html_response(conn, 200)
      assert response =~ "You need the admin role to edit this policy"
      refute response =~ "Save policy"
      refute response =~ "delete-policy-header-btn"
    end

    test "renders existing restrictions and overrides", %{user: user, organization: org} do
      {:ok, %{policy: policy}} =
        Policies.create(
          org,
          %{
            "name" => "strict-prod",
            "visibility" => "public",
            "repositories" => [
              %{
                "repository" => "hexpm",
                "cooldown" => "14d",
                "advisory_min_severity" => 3,
                "overrides" => [%{"action" => "deny", "package" => "badlib"}]
              },
              %{"repository" => org.name}
            ]
          },
          audit: audit_data(user)
        )

      conn = build_conn() |> test_login(user)
      conn = get(conn, "/dashboard/orgs/#{org.name}/policies/#{policy.name}")

      response = html_response(conn, 200)
      assert response =~ "14d"
      assert response =~ "badlib"

      {:ok, document} = Floki.parse_document(response)

      assert [_ | _] = Floki.find(document, ~s(input[data-override-package]))
      assert [_ | _] = Floki.find(document, ~s(input[data-override-requirement]))
      assert [_ | _] = Floki.find(document, ~s([data-override-suggestions="package"]))
      assert [_ | _] = Floki.find(document, ~s([data-override-suggestions="version"]))

      assert [card | _] = Floki.find(document, ~s([phx-hook="OverrideList"]))
      assert [package_url] = Floki.attribute(card, "data-package-suggestions-url")
      assert [version_url] = Floki.attribute(card, "data-version-suggestions-url")
      assert package_url =~ "/policies/package-suggestions"
      assert package_url =~ "repository=hexpm"
      assert version_url =~ "/policies/version-suggestions"
      assert version_url =~ "repository=hexpm"
      refute response =~ "data-package-catalog"
      refute response =~ "<datalist"
    end

    test "suggests override packages with the existing bounded package search", %{
      user: user,
      organization: org
    } do
      for index <- 1..10 do
        package = insert(:package, name: "dep_pkg_#{index}")
        insert(:release, package: package, version: "1.0.#{index}")
      end

      conn = build_conn() |> test_login(user)

      conn =
        get(
          conn,
          "/dashboard/orgs/#{org.name}/policies/package-suggestions?repository=hexpm&term=dep"
        )

      items = json_response(conn, 200)["items"]
      assert length(items) == 8
      assert Enum.all?(items, &String.starts_with?(&1["name"], "dep_pkg_"))
    end

    test "suggests override packages from the organization repository", %{
      user: user,
      organization: org
    } do
      org_repo = insert(:repository, name: org.name, organization: org)

      package =
        insert(:package, name: "internal_dep", repository: org_repo, repository_id: org_repo.id)

      insert(:release, package: package, version: "0.3.0")

      conn = build_conn() |> test_login(user)

      conn =
        get(
          conn,
          "/dashboard/orgs/#{org.name}/policies/package-suggestions?repository=#{org.name}&term=internal"
        )

      assert [%{"name" => "internal_dep", "latest_version" => "0.3.0"}] =
               json_response(conn, 200)["items"]
    end

    test "suggests override versions for the selected package", %{
      user: user,
      organization: org
    } do
      package = insert(:package, name: "badlib")
      insert(:release, package: package, version: "1.0.0")
      insert(:release, package: package, version: "1.2.3")
      insert(:release, package: package, version: "2.0.0")

      conn = build_conn() |> test_login(user)

      conn =
        get(
          conn,
          "/dashboard/orgs/#{org.name}/policies/version-suggestions?repository=hexpm&package=badlib&term=1."
        )

      assert [%{"version" => "1.2.3"}, %{"version" => "1.0.0"}] =
               json_response(conn, 200)["items"]
    end

    test "renders the org repository tab for policies missing it", %{
      user: user,
      organization: org
    } do
      policy =
        %OrganizationPolicy{organization_id: org.id}
        |> OrganizationPolicy.changeset(%{
          "name" => "public-only",
          "visibility" => "public",
          "repositories" => [%{"repository" => "hexpm"}]
        })
        |> Repo.insert!()

      conn = build_conn() |> test_login(user)
      conn = get(conn, "/dashboard/orgs/#{org.name}/policies/#{policy.name}")

      {:ok, document} = Floki.parse_document(html_response(conn, 200))

      assert [tablist] = Floki.find(document, "#repo-tabs")
      assert Floki.attribute(tablist, "data-panel-container") == ["#repo-config"]

      assert [tab] = Floki.find(document, ~s(#repo-tabs [data-value="#{org.name}"]))
      assert Floki.attribute(tab, "data-private-only") == ["true"]
      refute Floki.attribute(tab, "hidden") == []

      assert [panel] = Floki.find(document, ~s(#repo-config [data-panel="#{org.name}"]))
      refute Floki.attribute(panel, "hidden") == []
    end
  end

  describe "delete" do
    test "deletes a policy", %{user: user, organization: org} do
      {:ok, %{policy: policy}} =
        Policies.create(org, %{"name" => "doomed", "visibility" => "public"},
          audit: audit_data(user)
        )

      conn = build_conn() |> test_login(user)
      conn = delete(conn, "/dashboard/orgs/#{org.name}/policies/#{policy.name}")

      assert redirected_to(conn) == "/dashboard/orgs/#{org.name}/policies"
      assert is_nil(Policies.get(org, "doomed"))
    end
  end

  describe "tier gating" do
    test "free org cannot create a private policy", %{user: user} do
      free_org = insert(:organization, billing_active: false)
      insert(:organization_user, organization: free_org, user: user, role: "admin")

      conn = build_conn() |> test_login(user)
      params = %{"policy" => %{"name" => "secret", "visibility" => "private"}}
      conn = post(conn, "/dashboard/orgs/#{free_org.name}/policies", params)

      assert html_response(conn, 400) =~ "private policies require a paid plan"
      assert is_nil(Policies.get(free_org, "secret"))
    end

    test "paid org can create a private policy", %{user: user, organization: org} do
      conn = build_conn() |> test_login(user)
      params = %{"policy" => %{"name" => "secret", "visibility" => "private"}}
      conn = post(conn, "/dashboard/orgs/#{org.name}/policies", params)

      assert redirected_to(conn) =~ "/dashboard/orgs/#{org.name}/policies/secret"
      assert Policies.get(org, "secret").visibility == "private"
    end

    test "free org cannot flip a public policy to private", %{user: user} do
      free_org = insert(:organization, billing_active: false)
      insert(:organization_user, organization: free_org, user: user, role: "admin")

      {:ok, %{policy: policy}} =
        Policies.create(free_org, %{"name" => "pol1", "visibility" => "public"},
          audit: audit_data(user)
        )

      conn = build_conn() |> test_login(user)
      params = %{"policy" => %{"visibility" => "private"}}
      conn = post(conn, "/dashboard/orgs/#{free_org.name}/policies/#{policy.name}", params)

      assert html_response(conn, 400) =~ "private policies require a paid plan"
      assert Policies.get(free_org, "pol1").visibility == "public"
    end
  end
end
