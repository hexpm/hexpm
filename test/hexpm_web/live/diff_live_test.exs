defmodule HexpmWeb.DiffLiveTest do
  use HexpmWeb.ConnCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  import Phoenix.LiveViewTest

  alias Hexpm.Diff.Cache
  alias HexpmWeb.Plugs.Attack

  setup do
    PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)
    package = insert(:package, name: "live_diff")

    releases =
      for major <- 1..7 do
        insert(:release,
          package: package,
          version: "#{major}.0.0",
          outer_checksum: :crypto.hash(:sha256, "#{major}")
        )
      end

    {:ok, package: package, releases: releases}
  end

  test "cache hit renders five pieces initially and lazy-loads the next batch", %{
    package: package
  } do
    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "7.0.0", [])
    put_ready_cache(request, 6)

    {:ok, view, html} = live(build_conn(), "/diff/#{package.name}/1.0.0..7.0.0")

    {:ok, document} = Floki.parse_document(html)

    assert Floki.find(document, "#diff-files-changed strong") |> Floki.text() |> String.trim() ==
             "6"

    assert Floki.find(document, "#diff-files-changed span") |> Floki.text() |> String.trim() ==
             "files changed"

    assert Floki.find(document, "a.border-primary-default") |> Floki.text() =~ "Versions"
    assert html =~ ~s(phx-hook="LineHighlight")

    actions = Floki.find(document, "#diff-page-actions")
    refute Floki.text(actions) =~ package.name
    refute Floki.text(actions) =~ "1.0.0..7.0.0"

    assert [files_button, find_file_button] = Floki.find(actions, "button")
    assert files_button |> Floki.text() |> String.trim() == "Files"
    assert find_file_button |> Floki.text() |> String.trim() == "Find file…"

    assert "lg:hidden" in (Floki.attribute(files_button, "class")
                           |> List.first()
                           |> String.split())

    assert "lg:inline-flex" in (Floki.attribute(find_file_button, "class")
                                |> List.first()
                                |> String.split())

    assert has_element?(view, "#diff-4-container", "file-4.bin")
    refute has_element?(view, "#diff-5-container")
    assert html =~ "Hide whitespace"
    assert html =~ ~s(aria-label="Changed files")
    assert html =~ ~s(id="diff-files-tree-search")
    assert html =~ ~s(id="diff-loading-trigger")

    assert Floki.attribute(document, "#whitespace-toggle", "href") == [
             "/diff/#{package.name}/1.0.0..7.0.0?w=1"
           ]

    html = render_hook(view, "load-more")
    assert has_element?(view, "#diff-5-container", "file-5.bin")
    refute html =~ ~s(id="diff-loading-trigger")
  end

  test "changed-file selector filters and loads only the selected unloaded file", %{
    package: package
  } do
    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "7.0.0", [])
    put_ready_cache(request, 7)

    {:ok, view, _html} = live(build_conn(), "/diff/#{package.name}/1.0.0..7.0.0")
    refute has_element?(view, "#diff-6-container")

    html =
      view
      |> element("#diff-files-tree-search")
      |> render_change(%{"query" => "file-6"})

    assert html =~ "file-6.bin"
    refute html =~ "file-5.bin"

    view
    |> element("#diff-files-tree button", "file-6.bin")
    |> render_click()

    assert has_element?(view, "#diff-6-container", "file-6.bin")
    assert has_element?(view, ~s(button[aria-current="true"]), "file-6.bin")
    refute has_element?(view, "#diff-5-container")
    assert has_element?(view, "#diff-loading-trigger")
  end

  test "legacy metadata remains bounded and can load a deep-linked piece", %{package: package} do
    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "7.0.0", [])

    for index <- 0..6 do
      Cache.put_piece!(request, index, %{type: "too_large", file: "legacy-#{index}.bin"})
    end

    Cache.put_metadata!(request, %{
      total_diffs: 7,
      total_additions: 0,
      total_deletions: 0,
      files_changed: 7
    })

    {:ok, view, html} = live(build_conn(), "/diff/#{package.name}/1.0.0..7.0.0")

    assert html =~ "legacy-4.bin"
    refute html =~ "legacy-5.bin"
    refute has_element?(view, "#diff-files-tree")

    render_hook(view, "load-piece", %{"id" => "diff-6"})

    assert has_element?(view, "#diff-6-container", "legacy-6.bin")
    refute has_element?(view, "#diff-5-container")
    assert has_element?(view, "#diff-loading-trigger")
  end

  test "cached patches are highlighted through Lumis with stable line anchors", %{
    package: package
  } do
    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])

    Cache.put_piece!(request, 0, %{
      "diff" => """
      diff --git a/lib/app.ex b/lib/app.ex
      index 3367afd..646f620 100644
      --- a/lib/app.ex
      +++ b/lib/app.ex
      @@ -1 +1 @@
      -old = 1
      +value = <script>
      """,
      "path_from" => "/",
      "path_to" => "/"
    })

    Cache.put_metadata!(request, %{
      total_diffs: 1,
      total_additions: 1,
      total_deletions: 1,
      files_changed: 1
    })

    {:ok, _view, html} = live(build_conn(), "/diff/#{package.name}/1.0.0..2.0.0")

    assert html =~ ~s(id="diff-0-L1-0")
    assert html =~ ~s(id="diff-0-L0-1")
    assert html =~ ~s(class="l-variable")
    assert html =~ "&lt;"
    refute html =~ "<script>"
  end

  test "missing cache pieces render an in-page file error", %{package: package} do
    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])

    Cache.put_metadata!(request, %{
      total_diffs: 1,
      total_additions: 1,
      total_deletions: 1,
      files_changed: 1
    })

    {:ok, _view, html} = live(build_conn(), "/diff/#{package.name}/1.0.0..2.0.0")
    assert html =~ "Failed to load diff"
  end

  test "cache miss is unique across disconnected and connected mounts", %{package: package} do
    {:ok, _view, html} = live(build_conn(), "/diff/#{package.name}/1.0.0..2.0.0")
    assert html =~ "Diff queued"

    {:ok, _reconnected_view, _html} =
      live(build_conn(), "/diff/#{package.name}/1.0.0..2.0.0")

    jobs = Repo.all(from job in Oban.Job, where: job.worker == "Hexpm.Diff.Worker")
    assert length(jobs) == 1

    identity = {:ip, {127, 0, 0, 1}}

    assert [{{:throttle, {:diff, ^identity}, _bucket}, 1, _expires_at}] =
             :ets.match_object(
               HexpmWeb.Plugs.Attack.Storage,
               {{:throttle, {:diff, identity}, :_}, :_, :_}
             )
  end

  test "a non-JavaScript request enqueues and renders the pending state", %{package: package} do
    conn = get(build_conn(), "/diff/#{package.name}/1.0.0..2.0.0")
    assert html_response(conn, 200) =~ "Diff queued"

    assert Repo.aggregate(from(job in Oban.Job, where: job.worker == "Hexpm.Diff.Worker"), :count) ==
             1
  end

  test "a disconnected request is throttled by its real remote address", %{package: package} do
    remote_ip = {203, 0, 113, 42}
    conn = %{build_conn() | remote_ip: remote_ip}

    conn = get(conn, "/diff/#{package.name}/1.0.0..2.0.0")
    assert html_response(conn, 200) =~ "Diff queued"

    identity = {:ip, remote_ip}

    assert [{{:throttle, {:diff, ^identity}, _bucket}, 1, _expires_at}] =
             :ets.match_object(
               HexpmWeb.Plugs.Attack.Storage,
               {{:throttle, {:diff, identity}, :_}, :_, :_}
             )
  end

  test "storage failures render an error without enqueueing regeneration", %{package: package} do
    original_bucket = Application.fetch_env!(:hexpm, :diff_bucket)
    Application.put_env(:hexpm, :diff_bucket, {Hexpm.Diff.TestStore, "diff_bucket"})
    Application.put_env(:hexpm, :diff_test_store_get, :throw)

    on_exit(fn ->
      Application.put_env(:hexpm, :diff_bucket, original_bucket)
      Application.delete_env(:hexpm, :diff_test_store_get)
    end)

    {:ok, _view, html} = live(build_conn(), "/diff/#{package.name}/1.0.0..2.0.0")

    assert html =~ "Could not load diff cache"

    assert Repo.aggregate(from(job in Oban.Job, where: job.worker == "Hexpm.Diff.Worker"), :count) ==
             0
  end

  test "storage exceptions render an error without crashing or enqueueing", %{package: package} do
    original_bucket = Application.fetch_env!(:hexpm, :diff_bucket)
    Application.put_env(:hexpm, :diff_bucket, {Hexpm.Diff.TestStore, "diff_bucket"})
    Application.put_env(:hexpm, :diff_test_store_get, :raise)

    on_exit(fn ->
      Application.put_env(:hexpm, :diff_bucket, original_bucket)
      Application.delete_env(:hexpm, :diff_test_store_get)
    end)

    {:ok, _view, html} = live(build_conn(), "/diff/#{package.name}/1.0.0..2.0.0")

    assert html =~ "Could not load diff cache"

    assert Repo.aggregate(from(job in Oban.Job, where: job.worker == "Hexpm.Diff.Worker"), :count) ==
             0
  end

  test "read-only mode rejects generation without inserting a job", %{package: package} do
    Application.put_env(:hexpm, :read_only_mode, true)
    on_exit(fn -> Application.put_env(:hexpm, :read_only_mode, false) end)

    {:ok, _view, html} = live(build_conn(), "/diff/#{package.name}/1.0.0..2.0.0")

    assert html =~ "Diff generation is unavailable during maintenance"

    assert Repo.aggregate(from(job in Oban.Job, where: job.worker == "Hexpm.Diff.Worker"), :count) ==
             0
  end

  test "distinct anonymous generation requests are rate limited", %{package: package} do
    identity = {:ip, {127, 0, 0, 1}}

    for _ <- 1..20 do
      assert {:allow, _data} = Attack.diff_throttle(identity)
    end

    {:ok, _view, html} = live(build_conn(), "/diff/#{package.name}/1.0.0..2.0.0")
    assert html =~ "Too many diff generation requests"

    assert Repo.aggregate(from(job in Oban.Job, where: job.worker == "Hexpm.Diff.Worker"), :count) ==
             0
  end

  test "polls queued, running, retrying, discarded, and cancelled jobs and retries manually", %{
    package: package
  } do
    {:ok, view, _html} = live(build_conn(), "/diff/#{package.name}/1.0.0..2.0.0")
    job = Repo.one!(from job in Oban.Job, where: job.worker == "Hexpm.Diff.Worker")

    set_job_state(job, "scheduled")
    send(view.pid, {:poll_job, job.id})
    assert render(view) =~ "Diff queued"

    set_job_state(job, "executing")
    send(view.pid, {:poll_job, job.id})
    assert render(view) =~ "Generating diff"

    set_job_state(job, "retryable")
    send(view.pid, {:poll_job, job.id})
    assert render(view) =~ "Retrying diff generation"

    set_job_state(job, "discarded")
    send(view.pid, {:poll_job, job.id})
    assert render(view) =~ "Generation failed after all retry attempts"
    assert render(view) =~ "Try again"

    render_click(view, "retry")

    assert Repo.aggregate(from(job in Oban.Job, where: job.worker == "Hexpm.Diff.Worker"), :count) ==
             2

    retried = Repo.one!(from job in Oban.Job, order_by: [desc: job.id], limit: 1)
    set_job_state(retried, "cancelled")
    send(view.pid, {:poll_job, retried.id})
    assert render(view) =~ "Generation was cancelled"
  end

  test "shows retry controls for missing and completed-without-metadata jobs", %{package: package} do
    {:ok, missing_view, _html} = live(build_conn(), "/diff/#{package.name}/1.0.0..2.0.0")
    missing_job = Repo.one!(from job in Oban.Job, where: job.worker == "Hexpm.Diff.Worker")
    Repo.delete!(missing_job)
    send(missing_view.pid, {:poll_job, missing_job.id})
    assert render(missing_view) =~ "generation job could not be found"

    {:ok, completed_view, _html} = live(build_conn(), "/diff/#{package.name}/2.0.0..3.0.0")
    completed_job = Repo.one!(from job in Oban.Job, order_by: [desc: job.id], limit: 1)
    set_job_state(completed_job, "completed")
    send(completed_view.pid, {:poll_job, completed_job.id})
    assert render(completed_view) =~ "completed without a readable cache entry"
  end

  test "manual retry refreshes release checksums", %{package: package, releases: releases} do
    {:ok, view, _html} = live(build_conn(), "/diff/#{package.name}/1.0.0..2.0.0")
    old_job = Repo.one!(from job in Oban.Job, where: job.worker == "Hexpm.Diff.Worker")
    set_job_state(old_job, "discarded")

    replacement_checksum = :crypto.hash(:sha256, "replacement")
    release = Enum.find(releases, &(to_string(&1.version) == "2.0.0"))
    release |> Ecto.Changeset.change(outer_checksum: replacement_checksum) |> Repo.update!()

    render_click(view, "retry")

    new_job = Repo.one!(from job in Oban.Job, order_by: [desc: job.id], limit: 1)
    refute new_job.id == old_job.id
    assert new_job.args["to_checksum"] == Base.encode16(replacement_checksum, case: :lower)
  end

  test "completed job loads metadata and pieces", %{package: package} do
    path = "/diff/#{package.name}/3.0.0..4.0.0"
    {:ok, view, _html} = live(build_conn(), path)
    job = Repo.one!(from job in Oban.Job, where: job.worker == "Hexpm.Diff.Worker")
    {:ok, request} = Hexpm.Diff.prepare(package.name, "3.0.0", "4.0.0", [])
    put_ready_cache(request, 1)
    set_job_state(job, "completed")

    send(view.pid, {:poll_job, job.id})
    html = render(view)
    assert html =~ ">1</strong>"
    assert html =~ ">file changed</span>"
    assert html =~ "file-0.bin"
  end

  test "selector uses an explicit action, disables identical choices, and keeps whitespace mode",
       %{
         package: package
       } do
    {:ok, request} =
      Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", ignore_whitespace: true)

    put_ready_cache(request, 0)
    {:ok, view, html} = live(build_conn(), "/diff/#{package.name}/1.0.0..2.0.0?w=1")

    assert html =~ "Show whitespace"
    assert html =~ "View diff"
    assert html =~ ~s(data-phx-link="redirect")
    {:ok, document} = Floki.parse_document(html)

    assert Floki.attribute(document, "#whitespace-toggle", "href") == [
             "/diff/#{package.name}/1.0.0..2.0.0"
           ]

    assert length(Floki.find(document, "select option")) == 14
    assert length(Floki.find(document, "select option[disabled]")) == 2

    render_submit(view, "view-diff", %{"versions" => %{"from" => "3.0.0", "to" => "4.0.0"}})
    assert_redirect(view, "/diff/#{package.name}/3.0.0..4.0.0?w=1")
  end

  test "selector rejects a crafted identical pair", %{package: package} do
    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])
    put_ready_cache(request, 0)
    {:ok, view, _html} = live(build_conn(), "/diff/#{package.name}/1.0.0..2.0.0")

    html =
      render_submit(view, "view-diff", %{
        "versions" => %{"from" => "3.0.0", "to" => "3.0.0"}
      })

    assert html =~ "Choose two different versions"
  end

  test "blank target resolves latest and invalid requests render in-page errors", %{
    package: package
  } do
    {:ok, latest_request} = Hexpm.Diff.prepare(package.name, "1.0.0", "", [])
    put_ready_cache(latest_request, 0)

    {:ok, _view, html} = live(build_conn(), "/diff/#{package.name}/1.0.0..")
    assert html =~ "#{package.name} 1.0.0..7.0.0 diff"

    assert html =~
             ~s(href="http://localhost:5000/diff/#{package.name}/1.0.0..7.0.0" rel="canonical")

    {:ok, _view, html} = live(build_conn(), "/diff/#{package.name}/bad..2.0.0")
    assert html =~ "Invalid version"

    {:ok, _view, html} = live(build_conn(), "/diff/#{package.name}/1.0.0..1.0.0")
    assert html =~ "Choose two different versions"

    {:ok, _view, html} = live(build_conn(), "/diff/missing/1.0.0..2.0.0")
    assert html =~ "Package not found"

    {:ok, _view, html} = live(build_conn(), "/diff/#{package.name}/1.0.0")
    assert html =~ "Invalid diff route"
  end

  test "package version links use the integrated Diff route", %{
    package: package
  } do
    html =
      build_conn()
      |> get("/packages/#{package.name}/versions")
      |> response(200)

    assert html =~ ~s(href="/diff/#{package.name}/1.0.0..2.0.0")
    refute html =~ "http://localhost:5004/diff/"
  end

  defp put_ready_cache(request, count) do
    for index <- zero_based_range(count) do
      Cache.put_piece!(request, index, %{type: "too_large", file: "file-#{index}.bin"})
    end

    Cache.put_metadata!(request, %{
      total_diffs: count,
      total_additions: count,
      total_deletions: count,
      files_changed: count,
      files: Enum.map(zero_based_range(count), &"file-#{&1}.bin")
    })
  end

  defp zero_based_range(0), do: []
  defp zero_based_range(count), do: 0..(count - 1)

  defp set_job_state(job, state) do
    job
    |> Ecto.Changeset.change(state: state)
    |> Repo.update!()
  end
end
