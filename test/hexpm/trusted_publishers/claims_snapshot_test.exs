defmodule Hexpm.TrustedPublishers.ClaimsSnapshotTest do
  use ExUnit.Case, async: true

  alias Hexpm.TrustedPublishers.ClaimsSnapshot

  @snapshot %ClaimsSnapshot{
    repository: "acme/widget",
    workflow_ref: "acme/widget/.github/workflows/release.yml@refs/heads/main",
    sha: "abc123",
    run_id: "42",
    run_attempt: "2"
  }

  test "links the source commit, build file, and run on GitHub" do
    assert ClaimsSnapshot.commit_url(@snapshot) == "https://github.com/acme/widget/commit/abc123"
    assert ClaimsSnapshot.workflow_path(@snapshot) == ".github/workflows/release.yml"

    assert ClaimsSnapshot.workflow_url(@snapshot) ==
             "https://github.com/acme/widget/blob/abc123/.github/workflows/release.yml"

    assert ClaimsSnapshot.run_url(@snapshot) ==
             "https://github.com/acme/widget/actions/runs/42/attempts/2"
  end

  test "links branches and tags by their short name" do
    branch = %{@snapshot | ref: "refs/heads/release/v1"}
    tag = %{@snapshot | ref: "refs/tags/v1.0.0"}

    assert ClaimsSnapshot.ref_name(branch) == "release/v1"
    assert ClaimsSnapshot.ref_url(branch) == "https://github.com/acme/widget/tree/release/v1"
    assert ClaimsSnapshot.ref_name(tag) == "v1.0.0"
    assert ClaimsSnapshot.ref_url(tag) == "https://github.com/acme/widget/tree/v1.0.0"
  end

  test "does not link refs GitHub has no tree for" do
    pull = %{@snapshot | ref: "refs/pull/7/merge"}

    assert ClaimsSnapshot.ref_name(pull) == "refs/pull/7/merge"
    assert ClaimsSnapshot.ref_url(pull) == nil
  end

  test "links the repository and the actor who triggered the run" do
    snapshot = %{@snapshot | actor: "octocat"}

    assert ClaimsSnapshot.repository_url(snapshot) == "https://github.com/acme/widget"
    assert ClaimsSnapshot.actor_url(snapshot) == "https://github.com/octocat"
  end

  test "has no links for claims the token did not carry" do
    snapshot = %ClaimsSnapshot{repository: "acme/widget"}

    assert ClaimsSnapshot.commit_url(snapshot) == nil
    assert ClaimsSnapshot.workflow_path(snapshot) == nil
    assert ClaimsSnapshot.workflow_url(snapshot) == nil
    assert ClaimsSnapshot.run_url(snapshot) == nil
    assert ClaimsSnapshot.ref_url(snapshot) == nil
    assert ClaimsSnapshot.actor_url(snapshot) == nil
  end
end
