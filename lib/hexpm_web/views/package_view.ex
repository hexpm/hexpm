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

  @spec retirement_message(map()) :: [any()]
  def retirement_message(retirement)

  def retirement_message(%{reason: reason, message: message}) do
    reason_text = ReleaseRetirement.reason_text(reason)
    retirement_head(:message, reason) ++ retirement_body(:message, reason_text, message)
  end

  @spec retirement_html(map) :: [any()]
  def retirement_html(retirement)

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
