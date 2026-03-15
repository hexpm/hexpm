defmodule Hexpm.Repo.Migrations.AddUserKeyDataToAuditLogs do
  use Ecto.Migration

  def up() do
    alter table(:audit_logs) do
      add :user_data, :map
      add :key_data, :map
    end

    flush()

    execute("""
    UPDATE audit_logs SET user_data = jsonb_build_object(
      'id', u.id,
      'username', u.username,
      'handles', u.handles,
      'emails', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'email', e.email, 'primary', e."primary", 'public', e."public", 'gravatar', e.gravatar
      )), '[]'::jsonb) FROM emails e WHERE e.user_id = u.id)
    ) FROM users u WHERE audit_logs.user_id = u.id
    """)

    execute("""
    UPDATE audit_logs SET key_data = jsonb_build_object(
      'id', k.id,
      'name', k.name,
      'permissions', k.permissions,
      'user', (SELECT jsonb_build_object('id', u.id, 'username', u.username)
               FROM users u WHERE u.id = k.user_id),
      'organization', (SELECT jsonb_build_object('id', o.id, 'name', o.name)
                       FROM organizations o WHERE o.id = k.organization_id)
    ) FROM keys k WHERE audit_logs.key_id = k.id
    """)
  end

  def down() do
    alter table(:audit_logs) do
      remove :user_data
      remove :key_data
    end
  end
end
