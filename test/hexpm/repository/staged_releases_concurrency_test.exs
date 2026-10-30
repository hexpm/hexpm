defmodule Hexpm.Repository.StagedReleasesConcurrencyTest do
  use Hexpm.DataCase
  import Hexpm.ConcurrencyCase

  alias Hexpm.Accounts.Key
  alias Hexpm.Repository.{Release, Releases, Repository, StagedRelease, StagedReleases}

  setup do
    put_feature_flag(:staged_publishing, mode: :enabled)
  end

  for operation <- [:configure, :approve, :reject] do
    @tag :package_policy_membership
    test "#{operation} serializes with an organization admin demotion" do
      committed(
        fn ->
          user = insert(:user_with_tfa)
          admin = insert(:user_with_tfa)
          repository = insert(:repository)

          for member <- [user, admin] do
            insert(:organization_user,
              organization: repository.organization,
              user: member,
              role: "admin"
            )
          end

          package = insert(:package, repository_id: repository.id)
          key = insert(:key, user: user)

          ctx =
            %{
              user: user,
              admin: admin,
              repository: repository,
              package: package,
              path: nil,
              meta: nil,
              inner: nil,
              outer: nil
            }
            |> with_tarball("Concurrent membership change")

          {:ok, %{staged_release: staged}} = publish(ctx, audit_data(user, key: key))
          Map.put(ctx, :staged, staged)
        end,
        fn ctx ->
          parent = self()

          demoting =
            unboxed_task(fn ->
              Ecto.Multi.new()
              |> Hexpm.Accounts.SSO.lock_member_removal(ctx.repository.organization, ctx.user)
              |> Ecto.Multi.run(:demotion, fn _repo, _changes ->
                send(parent, :membership_locked)
                receive do: (:continue -> :ok)

                Hexpm.Accounts.Organizations.change_role(
                  ctx.repository.organization,
                  ctx.user,
                  %{"role" => "read"},
                  audit: audit_data(ctx.admin)
                )
              end)
              |> Repo.transaction()
            end)

          assert_receive :membership_locked, 15_000

          changing =
            unboxed_task(fn ->
              case unquote(operation) do
                :configure ->
                  StagedReleases.configure(ctx.package, ctx.user, false,
                    audit: audit_data(ctx.user)
                  )

                :approve ->
                  approve(ctx, ctx.staged)

                :reject ->
                  StagedReleases.reject(ctx.staged.id, ctx.user, audit: audit_data(ctx.user))
              end
            end)

          result = Task.yield(changing, 100)
          if is_nil(result), do: await_lock_wait()
          send(demoting.pid, :continue)
          assert {:ok, {:ok, _}} = result || Task.yield(changing, 15_000)
          assert {:ok, %{demotion: %{role: "read"}}} = Task.await(demoting, 15_000)

          if unquote(operation) == :configure do
            refute Repo.get!(Hexpm.Repository.Package, ctx.package.id).require_publish_approval
          else
            refute StagedReleases.get(ctx.staged.id)

            assert committed_count(ctx, Release) ==
                     if(unquote(operation) == :approve, do: 1, else: 0)
          end

          assert StagedReleases.configure(ctx.package, ctx.user, true,
                   audit: audit_data(ctx.user)
                 ) ==
                   {:error, :forbidden}
        end
      )
    end
  end

  test "approval stays pending while package and docs uploads are unfinished" do
    committed(&build_context/0, fn ctx ->
      {:ok, %{staged_release: _}} = stage(ctx)
      token = Repo.get_by!(Hexpm.OAuth.Token, workload_identity_id: ctx.wi.id)
      audit = %{user: ctx.wi, auth_credential: token, user_agent: "TEST", remote_ip: "127.0.0.1"}
      docs_path = Path.join(Hexpm.TmpDir.tmp_dir("staged-docs"), "docs.tar.gz")
      {:ok, docs} = :hex_tarball.create_docs([{~c"index.html", "Docs"}])
      File.write!(docs_path, docs)

      {:ok, %{staged_release: staged}} =
        StagedReleases.stage_docs(
          ctx.repository,
          ctx.package.name,
          "1.0.0",
          docs_path,
          audit
        )

      parent = self()
      app_env(:hexpm, :repo_bucket, {Hexpm.Store.Mock, "repo_bucket"})
      Mox.set_mox_global()

      Mox.stub(Hexpm.Store.Mock, :get_to_file, &Hexpm.Store.Memory.get_to_file/4)

      Mox.stub(Hexpm.Store.Mock, :put_file, fn bucket, key, path, opts ->
        refute Repo.in_transaction?()

        if String.ends_with?(key, ".tar") do
          send(parent, {:uploading, self()})
          receive do: (:continue -> :ok)
        end

        Hexpm.Store.Memory.put_file(bucket, key, path, opts)
      end)

      approval = unboxed_task(fn -> approve(ctx, staged) end)
      assert_receive {:uploading, uploader}, 15_000
      assert StagedReleases.get(staged.id)

      response =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("authorization", ctx.key.user_secret)
        |> Phoenix.ConnTest.dispatch(
          HexpmWeb.Endpoint,
          :get,
          "/api/staged-releases/#{staged.id}",
          nil
        )

      assert Phoenix.ConnTest.json_response(response, 200)["status"] == "staged"

      assert Repo.exists?(
               from(l in Hexpm.Accounts.AuditLog, where: l.action == "release.approve")
             )

      assert committed_count(ctx, Release) == 1
      send(uploader, :continue)
      assert {:ok, _} = Task.await(approval, 15_000)
      refute StagedReleases.get(staged.id)
      assert Repo.one!(from(r in Release, where: r.package_id == ^ctx.package.id)).has_docs
    end)
  end

  for credential <- [:workload_identity, :key] do
    @tag :policy_race
    test "enabling package approval serializes with an authenticated #{credential} publish" do
      committed(
        fn ->
          ctx = build_context()

          %{
            ctx
            | package:
                Repo.update!(Ecto.Changeset.change(ctx.package, require_publish_approval: false))
          }
        end,
        fn ctx ->
          parent = self()

          enabling =
            unboxed_task(fn ->
              Repo.transaction(fn ->
                Repo.one!(
                  from(p in Hexpm.Repository.Package,
                    where: p.id == ^ctx.package.id,
                    lock: "FOR NO KEY UPDATE"
                  )
                )

                Repo.update!(Ecto.Changeset.change(ctx.package, require_publish_approval: true))
                send(parent, :policy_uncommitted)
                receive do: (:commit -> :ok)
              end)
            end)

          assert_receive :policy_uncommitted, 15_000

          publishing =
            unboxed_task(fn ->
              case unquote(credential) do
                :workload_identity -> stage(ctx)
                :key -> publish(ctx, audit_data(ctx.user, key: ctx.key))
              end
            end)

          assert await_lock_wait() == :waiting
          send(enabling.pid, :commit)
          assert {:ok, :ok} = Task.await(enabling, 15_000)
          assert {:ok, %{action: :staged}} = Task.await(publishing, 15_000)
          assert committed_count(ctx, StagedRelease) == 1
          assert committed_count(ctx, Release) == 0
        end
      )
    end
  end

  test "a direct publish waits for staging to commit before checking its reservation" do
    committed(&build_context/0, fn ctx ->
      parent = self()

      staging =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            result = stage(ctx)
            send(parent, :staged)
            receive do: (:commit -> result)
          end)
        end)

      assert_receive :staged, 15_000
      direct = unboxed_task(fn -> publish(ctx, audit_data(ctx.user)) end)
      assert await_lock_wait() == :waiting
      send(staging.pid, :commit)
      assert {:ok, {:ok, %{staged_release: _}}} = Task.await(staging, 15_000)
      assert {:error, :staged_reservation, %Ecto.Changeset{}, _} = Task.await(direct, 15_000)
      assert committed_count(ctx, StagedRelease) == 1
      assert committed_count(ctx, Release) == 0
    end)
  end

  for operation <- [:approval, :docs] do
    test "#{operation} allows uploads longer than the default database checkout timeout" do
      committed(&build_context/0, &slow_upload(&1, unquote(operation)))
    end
  end

  test "approval rechecks a key revoked while it waits for the key lock" do
    committed(&build_context/0, fn ctx ->
      # Private repository policy stages a user API key.
      repository =
        insert(:repository, organization: build(:organization, require_publish_approval: true))

      insert(:organization_user,
        organization: repository.organization,
        user: ctx.user,
        role: "write"
      )

      package =
        insert(:package, repository_id: repository.id, require_publish_approval: false)
        |> Repo.preload(repository: :organization)

      ctx = %{ctx | repository: repository, package: package} |> with_tarball("first")
      {:ok, %{staged_release: staged}} = publish(ctx, audit_data(ctx.user, key: ctx.key))
      parent = self()

      revocation =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            Repo.update!(Key.revoke(ctx.key))
            send(parent, :revoked)
            receive do: (:commit -> :ok)
          end)
        end)

      assert_receive :revoked, 15_000
      approval = unboxed_task(fn -> approve(ctx, staged) end)
      assert await_lock_wait() == :waiting
      send(revocation.pid, :commit)
      assert {:ok, :ok} = Task.await(revocation, 15_000)
      assert {:error, :credential_revoked} = Task.await(approval, 15_000)
      assert StagedReleases.get(staged.id)
      assert committed_count(ctx, Release) == 0
    end)
  end

  test "approval checks the checksum after a concurrent restage commits" do
    committed(&build_context/0, fn ctx ->
      {:ok, %{staged_release: staged}} = stage(ctx)
      parent = self()

      restaging =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            result = stage(with_tarball(ctx, "replacement"))
            send(parent, :restaged)
            receive do: (:commit -> result)
          end)
        end)

      assert_receive :restaged, 15_000
      approval = unboxed_task(fn -> approve(ctx, staged) end)
      assert await_lock_wait() == :waiting
      send(restaging.pid, :commit)
      assert {:ok, {:ok, %{staged_release: _}}} = Task.await(restaging, 15_000)
      assert {:error, :changed} = Task.await(approval, 15_000)
      assert committed_count(ctx, Release) == 0
    end)
  end

  test "two approvals can't publish or delete the staged release twice" do
    committed(&build_context/0, fn ctx ->
      {:ok, %{staged_release: staged}} = stage(ctx)
      results = race(2, fn -> approve(ctx, staged) end)
      assert Enum.all?(results, &(match?({:ok, _}, &1) or &1 == {:error, :not_found}))

      assert Repo.aggregate(
               from(l in Hexpm.Accounts.AuditLog, where: l.action == "release.approve"),
               :count
             ) == 1

      assert Repo.aggregate(
               from(l in Hexpm.Accounts.AuditLog, where: l.action == "release.publish"),
               :count
             ) == 1

      assert committed_count(ctx, Release) == 1
      assert committed_count(ctx, StagedRelease) == 0
    end)
  end

  test "a policy enabled during the API request doesn't log staged bytes outside their private prefix" do
    committed(&build_context/0, fn ctx ->
      repository = insert(:repository)

      insert(:organization_user,
        organization: repository.organization,
        user: ctx.user,
        role: "write"
      )

      package =
        insert(:package, repository_id: repository.id, require_publish_approval: false)
        |> Repo.preload(repository: :organization)

      ctx = %{ctx | repository: repository, package: package} |> with_tarball("policy race")
      parent = self()
      app_env(:hexpm, :repo_bucket, {Hexpm.Store.Mock, "repo_bucket"})
      Mox.set_mox_global()

      Mox.stub(Hexpm.Store.Mock, :put_file, fn bucket, key, path, opts ->
        assert bucket == "repo_bucket"
        assert "staged/" <> _ = key
        Hexpm.Store.Memory.put_file(bucket, key, path, opts)
      end)

      enabling =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            Repo.update!(
              Ecto.Changeset.change(repository.organization, require_publish_approval: true)
            )

            send(parent, :policy_enabled)
            receive do: (:commit -> :ok)
          end)
        end)

      assert_receive :policy_enabled, 15_000

      publishing =
        unboxed_task(fn ->
          Phoenix.ConnTest.build_conn()
          |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
          |> Plug.Conn.put_req_header("authorization", ctx.key.user_secret)
          |> Phoenix.ConnTest.dispatch(
            HexpmWeb.Endpoint,
            :post,
            "/api/repos/#{repository.name}/packages/#{package.name}/releases",
            File.read!(ctx.path)
          )
        end)

      assert await_lock_wait() == :waiting
      send(enabling.pid, :commit)
      assert {:ok, :ok} = Task.await(enabling, 15_000)
      response = Task.await(publishing, 15_000)
      assert Phoenix.ConnTest.json_response(response, 201)["status"] == "staged"
      assert committed_count(ctx, Release) == 0
    end)
  end

  test "a direct publish observes a policy enabled while it waits for the organization lock" do
    committed(&build_context/0, fn ctx ->
      repository = insert(:repository)

      insert(:organization_user,
        organization: repository.organization,
        user: ctx.user,
        role: "write"
      )

      package =
        insert(:package, repository_id: repository.id, require_publish_approval: false)
        |> Repo.preload(repository: :organization)

      ctx = %{ctx | repository: repository, package: package} |> with_tarball("first")
      parent = self()

      enabling =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            Repo.update!(
              Ecto.Changeset.change(repository.organization, require_publish_approval: true)
            )

            send(parent, :enabled)
            receive do: (:commit -> :ok)
          end)
        end)

      assert_receive :enabled, 15_000
      publishing = unboxed_task(fn -> publish(ctx, audit_data(ctx.user, key: ctx.key)) end)
      assert await_lock_wait() == :waiting
      send(enabling.pid, :commit)
      assert {:ok, :ok} = Task.await(enabling, 15_000)
      assert {:ok, %{staged_release: _}} = Task.await(publishing, 15_000)
      assert committed_count(ctx, Release) == 0
    end)
  end

  test "a failed staged API request doesn't log bytes after the policy is disabled" do
    committed(&build_context/0, fn ctx ->
      repository =
        insert(:repository, organization: build(:organization, require_publish_approval: true))

      insert(:organization_user,
        organization: repository.organization,
        user: ctx.user,
        role: "write"
      )

      package =
        insert(:package, repository_id: repository.id, require_publish_approval: false)
        |> Repo.preload(repository: :organization)

      ctx = %{ctx | repository: repository, package: package} |> with_tarball("reserved")
      {:ok, _} = publish(ctx, audit_data(ctx.user, key: ctx.key))
      other_key = insert(:key, user: ctx.user)
      parent = self()
      app_env(:hexpm, :repo_bucket, {Hexpm.Store.Mock, "repo_bucket"})
      Mox.set_mox_global()

      Mox.stub(Hexpm.Store.Mock, :put_file, fn bucket, key, path, opts ->
        assert bucket == "repo_bucket"
        assert String.starts_with?(key, "staged/")
        send(parent, {:storing, self()})
        receive do: (:continue -> :ok)
        Hexpm.Store.Memory.put_file(bucket, key, path, opts)
      end)

      Mox.stub(Hexpm.Store.Mock, :delete, &Hexpm.Store.Memory.delete/2)

      publishing =
        unboxed_task(fn ->
          Phoenix.ConnTest.build_conn()
          |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
          |> Plug.Conn.put_req_header("authorization", other_key.user_secret)
          |> Phoenix.ConnTest.dispatch(
            HexpmWeb.Endpoint,
            :post,
            "/api/repos/#{repository.name}/packages/#{package.name}/releases",
            File.read!(ctx.path)
          )
        end)

      assert_receive {:storing, uploader}, 15_000

      Repo.update!(
        Ecto.Changeset.change(repository.organization, require_publish_approval: false)
      )

      send(uploader, :continue)
      response = Task.await(publishing, 15_000)

      assert Phoenix.ConnTest.json_response(response, 422)["errors"]["staged_release"] ==
               "different_credential"

      assert committed_count(ctx, Release) == 0
    end)
  end

  test "a docs request reports a staging error when approval is enabled during publishing" do
    committed(&build_context/0, fn ctx ->
      repository =
        insert(:repository, organization: build(:organization, require_publish_approval: true))

      insert(:organization_user,
        organization: repository.organization,
        user: ctx.user,
        role: "write"
      )

      package =
        insert(:package, repository_id: repository.id, require_publish_approval: false)
        |> Repo.preload(repository: :organization)

      insert(:release, package: package, version: "1.0.0")
      path = Hexpm.TmpDir.tmp_file("reserved-docs")
      {:ok, docs} = :hex_tarball.create_docs([{~c"index.html", "Docs"}])
      File.write!(path, docs)

      {:ok, _} =
        StagedReleases.stage_docs(
          repository,
          package.name,
          "1.0.0",
          path,
          audit_data(ctx.user, key: ctx.key)
        )

      organization =
        Repo.update!(
          Ecto.Changeset.change(repository.organization, require_publish_approval: false)
        )

      other_key = insert(:key, user: ctx.user)
      parent = self()

      enabling =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            Repo.update!(Ecto.Changeset.change(organization, require_publish_approval: true))

            send(parent, :policy_enabled)
            receive do: (:commit -> :ok)
          end)
        end)

      assert_receive :policy_enabled, 15_000

      publishing =
        unboxed_task(fn ->
          Phoenix.ConnTest.build_conn()
          |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
          |> Plug.Conn.put_req_header("authorization", other_key.user_secret)
          |> Phoenix.ConnTest.dispatch(
            HexpmWeb.Endpoint,
            :post,
            "/api/repos/#{repository.name}/packages/#{package.name}/releases/1.0.0/docs",
            docs
          )
        end)

      assert await_lock_wait() == :waiting
      send(enabling.pid, :commit)
      assert {:ok, :ok} = Task.await(enabling, 15_000)
      response = Task.await(publishing, 15_000)

      assert Phoenix.ConnTest.json_response(response, 422)["errors"]["staged_release"] ==
               "different_credential"
    end)
  end

  test "approval and a policy change take organization and user locks in the same order" do
    committed(&build_context/0, fn ctx ->
      repository =
        insert(:repository, organization: build(:organization, require_publish_approval: true))

      insert(:organization_user,
        organization: repository.organization,
        user: ctx.user,
        role: "admin"
      )

      package =
        insert(:package, repository_id: repository.id, require_publish_approval: false)
        |> Repo.preload(repository: :organization)

      ctx = %{ctx | repository: repository, package: package} |> with_tarball("first")
      {:ok, %{staged_release: staged}} = publish(ctx, audit_data(ctx.user, key: ctx.key))
      parent = self()

      configuring =
        unboxed_task(fn ->
          Repo.transaction(fn ->
            Hexpm.Accounts.Seats.lock!(repository.organization)
            send(parent, :policy_locked)

            receive do
              :configure ->
                StagedReleases.configure(repository.organization, ctx.user, false,
                  audit: audit_data(ctx.user)
                )
            end
          end)
        end)

      assert_receive :policy_locked, 15_000
      approval = unboxed_task(fn -> approve(ctx, staged) end)
      assert await_lock_wait() == :waiting
      send(configuring.pid, :configure)
      assert {:ok, {:ok, _}} = Task.await(configuring, 15_000)
      assert {:ok, _} = Task.await(approval, 15_000)
      assert committed_count(ctx, Release) == 1
    end)
  end

  defp slow_upload(ctx, operation) do
    publish =
      if operation == :approval do
        {:ok, %{staged_release: staged}} = stage(ctx)
        fn -> approve(ctx, staged) end
      else
        release = insert(:release, package: ctx.package, version: "1.0.0")
        path = Hexpm.TmpDir.tmp_file("slow-docs")
        {:ok, docs} = :hex_tarball.create_docs([{~c"index.html", "Docs"}])
        File.write!(path, docs)

        fn ->
          Releases.publish_docs(ctx.package, release, path, audit: audit_data(ctx.user))
        end
      end

    app_env(:hexpm, :repo_bucket, {Hexpm.Store.Mock, "repo_bucket"})
    Mox.set_mox_global()

    Mox.stub(Hexpm.Store.Mock, :get_to_file, &Hexpm.Store.Memory.get_to_file/4)

    Mox.stub(Hexpm.Store.Mock, :put_file, fn bucket, key, path, opts ->
      Process.sleep(16_000)
      Hexpm.Store.Memory.put_file(bucket, key, path, opts)
    end)

    assert {:ok, _} = publish |> unboxed_task() |> Task.await(30_000)
    assert committed_count(ctx, StagedRelease) == 0
    release = Repo.one!(from(r in Release, where: r.package_id == ^ctx.package.id))
    if operation == :docs, do: assert(release.has_docs)
  end

  defp build_context do
    user = insert(:user_with_tfa)
    repository = Repository.hexpm()

    package =
      insert(:package, package_owners: [build(:package_owner, user: user)])
      |> Repo.preload(repository: :organization)

    key = insert(:key, user: user)

    wi =
      insert(:workload_identity,
        package: package,
        workflow: "release.yml",
        repositories: [
          %Hexpm.WorkloadIdentities.TrustedRepository{name: "acme/widget", id: "67890"}
        ]
      )

    body = create_tar(%{name: package.name, version: "1.0.0", description: "Concurrent publish"})
    path = Hexpm.TmpDir.tmp_file("staged-concurrency")
    File.write!(path, body)

    {:ok, %{metadata: meta, inner_checksum: inner, outer_checksum: outer}} =
      :hex_tarball.unpack(body, :memory)

    %{
      user: user,
      repository: repository,
      package: package,
      key: key,
      wi: wi,
      meta: meta,
      inner: inner,
      outer: outer,
      path: path
    }
  end

  defp with_tarball(ctx, contents) do
    body =
      create_tar(%{name: ctx.package.name, version: "1.0.0", description: "Concurrent publish"}, [
        {"mix.exs", contents}
      ])

    path = Hexpm.TmpDir.tmp_file("staged-concurrency")
    File.write!(path, body)

    {:ok, %{metadata: meta, inner_checksum: inner, outer_checksum: outer}} =
      :hex_tarball.unpack(body, :memory)

    %{ctx | path: path, meta: meta, inner: inner, outer: outer}
  end

  defp stage(ctx) do
    claims = Hexpm.WorkloadIdentityHelpers.github_claims()

    snapshot =
      %Hexpm.WorkloadIdentities.ClaimsSnapshot{}
      |> Hexpm.WorkloadIdentities.ClaimsSnapshot.changeset(claims)
      |> Ecto.Changeset.apply_changes()

    token =
      insert(:oauth_token,
        client_id: nil,
        grant_type: "workload_identity",
        workload_identity_id: ctx.wi.id,
        oidc_claims: snapshot,
        scopes: ["package:hexpm/#{ctx.package.name}"],
        granted_scopes: ["package:hexpm/#{ctx.package.name}"]
      )

    audit = %{user: ctx.wi, auth_credential: token, user_agent: "TEST", remote_ip: "127.0.0.1"}
    publish(ctx, audit, %{workload_identity_id: ctx.wi.id, oidc_claims: snapshot})
  end

  defp publish(ctx, audit, wi \\ nil) do
    Releases.publish(
      ctx.repository,
      ctx.package,
      if(wi, do: nil, else: ctx.user),
      ctx.path,
      ctx.meta,
      ctx.inner,
      ctx.outer,
      audit: audit,
      replace: true,
      workload_identity: wi
    )
  end

  defp approve(ctx, staged),
    do:
      StagedReleases.approve(staged.id, ctx.user, StagedRelease.checksum(staged),
        audit: audit_data(ctx.user)
      )
end
