defmodule Hexpm.WorkloadIdentities.Provider.GitHubTest do
  use Hexpm.DataCase, async: true
  import Mox

  alias Hexpm.WorkloadIdentities.Provider.GitHub
  alias Hexpm.WorkloadIdentities.WorkloadIdentity

  setup :verify_on_exit!

  describe "match?/2" do
    test "an @ in the workflow filename doesn't pass for the name before it" do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repository_id: "456",
        repository: "acme/widget",
        workflow: "release.yml",
        environment: ""
      }

      claims = fn workflow_ref ->
        %{
          "repository" => "acme/widget",
          "repository_owner_id" => "123",
          "repository_id" => "456",
          "workflow_ref" => workflow_ref,
          "job_workflow_ref" => workflow_ref
        }
      end

      refute GitHub.match?(
               identity,
               claims.("acme/widget/.github/workflows/release.yml@x.yml@refs/heads/main")
             )

      assert GitHub.match?(
               identity,
               claims.("acme/widget/.github/workflows/release.yml@refs/heads/a@b")
             )

      assert GitHub.match?(
               identity,
               claims.("acme/widget/.github/workflows/release.yml@refs/tags/v1.0.0")
             )
    end

    test "an empty repository matches every repository of the owner only for an organization read workload identity" do
      claims = fn repository, repository_id, owner_id ->
        %{
          "repository" => repository,
          "repository_owner_id" => owner_id,
          "repository_id" => repository_id,
          "workflow_ref" => "#{repository}/.github/workflows/ci.yml@refs/heads/main"
        }
      end

      identity = %WorkloadIdentity{
        repository_owner: "acme",
        repository_owner_id: "123",
        repository_id: "",
        repository: "",
        workflow: "",
        environment: "",
        role: "read",
        organization_id: 1
      }

      assert GitHub.match?(identity, claims.("acme/widget", "456", "123"))
      assert GitHub.match?(identity, claims.("acme/gadget", "789", "123"))
      refute GitHub.match?(identity, claims.("other/widget", "456", "999"))

      refute GitHub.match?(
               identity,
               Map.delete(claims.("acme/widget", "456", "123"), "repository_id")
             )

      refute GitHub.match?(%{identity | role: "write"}, claims.("acme/widget", "456", "123"))

      refute GitHub.match?(
               %{identity | organization_id: nil, package_id: 1},
               claims.("acme/widget", "456", "123")
             )
    end

    test "an empty workflow matches any workflow only for an organization read workload identity" do
      claims = %{
        "repository" => "acme/widget",
        "repository_owner_id" => "123",
        "repository_id" => "456",
        "workflow_ref" => "acme/widget/.github/workflows/test.yml@refs/heads/main"
      }

      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repository_id: "456",
        repository: "acme/widget",
        workflow: "",
        environment: "",
        role: "read",
        organization_id: 1
      }

      assert GitHub.match?(identity, claims)
      refute GitHub.match?(%{identity | role: "write"}, claims)
      refute GitHub.match?(%{identity | organization_id: nil, package_id: 1}, claims)
    end

    test "matches repository, workflow filename, and owner id" do
      identity = %WorkloadIdentity{
        provider: "github",
        repository_owner: "acme",
        repository_owner_id: "123",
        repository_id: "456",
        repository: "acme/widget",
        workflow: "release.yml",
        environment: ""
      }

      claims = %{
        "repository" => "acme/widget",
        "repository_owner_id" => "123",
        "repository_id" => "456",
        "workflow_ref" => "acme/widget/.github/workflows/release.yml@refs/heads/main"
      }

      assert GitHub.match?(identity, claims)
    end

    test "rejects mismatched repository_owner_id (anti-resurrection)" do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repository_id: "456",
        repository: "acme/widget",
        workflow: "release.yml",
        environment: ""
      }

      claims = %{
        "repository" => "acme/widget",
        "repository_owner_id" => "999",
        "repository_id" => "456",
        "workflow_ref" => "acme/widget/.github/workflows/release.yml@refs/heads/main"
      }

      refute GitHub.match?(identity, claims)
    end

    test "rejects mismatched repository_id" do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repository_id: "456",
        repository: "acme/widget",
        workflow: "release.yml",
        environment: ""
      }

      claims = %{
        "repository" => "acme/widget",
        "repository_owner_id" => "123",
        "repository_id" => "999",
        "workflow_ref" => "acme/widget/.github/workflows/release.yml@refs/heads/main"
      }

      refute GitHub.match?(identity, claims)
    end

    test "rejects wrong repository claim" do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repository_id: "456",
        repository: "acme/widget",
        workflow: "release.yml",
        environment: ""
      }

      claims = %{
        "repository" => "acme/other",
        "repository_owner_id" => "123",
        "repository_id" => "456",
        "workflow_ref" => "acme/other/.github/workflows/release.yml@refs/heads/main"
      }

      refute GitHub.match?(identity, claims)
    end

    test "requires environment when configured" do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repository_id: "456",
        repository: "acme/widget",
        workflow: "release.yml",
        environment: "production"
      }

      claims = %{
        "repository" => "acme/widget",
        "repository_owner_id" => "123",
        "repository_id" => "456",
        "workflow_ref" => "acme/widget/.github/workflows/release.yml@refs/heads/main",
        "environment" => "staging"
      }

      refute GitHub.match?(identity, claims)

      assert GitHub.match?(identity, Map.put(claims, "environment", "production"))
    end

    test "uses workflow_ref even when job_workflow_ref points at a reusable workflow" do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repository_id: "456",
        repository: "acme/widget",
        workflow: "release.yml",
        environment: ""
      }

      claims = %{
        "repository" => "acme/widget",
        "repository_owner_id" => "123",
        "repository_id" => "456",
        "workflow_ref" => "acme/widget/.github/workflows/release.yml@refs/heads/main",
        "job_workflow_ref" => "org/actions/.github/workflows/publish.yml@refs/heads/main"
      }

      assert GitHub.match?(identity, claims)
    end

    test "rejects reusable workflow basename from another repository" do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repository_id: "456",
        repository: "acme/widget",
        workflow: "release.yml",
        environment: ""
      }

      claims = %{
        "repository" => "acme/widget",
        "repository_owner_id" => "123",
        "repository_id" => "456",
        "job_workflow_ref" => "evil-org/anything/.github/workflows/release.yml@refs/heads/main"
      }

      refute GitHub.match?(identity, claims)
    end

    test "matches repository names case-insensitively" do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repository_id: "456",
        repository: "acme/widget",
        workflow: "release.yml",
        environment: ""
      }

      claims = %{
        "repository" => "Acme/Widget",
        "repository_owner_id" => "123",
        "repository_id" => "456",
        "workflow_ref" => "Acme/Widget/.github/workflows/release.yml@refs/heads/main"
      }

      assert GitHub.match?(identity, claims)
    end

    test "rejects workflow filename differing only by casing" do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repository_id: "456",
        repository: "acme/widget",
        workflow: "release.yml",
        environment: ""
      }

      claims = %{
        "repository" => "acme/widget",
        "repository_owner_id" => "123",
        "repository_id" => "456",
        "workflow_ref" => "acme/widget/.github/workflows/Release.yml@refs/heads/main"
      }

      refute GitHub.match?(identity, claims)
    end

    test "matches environment differing only by casing" do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repository_id: "456",
        repository: "acme/widget",
        workflow: "release.yml",
        environment: "production"
      }

      claims = %{
        "repository" => "acme/widget",
        "repository_owner_id" => "123",
        "repository_id" => "456",
        "workflow_ref" => "acme/widget/.github/workflows/release.yml@refs/heads/main",
        "environment" => "Production"
      }

      assert GitHub.match?(identity, claims)
    end

    test "rejects claims without a usable workflow ref" do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repository_id: "456",
        repository: "acme/widget",
        workflow: nil,
        environment: ""
      }

      claims = %{
        "repository" => "acme/widget",
        "repository_owner_id" => "123",
        "repository_id" => "456"
      }

      refute GitHub.match?(identity, claims)
    end

    test "rejects claims without a repository id" do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repository_id: "456",
        repository: "acme/widget",
        workflow: "release.yml",
        environment: ""
      }

      claims = %{
        "repository" => "acme/widget",
        "repository_owner_id" => "123",
        "workflow_ref" => "acme/widget/.github/workflows/release.yml@refs/heads/main"
      }

      refute GitHub.match?(identity, claims)
    end
  end

  describe "validate_claims/1" do
    test "rejects pull_request_target" do
      assert GitHub.validate_claims(%{"event_name" => "pull_request_target"}) ==
               {:error, :event_not_allowed}
    end

    test "rejects workflow_run" do
      assert GitHub.validate_claims(%{"event_name" => "workflow_run"}) ==
               {:error, :event_not_allowed}
    end

    test "accepts other events" do
      assert GitHub.validate_claims(%{"event_name" => "push"}) == :ok
      assert GitHub.validate_claims(%{"event_name" => "release"}) == :ok
      assert GitHub.validate_claims(%{}) == :ok
    end
  end

  describe "resolve_immutable_ids/1" do
    test "resolves owner and repository ids from a single repository lookup" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget",
                                       _headers,
                                       _opts ->
        {:ok, 200, [], %{"id" => 456, "owner" => %{"id" => 123}}}
      end)

      assert {:ok, %{repository_owner_id: 123, repository_id: 456}} =
               GitHub.resolve_immutable_ids(%{repository: "acme/widget"})
    end

    test "pins only the owner id for a workload identity that matches every repository" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 200, [], %{"id" => 123}}
      end)

      assert {:ok, %{repository_owner_id: 123, repository_id: nil}} =
               GitHub.resolve_immutable_ids(%{repository: "", repository_owner: "acme"})
    end

    test "pins only the owner id for a repository Hex cannot see" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/private", _, _ ->
        {:ok, 404, [], %{}}
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 200, [], %{"id" => 123}}
      end)

      assert {:ok, %{repository_owner_id: 123, repository_id: nil}} =
               GitHub.resolve_immutable_ids(%{repository: "acme/private"})
    end

    test "maps an unknown owner to repository_not_found" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/missing/widget", _, _ ->
        {:ok, 404, [], %{}}
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/missing", _, _ ->
        {:ok, 404, [], %{}}
      end)

      assert {:error, :repository_not_found} =
               GitHub.resolve_immutable_ids(%{repository: "missing/widget"})
    end

    test "maps an owner response without an id to invalid_github_response" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/private", _, _ ->
        {:ok, 404, [], %{}}
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 200, [], %{"login" => "acme"}}
      end)

      assert {:error, :invalid_github_response} =
               GitHub.resolve_immutable_ids(%{repository: "acme/private"})
    end

    test "propagates a rate-limited owner lookup" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/private", _, _ ->
        {:ok, 404, [], %{}}
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 403, [], %{}}
      end)

      assert {:error, {:http_status, 403}} =
               GitHub.resolve_immutable_ids(%{repository: "acme/private"})
    end

    test "maps a response without an owner id to invalid_github_response" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 456}}
      end)

      assert {:error, :invalid_github_response} =
               GitHub.resolve_immutable_ids(%{repository: "acme/widget"})
    end

    test "propagates a rate-limited response" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 403, [], %{}}
      end)

      assert {:error, {:http_status, 403}} =
               GitHub.resolve_immutable_ids(%{repository: "acme/widget"})
    end

    test "rejects a repository that is not owner-qualified without calling GitHub" do
      assert {:error, :repository_not_found} =
               GitHub.resolve_immutable_ids(%{repository: "widget"})
    end
  end
end
