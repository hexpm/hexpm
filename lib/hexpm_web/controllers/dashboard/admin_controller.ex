defmodule HexpmWeb.Dashboard.AdminController do
  use HexpmWeb, :controller

  alias Hexpm.AdminTasks
  alias HexpmWeb.Dashboard.AdminView

  require Logger

  plug :requires_login
  plug :requires_mod
  plug :requires_tfa
  plug HexpmWeb.Plugs.Sudo when action in [:index, :lookup]

  plug HexpmWeb.Plugs.Sudo,
       [force: true]
       when action in [:show, :run, :audit_log, :user, :package, :organization]

  @per_page 50

  def index(conn, _params) do
    render(conn, "index.html",
      title: "Admin",
      container: "container page dashboard",
      sections: AdminView.sections()
    )
  end

  def show(conn, %{"task" => task_id} = params) do
    case AdminView.find_task(task_id) do
      nil ->
        not_found(conn)

      task ->
        prefill =
          for {key, value} when is_binary(value) <- args(params), into: %{}, do: {key, value}

        render(conn, "show.html",
          title: "Admin - #{task.title}",
          container: "container page dashboard",
          task: task,
          list: task_list(task.list),
          prefill: prefill
        )
    end
  end

  def lookup(conn, params) do
    name = String.trim(if is_binary(params["name"]), do: params["name"], else: "")

    case {params["kind"], String.split(name, "/")} do
      {_kind, [""]} ->
        conn
        |> put_flash(:error, "Enter a name to look up.")
        |> redirect(to: ~p"/dashboard/admin")

      {"package", [repository, package]} ->
        redirect(conn, to: ~p"/dashboard/admin/packages/#{repository}/#{package}")

      {"package", _name} ->
        redirect(conn, to: ~p"/dashboard/admin/packages/hexpm/#{name}")

      {"organization", _name} ->
        redirect(conn, to: ~p"/dashboard/admin/organizations/#{name}")

      {_user, _name} ->
        redirect(conn, to: ~p"/dashboard/admin/users/#{name}")
    end
  end

  def user(conn, %{"name" => name}) do
    case AdminTasks.lookup_user(name) do
      {:ok, lookup} ->
        names = [lookup.user.username | Enum.map(lookup.user.emails, & &1.email)]
        render_lookup(conn, lookup, {:user, names})

      {:error, reason} ->
        lookup_not_found(conn, reason)
    end
  end

  def package(conn, %{"repository" => repository, "name" => name}) do
    case AdminTasks.lookup_package(repository, name) do
      {:ok, lookup} ->
        target = {:package, {lookup.package.repository.name, lookup.package.name}}
        render_lookup(conn, lookup, target)

      {:error, reason} ->
        lookup_not_found(conn, reason)
    end
  end

  def organization(conn, %{"name" => name}) do
    case AdminTasks.lookup_organization(name) do
      {:ok, lookup} ->
        target = {:organization, lookup.organization.name}
        render_lookup(conn, lookup, target)

      {:error, reason} ->
        lookup_not_found(conn, reason)
    end
  end

  defp render_lookup(conn, lookup, {kind, target}) do
    render(conn, "lookup.html",
      title: "Admin - #{AdminView.lookup_title(kind, lookup)}",
      container: "container page dashboard",
      kind: kind,
      lookup: lookup,
      audit_logs: AdminTasks.target_audit_logs(kind, target)
    )
  end

  defp lookup_not_found(conn, reason) do
    conn
    |> put_flash(:error, "Look up failed, #{inspect(reason)}.")
    |> redirect(to: ~p"/dashboard/admin")
  end

  def audit_log(conn, params) do
    page = Hexpm.Utils.safe_int(params["page"]) || 1

    render(conn, "audit_log.html",
      title: "Admin audit log",
      container: "container page dashboard",
      audit_logs: AdminTasks.audit_logs(page, @per_page),
      total_count: AdminTasks.count_audit_logs(),
      page: page,
      per_page: @per_page,
      path_fn: &~p"/dashboard/admin/audit-log?#{&1}"
    )
  end

  def run(conn, %{"task" => task_id} = params) do
    case AdminView.find_task(task_id) do
      nil -> not_found(conn)
      %{danger: true} = task -> confirm_task(conn, task, args(params), params)
      task -> run_task(conn, task, args(params))
    end
  end

  # A danger task first renders what it is about to act on, and runs once the
  # moderator posts that page back with the target's name typed in. The page
  # carries the task form's sudo token, since signing a new one here would let
  # each confirmation page extend the window the token gives.
  defp confirm_task(conn, task, args, params) do
    case preview(task.id, args) do
      {:ok, preview} ->
        case {params["confirm"], preview.name} do
          {typed, name} when is_binary(typed) and (is_nil(name) or typed == name) ->
            run_task(conn, task, args)

          {typed, _name} ->
            render_confirm(conn, task, args, params, preview: preview, mismatch: is_binary(typed))
        end

      {:error, reason} ->
        render_confirm(conn, task, args, params, error: reason)
    end
  end

  defp render_confirm(conn, task, args, params, opts) do
    sudo_token = if is_binary(params["_sudo_token"]), do: params["_sudo_token"]

    render(conn, "confirm.html",
      title: "Admin - #{task.title}",
      container: "container page dashboard",
      task: task,
      args: for({key, value} when is_binary(value) <- args, do: {key, value}),
      sudo_token: sudo_token,
      preview: opts[:preview],
      mismatch: opts[:mismatch] || false,
      error: opts[:error]
    )
  end

  # The target the task is about to act on and the name to type to confirm,
  # `nil` when there is no single target.
  defp preview("remove_user", args) do
    with {:ok, lookup} <- AdminTasks.lookup_user(arg(args, "user")) do
      {:ok,
       %{
         kind: :user,
         lookup: lookup,
         name: lookup.user.username,
         delete_packages: checked?(args, "delete_packages"),
         reason: reason_text(args, :user)
       }}
    end
  end

  defp preview("remove_release", args) do
    version = arg(args, "version")

    with {:ok, lookup} <- AdminTasks.lookup_package(arg(args, "repository"), arg(args, "package")),
         %{} = release <- Enum.find(lookup.releases, &(to_string(&1.version) == version)) do
      {:ok,
       %{
         kind: :package,
         lookup: lookup,
         name: lookup.package.name,
         release: release,
         reason: reason_text(args, :release)
       }}
    else
      nil -> {:error, :release_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp preview("remove_package", args) do
    with {:ok, lookup} <- AdminTasks.lookup_package(arg(args, "repository"), arg(args, "package")) do
      {:ok,
       %{
         kind: :package,
         lookup: lookup,
         name: lookup.package.name,
         reason: reason_text(args, :package)
       }}
    end
  end

  defp preview(task_id, args)
       when task_id in ["delete_organization", "delete_organization_data"] do
    with {:ok, lookup} <- AdminTasks.lookup_organization(arg(args, "organization")) do
      {:ok,
       %{
         kind: :organization,
         lookup: lookup,
         name: lookup.organization.name,
         delete_data: checked?(args, "delete_data"),
         unless_billing_live: checked?(args, "unless_billing_live")
       }}
    end
  end

  defp preview("send_email", args) do
    {:ok,
     %{
       kind: :email,
       name: nil,
       recipients: Enum.uniq(list(args, "recipients")),
       subject: arg(args, "subject"),
       body: arg(args, "body")
     }}
  end

  defp requires_mod(conn, _opts) do
    if User.has_role?(conn.assigns.current_user, "mod") do
      conn
    else
      conn
      |> not_found()
      |> halt()
    end
  end

  defp requires_tfa(conn, _opts) do
    if User.tfa_enabled?(conn.assigns.current_user) do
      conn
    else
      conn
      |> put_flash(:error, "Admin tasks require two-factor authentication.")
      |> redirect(to: ~p"/dashboard/security")
      |> halt()
    end
  end

  defp run_task(conn, task, args) do
    result =
      try do
        execute(task.id, args, audit: audit_data(conn))
      rescue
        exception ->
          Logger.error(Exception.format(:error, exception, __STACKTRACE__))
          {:raised, exception}
      end

    {kind, message} = describe_result(result)

    conn
    |> put_flash(kind, "#{task.title}: #{message}")
    |> redirect(to: ~p"/dashboard/admin")
  end

  defp task_list(nil), do: nil
  defp task_list(:blocked_email_domains), do: AdminTasks.blocked_email_domains()
  defp task_list(:search_disabled_packages), do: AdminTasks.search_disabled_packages()

  defp execute("reset_tfa", args, opts) do
    AdminTasks.reset_tfa(arg(args, "user"), opts)
  end

  defp execute("security_password_reset", args, opts) do
    AdminTasks.security_password_reset(
      arg(args, "user"),
      [
        disable_password: checked?(args, "disable_password"),
        revoke_all_access: checked?(args, "revoke_all_access")
      ] ++ opts
    )
  end

  defp execute("change_password", args, opts) do
    type = if args["type"] == "email", do: :email, else: :username
    password = if is_binary(args["password"]), do: args["password"], else: ""
    AdminTasks.change_password(type, arg(args, "user"), password, opts)
  end

  defp execute("rename_user", args, opts) do
    AdminTasks.rename_user(arg(args, "old_name"), arg(args, "new_name"), opts)
  end

  defp execute("remove_user", args, opts) do
    AdminTasks.remove_user(
      arg(args, "user"),
      [delete_packages: checked?(args, "delete_packages")] ++ reason(args, :user) ++ opts
    )
  end

  defp execute("block_email_domain", args, opts) do
    AdminTasks.block_email_domain(
      arg(args, "domain"),
      [comment: optional(args, "comment")] ++ opts
    )
  end

  defp execute("unblock_email_domain", args, opts) do
    AdminTasks.unblock_email_domain(arg(args, "domain"), opts)
  end

  defp execute("add_owner", args, opts) do
    AdminTasks.add_owner(
      arg(args, "package"),
      arg(args, "user"),
      [level: optional(args, "level"), transfer: checked?(args, "transfer") || nil] ++ opts
    )
  end

  defp execute("remove_owner", args, opts) do
    AdminTasks.remove_owner(arg(args, "package"), arg(args, "user"), opts)
  end

  defp execute("allow_republish", args, opts) do
    AdminTasks.allow_republish(
      arg(args, "package"),
      arg(args, "version"),
      [organization: optional(args, "organization")] ++ opts
    )
  end

  defp execute("remove_release", args, opts) do
    AdminTasks.remove_release(
      arg(args, "repository"),
      arg(args, "package"),
      arg(args, "version"),
      reason(args, :release) ++ opts
    )
  end

  defp execute("remove_package", args, opts) do
    AdminTasks.remove_package(
      arg(args, "repository"),
      arg(args, "package"),
      reason(args, :package) ++ opts
    )
  end

  defp execute("disable_search", args, opts) do
    AdminTasks.disable_search(
      arg(args, "package"),
      [delete_index: checked?(args, "delete_index"), notify: checked?(args, "notify")] ++ opts
    )
  end

  defp execute("enable_search", args, opts) do
    AdminTasks.enable_search(arg(args, "package"), [reindex: checked?(args, "reindex")] ++ opts)
  end

  defp execute("remove_organization_member", args, opts) do
    AdminTasks.remove_organization_member(arg(args, "organization"), arg(args, "user"), opts)
  end

  defp execute("rename_organization", args, opts) do
    AdminTasks.rename_organization(arg(args, "old_name"), arg(args, "new_name"), opts)
  end

  defp execute("delete_organization_data", args, opts) do
    AdminTasks.delete_organization_data(arg(args, "organization"), opts)
  end

  defp execute("delete_organization", args, opts) do
    AdminTasks.delete_organization(
      arg(args, "organization"),
      [
        delete_data: checked?(args, "delete_data"),
        unless_billing_live: checked?(args, "unless_billing_live")
      ] ++ opts
    )
  end

  defp execute("send_email", args, opts) do
    AdminTasks.send_email(
      list(args, "recipients"),
      arg(args, "subject"),
      arg(args, "body"),
      opts
    )
  end

  defp execute("retry_oban_jobs", args, opts) do
    AdminTasks.retry_oban_jobs(
      [worker: optional(args, "worker"), uniq: checked?(args, "uniq")] ++ opts
    )
  end

  defp execute("backfill_doc_files", _args, opts) do
    AdminTasks.backfill_doc_files(opts)
  end

  # The canned reasons are looked up by their string so a form value never
  # becomes an atom it does not already name. Custom text takes precedence.
  defp reason(args, scope) do
    id = arg(args, "reason")

    cond do
      custom = optional(args, "reason_text") ->
        [reason: custom]

      canned = Enum.find(Keyword.keys(AdminTasks.reasons(scope)), &(Atom.to_string(&1) == id)) ->
        [reason: canned]

      true ->
        []
    end
  end

  defp reason_text(args, scope) do
    case reason(args, scope) do
      [reason: id] when is_atom(id) -> Keyword.fetch!(AdminTasks.reasons(scope), id)
      [reason: text] -> text
      [] -> nil
    end
  end

  defp args(%{"args" => %{} = args}), do: args
  defp args(_params), do: %{}

  defp arg(args, key) do
    case args[key] do
      value when is_binary(value) -> String.trim(value)
      _other -> ""
    end
  end

  defp optional(args, key) do
    case arg(args, key) do
      "" -> nil
      value -> value
    end
  end

  defp checked?(args, key), do: args[key] == "true"

  defp list(args, key) do
    args
    |> arg(key)
    |> String.split(~r/[\s,]+/, trim: true)
  end

  defp describe_result(:ok), do: {:info, "done."}
  defp describe_result({:ok, count}) when is_integer(count), do: {:info, "done, #{count}."}
  defp describe_result({:ok, %Oban.Job{id: id}}), do: {:info, "done, job #{id} queued."}
  defp describe_result({:ok, _value}), do: {:info, "done."}

  defp describe_result({:error, %Ecto.Changeset{} = changeset}) do
    errors =
      Enum.map_join(translate_errors(changeset), ", ", fn {key, message} ->
        "#{key} #{message}"
      end)

    {:error, "failed, #{errors}."}
  end

  defp describe_result({:error, reason}), do: {:error, "failed, #{inspect(reason)}."}

  defp describe_result({:raised, exception}) do
    {:error, "raised #{inspect(exception.__struct__)}: #{Exception.message(exception)}"}
  end
end
