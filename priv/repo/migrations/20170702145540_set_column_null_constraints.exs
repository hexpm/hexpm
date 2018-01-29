defmodule Hexpm.Repo.Migrations.SetColumnNullConstraints do
  use Ecto.Migration

  defp set_not_null(table, columns) do
    sql =
      ~s(ALTER TABLE "#{table}" ) <> Enum.map_join(columns, ", ", &~s(ALTER "#{&1}" SET NOT NULL))

    execute(sql)
  end

  defp drop_not_null(table, columns) do
    sql =
      ~s(ALTER TABLE "#{table}" ) <>
        Enum.map_join(columns, ", ", &~s(ALTER "#{&1}" DROP NOT NULL))

    execute(sql)
  end

  def up() do
    execute("UPDATE requirements SET requirement = '>= 0.0.0' WHERE requirement IS NULL")

    set_not_null("blocked_addresses", ~w(ip))
    set_not_null("downloads", ~w(release_id downloads day))
    set_not_null("emails", ~w(email verified primary public user_id inserted_at updated_at))
    set_not_null("installs", ~w(hex elixirs))
    set_not_null("keys", ~w(user_id name inserted_at updated_at secret_first secret_second))
    set_not_null("package_owners", ~w(package_id owner_id))
    set_not_null("packages", ~w(name meta inserted_at updated_at))
    set_not_null("releases", ~w(package_id version inserted_at updated_at checksum has_docs meta))
    set_not_null("repository_users", ~w(repository_id user_id))
    set_not_null("requirements", ~w(release_id dependency_id requirement optional app))
    set_not_null("users", ~w(username password inserted_at updated_at))
  end

  def down() do
    drop_not_null("blocked_addresses", ~w(ip))
    drop_not_null("downloads", ~w(release_id downloads day))
    drop_not_null("emails", ~w(email verified primary public user_id inserted_at updated_at))
    drop_not_null("installs", ~w(hex elixirs))
    drop_not_null("keys", ~w(user_id name inserted_at updated_at secret_first secret_second))
    drop_not_null("package_owners", ~w(package_id owner_id))
    drop_not_null("packages", ~w(name meta inserted_at updated_at))

    drop_not_null(
      "releases",
      ~w(package_id version inserted_at updated_at checksum has_docs meta)
    )

    drop_not_null("repository_users", ~w(repository_id user_id))
    drop_not_null("requirements", ~w(release_id dependency_id requirement optional app))
    drop_not_null("users", ~w(username password inserted_at updated_at))
  end
end
