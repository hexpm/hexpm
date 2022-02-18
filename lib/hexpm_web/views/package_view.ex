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
      inspect(String.to_charlist(name))
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
      Routes.package_path(Endpoint, :audit_logs, package, options)
    else
      Routes.package_path(Endpoint, :audit_logs, package.repository, package, options)
    end
  end

  @doc """
  This function turns an audit_log struct into a short description.

  Please check Hexpm.Accounts.AuditLog.extract_params/2 to see all the
  package related actions and their params structures.
  """
  def humanize_audit_log_info(%{action: "docs.publish"} = audit_log) do
    if release_version = audit_log.params["release"]["version"] do
      "Publish documentation for release #{release_version}"
    else
      "Publish documentation"
    end
  end

  def humanize_audit_log_info(%{action: "docs.revert"} = audit_log) do
    if release_version = audit_log.params["release"]["version"] do
      "Revert documentation for release #{release_version}"
    else
      "Revert documentation"
    end
  end

  def humanize_audit_log_info(%{action: "owner.add"} = audit_log) do
    username = audit_log.params["user"]["username"]
    level = audit_log.params["level"]

    if username && level do
      "Add #{username} as a level #{level} owner"
    else
      "Add owner"
    end
  end

  def humanize_audit_log_info(%{action: "owner.transfer"} = audit_log) do
    if username = audit_log.params["user"]["username"] do
      "Transfer owner to #{username}"
    else
      "Transfer owner"
    end
  end

  def humanize_audit_log_info(%{action: "owner.remove"} = audit_log) do
    username = audit_log.params["user"]["username"]
    level = audit_log.params["level"]

    if username && level do
      "Remove level #{level} owner #{username}"
    else
      "Remove owner"
    end
  end

  def humanize_audit_log_info(%{action: "release.publish"} = audit_log) do
    if version = audit_log.params["release"]["version"] do
      "Publish release #{version}"
    else
      "Publish release"
    end
  end

  def humanize_audit_log_info(%{action: "release.revert"} = audit_log) do
    if version = audit_log.params["release"]["version"] do
      "Revert release #{version}"
    else
      "Revert release"
    end
  end

  def humanize_audit_log_info(%{action: "release.retire"} = audit_log) do
    if version = audit_log.params["release"]["version"] do
      "Retire release #{version}"
    else
      "Retire release"
    end
  end

  def humanize_audit_log_info(%{action: "release.unretire"} = audit_log) do
    if version = audit_log.params["release"]["version"] do
      "Unretire release #{version}"
    else
      "Unretire release"
    end
  end
end
