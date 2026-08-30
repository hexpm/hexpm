defmodule Hexpm.Docs.Files do
  @moduledoc """
  Recognition table for conventional package documentation files.

  Maps documentation kinds (readme, changelog, license, ...) to the
  filenames that may back them in a release tarball. Matching is
  case-insensitive on the basename, restricted to the tarball root, and
  prefers extensions in the order .md, .markdown, .txt, bare -- matching
  Hexpm.Preview's existing README filename priority exactly.
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

  @extensions ["md", "markdown", "txt", ""]

  @labels %{
    readme: "Readme",
    changelog: "Changelog",
    license: "License",
    security: "Security",
    support: "Support",
    acknowledgments: "Acknowledgments",
    threat_model: "Threat Model"
  }

  # Reverse lookup from an uppercased basename to the kind it belongs to,
  # built once at compile time so resolve_all/1 classifies each file in a
  # single pass instead of checking every kind against every file.
  @basename_to_kind for {kind, names} <- @basenames, name <- names, into: %{}, do: {name, kind}

  def kinds(), do: @kinds

  def label(kind) when kind in @kinds, do: @labels[kind]

  def parse_segment(segment) when is_binary(segment) do
    Enum.find(@kinds, &(Atom.to_string(&1) == segment))
  end

  def parse_segment(_segment), do: nil

  @doc """
  Resolves every kind against `files` in a single pass, returning a map of
  kind => winning filename for each kind that has a match. Tolerates a
  non-list argument or non-string entries by treating them as no match
  rather than raising -- `files` ultimately comes from a release tarball's
  recorded index, which this module does not control the shape of.
  """
  def resolve_all(files) when is_list(files) do
    files
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&String.contains?(&1, "/"))
    |> Enum.reduce(%{}, &classify_into/2)
    |> Map.new(fn {kind, by_ext} -> {kind, pick_extension(by_ext)} end)
  end

  def resolve_all(_files), do: %{}

  @doc """
  The kinds present in a `resolve_all/1` result, in canonical `kinds/0` order.
  """
  def present_kinds(resolved) when is_map(resolved) do
    Enum.filter(@kinds, &Map.has_key?(resolved, &1))
  end

  def resolve(kind, files) when kind in @kinds do
    files |> resolve_all() |> Map.get(kind)
  end

  defp classify_into(filename, acc) do
    case classify(filename) do
      {kind, ext} ->
        Map.update(acc, kind, %{ext => filename}, fn by_ext ->
          Map.update(by_ext, ext, filename, &min(&1, filename))
        end)

      :nomatch ->
        acc
    end
  end

  defp classify(filename) do
    if String.ends_with?(filename, ".") do
      :nomatch
    else
      {base, ext} = split_extension(filename)

      case Map.get(@basename_to_kind, String.upcase(base)) do
        nil -> :nomatch
        kind -> {kind, ext}
      end
    end
  end

  defp split_extension(filename) do
    case Path.extname(filename) do
      "" -> {filename, ""}
      "." <> ext -> {Path.rootname(filename), String.downcase(ext)}
    end
  end

  defp pick_extension(by_ext) do
    Enum.find_value(@extensions, fn ext -> Map.get(by_ext, ext) end)
  end
end
