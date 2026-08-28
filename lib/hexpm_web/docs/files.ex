defmodule HexpmWeb.Docs.Files do
  @moduledoc """
  Recognition table for conventional package documentation files.

  Maps documentation kinds (readme, changelog, license, ...) to the
  filenames that may back them in a release tarball. Matching is
  case-insensitive on the basename, restricted to the tarball root, and
  prefers extensions in the order .md, .markdown, .txt, bare.
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
  # built once at compile time so resolve_all/1 can classify each file in a
  # single pass.
  @basename_to_kind for {kind, names} <- @basenames, name <- names, into: %{}, do: {name, kind}

  def kinds(), do: @kinds

  def label(kind) when kind in @kinds, do: @labels[kind]

  def parse_segment(segment) when is_binary(segment) do
    Enum.find(@kinds, &(Atom.to_string(&1) == segment))
  end

  @doc """
  Resolves every kind against `files` in a single pass, returning a map of
  kind => winning filename for each kind that has a match.
  """
  def resolve_all(files) when is_list(files) do
    files
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&String.contains?(&1, "/"))
    |> Enum.reduce(%{}, fn filename, acc ->
      case classify(filename) do
        {kind, ext} ->
          Map.update(acc, kind, %{ext => filename}, fn by_ext ->
            Map.update(by_ext, ext, filename, &min(&1, filename))
          end)

        :nomatch ->
          acc
      end
    end)
    |> Map.new(fn {kind, by_ext} -> {kind, pick(by_ext)} end)
  end

  def resolve_all(_files), do: %{}

  @doc """
  Returns the kinds present in a `resolve_all/1` result, in canonical
  `kinds/0` order.
  """
  def present_kinds(resolved) when is_map(resolved) do
    Enum.filter(@kinds, &Map.has_key?(resolved, &1))
  end

  def resolve(kind, files) when kind in @kinds do
    files
    |> resolve_all()
    |> Map.get(kind)
  end

  def available_kinds(files) do
    files
    |> resolve_all()
    |> present_kinds()
  end

  defp pick(by_ext) do
    Enum.find_value(@extensions, fn ext -> Map.get(by_ext, ext) end)
  end

  # Classifies a root-level filename as {kind, extension} if it matches one
  # of the recognized basenames/extensions, or :nomatch otherwise. A
  # filename ending in a bare "." (e.g. "README.") never matches anything.
  defp classify(filename) do
    with false <- String.ends_with?(filename, "."),
         {base, ext} <- split_extension(filename),
         kind when not is_nil(kind) <- @basename_to_kind[String.upcase(base)],
         true <- ext in @extensions do
      {kind, ext}
    else
      _ -> :nomatch
    end
  end

  defp split_extension(filename) do
    case Path.extname(filename) do
      "" -> {filename, ""}
      "." <> extension -> {Path.rootname(filename), String.downcase(extension)}
    end
  end
end
