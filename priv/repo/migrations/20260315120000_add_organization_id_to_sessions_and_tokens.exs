defmodule Hexpm.RepoBase.Migrations.AddOrganizationIdToSessionsAndTokens do
  use Ecto.Migration

  def change do
    alter table(:user_sessions) do
      add_if_not_exists :organization_id, references(:organizations, on_delete: :delete_all)
      modify :user_id, :bigint, null: true, from: {:bigint, null: false}
    end

    alter table(:oauth_tokens) do
      add_if_not_exists :organization_id, references(:organizations, on_delete: :delete_all)
      modify :user_id, :bigint, null: true, from: {:bigint, null: false}
    end

    create_if_not_exists index(:user_sessions, [:organization_id])
    create_if_not_exists index(:oauth_tokens, [:organization_id])

    create constraint(:user_sessions, :user_or_organization_required,
             check: "user_id IS NOT NULL OR organization_id IS NOT NULL"
           )

    create constraint(:oauth_tokens, :user_or_organization_required,
             check: "user_id IS NOT NULL OR organization_id IS NOT NULL"
           )

    # Backfill organization_id on existing sessions and tokens created
    # for org virtual users, so they are findable by organization_id
    execute(
      """
      UPDATE user_sessions
      SET organization_id = u.organization_id
      FROM users u
      WHERE user_sessions.user_id = u.id
        AND u.organization_id IS NOT NULL
        AND user_sessions.organization_id IS NULL
      """,
      ""
    )

    execute(
      """
      UPDATE oauth_tokens
      SET organization_id = u.organization_id
      FROM users u
      WHERE oauth_tokens.user_id = u.id
        AND u.organization_id IS NOT NULL
        AND oauth_tokens.organization_id IS NULL
      """,
      ""
    )
  end
end
