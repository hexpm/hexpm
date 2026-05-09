defmodule Hexpm.Repo.Migrations.DropMoreUnusedIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    drop_if_exists(
      index(:sessions, ["((data->>'user_id')::integer)"],
        name: :sessions__data__user_id__integer_index,
        concurrently: true
      )
    )

    drop_if_exists(
      index(:package_downloads, [:view],
        name: :package_downloads_view_index,
        concurrently: true
      )
    )

    drop_if_exists(
      index(:organizations, [:public],
        name: :organizations_public_index,
        concurrently: true
      )
    )

    drop_if_exists(
      index(:blocked_addresses, [:ip],
        name: :blocked_addresses_ip_idx,
        concurrently: true
      )
    )

    drop_if_exists(
      index(:oauth_tokens, [:refresh_token_expires_at],
        name: :oauth_tokens_refresh_token_expires_at_index,
        concurrently: true
      )
    )

    drop_if_exists(
      index(:device_codes, [:user_id],
        name: :device_codes_user_id_index,
        concurrently: true
      )
    )

    drop_if_exists(
      index(:authorization_codes, [:user_id],
        name: :authorization_codes_user_id_index,
        concurrently: true
      )
    )

    drop_if_exists(
      index(:oauth_tokens, [:client_id],
        name: :oauth_tokens_client_id_index,
        concurrently: true
      )
    )

    drop_if_exists(
      index(:oauth_tokens, [:organization_id],
        name: :oauth_tokens_organization_id_index,
        concurrently: true
      )
    )

    drop_if_exists(
      index(:user_sessions, [:client_id],
        name: :user_sessions_client_id_index,
        concurrently: true
      )
    )
  end

  def down() do
    create_if_not_exists(
      index(:user_sessions, [:client_id],
        name: :user_sessions_client_id_index,
        concurrently: true
      )
    )

    create_if_not_exists(
      index(:oauth_tokens, [:organization_id],
        name: :oauth_tokens_organization_id_index,
        concurrently: true
      )
    )

    create_if_not_exists(
      index(:oauth_tokens, [:client_id],
        name: :oauth_tokens_client_id_index,
        concurrently: true
      )
    )

    create_if_not_exists(
      index(:authorization_codes, [:user_id],
        name: :authorization_codes_user_id_index,
        concurrently: true
      )
    )

    create_if_not_exists(
      index(:device_codes, [:user_id],
        name: :device_codes_user_id_index,
        concurrently: true
      )
    )

    create_if_not_exists(
      index(:oauth_tokens, [:refresh_token_expires_at],
        name: :oauth_tokens_refresh_token_expires_at_index,
        concurrently: true
      )
    )

    create_if_not_exists(
      index(:blocked_addresses, [:ip],
        name: :blocked_addresses_ip_idx,
        concurrently: true
      )
    )

    create_if_not_exists(
      index(:organizations, [:public],
        name: :organizations_public_index,
        concurrently: true
      )
    )

    create_if_not_exists(
      index(:package_downloads, [:view],
        name: :package_downloads_view_index,
        concurrently: true
      )
    )

    create_if_not_exists(
      index(:sessions, ["((data->>'user_id')::integer)"],
        name: :sessions__data__user_id__integer_index,
        concurrently: true
      )
    )
  end
end
