defmodule HexpmWeb.PackageView do
  use HexpmWeb, :view

  alias Hexpm.SecurityVulnerability.Disclosure

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

  def display_downloads(package_downloads, :recent_downloads),
    do: Map.get(package_downloads, "recent")

  def display_downloads(package_downloads, _view), do: Map.get(package_downloads, "all")

  def display_downloads_for_opposite_views(package_downloads, :recent_downloads) do
    downloads = display_downloads(package_downloads, :all) || 0
    "total downloads: #{ViewHelpers.human_number_space(downloads)}"
  end

  def display_downloads_for_opposite_views(package_downloads, _view) do
    downloads = display_downloads(package_downloads, :recent_downloads) || 0
    "recent downloads: #{ViewHelpers.human_number_space(downloads)}"
  end

  def display_downloads_view_title(:recent_downloads), do: "recent downloads"
  def display_downloads_view_title(_view), do: "total downloads"

  def dep_snippet(:mix, %{name: name, repository: repo}, release) do
    version = snippet_version(:mix, release.version)
    app_name = (release.meta && release.meta.app) || name
    organization = snippet_organization(repo.name)
    do_dep_snippet(:mix, {name, app_name}, version, organization)
  end

  def dep_snippet(:rebar, %{name: name}, release) do
    version = snippet_version(:rebar, release.version)
    app_name = (release.meta && release.meta.app) || name
    do_dep_snippet(:rebar, {name, app_name}, version)
  end

  def dep_snippet(:erlang_mk, package, release) do
    version = snippet_version(:erlang_mk, release.version)
    "dep_#{package.name} = hex #{version}"
  end

  defp do_dep_snippet(tool, name, version, organization \\ nil)

  defp do_dep_snippet(:mix, {name, app_name}, version, organization) when name == app_name,
    do: "{:#{name}, \"#{version}\"#{organization}}"

  defp do_dep_snippet(:mix, {name, app_name}, version, organization),
    do: "{#{app_name(:mix, app_name)}, \"#{version}\", hex: :#{name}#{organization}}"

  defp do_dep_snippet(:rebar, {name, app_name}, version, _organization) when name == app_name do
    "{#{name}, \"#{version}\"}"
  end

  defp do_dep_snippet(:rebar, {name, app_name}, version, _organization) do
    "{#{app_name(:rebar, app_name)}, \"#{version}\", {pkg, #{name}}}"
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

  defp pre_snippet([]) do
    ""
  end

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

  def retirement_message(%{reason: reason, message: message}) do
    reason_text = ReleaseRetirement.reason_text(reason)
    retirement_head(:message, reason) ++ retirement_body(:message, reason_text, message)
  end

  def retirement_html(%{reason: reason, message: message}) do
    reason_text = ReleaseRetirement.reason_text(reason)
    retirement_head(:html, reason) ++ retirement_body(:html, reason_text, message)
  end

  defp retirement_head(:message, "report"), do: ["Marked package"]
  defp retirement_head(:message, _reason), do: ["Retired package"]
  defp retirement_head(:html, "report"), do: [content_tag(:strong, "Marked package:")]
  defp retirement_head(:html, _reason), do: [content_tag(:strong, "Retired package:")]

  defp retirement_body(:message, nil, nil), do: []
  defp retirement_body(:message, reason_text, nil), do: [": ", reason_text]
  defp retirement_body(:message, nil, message), do: [": ", message]
  defp retirement_body(:message, reason, message), do: [": ", reason, " - ", message]
  defp retirement_body(:html, nil, nil), do: []
  defp retirement_body(:html, reason_text, nil), do: [" ", reason_text]
  defp retirement_body(:html, nil, message), do: [" ", message]
  defp retirement_body(:html, reason, message), do: [" ", reason, " - ", message]

  def path_for_audit_logs(package, options \\ %{})

  def path_for_audit_logs(%{repository: %{id: 1}} = package, options) do
    ~p"/packages/#{package}/audit-logs?#{options}"
  end

  def path_for_audit_logs(package, options) do
    ~p"/packages/#{package.repository}/#{package}/audit-logs?#{options}"
  end

  @doc """
  This function turns an audit_log struct into a short description.

  Please check Hexpm.Accounts.AuditLog.extract_params/2 to see all the
  package related actions and their params structures.
  """

  def humanize_audit_log_info(%{action: action, params: params}) do
    case action do
      "docs.publish" ->
        do_docs_action("Publish documentation", version_from_params(params))

      "docs.revert" ->
        do_docs_action("Revert documentation", version_from_params(params))

      "owner.add" ->
        do_owner_action(:add, params)

      "owner.transfer" ->
        do_owner_action(:transfer, params)

      "owner.remove" ->
        do_owner_action(:remove, params)

      "release.publish" ->
        do_release_action("Publish release", version_from_params(params))

      "release.revert" ->
        do_release_action("Revert release", version_from_params(params))

      "release.retire" ->
        do_release_action("Retire release", version_from_params(params))

      "release.unretire" ->
        do_release_action("Unretire release", version_from_params(params))

      _ ->
        "Action not recognized"
    end
  end

  defp do_docs_action(base_message, nil), do: base_message

  defp do_docs_action(base_message, release_version),
    do: "#{base_message} for release #{release_version}"

  defp do_owner_action(:add, %{"user" => %{"username" => username}, "level" => level})
       when not is_nil(username) and not is_nil(level),
       do: "Add #{username} as a level #{level} owner"

  defp do_owner_action(:add, _params), do: "Add owner"

  defp do_owner_action(:transfer, %{"user" => %{"username" => username}})
       when not is_nil(username),
       do: "Transfer owner to #{username}"

  defp do_owner_action(:transfer, _params), do: "Transfer owner"

  defp do_owner_action(:remove, %{"user" => %{"username" => username}, "level" => level})
       when not is_nil(username) and not is_nil(level),
       do: "Remove level #{level} owner #{username}"

  defp do_owner_action(:remove, _params), do: "Remove owner"

  defp do_release_action(base_message, nil), do: base_message

  defp do_release_action(base_message, release_version),
    do: "#{base_message} #{release_version}"

  defp version_from_params(params) when is_map(params), do: params["release"]["version"]
end
