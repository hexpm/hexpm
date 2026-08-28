defmodule HexpmWeb.Docs.Files do
  @moduledoc """
  Recognition table for conventional package documentation files.

  Maps documentation kinds (readme, changelog, license, ...) to the
  filenames that may back them in a release tarball. Matching is
  case-insensitive on the basename, restricted to the tarball root, and
  prefers extensions in the order .md, .markdown, bare, .txt.
  """

  @kinds [:readme, :changelog, :license, :security, :support, :acknowledgments, :threat_model]

  @basenames %{
    readme: ["README"],
    changelog: ["CHANGELOG"],
    license: ["LICENSE"],
    security: ["SECURITY"],
    support: ["SUPPORT"],
    acknowledgments: ["ACKNOWLEDGMENTS", "ACKNOWLEDGEMENTS"],
    threat_model: ["THREAT_MODEL", "THREATMODEL", "THREAT-MODEL"]
  }

  @extensions ["md", "markdown", "", "txt"]

  @labels %{
    readme: "Readme",
    changelog: "Changelog",
    license: "License",
    security: "Security",
    support: "Support",
    acknowledgments: "Acknowledgments",
    threat_model: "Threat Model"
  }

  def kinds(), do: @kinds

  def label(kind) when kind in @kinds, do: @labels[kind]

  def parse_segment(segment) when is_binary(segment) do
    Enum.find(@kinds, &(Atom.to_string(&1) == segment))
  end

  def resolve(kind, files) when kind in @kinds and is_list(files) do
    root_files = Enum.reject(files, &String.contains?(&1, "/"))
    basenames = @basenames[kind]

    Enum.find_value(@extensions, fn ext ->
      root_files
      |> Enum.filter(&matches?(&1, basenames, ext))
      |> Enum.sort()
      |> List.first()
    end)
  end

  def available_kinds(files) when is_list(files) do
    Enum.filter(@kinds, &resolve(&1, files))
  end

  defp matches?(filename, basenames, ext) do
    {base, file_ext} =
      case Path.extname(filename) do
        "" -> {filename, ""}
        "." <> extension -> {Path.rootname(filename), String.downcase(extension)}
      end

    file_ext == ext and String.upcase(base) in basenames
  end
end
