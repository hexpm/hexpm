defmodule Hexpm.SecretScan.Scanner do
  @moduledoc """
  Runs the ruleset over the files of an unpacked release.

  Files are streamed rather than read whole. A release can legitimately hold a
  128 MB file (`tarball_max_uncompressed_size`), and the preview job this runs
  inside uploads with `File.stream!/2` precisely so it never has a whole file
  on the heap. Scanning keeps that property: peak memory is one window, not one
  file.
  """

  require Logger

  alias Hexpm.SecretScan.Rules

  @chunk_size 262_144
  @carry_size 65_536
  @max_findings 100
  @file_timeout 10_000
  @release_timeout 30_000
  @line_context 4_096
  @preview_stars 12
  @inline_allow "gitleaks:allow"

  # The one catch-all in the ruleset. It fires alongside whichever specific
  # rule already caught the same value, so it loses when they collide.
  @catch_all_rule "generic-api-key"

  @doc """
  Scans `file_paths`, relative to `dir`, and returns `{findings, truncated?}`.

  Findings are capped at #{@max_findings}; `truncated?` says whether anything
  was dropped. Files are scanned concurrently because matching is CPU-bound,
  and a single file that defeats the keyword prefilter is abandoned after
  #{div(@file_timeout, 1000)} seconds rather than being allowed to eat the
  job's timeout.
  """
  def scan_files(dir, file_paths, opts \\ []) do
    deadline = System.monotonic_time(:millisecond) + release_timeout()
    empty = %{kept: [], total: 0, halted: false, timeouts: 0}
    # Compile the package's ignore globs once, not once per file.
    opts = Keyword.update(opts, :ignore, [], &compile_globs/1)

    state =
      file_paths
      # Unordered so a file that runs to its timeout doesn't hold every result
      # behind it: the deadline below can only look at the clock when a result
      # arrives, and nothing here cares what order they arrive in.
      |> Task.async_stream(&scan_file(dir, &1, opts),
        max_concurrency: System.schedulers_online(),
        timeout: file_timeout(),
        on_timeout: :kill_task,
        ordered: false,
        zip_input_on_exit: true
      )
      # The budget is read when a result arrives, so a file consumed just before
      # the deadline can still be followed by one that runs its full timeout:
      # 40s worst case against the worker's 270s.
      |> Enum.reduce_while(empty, fn result, state ->
        if System.monotonic_time(:millisecond) > deadline do
          {:halt, %{state | halted: true}}
        else
          {:cont, accumulate(result, state)}
        end
      end)

    log_incomplete(dir, state)
    findings = dedupe(state.kept)

    {cap(findings),
     state.halted or state.timeouts > 0 or state.total > @max_findings or
       length(findings) > @max_findings}
  end

  # The accumulator is capped as it grows rather than at the end. A release of
  # small files each holding thousands of matches would otherwise build the
  # whole list before the cap ever applied — 3 GB of heap to report one finding.
  defp accumulate({:ok, found}, state) do
    %{state | kept: cap(state.kept ++ found), total: state.total + length(found)}
  end

  defp accumulate({:exit, {_path, :timeout}}, state) do
    %{state | timeouts: state.timeouts + 1}
  end

  defp accumulate({:exit, {path, reason}}, state) do
    Logger.warning("Secret scan died on #{path}: #{inspect(reason)}")
    %{state | timeouts: state.timeouts + 1}
  end

  # Both are configurable so a test can exercise them without spending the
  # real budget, and so they can be turned down in production without a deploy.
  # Defaulted on the value, not on `get_env/3`: a key that exists holding nil
  # never reaches the third argument.
  defp file_timeout,
    do: Application.get_env(:hexpm, :secret_scan_file_timeout) || @file_timeout

  defp release_timeout,
    do: Application.get_env(:hexpm, :secret_scan_release_timeout) || @release_timeout

  # Once per release rather than once per file: a tarball built to be slow
  # times out on every file in it, and ninety identical lines say nothing the
  # count doesn't.
  defp log_incomplete(_dir, %{halted: false, timeouts: 0}), do: :ok

  defp log_incomplete(dir, state) do
    Logger.warning(
      "Secret scan of #{dir} incomplete: #{state.timeouts} files timed out" <>
        if(state.halted, do: ", hit the #{release_timeout()}ms budget", else: "")
    )
  end

  # One leaked credential is one finding, however many rules recognised it and
  # however many files it was pasted into. The specific rule wins over the
  # catch-all, and the earliest occurrence is the one worth pointing at.
  defp dedupe(findings) do
    findings
    |> Enum.sort_by(&{&1.rule == @catch_all_rule, &1.file_path, &1.line, &1.rule})
    |> Enum.uniq_by(& &1.fingerprint)
    |> Enum.sort_by(&{&1.file_path, &1.line, &1.rule})
  end

  # Findings that can send email survive truncation first. A vendored bundle
  # that trips the catch-all rule a hundred times would otherwise bury the one
  # AWS key in config/prod.exs, and the scan row is written either way, so
  # nothing would ever look again.
  defp cap(findings) when length(findings) <= @max_findings, do: findings

  defp cap(findings) do
    {notifying, rest} = Enum.split_with(findings, &Rules.notify?(&1.rule))

    (notifying ++ rest)
    |> Enum.take(@max_findings)
    |> Enum.sort_by(&{&1.file_path, &1.line, &1.rule})
  end

  @doc """
  Scans one file, relative to `dir`.

  `opts`: `:scope` (`:notify` or `:all`) and `:ignore` (path globs the package
  asked to suppress).
  """
  def scan_file(dir, path, opts \\ []) do
    # `hex_tarball` rejects an escaping entry and `Hexpm.Preview` filters the
    # unpacked tree again, so the paths that reach here are already safe. Check
    # anyway: this opens whatever it is handed, and the cost is one lstat.
    with {:ok, relative} <- Path.safe_relative(path, dir),
         full = Path.join(dir, relative),
         true <- File.regular?(full) do
      scan(path, fn -> stream_windows(full) end, opts)
    else
      :error ->
        Logger.warning(
          "Secret scan could not read #{path}: not a relative path inside the release"
        )

        []

      false ->
        Logger.warning("Secret scan could not read #{path}: not a regular file")
        []
    end
  rescue
    # A task raising here would leave the stream as an exit, which the caller's
    # rescue cannot catch, so one unreadable file would kill the whole release's
    # scan and take the preview job with it.
    exception ->
      Logger.warning("Secret scan could not read #{path}: #{Exception.message(exception)}")
      []
  end

  @doc """
  Scans content already in memory, under the name `path`.

  Same windowing as reading from disk, so a caller holding the bytes already —
  the corpus scan unpacks tarballs straight to memory — gets the same answer
  without a round trip through the filesystem.
  """
  def scan_content(path, content, opts \\ []) do
    scan(path, fn -> binary_windows(content) end, opts)
  end

  defp scan(path, windows, opts) do
    scope = Keyword.get(opts, :scope, :notify)
    ignore = Keyword.get(opts, :ignore, [])

    if Rules.allowed_path?(path) or ignored?(path, ignore) do
      []
    else
      rules = Rules.for_path(path, scope)

      # Stop once this one file has produced more than a whole release is
      # allowed to report. A file of one repeated credential yields a match
      # every twenty bytes, and the finding list would otherwise grow with the
      # file rather than with the answer.
      {findings, _state} =
        Enum.reduce_while(windows.(), {[], MapSet.new()}, fn window, {found, seen} ->
          {new, seen} = scan_window(window, path, rules, forget_passed(seen, window))
          found = found ++ new

          # One over the cap, so the caller can still tell it was truncated.
          if length(found) > @max_findings do
            {:halt, {Enum.take(found, @max_findings + 1), seen}}
          else
            {:cont, {found, seen}}
          end
        end)

      path_findings(path, scope) ++ findings
    end
  end

  # `seen` exists to stop the overlap between two windows reporting the same
  # match twice, so it only has to remember the part of the file the next window
  # will read again. Every match puts a key in it whether or not it survives the
  # entropy floor and the allowlists, and only survivors count towards the cap
  # that stops the file, so without this a file of dense low-entropy matches
  # grows the set with the file rather than with the answer. Bounded now by the
  # matches in one window, the same order as the list `Regex.scan/3` builds for
  # a single rule.
  defp forget_passed(seen, {_content, offset, _first?, _last?, _newlines}) do
    MapSet.filter(seen, fn {_rule, position} -> position >= offset end)
  end

  # A path the package's `secret_scan: [ignore: [...]]` metadata asked us to
  # skip. `patterns` are already-compiled regexes (see `compile_globs/1`).
  defp ignored?(_path, []), do: false

  defp ignored?(path, patterns), do: Enum.any?(patterns, &Regex.match?(&1, path))

  # `**` spans directory separators, `*` stays within a segment, `?` is one
  # non-separator character. A malformed glob is dropped rather than crashing
  # the scan. `a/**/b` matches `a/b` as well as `a/x/b`, and `**/b` matches a
  # `b` at the root, the way shells and gitignore read them.
  defp compile_globs(globs), do: Enum.flat_map(globs, &compile_glob/1)

  defp compile_glob(glob) when is_binary(glob) do
    pattern =
      glob
      |> String.split(~r{(\A\*\*/|/\*\*/|\*\*|\*|\?)}, include_captures: true, trim: true)
      |> Enum.map_join(fn
        "**/" -> "(?:.*/)?"
        "/**/" -> "(?:/.*/|/)"
        "**" -> ".*"
        "*" -> "[^/]*"
        "?" -> "[^/]"
        literal -> Regex.escape(literal)
      end)

    case Regex.compile("\\A" <> pattern <> "\\z") do
      {:ok, regex} -> [regex]
      _ -> []
    end
  end

  defp compile_glob(_glob), do: []

  # Rules that fire on the filename alone, like a checked-in .p12 keystore.
  defp path_findings(path, scope) do
    for rule <- Rules.path_rules(scope), Regex.match?(rule.path, path) do
      %{
        rule: rule.id,
        file_path: printable(path),
        line: 1,
        byte_offset: 0,
        # Domain separated: a path finding and a content finding whose secret
        # happens to be that path must not collapse into one another through
        # the fingerprint they are deduped on.
        fingerprint: fingerprint("path:" <> path),
        preview: printable(Path.basename(path))
      }
    end
  end

  @doc false
  # Emits `{content, offset, first?, last?, newlines_before}` windows, each the
  # last #{@carry_size} bytes of the previous window followed by the next chunk.
  # `last?` comes from the total size rather than from waiting to see the
  # stream end, so no window has to be held back to discover it is the final
  # one.
  def stream_windows(absolute_path) do
    absolute_path
    |> File.stream!(@chunk_size)
    |> windows(File.stat!(absolute_path).size)
  end

  @doc false
  def binary_windows(content) do
    size = byte_size(content)

    0..max(size - 1, 0)//@chunk_size
    |> Stream.map(&binary_part(content, &1, min(@chunk_size, size - &1)))
    |> windows(size)
  end

  defp windows(chunks, size) do
    Stream.transform(chunks, {<<>>, 0, 0, true}, fn chunk, {carry, offset, newlines, first?} ->
      window = carry <> chunk
      window_size = byte_size(window)
      last? = offset + window_size >= size
      keep = if last?, do: 0, else: min(@carry_size, window_size)
      consumed = window_size - keep

      next = {
        :binary.copy(binary_part(window, consumed, keep)),
        offset + consumed,
        newlines + count_newlines(binary_part(window, 0, consumed)),
        false
      }

      {[{window, offset, first?, last?, newlines}], next}
    end)
  end

  defp scan_window({content, offset, first?, last?, newlines_before}, path, rules, seen) do
    rules
    |> Rules.candidates(content)
    |> Enum.flat_map_reduce(seen, fn rule, seen ->
      rule
      |> matches(content, first?, last?)
      # A window of one repeated credential yields a match every twenty bytes,
      # and the caller's cap only applies between windows, so the window has to
      # stop itself. Counting findings rather than matches: most matches die in
      # the entropy floor or an allowlist, and capping the raw matches would
      # hold the survivors well under the limit.
      |> Enum.reduce_while({[], seen}, fn match, {found, seen} ->
        key = {rule.id, offset + match.start}

        {found, seen} =
          if MapSet.member?(seen, key) do
            {found, seen}
          else
            finding = finding(rule, match, content, path, offset, newlines_before)
            {found ++ List.wrap(finding), MapSet.put(seen, key)}
          end

        # One over the cap, so a window producing exactly the cap stays
        # distinguishable from one that overflowed it.
        if length(found) > @max_findings do
          {:halt, {found, seen}}
        else
          {:cont, {found, seen}}
        end
      end)
    end)
  end

  # A match touching a window edge is left to the neighbouring window, which
  # sees it with real context. 152 of the rules end in an alternation with `$`,
  # and `$` matches the end of the window, so a secret sliced by a chunk
  # boundary would otherwise match against the cut. Symmetrically `\b` fires at
  # the first byte of a window where mid-file it would not.
  #
  # Since windows overlap by the carry, any match shorter than that is interior
  # to one of them and is found exactly once. Longer matches depend on where
  # they land, and one longer than a whole window is missed — only the handful
  # of rules with unbounded quantifiers can produce those, `private-key` being
  # the realistic one, and a 4096-bit key is three kilobytes.
  defp matches(rule, content, first?, last?) do
    size = byte_size(content)

    rule.regex
    |> Regex.scan(content, return: :index)
    |> Enum.flat_map(fn groups ->
      {start, length} = hd(groups)

      cond do
        not first? and start == 0 -> []
        not last? and start + length == size -> []
        true -> [%{start: start, length: length, secret: secret_span(groups, rule.secret_group)}]
      end
    end)
  end

  # gitleaks takes the first NON-EMPTY capture group when a rule sets no
  # `secretGroup`, and keeps the whole match when every group is empty. Taking
  # group 1 unconditionally silently drops every rule written as a top-level
  # alternation with one group per branch — `atlassian-api-token` never fired
  # on a modern ATATT3 token, and that rule sends email.
  defp secret_span([whole | groups], nil) do
    Enum.find(groups, whole, fn {start, length} -> start >= 0 and length > 0 end)
  end

  defp secret_span([whole | _] = groups, index) do
    case Enum.at(groups, index) do
      {start, length} when start >= 0 and length > 0 -> {start, length}
      _ -> whole
    end
  end

  defp finding(rule, match, content, path, offset, newlines_before) do
    {secret_start, secret_length} = match.secret
    secret = :binary.copy(binary_part(content, secret_start, secret_length))
    whole = :binary.copy(binary_part(content, match.start, match.length))

    targets = %{
      path: path,
      secret: secret,
      match: whole,
      line: line_text(content, match)
    }

    with false <- annotated_allowed?(targets.line),
         true <- entropy_ok?(rule, secret),
         false <- Rules.allowed?(rule.allowlists, targets),
         false <- Rules.allowed?(Rules.global_allowlists(), targets) do
      %{
        rule: rule.id,
        file_path: printable(path),
        line: newlines_before + count_newlines(binary_part(content, 0, match.start)) + 1,
        byte_offset: offset + match.start,
        fingerprint: fingerprint(secret),
        preview: redact(secret)
      }
    else
      _ -> nil
    end
  end

  # The fingerprint is the dedup key, so it must be stable for a given secret.
  # Keying the HMAC on `:hexpm, :secret`, the same way API keys are stored, means
  # the stored value confirms nothing on its own: without the app secret the
  # table cannot test a candidate against a finding or brute-force a low-entropy
  # one.
  defp fingerprint(value) do
    :crypto.mac(:hmac, :sha256, Application.fetch_env!(:hexpm, :secret), value)
  end

  # gitleaks honours an inline `gitleaks:allow` on the line, which is how a
  # project marks a deliberate fixture. A package that vendors an annotated
  # test file should not earn its owner a security email.
  defp annotated_allowed?(line), do: String.contains?(line, @inline_allow)

  defp entropy_ok?(%{entropy: nil}, _secret), do: true
  # Exclusive, as in gitleaks: `if entropy <= r.Entropy { continue }`.
  defp entropy_ok?(%{entropy: floor}, secret), do: Rules.entropy(secret) > floor

  # Bounded on both sides: a minified bundle is one line and we are not putting
  # a megabyte of it through a regex.
  defp line_text(content, match) do
    before_start = max(match.start - @line_context, 0)
    after_end = min(match.start + match.length + @line_context, byte_size(content))

    from =
      case :binary.matches(binary_part(content, before_start, match.start - before_start), "\n") do
        [] -> before_start
        matches -> before_start + elem(List.last(matches), 0) + 1
      end

    tail_start = match.start + match.length

    to =
      case :binary.match(binary_part(content, tail_start, after_end - tail_start), "\n") do
        :nomatch -> after_end
        {position, _length} -> tail_start + position
      end

    :binary.copy(binary_part(content, from, to - from))
  end

  defp count_newlines(binary), do: length(:binary.matches(binary, "\n"))

  @doc """
  Masks a secret for display, keeping enough of it to be recognisable.

  The raw value is never stored or mailed — only this and a sha256 of it. The
  mask is a fixed width rather than the secret's length, so a matched PEM block
  doesn't become a three kilobyte row of asterisks.
  """
  def redact(secret) do
    size = byte_size(secret)
    # Never show more than a sixth from each end. The row also carries a sha256
    # HMAC of the value, so on a ten character secret the old fixed
    # four-and-four left two unknown characters and the hash to check them
    # against, which is not redaction.
    keep = if size < 12, do: 0, else: min(4, div(size, 6))

    if keep == 0 do
      String.duplicate("*", min(size, @preview_stars))
    else
      printable(binary_part(secret, 0, keep)) <>
        String.duplicate("*", @preview_stars) <>
        printable(binary_part(secret, size - keep, keep))
    end
  end

  # Rules run over binary files and paths come from tar entry names, so both a
  # match and a file name can hold bytes that are not text. They land in a
  # Postgres text column, which rejects a NUL outright, and in a plain text
  # email, where an escape sequence lets a publisher write their own paragraph
  # into mail that arrives from hex.pm.
  defp printable(binary) do
    binary
    |> String.replace_invalid()
    |> String.replace(~r/[[:cntrl:]]/u, "�")
  end
end
