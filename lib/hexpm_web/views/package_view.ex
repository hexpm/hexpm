defmodule HexpmWeb.PackageView do
  use HexpmWeb, :view

  def show_sort_info(nil), do: show_sort_info(:name)
  def show_sort_info(:name), do: "Sort: Name"
  def show_sort_info(:inserted_at), do: "Sort: Recently created"
  def show_sort_info(:updated_at), do: "Sort: Recently updated"
  def show_sort_info(:total_downloads), do: "Sort: Total downloads"
  def show_sort_info(:recent_downloads), do: "Sort: Recent downloads"
  def show_sort_info(_param), do: nil

  def downloads_for_package(package, downloads) do
    Map.get(downloads, package.id, %{"all" => 0, "recent" => 0})
  end

  def display_downloads(package_downloads, view) do
    case view do
      :recent_downloads ->
        Map.get(package_downloads, "recent")

      _ ->
        Map.get(package_downloads, "all")
    end
  end

  def display_downloads_for_opposite_views(package_downloads, view) do
    case view do
      :recent_downloads ->
        downloads = display_downloads(package_downloads, :all) || 0
        "total downloads: #{ViewHelpers.human_number_space(downloads)}"

      _ ->
        downloads = display_downloads(package_downloads, :recent_downloads) || 0
        "recent downloads: #{ViewHelpers.human_number_space(downloads)}"
    end
  end

  def display_downloads_view_title(view) do
    case view do
      :recent_downloads -> "recent downloads"
      _ -> "total downloads"
    end
  end

  def dep_snippet(:mix, package, release) do
    version = snippet_version(:mix, release.version)
    app_name = (release.meta && release.meta.app) || package.name
    organization = snippet_organization(package.repository.name)

    if package.name == app_name do
      "{:#{package.name}, \"#{version}\"#{organization}}"
    else
      "{#{app_name(:mix, app_name)}, \"#{version}\", hex: :#{package.name}#{organization}}"
    end
  end

  def dep_snippet(:rebar, package, release) do
    version = snippet_version(:rebar, release.version)
    app_name = (release.meta && release.meta.app) || package.name

    if package.name == app_name do
      "{#{package.name}, \"#{version}\"}"
    else
      "{#{app_name(:rebar, app_name)}, \"#{version}\", {pkg, #{package.name}}}"
    end
  end

  def dep_snippet(:erlang_mk, package, release) do
    version = snippet_version(:erlang_mk, release.version)
    "dep_#{package.name} = hex #{version}"
  end

  def snippet_version(:mix, %Version{major: 0, minor: minor, patch: patch, pre: []}) do
    "~> 0.#{minor}.#{patch}"
  end

  def snippet_version(:mix, %Version{major: major, minor: minor, pre: []}) do
    "~> #{major}.#{minor}"
  end

  def snippet_version(:mix, %Version{major: major, minor: minor, patch: patch, pre: pre}) do
    "~> #{major}.#{minor}.#{patch}#{pre_snippet(pre)}"
  end

  def snippet_version(other, %Version{major: major, minor: minor, patch: patch, pre: pre})
      when other in [:rebar, :erlang_mk] do
    "#{major}.#{minor}.#{patch}#{pre_snippet(pre)}"
  end

  defp snippet_organization("hexpm"), do: ""
  defp snippet_organization(repository), do: ", organization: #{inspect(repository)}"

  defp pre_snippet([]), do: ""

  defp pre_snippet(pre) do
    "-" <>
      Enum.map_join(pre, ".", fn
        int when is_integer(int) -> Integer.to_string(int)
        string when is_binary(string) -> string
      end)
  end

  @elixir_atom_chars ~r"^[a-zA-Z_][a-zA-Z_0-9]*$"
  @erlang_atom_chars ~r"^[a-z][a-zA-Z_0-9]*$"

  defp app_name(:mix, name) do
    if Regex.match?(@elixir_atom_chars, name) do
      ":#{name}"
    else
      ":#{inspect(name)}"
    end
  end

  defp app_name(:rebar, name) do
    if Regex.match?(@erlang_atom_chars, name) do
      name
    else
      "'#{name}'"
    end
  end

  def retirement_message(retirement) do
    reason = ReleaseRetirement.reason_text(retirement.reason)

    head =
      case retirement.reason do
        "report" -> ["Marked package"]
        _ -> ["Retired package"]
      end

    body =
      cond do
        reason && retirement.message ->
          [": ", reason, " - ", retirement.message]

        reason ->
          [": ", reason]

        retirement.message ->
          [": ", retirement.message]

        true ->
          []
      end

    head ++ body
  end

  def retirement_html(retirement) do
    reason = ReleaseRetirement.reason_text(retirement.reason)

    msg_head =
      case retirement.reason do
        "report" -> [content_tag(:strong, "Marked package:")]
        _ -> [content_tag(:strong, "Retired package:")]
      end

    msg_body =
      cond do
        reason && retirement.message ->
          [" ", reason, " - ", retirement.message]

        reason ->
          [" ", reason]

        retirement.message ->
          [" ", retirement.message]

        true ->
          []
      end

    msg_head ++ msg_body
  end

  def path_for_audit_logs(package, options) do
    if package.repository.id == 1 do
      ~p"/packages/#{package}/audit-logs?#{options}"
    else
      ~p"/packages/#{package.repository}/#{package}/audit-logs?#{options}"
    end
  end

  @doc """
  This function turns an audit_log struct into a short description.

  Please check Hexpm.Accounts.AuditLog.extract_params/2 to see all the
  package related actions and their params structures.
  """
  @spec humanize_audit_log_info(map()) :: String.t()
  def humanize_audit_log_info(audit_log)

  def humanize_audit_log_info(%{action: action, params: params}) do
    case action do
      "docs.publish" ->
        do_action(:docs, "Publish documentation", get_version(params))

      "docs.revert" ->
        do_action(:docs, "Revert documentation", get_version(params))

      "owner.add" ->
        do_action(:owner_add, nil, params)

      "owner.transfer" ->
        do_action(:owner_transfer, nil, params)

      "owner.remove" ->
        do_action(:owner_remove, nil, params)

      "release.publish" ->
        do_action(:release, "Publish release", get_version(params))

      "release.revert" ->
        do_action(:release, "Revert release", get_version(params))

      "release.retire" ->
        do_action(:release, "Retire release", get_version(params))

      "release.unretire" ->
        do_action(:release, "Unretire release", get_version(params))

      _ ->
        "Action not recognized"
    end
  end

  defp do_action(:docs, base_message, nil), do: base_message

  defp do_action(:docs, base_message, release_version),
    do: "#{base_message} for release #{release_version}"

  defp do_action(:owner_add, _, %{"user" => %{"username" => username}, "level" => level})
       when not is_nil(username) and not is_nil(level),
       do: "Add #{username} as a level #{level} owner"

  defp do_action(:owner_add, _, _), do: "Add owner"

  defp do_action(:owner_transfer, _, %{"user" => %{"username" => username}})
       when not is_nil(username),
       do: "Transfer owner to #{username}"

  defp do_action(:owner_transfer, _, _), do: "Transfer owner"

  defp do_action(:owner_remove, _, %{"user" => %{"username" => username}, "level" => level})
       when not is_nil(username) and not is_nil(level),
       do: "Remove level #{level} owner #{username}"

  defp do_action(:owner_remove, _, _), do: "Remove owner"

  defp do_action(:release, base_message, nil), do: base_message

  defp do_action(:release, base_message, release_version),
    do: "#{base_message} #{release_version}"

  defp get_version(params), do: get_in(params, ["release", "version"])
end
