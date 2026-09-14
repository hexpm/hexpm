defmodule Hexpm.Docs.Files do
  @moduledoc """
  Recognition table for conventional documentation files in a release.

  Matched case-insensitively at the tarball root, preferring .md, .markdown,
  .txt then bare -- Preview's existing README priority.
  """

  @type resolved :: %{atom => String.t()}

  @kinds_and_labels [
    readme: "Readme",
    changelog: "Changelog",
    license: "License",
    security: "Security",
    support: "Support"
    # ACKNOWLEDGMENTS and THREAT_MODEL were in none of the 2,680 packages
    # surveyed on #1569; add a kind here and its basenames below for one.
  ]

  @kinds Keyword.keys(@kinds_and_labels)

  @basenames %{
    readme: ["README"],
    changelog: ["CHANGELOG"],
    license: ["LICENSE"],
    security: ["SECURITY"],
    support: ["SUPPORT"]
  }

  @extensions ["md", "markdown", "txt", ""]

  @extension_rank @extensions |> Enum.with_index() |> Map.new()

  @basename_to_kind for {kind, names} <- @basenames, name <- names, into: %{}, do: {name, kind}

  @doc "Recognized kinds, in canonical order."
  @spec kinds() :: [atom]
  def kinds(), do: Keyword.keys(@kinds_and_labels)

  @doc "Label for a kind, falling back to its string form."
  @spec label(atom) :: String.t()
  def label(kind), do: Keyword.get(@kinds_and_labels, kind, to_string(kind))

  @spec parse_segment(term) :: atom | nil
  for kind <- @kinds do
    def parse_segment(unquote(Atom.to_string(kind))), do: unquote(kind)
  end

  def parse_segment(_segment), do: nil

  @doc """
  Every kind resolvable from `files`, as kind => filename. Malformed input
  resolves to nothing rather than raising; `files` comes from the tarball index.
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

  @doc "Kinds present in a `resolve_all/1` result, in canonical order."
  @spec present_kinds(resolved) :: [atom]
  def present_kinds(resolved) do
    Enum.filter(@kinds, &Map.has_key?(resolved, &1))
  end

  @doc """
  Kinds to list in navigation: every kind in `resolved`, plus `active` so a
  deep link to a file the release lacks still shows as the current page.
  """
  @spec nav_kinds(resolved, atom) :: [atom]
  def nav_kinds(resolved, active) do
    resolved |> Map.put_new(active, nil) |> present_kinds()
  end

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
