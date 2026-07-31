defmodule Hexpm.TrustedPublishers.Provider.GitHubTest do
  use Hexpm.DataCase, async: true
  import Mox

  alias Hexpm.TrustedPublishers.Provider.GitHub
  alias Hexpm.TrustedPublishers.TrustedPublisher

  setup :verify_on_exit!

  describe "match?/2" do
    test "matches repository, workflow filename, and owner id" do
      publisher = %TrustedPublisher{
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

      assert GitHub.match?(publisher, claims)
    end

    test "rejects mismatched repository_owner_id (anti-resurrection)" do
      publisher = %TrustedPublisher{
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

      refute GitHub.match?(publisher, claims)
    end

    test "rejects mismatched repository_id" do
      publisher = %TrustedPublisher{
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

      refute GitHub.match?(publisher, claims)
    end

    test "rejects wrong repository claim" do
      publisher = %TrustedPublisher{
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

      refute GitHub.match?(publisher, claims)
    end

    test "requires environment when configured" do
      publisher = %TrustedPublisher{
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

      refute GitHub.match?(publisher, claims)

      assert GitHub.match?(publisher, Map.put(claims, "environment", "production"))
    end

    test "uses workflow_ref even when job_workflow_ref points at a reusable workflow" do
      publisher = %TrustedPublisher{
        repository_owner_id: "123",
        repository_id: nil,
        repository: "acme/widget",
        workflow: "release.yml",
        environment: ""
      }

      claims = %{
        "repository" => "acme/widget",
        "repository_owner_id" => "123",
        "workflow_ref" => "acme/widget/.github/workflows/release.yml@refs/heads/main",
        "job_workflow_ref" => "org/actions/.github/workflows/publish.yml@refs/heads/main"
      }

      assert GitHub.match?(publisher, claims)
    end

    test "rejects reusable workflow basename from another repository" do
      publisher = %TrustedPublisher{
        repository_owner_id: "123",
        repository_id: nil,
        repository: "acme/widget",
        workflow: "release.yml",
        environment: ""
      }

      claims = %{
        "repository" => "acme/widget",
        "repository_owner_id" => "123",
        "job_workflow_ref" => "evil-org/anything/.github/workflows/release.yml@refs/heads/main"
      }

      refute GitHub.match?(publisher, claims)
    end

    test "matches repository names case-insensitively" do
      publisher = %TrustedPublisher{
        repository_owner_id: "123",
        repository_id: nil,
        repository: "acme/widget",
        workflow: "release.yml",
        environment: ""
      }

      claims = %{
        "repository" => "Acme/Widget",
        "repository_owner_id" => "123",
        "workflow_ref" => "Acme/Widget/.github/workflows/release.yml@refs/heads/main"
      }

      assert GitHub.match?(publisher, claims)
    end
  end

  describe "resolve_immutable_ids/1" do
    test "resolves owner and repository ids from GitHub API" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _headers, _opts ->
        {:ok, 200, [], %{"id" => 123}}
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget",
                                       _headers,
                                       _opts ->
        {:ok, 200, [], %{"id" => 456}}
      end)

      assert {:ok, %{repository_owner_id: 123, repository_id: 456}} =
               GitHub.resolve_immutable_ids(%{
                 repository_owner: "acme",
                 repository: "acme/widget"
               })
    end

    test "maps owner 404 to repository_owner_not_found" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/missing", _, _ ->
        {:ok, 404, [], %{}}
      end)

      assert {:error, :repository_owner_not_found} =
               GitHub.resolve_immutable_ids(%{
                 repository_owner: "missing",
                 repository: "missing/widget"
               })
    end

    test "maps repository 404 to repository_not_found" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 200, [], %{"id" => 123}}
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/missing", _, _ ->
        {:ok, 404, [], %{}}
      end)

      assert {:error, :repository_not_found} =
               GitHub.resolve_immutable_ids(%{
                 repository_owner: "acme",
                 repository: "acme/missing"
               })
    end
  end
end
