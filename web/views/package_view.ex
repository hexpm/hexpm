defmodule HexWeb.PackageView do
  use HexWeb.Web, :view

  def show_sort_info(nil), do: "(Sorted by name)"
  def show_sort_info("name"), do: "(Sorted by name)"
  def show_sort_info("inserted_at"), do: "(Sorted by recently created)"
  def show_sort_info("updated_at"), do: "(Sorted by recently updated)"
  def show_sort_info("downloads"), do: "(Sorted by downloads)"
  def show_sort_info(_param), do: nil

  @doc """
  Formats a package's release info into a build tools dependency snippet.
  """
  def dep_snippet(:mix, package_name, release) do
    version = snippet_version(:mix, release.version)
    app_name = release.meta.app || package_name

    if package_name == app_name do
      "{:#{package_name}, \"#{version}\"}"
    else
      "{#{app_name(:mix, app_name)}, \"#{version}\", hex: :#{package_name}}"
    end
  end

  def dep_snippet(:rebar, package_name, release) do
    version = snippet_version(:rebar, release.version)
    app_name = release.meta.app || package_name

    if package_name == app_name do
      "{#{package_name}, \"#{version}\"}"
    else
      "{#{app_name(:rebar, app_name)}, \"#{version}\", {pkg, #{package_name}}}"
    end
  end

  def dep_snippet(:erlang_mk, package_name, release) do
    version = snippet_version(:erlang_mk, release.version)
    "dep_#{package_name} = hex #{version}"
  end

  def snippet_version(:mix, %Version{major: 0, minor: minor, patch: patch, pre: []}),
    do: "~> 0.#{minor}.#{patch}"
  def snippet_version(:mix, %Version{major: major, minor: minor, pre: []}),
    do: "~> #{major}.#{minor}"
  def snippet_version(:mix, %Version{major: major, minor: minor, patch: patch, pre: pre}),
    do: "~> #{major}.#{minor}.#{patch}#{pre_snippet(pre)}"

  def snippet_version(other, %Version{major: major, minor: minor, patch: patch, pre: pre})
    when other in [:rebar, :erlang_mk],
    do: "#{major}.#{minor}.#{patch}#{pre_snippet(pre)}"

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
    if Regex.match?(@elixir_atom_chars, name),
      do: ":#{name}",
    else: ":#{inspect name}"
  end
  defp app_name(:rebar, name) do
    if Regex.match?(@erlang_atom_chars, name),
      do: name,
    else: inspect(String.to_charlist(name))
  end
end
