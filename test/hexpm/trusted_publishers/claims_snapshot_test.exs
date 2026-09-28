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

  test "has no links for claims the token did not carry" do
    snapshot = %ClaimsSnapshot{repository: "acme/widget"}

    assert ClaimsSnapshot.commit_url(snapshot) == nil
    assert ClaimsSnapshot.workflow_path(snapshot) == nil
    assert ClaimsSnapshot.workflow_url(snapshot) == nil
    assert ClaimsSnapshot.run_url(snapshot) == nil
  end
end
