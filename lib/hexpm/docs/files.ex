defmodule Hexpm.Docs.Files do
  @moduledoc """
  Recognition table for conventional package documentation files.

  Maps documentation kinds (readme, changelog, license, ...) to the
  filenames that may back them in a release tarball. Matching is
  case-insensitive on the basename, restricted to the tarball root, and
  prefers extensions in the order .md, .markdown, .txt, bare -- matching
  Hexpm.Preview's existing README filename priority exactly.
  """

  @type resolved :: %{atom => String.t()}

  @kinds_and_labels [
    readme: "Readme",
    changelog: "Changelog",
    license: "License",
    security: "Security",
    support: "Support",
    acknowledgments: "Acknowledgments",
    threat_model: "Threat Model"
  ]

  @kinds Keyword.keys(@kinds_and_labels)

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

  @extension_rank @extensions |> Enum.with_index() |> Map.new()

  # Reverse lookup from an uppercased basename to the kind it belongs to,
  # built once at compile time so resolve_all/1 classifies each file in a
  # single pass instead of checking every kind against every file.
  @basename_to_kind for {kind, names} <- @basenames, name <- names, into: %{}, do: {name, kind}

  @doc "The recognized documentation kinds, in canonical order."
  @spec kinds() :: [atom]
  def kinds(), do: Keyword.keys(@kinds_and_labels)

  @doc "Human-readable label for a kind, falling back to its string form when unrecognized."
  @spec label(atom) :: String.t()
  def label(kind), do: Keyword.get(@kinds_and_labels, kind, to_string(kind))

  @doc "Parses a URL segment into its kind, or nil when unrecognized."
  @spec parse_segment(term) :: atom | nil
  for kind <- @kinds do
    def parse_segment(unquote(Atom.to_string(kind))), do: unquote(kind)
  end

  def parse_segment(_segment), do: nil

  @doc """
  Resolves every kind against `files` in a single pass, returning a map of
  kind => winning filename for each kind that has a match. Tolerates a
  non-list argument or non-string entries by treating them as no match
  rather than raising -- `files` ultimately comes from a release tarball's
  recorded index, which this module does not control the shape of.
  """
  @spec resolve_all(term) :: resolved
  def resolve_all(files) when is_list(files) do
    files
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&String.contains?(&1, "/"))
    |> Enum.flat_map(fn filename ->
      case classify(filename) do
        {kind, ext} -> [{kind, ext, filename}]
        :nomatch -> []
      end
    end)
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {kind, matches} ->
      {_kind, _ext, filename} =
        Enum.min_by(matches, fn {_, ext, name} -> {@extension_rank[ext], name} end)

      {kind, filename}
    end)
  end

  def resolve_all(_files), do: %{}

  @doc """
  The kinds present in a `resolve_all/1` result, in canonical `kinds/0` order.
  """
  @spec present_kinds(resolved) :: [atom]
  def present_kinds(resolved) do
    Enum.filter(@kinds, &Map.has_key?(resolved, &1))
  end

  @doc """
  Kinds to show in navigation: every kind the release has, plus `active` even
  when the release doesn't have it (a deep link to an unavailable kind).
  """
  @spec nav_kinds(resolved, atom) :: [atom]
  def nav_kinds(resolved, active) do
    resolved |> Map.put_new(active, nil) |> present_kinds()
  end

  @doc "Resolves a single kind against `files`, or nil when there is no match."
  @spec resolve(atom, term) :: String.t() | nil
  def resolve(kind, files) when kind in @kinds do
    files |> resolve_all() |> Map.get(kind)
  end

  def resolve(_kind, _files), do: nil

  defp classify(filename) do
    case split_extension(filename) do
      {base, ext} when ext in @extensions ->
        case Map.fetch(@basename_to_kind, String.upcase(base, :ascii)) do
          {:ok, kind} -> {kind, ext}
          :error -> :nomatch
        end

      _ ->
        :nomatch
    end
  end

  defp split_extension(filename) do
    case Path.extname(filename) do
      "." <> ext when ext != "" -> {Path.rootname(filename), String.downcase(ext)}
      _ -> {filename, ""}
    end
  end
end
