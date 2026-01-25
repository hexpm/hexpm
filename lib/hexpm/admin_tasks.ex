defmodule Hexpm.AdminTasks do
  @moduledoc """
  Administrative tasks for managing users, packages, and organizations.

  These functions are intended to be called from iex or CLI for administrative operations.

  ## Confirmation Handling

  Functions that perform destructive operations require confirmation by default.
  Pass `skip_confirmation: true` to bypass the confirmation prompt:

      AdminTasks.remove_user("spammer")                          # prompts
      AdminTasks.remove_user("spammer", skip_confirmation: true) # no prompt

  ## Return Values

  All functions return tagged tuples:
  - `:ok` or `{:ok, result}` for success
  - `{:error, reason}` for errors (`:user_not_found`, `:confirmation_rejected`, etc.)

  ## Examples

      # Change a user's password
      iex> AdminTasks.change_password(:username, "bob", "new_password")
      :ok

      # Reset 2FA for a user
      iex> AdminTasks.reset_tfa("bob@example.com")
      :ok

      # Remove a user (with confirmation)
      iex> AdminTasks.remove_user("spammer")
      %User{username: "spammer", ...}
      Remove? [Yn] y
      :ok

      # Add an owner to a package
      iex> AdminTasks.add_owner("phoenix", "jose", level: "full")
      {:ok, %PackageOwner{}}

      # Remove a package (with confirmation)
      iex> AdminTasks.remove_package("hexpm", "malicious_pkg", skip_confirmation: true)
      :ok
  """

  use Hexpm.Context

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp maybe_confirm(prompt, opts) do
    if Keyword.get(opts, :skip_confirmation, false) do
      :ok
    else
      answer = IO.gets(prompt)

      if answer =~ ~r/^(Y(es)?)?$/i do
        :ok
      else
        {:error, :confirmation_rejected}
      end
    end
  end

  defp maybe_display(item, opts) do
    unless Keyword.get(opts, :skip_confirmation, false) do
      IO.inspect(item)
    end
  end

  defp find_user(username_or_email) do
    case Users.get(username_or_email, [:emails]) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp find_package(repo_name, package_name) do
    repository = Repositories.get(repo_name)

    cond do
      is_nil(repository) ->
        {:error, :repository_not_found}

      package = Packages.get(repository, package_name) ->
        {:ok, Repo.preload(package, :repository)}

      true ->
        {:error, :package_not_found}
    end
  end

  defp find_organization(name) do
    case Organizations.get(name, [:user]) do
      nil -> {:error, :organization_not_found}
      organization -> {:ok, organization}
    end
  end

  defp find_release(package, version) do
    case Releases.get(package, version) do
      nil -> {:error, :release_not_found}
      release -> {:ok, Repo.preload(release, package: :repository)}
    end
  end

  # ============================================================================
  # User Management
  # ============================================================================

  @doc """
  Changes a user's password without requiring the old password.

  ## Arguments

  - `type` - Either `:username` or `:email`
  - `identifier` - The username or email to look up
  - `password` - The new password

  ## Examples

      iex> AdminTasks.change_password(:username, "bob", "new_password")
      :ok

      iex> AdminTasks.change_password(:email, "bob@example.com", "new_password")
      :ok

      iex> AdminTasks.change_password(:username, "nonexistent", "password")
      {:error, :user_not_found}
  """
  @spec change_password(:username | :email, String.t(), String.t()) :: :ok | {:error, atom()}
  def change_password(type, identifier, password)

  def change_password(:username, username, password) do
    case Repo.get_by(User, username: username) do
      nil ->
        {:error, :user_not_found}

      user ->
        User.update_password_no_check(user, %{password: password})
        |> Repo.update!()

        :ok
    end
  end

  def change_password(:email, email, password) do
    # Users.get handles looking up by email through the emails table
    case Users.get(email) do
      nil ->
        {:error, :user_not_found}

      user ->
        User.update_password_no_check(user, %{password: password})
        |> Repo.update!()

        :ok
    end
  end

  @doc """
  Resets (disables) two-factor authentication for a user.

  ## Arguments

  - `username_or_email` - The username or email of the user

  ## Examples

      iex> AdminTasks.reset_tfa("bob")
      :ok

      iex> AdminTasks.reset_tfa("bob@example.com")
      :ok

      iex> AdminTasks.reset_tfa("nonexistent")
      {:error, :user_not_found}
  """
  @spec reset_tfa(String.t()) :: :ok | {:error, atom()}
  def reset_tfa(username_or_email) do
    with {:ok, user} <- find_user(username_or_email) do
      cond do
        not User.tfa_enabled?(user) ->
          {:error, :tfa_not_enabled}

        true ->
          Users.tfa_disable(user, audit: AuditLogs.admin())
          :ok
      end
    end
  end

  @doc """
  Removes a user from the system.

  ## Arguments

  - `username` - The username of the user to remove
  - `opts` - Options:
    - `:skip_confirmation` - Skip the confirmation prompt (default: `false`)

  ## Examples

      iex> AdminTasks.remove_user("spammer")
      %User{username: "spammer", ...}
      Remove? [Yn] y
      :ok

      iex> AdminTasks.remove_user("spammer", skip_confirmation: true)
      :ok
  """
  @spec remove_user(String.t(), keyword()) :: :ok | {:error, atom()}
  def remove_user(username, opts \\ []) do
    with {:ok, user} <- find_user(username) do
      maybe_display(user, opts)

      with :ok <- maybe_confirm("Remove? [Yn] ", opts) do
        Repo.delete!(user)
        :ok
      end
    end
  end

  @doc """
  Renames a user.

  ## Arguments

  - `old_name` - The current username
  - `new_name` - The new username
  - `opts` - Options:
    - `:skip_confirmation` - Skip the confirmation prompt (default: `false`)

  ## Examples

      iex> AdminTasks.rename_user("oldname", "newname")
      %User{username: "oldname", ...}
      Rename? [Yn] y
      :ok

      iex> AdminTasks.rename_user("oldname", "newname", skip_confirmation: true)
      :ok
  """
  @spec rename_user(String.t(), String.t(), keyword()) :: :ok | {:error, atom()}
  def rename_user(old_name, new_name, opts \\ []) do
    with {:ok, user} <- find_user(old_name) do
      maybe_display(user, opts)

      with :ok <- maybe_confirm("Rename? [Yn] ", opts) do
        user
        |> Ecto.Changeset.change(username: new_name)
        |> Repo.update!()

        :ok
      end
    end
  end

  # ============================================================================
  # Package Management
  # ============================================================================

  @doc """
  Allows republishing a release by resetting its inserted_at timestamp.

  ## Arguments

  - `package_name` - The name of the package
  - `version` - The version to allow republishing
  - `opts` - Options:
    - `:organization` - The organization name (default: `nil` for hexpm)

  ## Examples

      iex> AdminTasks.allow_republish("phoenix", "1.0.0")
      :ok

      iex> AdminTasks.allow_republish("private_pkg", "1.0.0", organization: "my_org")
      :ok
  """
  @spec allow_republish(String.t(), String.t(), keyword()) :: :ok | {:error, atom()}
  def allow_republish(package_name, version, opts \\ []) do
    org_name = Keyword.get(opts, :organization)

    # Find repository - either by organization name or default to hexpm (id: 1)
    repository =
      if org_name do
        Repo.get_by(Repository, name: org_name)
      else
        Repo.get(Repository, 1)
      end

    cond do
      is_nil(repository) ->
        {:error, :repository_not_found}

      true ->
        package = Repo.get_by(Package, name: package_name, repository_id: repository.id)

        cond do
          is_nil(package) ->
            {:error, :package_not_found}

          true ->
            release = Repo.get_by(Ecto.assoc(package, :releases), version: version)

            cond do
              is_nil(release) ->
                {:error, :release_not_found}

              true ->
                Ecto.Changeset.change(release, %{inserted_at: DateTime.utc_now()})
                |> Repo.update!()

                :ok
            end
        end
    end
  end

  @doc """
  Removes a package and all its releases.

  ## Arguments

  - `repo` - The repository name (e.g., "hexpm")
  - `package_name` - The name of the package to remove
  - `opts` - Options:
    - `:skip_confirmation` - Skip the confirmation prompt (default: `false`)

  ## Examples

      iex> AdminTasks.remove_package("hexpm", "malicious_pkg")
      Owners:
      owner1 owner1@example.com
      Releases:
      1.0.0
      2.0.0
      Remove? [Yn] y
      :ok
  """
  @spec remove_package(String.t(), String.t(), keyword()) :: :ok | {:error, atom()}
  def remove_package(repo, package_name, opts \\ []) do
    with {:ok, package} <- find_package(repo, package_name) do
      owners =
        Ecto.assoc(package, :owners)
        |> Repo.all()
        |> Repo.preload(:emails)

      package_owners =
        Ecto.assoc(package, :package_owners)
        |> Repo.all()

      releases =
        Release.all(package)
        |> Repo.all()
        |> Repo.preload(package: :repository)

      unless Keyword.get(opts, :skip_confirmation, false) do
        IO.puts("")
        IO.puts("Owners:")

        Enum.each(owners, fn owner ->
          IO.puts("#{owner.username} #{User.email(owner, :primary)}")
        end)

        IO.puts("")
        IO.puts("Releases:")
        Enum.each(releases, &IO.puts(&1.version))
      end

      with :ok <- maybe_confirm("Remove? [Yn] ", opts) do
        Enum.each(package_owners, &Repo.delete!/1)

        Enum.each(releases, fn release ->
          Release.delete(release, force: true) |> Repo.delete!()
        end)

        Repo.delete!(package)
        Enum.each(releases, &Assets.revert_release/1)
        RegistryBuilder.package_delete(package)
        RegistryBuilder.repository(package.repository)
        :ok
      end
    end
  end

  @doc """
  Removes a specific release from a package.

  ## Arguments

  - `repo` - The repository name (e.g., "hexpm")
  - `package_name` - The name of the package
  - `version` - The version to remove
  - `opts` - Options:
    - `:skip_confirmation` - Skip the confirmation prompt (default: `false`)

  ## Examples

      iex> AdminTasks.remove_release("hexpm", "my_pkg", "1.0.0")
      Remove? [Yn] y
      :ok
  """
  @spec remove_release(String.t(), String.t(), String.t(), keyword()) :: :ok | {:error, atom()}
  def remove_release(repo, package_name, version, opts \\ []) do
    with {:ok, package} <- find_package(repo, package_name),
         {:ok, release} <- find_release(package, version) do
      with :ok <- maybe_confirm("Remove? [Yn] ", opts) do
        Release.delete(release, force: true)
        |> Repo.delete!()

        Assets.revert_release(release)
        RegistryBuilder.package(package)
        RegistryBuilder.repository(package.repository)
        :ok
      end
    end
  end

  # ============================================================================
  # Owner Management
  # ============================================================================

  @doc """
  Adds an owner to a package.

  ## Arguments

  - `package_name` - The name of the package
  - `username_or_email` - The username or email of the user to add
  - `opts` - Options:
    - `:level` - The ownership level (default: not specified, uses Owners.add default)
    - `:transfer` - Whether this is a transfer operation (default: `false`)

  ## Examples

      iex> AdminTasks.add_owner("phoenix", "jose")
      {:ok, %PackageOwner{}}

      iex> AdminTasks.add_owner("phoenix", "jose", level: "full")
      {:ok, %PackageOwner{}}

      iex> AdminTasks.add_owner("phoenix", "jose", transfer: true)
      {:ok, %PackageOwner{}}
  """
  @spec add_owner(String.t(), String.t(), keyword()) ::
          {:ok, PackageOwner.t()} | {:error, atom() | Ecto.Changeset.t()}
  def add_owner(package_name, username_or_email, opts \\ []) do
    package =
      Packages.get("hexpm", package_name)
      |> Repo.preload(repository: :organization)

    user = Users.get(username_or_email, [:emails])

    params =
      %{}
      |> maybe_put_param("level", Keyword.get(opts, :level))
      |> maybe_put_param("transfer", Keyword.get(opts, :transfer))

    Owners.add(package, user, params, audit: AuditLogs.admin())
  end

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, key, value), do: Map.put(params, key, value)

  @doc """
  Removes an owner from a package.

  ## Arguments

  - `package_name` - The name of the package
  - `username_or_email` - The username or email of the owner to remove

  ## Examples

      iex> AdminTasks.remove_owner("phoenix", "jose")
      :ok

      iex> AdminTasks.remove_owner("phoenix", "nonexistent")
      {:error, :not_owner}
  """
  @spec remove_owner(String.t(), String.t()) :: :ok | {:error, atom()}
  def remove_owner(package_name, username_or_email) do
    package = Packages.get("hexpm", package_name)
    user = Users.get(username_or_email, [:emails])

    Owners.remove(package, user, audit: AuditLogs.admin())
  end

  # ============================================================================
  # Organization Management
  # ============================================================================

  @doc """
  Renames an organization.

  This updates the organization name, its associated user's username, and all
  key permissions that reference the organization.

  ## Arguments

  - `old_name` - The current organization name
  - `new_name` - The new organization name
  - `opts` - Options:
    - `:skip_confirmation` - Skip the confirmation prompt (default: `false`)
    - `:dry_run` - Show what would be changed without making changes (default: `false`)

  ## Examples

      iex> AdminTasks.rename_organization("old_org", "new_org")
      %Organization{name: "old_org", ...}
      Rename? [Yn] y
      :ok

      iex> AdminTasks.rename_organization("old_org", "new_org", dry_run: true)
      # Shows changesets without applying them
      :ok
  """
  @spec rename_organization(String.t(), String.t(), keyword()) :: :ok | {:error, atom()}
  def rename_organization(old_name, new_name, opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)

    with {:ok, organization} <- find_organization(old_name) do
      maybe_display(organization, opts)

      with :ok <- maybe_confirm("Rename? [Yn] ", opts) do
        user_changeset = Ecto.Changeset.change(organization.user, username: new_name)

        changeset =
          organization
          |> Ecto.Changeset.change(name: new_name)
          |> Ecto.Changeset.put_assoc(:user, user_changeset)

        Repo.transaction(fn ->
          if dry_run? do
            IO.inspect(changeset)
          else
            Repo.update!(changeset)
          end

          keys = Repo.all(Key)

          Enum.each(keys, fn key ->
            needs_update? =
              Enum.any?(key.permissions, fn permission ->
                permission.domain == "repository" and permission.resource == old_name
              end)

            if needs_update? do
              permissions =
                Enum.map(key.permissions, fn permission ->
                  if permission.domain == "repository" do
                    Ecto.Changeset.change(permission, resource: new_name)
                  else
                    permission
                  end
                end)

              key_changeset =
                key
                |> Ecto.Changeset.change()
                |> Ecto.Changeset.put_embed(:permissions, permissions)

              if dry_run? do
                IO.inspect(key_changeset)
              else
                Repo.update!(key_changeset)
              end

              IO.puts("#{key.name} - #{key.id}")
            end
          end)
        end)

        :ok
      end
    end
  end

  # ============================================================================
  # Install Management
  # ============================================================================

  @doc """
  Adds a new Hex install version and uploads the install list to S3/CDN.

  ## Arguments

  - `hex_version` - The Hex version (optional, pass `nil` to only upload current list)
  - `elixir_versions` - List of compatible Elixir versions (default: `[]`)

  ## Examples

      iex> AdminTasks.add_install("2.0.0", ["1.14.0", "1.15.0"])
      :ok

      iex> AdminTasks.add_install(nil, [])  # Just uploads current list
      :ok
  """
  @spec add_install(String.t() | nil, [String.t()]) :: :ok
  def add_install(hex_version \\ nil, elixir_versions \\ []) do
    if hex_version do
      Install.build(hex_version, elixir_versions)
      |> Repo.insert!()

      IO.puts("Hex:     " <> hex_version)
      IO.puts("Elixirs: " <> Enum.join(elixir_versions, ", "))
    end

    all = Install.all() |> Repo.all()

    csv =
      Enum.map_join(all, "\n", fn install ->
        Enum.join([install.hex | install.elixirs], ",")
      end)

    store_opts = [
      acl: :public_read,
      content_type: "text/csv",
      cache_control: "public, max-age=604800",
      meta: [{"surrogate-key", "installs"}]
    ]

    Hexpm.Store.put(:repo_bucket, "installs/list.csv", csv, store_opts)
    Hexpm.CDN.purge_key(:fastly_hexrepo, "installs")

    IO.puts("Uploaded installs/list.csv")
    :ok
  end
end
