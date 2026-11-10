defmodule Hexpm.AdminTasks do
  @moduledoc """
  Administrative tasks for managing users, packages, and organizations.

  These functions are intended to be called from iex or CLI for administrative operations.

  ## Return Values

  All functions return tagged tuples:
  - `:ok` or `{:ok, result}` for success
  - `{:error, reason}` for errors (`:user_not_found`, etc.)

  ## Examples

      # Change a user's password
      iex> AdminTasks.change_password(:username, "bob", "new_password")
      :ok

      # Reset 2FA for a user
      iex> AdminTasks.reset_tfa("bob@example.com")
      :ok

      # Remove a user
      iex> AdminTasks.remove_user("spammer")
      :ok

      # Remove a user and their sole-owned packages
      iex> AdminTasks.remove_user("spammer", delete_packages: true)
      :ok

      # Add an owner to a package
      iex> AdminTasks.add_owner("phoenix", "jose", level: "full")
      {:ok, %PackageOwner{}}

      # Remove a member from an organization
      iex> AdminTasks.remove_organization_member("acme", "jose")
      :ok

      # Delete an organization and everything stored under its name
      iex> AdminTasks.delete_organization("acme", delete_data: true)
      :ok

      # Remove a package
      iex> AdminTasks.remove_package("hexpm", "malicious_pkg")
      :ok

      # Remove a package and tell its owners why
      iex> AdminTasks.reasons(:package) |> Keyword.keys()
      [:seo_spam, :empty, :name_squatting, ...]
      iex> AdminTasks.remove_package("hexpm", "seo_pkg", reason: :seo_spam)
      :ok

      # Take a package out of hexdocs search, and put it back
      iex> AdminTasks.disable_search("noisy_pkg", delete_index: true, notify: true)
      :ok
      iex> AdminTasks.enable_search("noisy_pkg", reindex: true)
      :ok

      # Send an email
      iex> AdminTasks.send_email(["bob@example.com"], "Hex.pm - Subject", "Body")
      {:ok, 1}

      # Report, then delete, objects no package or release accounts for
      iex> AdminTasks.orphaned_objects(buckets: [:diff_bucket])
      %{diff_bucket: %{scanned: 812, orphaned: 40, unrecognised: 0, ...}}
      iex> AdminTasks.delete_orphaned_objects(buckets: [:diff_bucket])
      %{diff_bucket: %{deleted: 40, ...}}

  ## Removal emails

  `remove_package/3`, `remove_release/4` and `remove_user/2` take a `:reason`
  and stay silent without one. A reason is either an id from `reasons/1` or
  your own text, and it is resolved before anything is deleted, so a
  misremembered id fails without touching the database. `reason: "seo_spam"`
  is refused too, since a string spelling an id is a quoted atom rather than
  something somebody wrote.

  The removal itself never depends on the mail. If the notice cannot be sent,
  because delivery failed or because nobody reachable is left to send it to,
  that is logged as an error and the removal still reports `:ok`.

  ## Audit log

  Every task that changes something writes a `Hexpm.AdminTasks.AuditLog`
  entry with its arguments before it runs, and fills in the outcome when it
  returns or raises. A task whose entry can't be written doesn't run, and an
  entry still `"started"` is a run that never finished. Passwords are left
  out. The `:audit` option takes the audit data of whoever
  ran it, see `HexpmWeb.ControllerHelpers.audit_data/1`; without it the entry
  is recorded as a console run. The read-only tasks, `reasons/1`,
  `blocked_email_domains/0`, `search_disabled_packages/0` and
  `orphaned_objects/1`, are not recorded.

      iex> AdminTasks.audit_logs(1, 20)
      [%Hexpm.AdminTasks.AuditLog{action: "remove_package", status: "ok", ...}]
  """

  use Hexpm.Context

  import Ecto.Query, only: [from: 2, dynamic: 2]

  alias Hexpm.AdminTasks.AuditLog, as: AdminAuditLog
  alias Hexpm.AdminTasks.Reasons
  alias Hexpm.Emails.{Outbox, OutboxEntry, OutboxLock}
  alias Hexpm.Hexdocs

  @announcement_category "admin.announcement"
  # Announcements queue behind transactional mail: package reports, secret-scan
  # alerts and SSO notices go out first.
  @announcement_priority 3

  # Fastly takes at most 256 surrogate keys in one purge request.

  @console_audit %{user: nil, auth_credential: nil, user_agent: "CONSOLE", remote_ip: nil}

  require Logger

  @doc """
  The audit log entries of every task run, newest first.
  """
  @spec audit_logs(pos_integer(), pos_integer()) :: [AdminAuditLog.t()]
  def audit_logs(page, per_page) do
    AdminAuditLog.newest_first()
    |> Hexpm.Utils.paginate(page, per_page)
    |> Repo.all()
  end

  @spec count_audit_logs() :: non_neg_integer()
  def count_audit_logs() do
    Repo.aggregate(AdminAuditLog, :count)
  end

  @doc """
  The newest audit log entries of the tasks run on a user, package or
  organization, matched on the names the tasks were given.

  A user is matched on its username and emails, a package on its repository
  and name, and an organization on its name.

      iex> AdminTasks.target_audit_logs(:user, ["bob", "bob@example.com"])
      [%Hexpm.AdminTasks.AuditLog{action: "reset_tfa", ...}]

      iex> AdminTasks.target_audit_logs(:package, {"hexpm", "phoenix"})
      [%Hexpm.AdminTasks.AuditLog{action: "add_owner", ...}]
  """
  @spec target_audit_logs(:user, [String.t()]) :: [AdminAuditLog.t()]
  @spec target_audit_logs(:package, {String.t(), String.t()}) :: [AdminAuditLog.t()]
  @spec target_audit_logs(:organization, String.t()) :: [AdminAuditLog.t()]
  def target_audit_logs(kind, target) do
    from(l in AdminAuditLog.newest_first(), where: ^target_filter(kind, target), limit: 20)
    |> Repo.all()
  end

  defp target_filter(:user, names) do
    dynamic(
      [l],
      fragment("?->>'user'", l.params) in ^names or
        (l.action == "rename_user" and
           (fragment("?->>'old_name'", l.params) in ^names or
              fragment("?->>'new_name'", l.params) in ^names))
    )
  end

  # The tasks on hexpm packages take no repository, and allow_republish names
  # it as an organization.
  defp target_filter(:package, {repository, name}) do
    dynamic(
      [l],
      fragment("?->>'package'", l.params) == ^name and
        fragment(
          "coalesce(?->>'repository', ?->>'organization', 'hexpm')",
          l.params,
          l.params
        ) == ^repository
    )
  end

  defp target_filter(:organization, name) do
    dynamic(
      [l],
      fragment("?->>'organization'", l.params) == ^name or
        (l.action == "rename_organization" and
           (fragment("?->>'old_name'", l.params) == ^name or
              fragment("?->>'new_name'", l.params) == ^name))
    )
  end

  @doc """
  Looks up a user by username or email with their emails, the packages they
  own and the organizations they are a member of. Records nothing.

  `owner_count` is the number of owners the package has, 1 when the user is
  its only owner.

      iex> AdminTasks.lookup_user("bob")
      {:ok, %{user: %User{}, packages: [%{repository: "hexpm", name: "decimal",
       level: "full", owner_count: 1}], organizations: [%{name: "acme", role: "admin"}]}}
  """
  @spec lookup_user(String.t()) :: {:ok, map()} | {:error, :user_not_found}
  def lookup_user(username_or_email) do
    with {:ok, user} <- find_user(username_or_email) do
      owner_counts =
        from(po in PackageOwner,
          group_by: po.package_id,
          select: %{package_id: po.package_id, count: count()}
        )

      packages =
        from(po in PackageOwner,
          join: p in assoc(po, :package),
          join: r in assoc(p, :repository),
          join: c in subquery(owner_counts),
          on: c.package_id == p.id,
          where: po.user_id == ^user.id,
          order_by: [r.name, p.name],
          select: %{repository: r.name, name: p.name, level: po.level, owner_count: c.count}
        )
        |> Repo.all()

      organizations =
        from(ou in OrganizationUser,
          join: o in assoc(ou, :organization),
          where: ou.user_id == ^user.id,
          order_by: o.name,
          select: %{name: o.name, role: ou.role}
        )
        |> Repo.all()

      {:ok, %{user: user, packages: packages, organizations: organizations}}
    end
  end

  @doc """
  Looks up a package with its owners and releases, newest first. Records
  nothing.

      iex> AdminTasks.lookup_package("hexpm", "decimal")
      {:ok, %{package: %Package{}, owners: [%{username: "eric", level: "full"}],
       releases: [%{version: #Version<2.0.0>, inserted_at: ~U[...], retired: false}]}}
  """
  @spec lookup_package(String.t(), String.t()) ::
          {:ok, map()} | {:error, :repository_not_found | :package_not_found}
  def lookup_package(repository, name) do
    with {:ok, package} <- find_package(repository, name) do
      owners =
        from(po in PackageOwner,
          join: u in assoc(po, :user),
          where: po.package_id == ^package.id,
          order_by: u.username,
          select: %{username: u.username, level: po.level}
        )
        |> Repo.all()

      releases =
        from(r in Release,
          where: r.package_id == ^package.id,
          order_by: [desc: r.inserted_at],
          select: %{
            version: r.version,
            inserted_at: r.inserted_at,
            retired: not is_nil(r.retirement)
          }
        )
        |> Repo.all()

      {:ok, %{package: package, owners: owners, releases: releases}}
    end
  end

  @doc """
  Looks up an organization with its members, the packages in its repository
  and the status of its billing subscription, `nil` without one. Records
  nothing.

      iex> AdminTasks.lookup_organization("acme")
      {:ok, %{organization: %Organization{}, repository: "acme",
       members: [%{username: "bob", role: "admin"}], packages: ["acme_api"],
       billing_status: "active"}}
  """
  @spec lookup_organization(String.t()) :: {:ok, map()} | {:error, :organization_not_found}
  def lookup_organization(name) do
    with {:ok, organization} <- find_organization(name) do
      organization = Repo.preload(organization, :repository)

      members =
        from(ou in OrganizationUser,
          join: u in assoc(ou, :user),
          where: ou.organization_id == ^organization.id,
          order_by: u.username,
          select: %{username: u.username, role: ou.role}
        )
        |> Repo.all()

      packages =
        case organization.repository do
          nil ->
            []

          repository ->
            from(p in Package,
              where: p.repository_id == ^repository.id,
              order_by: p.name,
              select: p.name
            )
            |> Repo.all()
        end

      billing_status =
        case Hexpm.Billing.get(organization.name) do
          %{"subscription" => %{"status" => status}} -> status
          _customer -> nil
        end

      {:ok,
       %{
         organization: organization,
         repository: organization.repository && organization.repository.name,
         members: members,
         packages: packages,
         billing_status: billing_status
       }}
    end
  end

  # The entry is written before the task and outside any transaction it opens,
  # so a task that rolls back, raises or is killed half way is still recorded.
  defp audited(action, params, opts, fun) do
    audit_data = Keyword.get(opts, :audit, @console_audit)
    log = Repo.insert!(AdminAuditLog.build(audit_data, action, params))

    try do
      fun.()
    catch
      kind, reason ->
        finish(log, "raised", Exception.format_banner(kind, reason, __STACKTRACE__))
        :erlang.raise(kind, reason, __STACKTRACE__)
    else
      result ->
        {status, summary} = summarize_result(result)
        finish(log, status, summary)
        result
    end
  end

  # The task has already run, so failing to record its outcome must not replace
  # its result or its exception. The entry stays "started".
  defp finish(log, status, summary) do
    from(l in AdminAuditLog, where: l.id == ^log.id)
    |> Repo.update_all(set: [status: status, result: summary])
  rescue
    exception ->
      Logger.error(
        "Could not record the outcome of admin task #{log.action} (audit log #{log.id}): " <>
          Exception.message(exception)
      )
  end

  defp summarize_result(:ok), do: {"ok", nil}
  defp summarize_result({:ok, count}) when is_integer(count), do: {"ok", "#{count}"}
  defp summarize_result({:ok, %Oban.Job{id: id}}), do: {"ok", "job #{id}"}
  defp summarize_result({:ok, _value}), do: {"ok", nil}
  defp summarize_result({:error, %Ecto.Changeset{errors: errors}}), do: {"error", inspect(errors)}
  defp summarize_result({:error, reason}), do: {"error", inspect(reason)}
  defp summarize_result(report) when is_map(report), do: {"ok", inspect(report, limit: 50)}

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

      iex> AdminTasks.change_password(:username, "bob", "short")
      {:error, %Ecto.Changeset{}}
  """
  @spec change_password(:username | :email, String.t(), String.t(), keyword()) ::
          :ok | {:error, atom() | Ecto.Changeset.t()}
  def change_password(type, identifier, password, opts \\ [])
      when type in [:username, :email] do
    audited(:change_password, %{type: type, user: identifier}, opts, fn ->
      case find_user_by(type, identifier) do
        nil ->
          {:error, :user_not_found}

        user ->
          case Repo.update(User.update_password_no_check(user, %{password: password})) do
            {:ok, _user} -> :ok
            {:error, changeset} -> {:error, changeset}
          end
      end
    end)
  end

  defp find_user_by(:username, username), do: Repo.get_by(User, username: username)
  # Users.get handles looking up by email through the emails table
  defp find_user_by(:email, email), do: Users.get(email)

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
  @spec reset_tfa(String.t(), keyword()) :: :ok | {:error, atom() | Ecto.Changeset.t()}
  def reset_tfa(username_or_email, opts \\ []) do
    audited(:reset_tfa, %{user: username_or_email}, opts, fn ->
      with {:ok, user} <- find_user(username_or_email) do
        cond do
          not User.tfa_enabled?(user) ->
            {:error, :tfa_not_enabled}

          true ->
            case Users.tfa_disable(user, audit: AuditLogs.admin()) do
              %User{} -> :ok
              {:error, reason} -> {:error, reason}
            end
        end
      end
    end)
  end

  @doc """
  Removes a user from the system.

  ## Arguments

  - `username` - The username of the user to remove
  - `opts` - Options:
    - `:delete_packages` - When `true`, deletes all packages where the user is
      the sole owner before removing the user (default: `false`)
    - `:reason` - Emails the user why the account was removed, either a canned
      id from `reasons(:user)` or your own text. Nothing is sent without it.

  ## Examples

      iex> AdminTasks.remove_user("spammer")
      :ok

      iex> AdminTasks.remove_user("spammer", delete_packages: true)
      :ok

      iex> AdminTasks.remove_user("spammer", reason: :spam_account)
      :ok
  """
  @spec remove_user(String.t(), keyword()) :: :ok | {:error, term()}
  def remove_user(username, opts \\ []) do
    deleted_packages? = Keyword.get(opts, :delete_packages, false)
    params = %{user: username, delete_packages: deleted_packages?, reason: opts[:reason]}

    audited(:remove_user, params, opts, fn ->
      with {:ok, user} <- find_user(username),
           {:ok, reason} <- resolve_reason(:user, opts),
           :ok <- delete_user(user, opts) do
        notify_removal(
          reason,
          "user #{user.username}",
          &Emails.account_removed(verified_only(user), deleted_packages?, &1)
        )

        :ok
      end
    end)
  end

  # A removal notice accuses somebody. An unverified address was never proved to
  # belong to this account, and on an abuse removal it is as likely as not to be
  # a bystander's, so it gets dropped and notify_removal logs that nobody was
  # reachable.
  defp verified_only(user) do
    %{user | emails: Enum.filter(user.emails, & &1.verified)}
  end

  defp delete_user(user, opts) do
    if Keyword.get(opts, :delete_packages, false) do
      Repo.transaction(fn ->
        deleted = delete_sole_owned_packages(user)

        case Users.delete(user, audit: AuditLogs.admin(), notify: false) do
          :ok -> deleted
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, deleted} ->
          Enum.each(deleted, &run_package_removal_side_effects/1)
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      Users.delete(user, audit: AuditLogs.admin(), notify: false)
    end
  end

  defp delete_sole_owned_packages(user) do
    owned_packages =
      Ecto.assoc(user, :owned_packages)
      |> Repo.all()
      |> Repo.preload(:repository)

    Enum.flat_map(owned_packages, fn package ->
      owner_count =
        Ecto.assoc(package, :package_owners)
        |> Repo.aggregate(:count)

      if owner_count == 1 do
        [remove_package_db(package)]
      else
        []
      end
    end)
  end

  @doc """
  Renames a user.

  ## Arguments

  - `old_name` - The current username
  - `new_name` - The new username, refused if it is reserved

  ## Examples

      iex> AdminTasks.rename_user("oldname", "newname")
      :ok

      iex> AdminTasks.rename_user("oldname", "deleted_user")
      {:error, :name_reserved}
  """
  @spec rename_user(String.t(), String.t(), keyword()) :: :ok | {:error, atom()}
  def rename_user(old_name, new_name, opts \\ []) do
    audited(:rename_user, %{old_name: old_name, new_name: new_name}, opts, fn ->
      with {:ok, user} <- find_user(old_name),
           :ok <- check_name_available(new_name) do
        user
        |> Ecto.Changeset.change(username: new_name)
        |> Repo.update!()

        :ok
      end
    end)
  end

  defp check_name_available(name) do
    if Repo.exists?(ReservedUsername.by_name(name)) do
      {:error, :name_reserved}
    else
      :ok
    end
  end

  @doc """
  Blocks new email addresses on a domain and everything under it.

  Existing addresses stay; only adding an address on the domain fails, at
  signup and in the account settings alike.

  ## Examples

      iex> AdminTasks.block_email_domain("example.com", comment: "signup farm")
      :ok
  """
  @spec block_email_domain(String.t(), keyword()) :: :ok | {:error, Ecto.Changeset.t()}
  def block_email_domain(domain, opts \\ []) do
    params = %{domain: domain, comment: Keyword.get(opts, :comment)}

    audited(:block_email_domain, params, opts, fn ->
      case Repo.insert(BlockedEmailDomain.changeset(%BlockedEmailDomain{}, params)) do
        {:ok, _blocked} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  @doc """
  Removes a domain from the email block list.

  ## Examples

      iex> AdminTasks.unblock_email_domain("example.com")
      :ok
  """
  @spec unblock_email_domain(String.t(), keyword()) :: :ok | {:error, :not_found}
  def unblock_email_domain(domain, opts \\ []) do
    audited(:unblock_email_domain, %{domain: domain}, opts, fn ->
      case Repo.delete_all(BlockedEmailDomain.by_domain(domain)) do
        {0, _} -> {:error, :not_found}
        {_count, _} -> :ok
      end
    end)
  end

  @doc """
  Lists the blocked email domains with their comments.

  ## Examples

      iex> AdminTasks.blocked_email_domains()
      [%{domain: "example.com", comment: "signup farm"}]
  """
  @spec blocked_email_domains() :: [%{domain: String.t(), comment: String.t() | nil}]
  def blocked_email_domains() do
    from(b in BlockedEmailDomain,
      order_by: b.domain,
      select: %{domain: b.domain, comment: b.comment}
    )
    |> Repo.all()
  end

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
    params = %{package: package_name, version: version, organization: org_name}

    audited(:allow_republish, params, opts, fn ->
      reset_release_inserted_at(package_name, version, org_name)
    end)
  end

  defp reset_release_inserted_at(package_name, version, org_name) do
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
    - `:reason` - Emails the owners why the package was removed, either a
      canned id from `reasons(:package)` or your own text. Nothing is sent
      without it.

  ## Examples

      iex> AdminTasks.remove_package("hexpm", "malicious_pkg")
      :ok

      iex> AdminTasks.remove_package("hexpm", "seo_pkg", reason: :seo_spam)
      :ok
  """
  @spec remove_package(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def remove_package(repo, package_name, opts \\ []) do
    params = %{repository: repo, package: package_name, reason: opts[:reason]}

    audited(:remove_package, params, opts, fn ->
      with {:ok, package} <- find_package(repo, package_name),
           {:ok, reason} <- resolve_reason(:package, opts) do
        owners = reason && removal_recipients(package)

        {:ok, {releases, package}} =
          Repo.transaction(fn ->
            remove_package_db(package)
          end)

        run_package_removal_side_effects({releases, package})

        notify_removal(
          reason,
          "owners of #{package.name}",
          &Emails.package_removed(owners, package.name, &1)
        )

        :ok
      end
    end)
  end

  # Read before the package goes, otherwise there is nobody left to write to.
  defp removal_recipients(package) do
    case Repo.all(assoc(package, :owners)) do
      [] ->
        organization_recipients(package)

      owners ->
        Repo.preload(owners, [:emails, organization: [organization_users: [user: :emails]]])
    end
  end

  # A package published into an organization repository has no package_owners
  # row at all: access there is decided by membership, and Package.put_first_owner
  # only writes an owner for repository 1. Without this fallback every removal
  # in a private repository would notify nobody.
  defp organization_recipients(%{repository: %Repository{id: 1}}), do: []

  defp organization_recipients(package) do
    package.repository
    |> Repo.preload(organization: [organization_users: [user: :emails]])
    |> Map.fetch!(:organization)
    |> List.wrap()
  end

  defp remove_package_db(package) do
    package_owners =
      Ecto.assoc(package, :package_owners)
      |> Repo.all()

    releases =
      Release.all(package)
      |> Repo.all()
      |> Repo.preload(package: :repository)

    Enum.each(package_owners, &Repo.delete!/1)

    Enum.each(releases, fn release ->
      Release.delete(release, force: true) |> Repo.delete!()
    end)

    Repo.delete!(package)
    {:ok, _} = RegistryWorker.enqueue_package_delete(package)
    {:ok, _} = RegistryWorker.enqueue_repository(package.repository)
    {releases, package}
  end

  defp run_package_removal_side_effects({releases, package}) do
    Enum.each(releases, &Assets.revert_release/1)
    {:ok, _} = Hexpm.Diff.CacheDeleteWorker.enqueue(package.repository.name, package.name)
  end

  @doc """
  Removes a specific release from a package.

  ## Arguments

  - `repo` - The repository name (e.g., "hexpm")
  - `package_name` - The name of the package
  - `version` - The version to remove
  - `opts` - Options:
    - `:reason` - Emails the owners why the release was removed, either a
      canned id from `reasons(:release)` or your own text. Nothing is sent
      without it.

  ## Examples

      iex> AdminTasks.remove_release("hexpm", "my_pkg", "1.0.0")
      :ok

      iex> AdminTasks.remove_release("hexpm", "my_pkg", "1.0.0", reason: :undisclosed_behaviour)
      :ok
  """
  @spec remove_release(String.t(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def remove_release(repo, package_name, version, opts \\ []) do
    params = %{repository: repo, package: package_name, version: version, reason: opts[:reason]}

    audited(:remove_release, params, opts, fn ->
      with {:ok, package} <- find_package(repo, package_name),
           {:ok, release} <- find_release(package, version),
           {:ok, reason} <- resolve_reason(:release, opts) do
        owners = reason && removal_recipients(package)

        Release.delete(release, force: true)
        |> Repo.delete!()

        Assets.revert_release(release)
        {:ok, _} = RegistryWorker.enqueue_package(package)
        {:ok, _} = RegistryWorker.enqueue_repository(package.repository)
        {:ok, _} = Hexpm.Diff.CacheDeleteWorker.enqueue(package.repository.name, package.name)

        remaining = Repo.aggregate(assoc(package, :releases), :count)

        notify_removal(
          reason,
          "owners of #{package.name}",
          &Emails.release_removed(owners, package.name, version, remaining, &1)
        )

        :ok
      end
    end)
  end

  @doc """
  The canned `:reason` values a removal task accepts, as `{id, text}` pairs.

      iex> AdminTasks.reasons(:package) |> Keyword.keys()
      [:seo_spam, :empty, :name_squatting, :typosquatting, :copyright,
       :undisclosed_behaviour, :malware, :owner_request, :terms_of_service]
  """
  @spec reasons(:package | :release | :user) :: keyword(String.t())
  defdelegate reasons(scope), to: Reasons, as: :all

  # Resolved before anything is deleted so an unknown id costs nothing.
  defp resolve_reason(scope, opts) do
    case Keyword.get(opts, :reason) do
      nil -> {:ok, nil}
      reason -> Reasons.fetch(scope, reason)
    end
  end

  # A delivery failure is logged and not raised, the deletion already happened
  # and the caller has no way to undo it. Having nobody to write to is logged
  # for the same reason: the removal is done either way, and an admin who asked
  # for a reason to be sent should not have to infer from a bare :ok that it
  # never went anywhere.
  defp notify_removal(nil, _description, _build_email), do: :ok

  defp notify_removal(reason, description, build_email) do
    case build_email.(reason) do
      %{to: []} ->
        Logger.error("Removed with a reason but found no address for #{description}")

      email ->
        deliver(email, description)
    end

    :ok
  end

  @doc """
  Stops indexing a hexpm package's documentation for the search on
  hexdocs.pm. The search indexer skips the package's new versions until
  `enable_search/2` is called.

  ## Options

  - `:delete_index` - Also removes the versions already in the search index,
    below the publish jobs. Defaults to `false`.
  - `:notify` - Emails the owners that the package was taken out of search,
    why, and that carrying on may get the package removed and its publishers
    banned. Defaults to `false`.

  ## Examples

      iex> AdminTasks.disable_search("noisy_pkg")
      :ok

      iex> AdminTasks.disable_search("noisy_pkg", delete_index: true, notify: true)
      :ok
  """
  @spec disable_search(String.t(), keyword()) :: :ok | {:error, atom()}
  def disable_search(package_name, opts \\ []) do
    delete_index? = Keyword.get(opts, :delete_index, false)
    notify? = Keyword.get(opts, :notify, false)
    params = %{package: package_name, delete_index: delete_index?, notify: notify?}

    audited(:disable_search, params, opts, fn ->
      with {:ok, package} <- find_package("hexpm", package_name) do
        {:ok, _} =
          Repo.transaction(fn ->
            Packages.set_search_disabled(package, true)

            if delete_index? do
              for version <- docs_versions(package) do
                %{package: package.name, version: to_string(version)}
                |> Hexdocs.Workers.DeleteSearch.new()
                |> Oban.insert!()
              end
            end
          end)

        if notify?, do: notify_search_disabled(package, delete_index?)
        :ok
      end
    end)
  end

  @doc """
  Indexes a hexpm package's documentation for the search on hexdocs.pm
  again after `disable_search/2`.

  ## Options

  - `:reindex` - Queues every version with docs for indexing, below the
    publish jobs, which puts back what `disable_search/2` removed. Without it
    only versions published from now on are indexed. Defaults to `false`.

  ## Examples

      iex> AdminTasks.enable_search("noisy_pkg", reindex: true)
      :ok
  """
  @spec enable_search(String.t(), keyword()) :: :ok | {:error, atom()}
  def enable_search(package_name, opts \\ []) do
    reindex? = Keyword.get(opts, :reindex, false)

    audited(:enable_search, %{package: package_name, reindex: reindex?}, opts, fn ->
      with {:ok, package} <- find_package("hexpm", package_name) do
        {:ok, _} =
          Repo.transaction(fn ->
            Packages.set_search_disabled(package, false)

            if reindex? do
              for version <- docs_versions(package) do
                %{key: Hexdocs.Bucket.archive_key("hexpm", package.name, version)}
                |> Hexdocs.Workers.Search.new(priority: 9)
                |> Oban.insert!()
              end
            end
          end)

        :ok
      end
    end)
  end

  @doc """
  The hexpm packages `disable_search/2` took out of the search, and when.

  ## Examples

      iex> AdminTasks.search_disabled_packages()
      [%{name: "noisy_pkg", disabled_at: ~U[2026-10-13 12:00:00.000000Z]}]
  """
  @spec search_disabled_packages() :: [%{name: String.t(), disabled_at: DateTime.t()}]
  def search_disabled_packages() do
    from(p in Package,
      join: r in assoc(p, :repository),
      where: r.name == "hexpm" and not is_nil(p.search_disabled_at),
      order_by: p.name,
      select: %{name: p.name, disabled_at: p.search_disabled_at}
    )
    |> Repo.all()
  end

  defp docs_versions(package) do
    {versions, _retired_versions} = Releases.docs_versions("hexpm", package.name)
    versions
  end

  defp notify_search_disabled(package, removed?) do
    description = "owners of #{package.name}"

    case Emails.package_search_disabled(removal_recipients(package), package.name, removed?) do
      %{to: []} -> Logger.error("Disabled search but found no address for #{description}")
      email -> deliver(email, description)
    end
  end

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
    params =
      %{}
      |> maybe_put_param("level", Keyword.get(opts, :level))
      |> maybe_put_param("transfer", Keyword.get(opts, :transfer))

    audit_params = Map.merge(%{"package" => package_name, "user" => username_or_email}, params)

    audited(:add_owner, audit_params, opts, fn ->
      with {:ok, package} <- find_package("hexpm", package_name),
           {:ok, user} <- find_user(username_or_email) do
        package
        |> Repo.preload(repository: :organization)
        |> Owners.add(user, params, audit: AuditLogs.admin(), admin: true)
      end
    end)
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

      iex> AdminTasks.remove_owner("phoenix", "not_an_owner")
      {:error, :not_owner}

      iex> AdminTasks.remove_owner("phoenix", "nonexistent")
      {:error, :user_not_found}
  """
  @spec remove_owner(String.t(), String.t(), keyword()) :: :ok | {:error, atom()}
  def remove_owner(package_name, username_or_email, opts \\ []) do
    audited(:remove_owner, %{package: package_name, user: username_or_email}, opts, fn ->
      with {:ok, package} <- find_package("hexpm", package_name),
           {:ok, user} <- find_user(username_or_email) do
        Owners.remove(package, user, audit: AuditLogs.admin(), admin: true)
      end
    end)
  end

  @doc """
  Removes a member from an organization.

  ## Arguments

  - `organization_name` - The name of the organization
  - `username_or_email` - The username or email of the member to remove

  ## Examples

      iex> AdminTasks.remove_organization_member("acme", "jose")
      :ok

      iex> AdminTasks.remove_organization_member("acme", "nonexistent")
      {:error, :user_not_found}
  """
  @spec remove_organization_member(String.t(), String.t(), keyword()) :: :ok | {:error, atom()}
  def remove_organization_member(organization_name, username_or_email, opts \\ []) do
    params = %{organization: organization_name, user: username_or_email}

    audited(:remove_organization_member, params, opts, fn ->
      with {:ok, organization} <- find_organization(organization_name),
           {:ok, user} <- find_user(username_or_email) do
        if Organizations.get_role(organization, user) do
          Organizations.remove_member(organization, user, audit: AuditLogs.admin())
        else
          {:error, :member_not_found}
        end
      end
    end)
  end

  @doc """
  Renames an organization.

  This updates the organization name, its associated user's username, and all
  key permissions that reference the organization.

  The old name is reserved. Stored objects keep the `repos/<old name>/` prefix
  they were written under, so letting another organization take the name would
  point its prefix at them, and `delete_organization/2` would then delete one
  organization's objects for another.

  ## Arguments

  - `old_name` - The current organization name
  - `new_name` - The new organization name, refused if it is reserved

  ## Examples

      iex> AdminTasks.rename_organization("old_org", "new_org")
      :ok

      iex> AdminTasks.rename_organization("old_org", "deleted_org")
      {:error, :name_reserved}
  """
  @spec rename_organization(String.t(), String.t(), keyword()) :: :ok | {:error, atom()}
  def rename_organization(old_name, new_name, opts \\ []) do
    audited(:rename_organization, %{old_name: old_name, new_name: new_name}, opts, fn ->
      do_rename_organization(old_name, new_name)
    end)
  end

  defp do_rename_organization(old_name, new_name) do
    with {:ok, organization} <- find_organization(old_name),
         :ok <- check_name_available(new_name) do
      user_changeset = Ecto.Changeset.change(organization.user, username: new_name)

      changeset =
        organization
        |> Ecto.Changeset.change(name: new_name)
        |> Ecto.Changeset.put_assoc(:user, user_changeset)

      Repo.transaction(fn ->
        Repo.update!(changeset)
        Repo.insert!(%ReservedUsername{name: old_name}, on_conflict: :nothing)

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

            Repo.update!(key_changeset)
          end
        end)
      end)

      :ok
    end
  end

  @live_billing_statuses ~w(active trialing past_due)

  @doc """
  Deletes an organization.

  Removes the organization together with its repository and every package and
  release in it, its members, keys and audit logs, and reserves the name so it
  cannot be taken again, as an organization or as a username.

  A billing subscription is cancelled first, the way the dashboard's cancel
  does it: a started one at the end of its period, a trialing or unpaid one at
  once. The billing service refusing or being unreachable raises, and at that
  point nothing has been deleted.

  ## Arguments

  - `name` - The name of the organization
  - `opts` - Options:
    - `:unless_billing_live` - When `true`, a subscription that is active,
      trialing or past due refuses the deletion with
      `{:error, {:billing_live, status}}` instead of being cancelled
      (default: `false`)
    - `:delete_data` - When `true`, also deletes the organization's stored
      objects, `repos/<name>/` in the repository, preview and diff buckets,
      the uploads kept under `debug/` in the repository bucket and `<name>/`
      in the private docs bucket, purges the CDN keys they were served under
      and records the deletion for the nightly backup, which removes the
      organization from every snapshot 35 days later (default: `false`). This
      runs in `Hexpm.Accounts.OrganizationDataWorker`, a job inserted with
      the deletion, which retries until it is through and posts the number of
      objects it deleted to Slack.

  ## Examples

      iex> AdminTasks.delete_organization("acme")
      :ok

      iex> AdminTasks.delete_organization("acme", delete_data: true)
      :ok
  """
  @spec delete_organization(String.t(), keyword()) :: :ok | {:error, term()}
  def delete_organization(name, opts \\ []) do
    delete_data? = Keyword.get(opts, :delete_data, false)
    unless_billing_live? = Keyword.get(opts, :unless_billing_live, false)

    params = %{
      organization: name,
      delete_data: delete_data?,
      unless_billing_live: unless_billing_live?
    }

    audited(:delete_organization, params, opts, fn ->
      with {:ok, organization} <- find_organization(name),
           :ok <- cancel_billing(organization, unless_billing_live?) do
        # Read while the rows are still there, the CDN keys are built from them.
        jobs = if delete_data?, do: [organization_data_job(organization)], else: []

        Organizations.delete(organization, audit: AuditLogs.admin(), jobs: jobs)
      end
    end)
  end

  # Before any row goes. A failure here raises with the organization as it
  # was, and a database failure after it leaves a period-end cancellation the
  # dashboard's resume button undoes. Not gated on billing_active, which is
  # false for a trialing subscription that Stripe would go on to charge.
  #
  # With `unless_billing_live?` a subscription that is paying or about to
  # pay refuses the deletion instead, decided on the same lookup the
  # cancellation would follow.
  defp cancel_billing(organization, unless_billing_live?) do
    case Hexpm.Billing.get(organization.name) do
      nil ->
        :ok

      %{"subscription" => %{"status" => status}}
      when unless_billing_live? and status in @live_billing_statuses ->
        {:error, {:billing_live, status}}

      _customer ->
        Hexpm.Billing.cancel(organization.name)
        :ok
    end
  end

  @doc """
  Deletes an organization's data and keeps the organization.

  Removes every package and release in the organization's repository and its
  policies, then its stored objects the way `delete_organization/2` does with
  `delete_data: true`: `repos/<name>/` in the repository, preview and diff
  buckets, the uploads kept under `debug/` in the repository bucket and
  `<name>/` in the private docs bucket, the CDN keys they were served under,
  and every backup snapshot 35 days later. The organization, its repository,
  members, keys, audit logs and billing customer stay, and its members can
  publish again once billing is back.

  A billing subscription that is active, trialing or past due refuses the
  deletion with `{:error, {:billing_live, status}}`; billing is otherwise left
  as it is.

  ## Examples

      iex> AdminTasks.delete_organization_data("acme")
      :ok
  """
  @spec delete_organization_data(String.t(), keyword()) :: :ok | {:error, term()}
  def delete_organization_data(name, opts \\ []) do
    audited(:delete_organization_data, %{organization: name}, opts, fn ->
      with {:ok, organization} <- find_organization(name),
           :ok <- refuse_live_billing(organization) do
        # Read while the rows are still there, the CDN keys are built from them.
        # The store's times have whole seconds, and a package published from
        # here on keeps its objects.
        written_before = DateTime.utc_now() |> DateTime.truncate(:second)
        job = organization_data_job(organization, written_before: written_before)
        Organizations.delete_data(organization, audit: AuditLogs.admin(), jobs: [job])
      end
    end)
  end

  @doc """
  Whether a subscription in this billing status refuses
  `delete_organization_data/2`, and `delete_organization/2` with
  `unless_billing_live: true`.
  """
  @spec billing_live?(String.t() | nil) :: boolean()
  def billing_live?(status), do: status in @live_billing_statuses

  defp refuse_live_billing(organization) do
    case Hexpm.Billing.get(organization.name) do
      %{"subscription" => %{"status" => status}} when status in @live_billing_statuses ->
        {:error, {:billing_live, status}}

      _customer ->
        :ok
    end
  end

  defp organization_data_job(organization, opts \\ []) do
    organization = Repo.preload(organization, [:repository, :policies])

    packages =
      case organization.repository do
        nil ->
          []

        repository ->
          from(p in Package,
            where: p.repository_id == ^repository.id,
            left_join: r in assoc(p, :releases),
            select: {p.name, r.version}
          )
          |> Repo.all()
      end

    # A renamed organization's objects stay under its repository's name.
    names = [
      organization.name | List.wrap(organization.repository && organization.repository.name)
    ]

    policies = Enum.map(organization.policies, & &1.name)
    Hexpm.Accounts.OrganizationDataWorker.new_job(names, packages, policies, opts)
  end

  @doc """
  Reports objects in the buckets that no repository, package, release or
  policy accounts for, without deleting anything.

  Takes `:buckets`, `:prefix`, `:older_than` and `:limit`, see
  `Hexpm.OrphanedObjects.scan/1`.

  ## Examples

      iex> AdminTasks.orphaned_objects()
      %{diff_bucket: %{scanned: 812, orphaned: 40, unrecognised: 0, ...}, ...}

      iex> AdminTasks.orphaned_objects(buckets: [:docs_bucket], prefix: "phoenix/")
      %{docs_bucket: %{scanned: 1204, orphaned: 0, ...}}
  """
  @spec orphaned_objects(keyword()) :: %{atom() => map()}
  defdelegate orphaned_objects(opts \\ []), to: Hexpm.OrphanedObjects, as: :scan

  @doc """
  Deletes what `orphaned_objects/1` reports, and returns the same report with
  the number deleted per bucket.

  Objects written in the last `:older_than` days are left alone, and every
  candidate is checked against a second read of the packages before it goes,
  so a release published while the bucket was being listed keeps its objects.
  Run `orphaned_objects/1` first and read `unrecognised_sample`: those keys
  are never deleted, and a shape appearing there means this needs teaching
  about it.

  ## Examples

      iex> AdminTasks.delete_orphaned_objects(buckets: [:diff_bucket])
      %{diff_bucket: %{deleted: 40, orphaned: 40, ...}}

      iex> AdminTasks.delete_orphaned_objects(older_than: 30)
      %{repo_bucket: %{deleted: 0, ...}, ...}
  """
  @spec delete_orphaned_objects(keyword()) :: %{atom() => map()}
  def delete_orphaned_objects(opts \\ []) do
    {_audit, delete_opts} = Keyword.pop(opts, :audit)

    audited(:delete_orphaned_objects, Map.new(delete_opts), opts, fn ->
      Hexpm.OrphanedObjects.delete(delete_opts)
    end)
  end

  @doc """
  Initiates a security password reset for a user by sending a password reset email.

  This is used when an admin needs to force a user to reset their password for security reasons.
  The user will receive an email explaining their password was reset for security reasons.

  ## Options

  - `:disable_password` - Set to `true` to disable the user's current password,
    preventing login until the password reset is completed (default: `false`)
  - `:revoke_all_access` - Set to `true` to immediately revoke all API keys and
    sessions (default: `false`)

  ## Examples

      # Just send reset email
      iex> AdminTasks.security_password_reset("bob")
      :ok

      # Disable password and revoke all access
      iex> AdminTasks.security_password_reset("bob", disable_password: true, revoke_all_access: true)
      :ok

      iex> AdminTasks.security_password_reset("nonexistent")
      {:error, :user_not_found}

      iex> AdminTasks.security_password_reset("org_username")
      {:error, :organization_user}
  """
  @spec security_password_reset(String.t(), keyword()) :: :ok | {:error, atom()}
  def security_password_reset(username_or_email, opts \\ []) do
    disable_password = Keyword.get(opts, :disable_password, false)
    revoke_all_access = Keyword.get(opts, :revoke_all_access, false)

    params = %{
      user: username_or_email,
      disable_password: disable_password,
      revoke_all_access: revoke_all_access
    }

    audited(:security_password_reset, params, opts, fn ->
      reset_password_for_security(username_or_email, disable_password, revoke_all_access)
    end)
  end

  defp reset_password_for_security(username_or_email, disable_password, revoke_all_access) do
    with {:ok, user} <- find_user(username_or_email),
         :ok <- check_not_organization(user) do
      Repo.transaction(fn ->
        # Disable password if requested
        if disable_password do
          user
          |> Ecto.Changeset.change(password: nil)
          |> Repo.update!()
        end

        # Revoke all keys and sessions if requested
        if revoke_all_access do
          {session_query, token_query, org_session_query} = Hexpm.UserSessions.revoke_all(user)
          Repo.update_all(session_query, [])
          Repo.update_all(token_query, [])
          Repo.update_all(org_session_query, [])
          Repo.update_all(Key.revoke_all(user), [])
        end

        # Create password reset record
        changeset = PasswordReset.changeset(Ecto.build_assoc(user, :password_resets), user)
        reset = Repo.insert!(changeset)

        # Send security password reset email
        Emails.security_password_reset(user, reset)
        |> Mailer.deliver!()
      end)

      :ok
    end
  end

  defp check_not_organization(user) do
    if User.organization?(user) do
      {:error, :organization_user}
    else
      :ok
    end
  end

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
    params = %{hex_version: hex_version, elixir_versions: elixir_versions}

    audited(:add_install, params, [], fn ->
      upload_installs(hex_version, elixir_versions)
    end)
  end

  defp upload_installs(hex_version, elixir_versions) do
    if hex_version do
      Install.build(hex_version, elixir_versions)
      |> Repo.insert!()
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

    {:ok, _} = Hexpm.Store.put(:repo_bucket, "installs/list.csv", csv, store_opts)
    Hexpm.CDN.purge(:fastly_hexrepo, "installs")

    :ok
  end

  @doc """
  Retries discarded Oban jobs at priority 8, optionally filtered by worker.

  ## Options

  - `:worker` - Only retry discarded jobs for this worker
  - `:uniq` - Retry only one job per worker and args (default: `false`)

  ## Examples

      iex> AdminTasks.retry_oban_jobs()
      {:ok, 12}

      iex> AdminTasks.retry_oban_jobs(worker: "Hexpm.Diff.Worker", uniq: true)
      {:ok, 3}
  """
  @spec retry_oban_jobs(keyword()) :: {:ok, non_neg_integer()}
  def retry_oban_jobs(opts \\ []) do
    params = %{worker: opts[:worker], uniq: Keyword.get(opts, :uniq, false)}
    audited(:retry_oban_jobs, params, opts, fn -> retry_discarded_jobs(opts) end)
  end

  defp retry_discarded_jobs(opts) do
    query = from(j in Oban.Job, where: j.state == "discarded")

    query =
      if worker = opts[:worker] do
        from(j in query, where: j.worker == ^worker)
      else
        query
      end

    Repo.update_all(query, set: [priority: 8])

    query =
      if opts[:uniq] do
        from(j in query, distinct: [j.worker, j.args])
      else
        query
      end

    Oban.retry_all_jobs(query)
  end

  @doc """
  Backfills `release_doc_files` for releases published before it existed.
  Runs in batches on the `:heavy` queue behind Preview uploads. Safe to start
  again: it only fills releases still missing a row.

  ## Examples

      iex> AdminTasks.backfill_doc_files()
      {:ok, %Oban.Job{}}
  """
  def backfill_doc_files(opts \\ []) do
    audited(:backfill_doc_files, %{}, opts, fn ->
      %{after_id: 0}
      |> Hexpm.Preview.Workers.BackfillDocFiles.new()
      |> Oban.insert()
    end)
  end

  @doc """
  Sends an email with an arbitrary subject and body.

  Every recipient gets a separate email so addresses are not disclosed between
  recipients. Duplicate addresses are only queued once, and so is an address
  that already has an announcement with this subject queued or delivered within
  the last 90 days, so a send that was interrupted can be run again with the
  full recipient list. The send holds a lock on the subject while it reads and
  queues, so two consoles running the same announcement cannot both queue it.
  The emails go into the outbox and are delivered by Oban, so a send survives
  the console it was started from and a failed delivery is retried.
  Announcements are queued at a lower priority than transactional mail, so a
  large send does not delay those. The returned count is the number queued, not
  the number delivered.

  Addresses that fail to render are logged and do not stop the rest.

  The entries share the group key `"admin.announcement:" <> subject`, so an
  announcement that has not gone out yet can be cancelled:

      iex> Hexpm.Emails.Outbox.cancel!(
      ...>   group_key: "admin.announcement:Hex.pm - Service update",
      ...>   categories: ["admin.announcement"]
      ...> )
      18392

  ## Arguments

  - `recipients` - Email addresses to send to, see `Hexpm.Accounts.Users.all_notifiable_emails/0`
    and `Hexpm.Accounts.Organizations.all_admin_notifiable_emails/1`
  - `subject` - Subject line, a leading `"Hex.pm - "` is dropped from the heading
  - `body` - Plain text body, blank lines separate paragraphs, single newlines
    are kept as line breaks and bare URLs become links in the HTML part

  ## Examples

      iex> AdminTasks.send_email(["bob@example.com"], "Hex.pm - Service update", "We are ...")
      {:ok, 1}
  """
  @spec send_email([String.t()], String.t(), String.t(), keyword()) :: {:ok, non_neg_integer()}
  def send_email(recipients, subject, body, opts \\ []) do
    recipient_count = recipients |> List.wrap() |> Enum.uniq() |> length()
    params = %{recipients: recipient_count, subject: subject, body: body}
    audited(:send_email, params, opts, fn -> queue_announcement(recipients, subject, body) end)
  end

  defp queue_announcement(recipients, subject, body) do
    group_key = announcement_group_key(subject)

    Repo.transaction(
      fn ->
        OutboxLock.acquire!(group_key)
        already_queued = announcement_recipients(subject)

        {skipped, pending} =
          recipients
          |> List.wrap()
          |> Enum.uniq()
          |> Enum.split_with(&MapSet.member?(already_queued, &1))

        if skipped != [] do
          Logger.info("Skipped #{length(skipped)} recipients already sent #{inspect(subject)}")
        end

        pending
        |> Enum.flat_map(&prepare_announcement(&1, subject, body, group_key))
        |> Outbox.insert_all!()
      end,
      timeout: :infinity
    )
  end

  defp announcement_group_key(subject), do: "#{@announcement_category}:#{subject}"

  defp announcement_recipients(subject) do
    from(entry in OutboxEntry,
      where: entry.category == ^@announcement_category,
      where: entry.subject == ^subject,
      select: entry.recipients
    )
    |> Repo.all()
    |> List.flatten()
    |> MapSet.new()
  end

  # Rendering is the part that can fail per recipient, and it is kept apart
  # from the inserts so a failure leaves the transaction usable.
  defp prepare_announcement(recipient, subject, body, group_key) do
    [
      Outbox.prepare!(Emails.announcement(recipient, subject, body),
        category: @announcement_category,
        group_key: group_key,
        priority: @announcement_priority,
        expires_at: Outbox.default_expires_at()
      )
    ]
  rescue
    error ->
      Logger.error("Could not queue email to #{recipient}: #{inspect(error.__struct__)}")
      []
  end

  defp deliver(email, description) do
    case Mailer.deliver(email) do
      {:ok, _} ->
        true

      {:error, reason} ->
        Logger.error("Could not send email to #{description}: #{inspect(reason)}")
        false
    end
  end
end
