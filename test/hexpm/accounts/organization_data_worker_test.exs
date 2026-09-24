defmodule Hexpm.Accounts.OrganizationDataWorkerTest do
  use Hexpm.DataCase, async: true
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Accounts.OrganizationDataWorker

  describe "prefixes/1" do
    test "are exactly these" do
      assert OrganizationDataWorker.prefixes("acme") == [
               {:repo_bucket, "repos/acme/"},
               {:repo_bucket, "debug/tarballs/acme-"},
               {:repo_bucket, "debug/docs/acme-"},
               {:preview_bucket, "repos/acme/"},
               {:diff_bucket, "repos/acme/"},
               {:docs_private_bucket, "acme/"}
             ]
    end

    test "refuse anything that is not an organization name, and the public repository" do
      for name <- ["", "Acme", "acme-renamed", "acme/", "../acme", "a*", "hexpm"] do
        assert_raise ArgumentError, fn -> OrganizationDataWorker.prefixes(name) end
      end
    end

    property "cover every object of the organization and no object of anyone else" do
      check all(
              organization <- organization_name(),
              other <- organization_name(),
              organization != other,
              package <- package_name(),
              version <- version(),
              random <- string(:alphanumeric, length: 16)
            ) do
        prefixes = OrganizationDataWorker.prefixes(organization)

        for {bucket, key} <- keys(organization, package, version, random) do
          assert Enum.any?(prefixes, fn {b, prefix} ->
                   b == bucket and String.starts_with?(key, prefix)
                 end),
                 "#{bucket} #{key} is not covered"
        end

        for {bucket, key} <-
              keys(other, package, version, random) ++
                public_keys(organization, package, version, random) do
          refute Enum.any?(prefixes, fn {b, prefix} ->
                   b == bucket and String.starts_with?(key, prefix)
                 end),
                 "#{bucket} #{key} would be deleted with #{organization}"
        end
      end
    end
  end

  describe "perform/1" do
    test "deletes the objects, records the deletion and can run again" do
      Hexpm.Store.put(:repo_bucket, "repos/acme/names", "NAMES", [])
      Hexpm.Store.put(:docs_private_bucket, "acme/pkg/index.html", "DOCS", [])
      Hexpm.Store.put(:repo_bucket, "repos/acme_two/names", "OTHER", [])

      args = OrganizationDataWorker.new_job(["acme"], [{"pkg", "1.0.0"}], []).changes.args

      assert :ok = perform_job(OrganizationDataWorker, args)

      assert Hexpm.Store.list(:repo_bucket, "repos/acme/") |> Enum.to_list() == []
      assert Hexpm.Store.list(:docs_private_bucket, "acme/") |> Enum.to_list() == []
      assert Hexpm.Store.get(:repo_bucket, "repos/acme_two/names", []) == "OTHER"
      assert Hexpm.Store.get(:deletions_bucket, "organizations/acme", [])

      assert :ok = perform_job(OrganizationDataWorker, args)
    end
  end

  # Organization names are [a-z0-9_]+, three characters or more.
  defp organization_name() do
    [?a..?z, ?0..?9, [?_]]
    |> Enum.concat()
    |> string(min_length: 3, max_length: 12)
    |> filter(&(&1 != "hexpm"))
  end

  defp package_name() do
    gen all(
          first <- string(?a..?z, length: 1),
          rest <- string(Enum.concat([?a..?z, ?0..?9, [?_]]), max_length: 10)
        ) do
      first <> rest
    end
  end

  defp version() do
    gen all(
          major <- integer(0..20),
          minor <- integer(0..20),
          pre <-
            one_of([
              constant(""),
              map(string(:alphanumeric, min_length: 1, max_length: 5), &("-" <> &1))
            ])
        ) do
      "#{major}.#{minor}.0#{pre}"
    end
  end

  # Every shape of key an organization's objects are written under.
  defp keys(organization, package, version, random) do
    repo = "repos/#{organization}"

    [
      {:repo_bucket, "#{repo}/names"},
      {:repo_bucket, "#{repo}/versions"},
      {:repo_bucket, "#{repo}/packages/#{package}"},
      {:repo_bucket, "#{repo}/tarballs/#{package}-#{version}.tar"},
      {:repo_bucket, "#{repo}/docs/#{package}-#{version}.tar.gz"},
      {:repo_bucket, "#{repo}/policies/#{package}"},
      {:repo_bucket, "debug/tarballs/#{organization}-#{package}-#{version}-#{random}.tar.gz"},
      {:repo_bucket, "debug/docs/#{organization}-#{package}-#{version}-#{random}.tar.gz"},
      {:preview_bucket, "#{repo}/files/#{package}/#{version}/README.md"},
      {:preview_bucket, "#{repo}/file_lists/#{package}-#{version}.json"},
      {:preview_bucket, "#{repo}/latest_versions/#{package}"},
      {:diff_bucket, "#{repo}/metadata/#{package}-#{version}-#{version}-1.json"},
      {:diff_bucket, "#{repo}/diffs/#{package}-#{version}-#{version}-1-diff-0.json"},
      {:docs_private_bucket, "#{organization}/#{package}/index.html"},
      {:docs_private_bucket, "#{organization}/#{package}/#{version}/index.html"}
    ]
  end

  # The public repository's keys, with a package named like the organization.
  defp public_keys(organization, package, version, random) do
    for name <- [package, organization],
        key <- [
          {:repo_bucket, "names"},
          {:repo_bucket, "packages/#{name}"},
          {:repo_bucket, "tarballs/#{name}-#{version}.tar"},
          {:repo_bucket, "docs/#{name}-#{version}.tar.gz"},
          {:repo_bucket, "installs/list.csv"},
          {:repo_bucket, "debug/tarballs/hexpm-#{name}-#{version}-#{random}.tar.gz"},
          {:repo_bucket, "debug/docs/hexpm-#{name}-#{version}-#{random}.tar.gz"},
          {:preview_bucket, "files/#{name}/#{version}/README.md"},
          {:preview_bucket, "latest_versions/#{name}"},
          {:diff_bucket, "metadata/#{name}-#{version}-#{version}-1.json"},
          {:docs_bucket, "#{name}/index.html"}
        ],
        do: key
  end
end
