defmodule HexpmWeb.Dashboard.AdminView do
  use HexpmWeb, :view

  import HexpmWeb.Components.Buttons, only: [button: 1]
  import HexpmWeb.Components.Form, only: [sudo_form: 1]
  import HexpmWeb.Components.Input, only: [select_input: 1, text_input: 1]
  import HexpmWeb.Components.Table, only: [table: 1]
  import HexpmWeb.ViewHelpers, only: [pretty_datetime: 1]
  import HexpmWeb.ViewIcons, only: [icon: 3]
  import HexpmWeb.Dashboard.Admin.Components.TaskField, only: [task_field: 1]
  import HexpmWeb.Dashboard.Admin.Components.Lookup

  alias Hexpm.AdminTasks

  @doc """
  The tasks in `Hexpm.AdminTasks` the dashboard runs, grouped by what they
  act on. `HexpmWeb.Dashboard.AdminController` reads each task's fields from
  `args[<name>]`.

  Each task has its own page, and a task with `:list` shows that list above
  its form. A `danger: true` task shows what it is about to act on and runs
  once that is confirmed, see `HexpmWeb.Dashboard.AdminController`.

  A section with `:lookup` holds tasks on a user, package or organization.
  Those are linked from its look up page, see `lookup_tasks/2`, and the task
  list shows only the sections without one.
  """
  def sections() do
    [
      %{
        id: "users",
        title: "Users",
        lookup: :user,
        tasks: [
          task(
            "reset_tfa",
            "Reset two-factor authentication",
            "Turns off two-factor authentication for the account.",
            fields: [text_field("user", "Username or email")]
          ),
          task(
            "security_password_reset",
            "Security password reset",
            "Emails the user a password reset link that says the password was reset for security reasons.",
            fields: [
              text_field("user", "Username or email"),
              checkbox_field(
                "disable_password",
                "Disable the current password until it is reset"
              ),
              checkbox_field("revoke_all_access", "Revoke every API key and session")
            ]
          ),
          task(
            "change_password",
            "Change password",
            "Sets a new password without asking for the old one.",
            fields: [
              text_field("user", "Username or email"),
              text_field("password", "New password", type: "password")
            ]
          ),
          task("rename_user", "Rename user", "Refused when the new name is reserved.",
            fields: [
              text_field("old_name", "Current username"),
              text_field("new_name", "New username")
            ]
          ),
          task(
            "remove_user",
            "Remove user",
            "Deletes the account. With a reason, the user's verified addresses are told why.",
            danger: true,
            fields: [
              text_field("user", "Username or email"),
              checkbox_field(
                "delete_packages",
                "Also delete the packages the user is the only owner of"
              ),
              reason_field(:user)
            ]
          )
        ]
      },
      %{
        id: "email-domains",
        title: "Email domains",
        lookup: nil,
        tasks: [
          task(
            "block_email_domain",
            "Block email domain",
            "New addresses on the domain and its subdomains are refused. Existing addresses stay.",
            list: :blocked_email_domains,
            fields: [
              text_field("domain", "Domain"),
              text_field("comment", "Comment", required: false)
            ]
          ),
          task(
            "unblock_email_domain",
            "Unblock email domain",
            "New addresses on the domain can be added again.",
            list: :blocked_email_domains,
            fields: [text_field("domain", "Domain")]
          )
        ]
      },
      %{
        id: "packages",
        title: "Packages",
        lookup: :package,
        tasks: [
          task("add_owner", "Add owner", "Adds an owner to a hexpm package.",
            fields: [
              text_field("package", "Package"),
              text_field("user", "Username or email"),
              select_field("level", "Level", [
                {"Default", ""},
                {"Maintainer", "maintainer"},
                {"Full", "full"}
              ]),
              checkbox_field("transfer", "Transfer the package, removing the other owners")
            ]
          ),
          task("remove_owner", "Remove owner", "Removes an owner from a hexpm package.",
            fields: [text_field("package", "Package"), text_field("user", "Username or email")]
          ),
          task(
            "allow_republish",
            "Allow republish",
            "Resets the release's publish time so it can be published again.",
            fields: [
              text_field("package", "Package"),
              text_field("version", "Version"),
              text_field("organization", "Organization",
                required: false,
                placeholder: "Leave empty for hexpm"
              )
            ]
          ),
          task(
            "remove_release",
            "Remove release",
            "Deletes one release. With a reason, the owners are told why.",
            danger: true,
            fields: [
              text_field("repository", "Repository", value: "hexpm"),
              text_field("package", "Package"),
              text_field("version", "Version"),
              reason_field(:release)
            ]
          ),
          task(
            "remove_package",
            "Remove package",
            "Deletes the package and every release. With a reason, the owners are told why.",
            danger: true,
            fields: [
              text_field("repository", "Repository", value: "hexpm"),
              text_field("package", "Package"),
              reason_field(:package)
            ]
          )
        ]
      },
      %{
        id: "search",
        title: "HexDocs search",
        lookup: :package,
        tasks: [
          task(
            "disable_search",
            "Disable search",
            "Stops indexing the package's documentation for the search on hexdocs.pm.",
            list: :search_disabled_packages,
            fields: [
              text_field("package", "Package"),
              checkbox_field("delete_index", "Also remove the versions already in the index"),
              checkbox_field("notify", "Email the owners")
            ]
          ),
          task(
            "enable_search",
            "Enable search",
            "Indexes the package's documentation again from the next publish.",
            list: :search_disabled_packages,
            fields: [
              text_field("package", "Package"),
              checkbox_field("reindex", "Also index every version that has docs")
            ]
          )
        ]
      },
      %{
        id: "organizations",
        title: "Organizations",
        lookup: :organization,
        tasks: [
          task("remove_organization_member", "Remove member", nil,
            fields: [
              text_field("organization", "Organization"),
              text_field("user", "Username or email")
            ]
          ),
          task(
            "rename_organization",
            "Rename organization",
            "The old name is reserved, since stored objects keep the prefix they were written under.",
            fields: [text_field("old_name", "Current name"), text_field("new_name", "New name")]
          ),
          task(
            "delete_organization_data",
            "Delete organization data",
            "Deletes every package, release, policy and stored object and keeps the organization. Refused while billing is active, trialing or past due.",
            danger: true,
            fields: [text_field("organization", "Organization")]
          ),
          task(
            "delete_organization",
            "Delete organization",
            "Cancels billing, then deletes the organization, its repository, packages, members, keys and audit logs, and reserves the name.",
            danger: true,
            fields: [
              text_field("organization", "Organization"),
              checkbox_field("delete_data", "Also delete its stored objects and backups"),
              checkbox_field(
                "unless_billing_live",
                "Refuse if billing is active, trialing or past due instead of cancelling it"
              )
            ]
          )
        ]
      },
      %{
        id: "maintenance",
        title: "Maintenance",
        lookup: nil,
        tasks: [
          task(
            "retry_oban_jobs",
            "Retry discarded jobs",
            "Retries discarded Oban jobs at priority 8.",
            fields: [
              text_field("worker", "Worker", required: false, placeholder: "Hexpm.Diff.Worker"),
              checkbox_field("uniq", "Retry one job per worker and arguments")
            ]
          ),
          task(
            "backfill_doc_files",
            "Backfill doc files",
            "Queues the job that fills release_doc_files for releases published before it existed.",
            fields: []
          )
        ]
      }
    ]
  end

  def listed_sections(), do: Enum.filter(sections(), &is_nil(&1.lookup))

  def find_task(id) do
    Enum.find_value(sections(), fn section -> Enum.find(section.tasks, &(&1.id == id)) end)
  end

  defp task(id, title, description, opts) do
    %{
      id: id,
      title: title,
      description: description,
      fields: Keyword.fetch!(opts, :fields),
      danger: Keyword.get(opts, :danger, false),
      list: Keyword.get(opts, :list)
    }
  end

  defp text_field(name, label, opts \\ []) do
    %{
      kind: :text,
      name: name,
      label: label,
      type: Keyword.get(opts, :type, "text"),
      required: Keyword.get(opts, :required, true),
      placeholder: Keyword.get(opts, :placeholder, ""),
      value: Keyword.get(opts, :value)
    }
  end

  defp checkbox_field(name, label), do: %{kind: :checkbox, name: name, label: label}

  defp select_field(name, label, options),
    do: %{kind: :select, name: name, label: label, options: options}

  defp reason_field(scope), do: %{kind: :reason, scope: scope}

  def lookup_title(:user, lookup), do: "User #{lookup.user.username}"

  def lookup_title(:package, %{package: package}) do
    case package.repository.name do
      "hexpm" -> "Package #{package.name}"
      repository -> "Package #{repository}/#{package.name}"
    end
  end

  def lookup_title(:organization, lookup), do: "Organization #{lookup.organization.name}"

  @doc """
  The tasks a lookup page links to, with the target's name filled in.
  """
  def lookup_tasks(:user, %{user: user}) do
    [
      {"reset_tfa", %{"user" => user.username}},
      {"security_password_reset", %{"user" => user.username}},
      {"change_password", %{"user" => user.username}},
      {"rename_user", %{"old_name" => user.username}},
      {"remove_user", %{"user" => user.username}}
    ]
    |> with_tasks()
  end

  def lookup_tasks(:package, %{package: package}) do
    repository = package.repository.name
    hexpm? = repository == "hexpm"
    organization = if hexpm?, do: %{}, else: %{"organization" => repository}

    [
      hexpm? && {"add_owner", %{"package" => package.name}},
      hexpm? && {"remove_owner", %{"package" => package.name}},
      {"allow_republish", Map.put(organization, "package", package.name)},
      {"remove_release", %{"repository" => repository, "package" => package.name}},
      {"remove_package", %{"repository" => repository, "package" => package.name}},
      hexpm? && is_nil(package.search_disabled_at) &&
        {"disable_search", %{"package" => package.name}},
      hexpm? && package.search_disabled_at && {"enable_search", %{"package" => package.name}}
    ]
    |> Enum.filter(& &1)
    |> with_tasks()
  end

  def lookup_tasks(:organization, %{organization: organization}) do
    [
      {"remove_organization_member", %{"organization" => organization.name}},
      {"rename_organization", %{"old_name" => organization.name}},
      {"delete_organization_data", %{"organization" => organization.name}},
      {"delete_organization", %{"organization" => organization.name}}
    ]
    |> with_tasks()
  end

  defp with_tasks(links) do
    Enum.map(links, fn {id, prefill} -> {find_task(id), prefill} end)
  end

  def task_path(task, prefill) when prefill == %{}, do: ~p"/dashboard/admin/tasks/#{task.id}"
  def task_path(task, prefill), do: ~p"/dashboard/admin/tasks/#{task.id}?#{%{args: prefill}}"

  # Only the text fields take a prefill.
  def back_path(task, args) do
    names = for %{kind: :text, name: name} <- task.fields, do: name
    task_path(task, Map.new(for {key, value} <- args, key in names, do: {key, value}))
  end

  @doc """
  What a danger task is about to do, one sentence each, see
  `HexpmWeb.Dashboard.AdminController`.
  """
  def consequences("remove_user", %{lookup: lookup} = preview) do
    username = lookup.user.username
    sole = for package <- lookup.packages, package.owner_count == 1, do: package.name

    packages =
      cond do
        sole == [] -> nil
        preview.delete_packages -> "Deletes the packages only #{username} owns: #{names(sole)}."
        true -> "Leaves the packages only #{username} owns without an owner: #{names(sole)}."
      end

    # The notice goes to the primary address, and only once it is verified.
    primary = Enum.find(lookup.user.emails, &(&1.primary and &1.verified))

    email =
      cond do
        is_nil(preview.reason) -> "Sends no email."
        is_nil(primary) -> "Sends no email, #{username} has no verified primary address."
        true -> "Emails the reason to #{primary.email}."
      end

    Enum.filter(["Deletes the account #{username}.", packages, email], & &1)
  end

  def consequences("remove_release", %{lookup: lookup, release: release} = preview) do
    remaining = length(lookup.releases) - 1

    [
      "Deletes #{lookup.package.name} #{release.version}, published " <>
        "#{pretty_datetime(release.inserted_at)}. #{remaining} #{plural(remaining, "release")} remain.",
      owner_email(preview)
    ]
  end

  def consequences("remove_package", %{lookup: lookup} = preview) do
    count = length(lookup.releases)

    [
      "Deletes #{lookup.package.name} and its #{count} #{plural(count, "release")}.",
      owner_email(preview)
    ]
  end

  def consequences("delete_organization_data", %{lookup: lookup}) do
    count = length(lookup.packages)

    [
      "Deletes the #{count} #{plural(count, "package")} in #{lookup.organization.name}'s " <>
        "repository, its policies and stored objects. The organization, its members and " <>
        "billing stay.",
      billing(lookup, true)
    ]
  end

  def consequences("delete_organization", %{lookup: lookup} = preview) do
    count = length(lookup.packages)
    members = length(lookup.members)

    [
      "Deletes #{lookup.organization.name}, its #{count} #{plural(count, "package")}, " <>
        "#{members} #{plural(members, "membership")}, keys and audit logs, and reserves the name.",
      preview.delete_data && "Deletes its stored objects and backups.",
      billing(lookup, preview.unless_billing_live)
    ]
    |> Enum.filter(& &1)
  end

  defp owner_email(%{reason: nil}), do: "Sends no email."

  defp owner_email(%{lookup: %{owners: [], package: %{repository: %{id: 1}}}}),
    do: "Sends no email, the package has no owners."

  defp owner_email(%{lookup: %{owners: []}}),
    do: "Emails the reason to the organization's admins."

  defp owner_email(%{lookup: %{owners: owners}}),
    do: "Emails the reason to the owners: #{names(Enum.map(owners, & &1.username))}."

  defp billing(%{billing_status: status}, refuse_live?) do
    cond do
      is_nil(status) -> "Has no billing subscription."
      refuse_live? and AdminTasks.billing_live?(status) -> "Refused, billing is #{status}."
      refuse_live? -> "Billing is #{status}."
      true -> "Billing is #{status}, and the subscription is cancelled first."
    end
  end

  defp names(names), do: Enum.join(names, ", ")

  defp plural(1, word), do: word
  defp plural(_count, word), do: word <> "s"
end
