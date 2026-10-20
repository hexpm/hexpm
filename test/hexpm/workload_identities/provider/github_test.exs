defmodule Hexpm.WorkloadIdentities.Provider.GitHubTest do
  use Hexpm.DataCase, async: true
  import Mox

  alias Hexpm.WorkloadIdentities.Provider.GitHub
  alias Hexpm.WorkloadIdentities.{TrustedRepository, WorkloadIdentity}

  setup :verify_on_exit!

  describe "match?/2" do
    test "an @ in the workflow filename doesn't pass for the name before it" do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
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

    test "no repositories match every repository of the owner only for an organization read workload identity" do
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
        repositories: [],
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
        repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
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
        repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
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
        repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
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
        repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
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
        repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
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
        repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
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
        repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
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
        repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
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
        repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
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
        repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
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

    test "requires an environment on a write workload identity from a public repository" do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
        workflow: "release.yml",
        environment: ""
      }

      claims = %{
        "repository" => "acme/widget",
        "repository_owner_id" => "123",
        "repository_id" => "456",
        "workflow_ref" => "acme/widget/.github/workflows/release.yml@refs/heads/main",
        "repository_visibility" => "public"
      }

      refute GitHub.match?(identity, claims)
      refute GitHub.match?(identity, Map.put(claims, "environment", "release"))
      assert GitHub.match?(identity, Map.put(claims, "repository_visibility", "private"))
      assert GitHub.match?(identity, Map.put(claims, "repository_visibility", "internal"))

      assert GitHub.match?(
               %{identity | environment: "release"},
               Map.put(claims, "environment", "release")
             )

      assert GitHub.match?(%{identity | role: "read", organization_id: 1}, claims)
    end

    test "matches environment differing only by casing" do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
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
        repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
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
        repositories: [%TrustedRepository{name: "acme/widget", id: "456"}],
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

  describe "match?/2 with several repositories" do
    setup do
      identity = %WorkloadIdentity{
        repository_owner_id: "123",
        repositories: [
          %TrustedRepository{name: "acme/widget", id: "456"},
          %TrustedRepository{name: "acme/gadget", id: "789"}
        ],
        workflow: "release.yml",
        environment: ""
      }

      claims = fn repository, repository_id ->
        %{
          "repository" => repository,
          "repository_owner_id" => "123",
          "repository_id" => repository_id,
          "workflow_ref" => "#{repository}/.github/workflows/release.yml@refs/heads/main"
        }
      end

      %{identity: identity, claims: claims}
    end

    test "matches any of the repositories", %{identity: identity, claims: claims} do
      assert GitHub.match?(identity, claims.("acme/widget", "456"))
      assert GitHub.match?(identity, claims.("acme/gadget", "789"))
      refute GitHub.match?(identity, claims.("acme/tool", "999"))
    end

    test "refuses a repository's name with another repository's ID", %{
      identity: identity,
      claims: claims
    } do
      refute GitHub.match?(identity, claims.("acme/gadget", "456"))
      refute GitHub.match?(identity, claims.("acme/widget", "789"))
      refute GitHub.match?(identity, claims.("acme/widget", "999"))
    end

    test "refuses a repository without a pinned ID", %{identity: identity, claims: claims} do
      for id <- [nil, ""] do
        identity = %{identity | repositories: [%TrustedRepository{name: "acme/widget", id: id}]}

        refute GitHub.match?(identity, claims.("acme/widget", "456"))
        refute GitHub.match?(identity, claims.("acme/widget", ""))
      end
    end

    test "no repositories match nothing for a write or package workload identity", %{
      identity: identity,
      claims: claims
    } do
      refute GitHub.match?(
               %{identity | repositories: [], role: "write", organization_id: 1},
               claims.("acme/widget", "456")
             )

      refute GitHub.match?(
               %{identity | repositories: [], package_id: 1},
               claims.("acme/widget", "456")
             )
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
    defp resolve(names, owner \\ "acme") do
      GitHub.resolve_immutable_ids(%{repository_owner: owner, repositories: names})
    end

    test "resolves the owner and each repository with one lookup each" do
      expect(Hexpm.HTTP.Mock, :get, 2, fn
        "https://api.github.com/repos/acme/widget", _headers, _opts ->
          {:ok, 200, [], %{"id" => 456, "owner" => %{"id" => 123}, "visibility" => "public"}}

        "https://api.github.com/repos/acme/gadget", _headers, _opts ->
          {:ok, 200, [], %{"id" => 789, "owner" => %{"id" => 123}}}
      end)

      assert resolve(["acme/widget", "acme/gadget"]) ==
               {:ok,
                %{
                  repository_owner_id: 123,
                  repositories: %{
                    "acme/widget" => %{id: 456, public: true},
                    "acme/gadget" => %{id: 789, public: false}
                  }
                }}
    end

    test "says whether a repository is public" do
      for {visibility, public?} <- [{"public", true}, {"internal", false}, {"private", false}] do
        expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
          {:ok, 200, [], %{"id" => 456, "owner" => %{"id" => 123}, "visibility" => visibility}}
        end)

        assert {:ok, %{repositories: %{"acme/widget" => %{public: ^public?}}}} =
                 resolve(["acme/widget"])
      end
    end

    test "pins only the owner id for a workload identity that matches every repository" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 200, [], %{"id" => 123}}
      end)

      assert resolve([]) == {:ok, %{repository_owner_id: 123, repositories: %{}}}
    end

    test "resolves a repository Hex cannot see without an ID, and the owner from its profile" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/private", _, _ ->
        {:ok, 404, [], %{}}
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 200, [], %{"id" => 123}}
      end)

      assert resolve(["acme/private"]) ==
               {:ok,
                %{
                  repository_owner_id: 123,
                  repositories: %{"acme/private" => %{id: nil, public: false}}
                }}
    end

    test "takes the owner id from the repositories Hex can see" do
      expect(Hexpm.HTTP.Mock, :get, 2, fn
        "https://api.github.com/repos/acme/widget", _, _ ->
          {:ok, 200, [], %{"id" => 456, "owner" => %{"id" => 123}}}

        "https://api.github.com/repos/acme/private", _, _ ->
          {:ok, 404, [], %{}}
      end)

      assert {:ok,
              %{
                repository_owner_id: 123,
                repositories: %{
                  "acme/widget" => %{id: 456},
                  "acme/private" => %{id: nil}
                }
              }} = resolve(["acme/widget", "acme/private"])
    end

    test "refuses repositories that report different owners" do
      expect(Hexpm.HTTP.Mock, :get, 2, fn
        "https://api.github.com/repos/acme/widget", _, _ ->
          {:ok, 200, [], %{"id" => 456, "owner" => %{"id" => 123}}}

        "https://api.github.com/repos/acme/moved", _, _ ->
          {:ok, 200, [], %{"id" => 789, "owner" => %{"id" => 999}}}
      end)

      assert resolve(["acme/widget", "acme/moved"]) == {:error, :repository_not_found}
    end

    test "maps an unknown owner to repository_not_found" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/missing/widget", _, _ ->
        {:ok, 404, [], %{}}
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/missing", _, _ ->
        {:ok, 404, [], %{}}
      end)

      assert resolve(["missing/widget"], "missing") == {:error, :repository_not_found}
    end

    test "maps an owner response without an id to invalid_github_response" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/private", _, _ ->
        {:ok, 404, [], %{}}
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 200, [], %{"login" => "acme"}}
      end)

      assert resolve(["acme/private"]) == {:error, :invalid_github_response}
    end

    test "propagates a rate-limited owner lookup" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/private", _, _ ->
        {:ok, 404, [], %{}}
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 403, [], %{}}
      end)

      assert resolve(["acme/private"]) == {:error, {:http_status, 403}}
    end

    test "maps a response without an owner id to invalid_github_response" do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 456}}
      end)

      assert resolve(["acme/widget"]) == {:error, :invalid_github_response}
    end

    test "propagates a rate-limited repository lookup" do
      expect(Hexpm.HTTP.Mock, :get, 2, fn
        "https://api.github.com/repos/acme/widget", _, _ ->
          {:ok, 200, [], %{"id" => 456, "owner" => %{"id" => 123}}}

        "https://api.github.com/repos/acme/gadget", _, _ ->
          {:ok, 403, [], %{}}
      end)

      assert resolve(["acme/widget", "acme/gadget"]) == {:error, {:http_status, 403}}
    end

    test "rejects a repository that isn't qualified with the owner without calling GitHub" do
      assert resolve(["widget"]) == {:error, :repository_not_found}
      assert resolve(["other/widget"]) == {:error, :repository_not_found}
      assert resolve(["acme/wid get"]) == {:error, :repository_not_found}
    end

    test "rejects an invalid owner without calling GitHub" do
      assert resolve([], "ac me") == {:error, :repository_not_found}
      assert resolve(["acme/widget"], "acme/widget") == {:error, :repository_not_found}
    end
  end
end
