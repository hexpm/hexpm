defmodule Hexpm.Repo.Migrations.RenameRequirePublishApproval do
  use Ecto.Migration

  def up do
    # Renaming takes ACCESS EXCLUSIVE on `packages`, which every request reads.
    # Give up rather than queue behind a long-running read and hold every
    # reader behind us.
    execute("SET LOCAL lock_timeout TO '5s'")

    rename table(:packages), :require_publish_approval, to: :require_staged_publishing
    rename table(:organizations), :require_publish_approval, to: :require_staged_publishing
  end

  def down do
    execute("SET LOCAL lock_timeout TO '5s'")

    rename table(:packages), :require_staged_publishing, to: :require_publish_approval
    rename table(:organizations), :require_staged_publishing, to: :require_publish_approval
  end
end
