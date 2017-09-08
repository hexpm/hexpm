defmodule Hexpm.Web.PackageView do
  use Hexpm.Web, :view

  def show_sort_info(nil), do: "(Sorted by name)"
  def show_sort_info(:name), do: "(Sorted by name)"
  def show_sort_info(:inserted_at), do: "(Sorted by recently created)"
  def show_sort_info(:updated_at), do: "(Sorted by recently updated)"
  def show_sort_info(:total_downloads), do: "(Sorted by total downloads)"
  def show_sort_info(:recent_downloads), do: "(Sorted by recent downloads)"
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
        "total downloads: #{human_number_space(downloads)}"
      _ ->
        downloads = display_downloads(package_downloads, :recent_downloads) || 0
        "recent downloads: #{human_number_space(downloads)}"
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
    app_name = release.meta.app || package.name
    organization = snippet_organization(package.repository.name)

    if package.name == app_name do
      "{:#{package.name}, \"#{version}\"#{organization}}"
    else
      "{#{app_name(:mix, app_name)}, \"#{version}\", hex: :#{package.name}#{organization}}"
    end
  end

  def dep_snippet(:rebar, package, release) do
    version = snippet_version(:rebar, release.version)
    app_name = release.meta.app || package.name

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
  defp snippet_organization(repository), do: ", organization: #{inspect repository}"

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
      ":#{inspect name}"
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
    [ReleaseRetirement.reason_text(retirement.reason)] ++
      if(retirement.message, do: [": ", retirement.message], else: [])
  end

  def retirement_html(retirement) do
    [content_tag(:strong, ReleaseRetirement.reason_text(retirement.reason))] ++
      if(retirement.message, do: [": ", retirement.message], else: [])
  end
end
