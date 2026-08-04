defmodule Hexpm.SecretScan.Rules do
  @moduledoc """
  The secret scanning ruleset, vendored from gitleaks.

  Rules come from `data/secret_scan/gitleaks.toml` and nothing else. We do not
  write our own: a rule nobody upstream has validated is where false positives
  come from, and a rule that consults our own data would answer questions about
  it to whoever supplies the input.

  The TOML is parsed at compile time into plain data. Regexes and the keyword
  trie are built once at runtime into `:persistent_term`, because a compiled
  pattern is a resource that can't survive being baked into a module.
  """

  # Read only at compile time, so it lives outside priv, which is for files a
  # release needs at runtime. `mix hexpm.secret_scan.refresh` rewrites it.
  @gitleaks_config Path.expand("../../../data/secret_scan/gitleaks.toml", __DIR__)

  @external_resource @gitleaks_config

  @persistent_key {__MODULE__, :compiled}

  # Rules allowed to send email. Everything else is recorded silently. gitleaks
  # is tuned for CI on your own repo, where a false positive costs a developer
  # half a minute; here it costs a stranger an unsolicited security email, so a
  # rule only graduates once a scan of the published corpus says it is clean.
  #
  # Membership is decided by how a rule is written, not by how often it fired
  # on the packages already published. A scan of all 163,630 existing releases
  # produced hits for 7 of these rules and nothing at all for the rest, which
  # is far too small a sample to say anything about precision, and the existing
  # corpus is the wrong population anyway: it is weighted toward old and
  # abandoned packages, where a fake token in a README was normal.
  #
  # Excluded because of what the pattern does:
  #
  #   the 18 rules shaped `[\w.-]{0,50}?(?:vendor)...=...(value)` are
  #     generic-api-key with a vendor word in front, and generic-api-key is
  #     already record-only for that reason. atlassian-api-token is the one
  #     worth splitting: its other branch, ATATT3 plus 186 characters, is as
  #     self-identifying as anything here.
  #   gcp-api-key            precise, but a Google API key is routinely shipped
  #                          in client code on purpose
  #   confluent-access-token another of the contextual shape: any sixteen
  #                          lowercase alphanumerics near the word "confluent",
  #                          which is why it matched a C++ identifier in duckdb
  #   private-key            fires on every test fixture that ships a PEM
  #   pkcs12-file            matches a filename and never looks inside
  #
  # stripe-access-token is included though its corpus hits were placeholder keys
  # in READMEs: a leaked sk_test_ still lets someone write to the owner's Stripe
  # test environment, so it is worth an email despite the false positive rate.
  @notify_rules ~w(
    adobe-client-secret
    age-secret-key
    alibaba-access-key-id
    anthropic-admin-api-key
    anthropic-api-key
    azure-ad-client-secret
    aws-access-token
    clojars-api-token
    stripe-access-token
    databricks-api-token
    digitalocean-access-token
    digitalocean-pat
    digitalocean-refresh-token
    doppler-api-token
    duffel-api-token
    dynatrace-api-token
    easypost-api-token
    flutterwave-secret-key
    frameio-api-token
    github-app-token
    github-fine-grained-pat
    github-oauth
    github-pat
    github-refresh-token
    gitlab-pat
    gitlab-ptt
    gitlab-rrt
    grafana-api-key
    grafana-cloud-api-token
    grafana-service-account-token
    intra42-client-secret
    linear-api-key
    npm-access-token
    openai-api-key
    planetscale-api-token
    planetscale-oauth-token
    planetscale-password
    postman-api-token
    prefect-api-token
    pulumi-api-token
    pypi-upload-token
    rubygems-api-token
    scalingo-api-token
    sendgrid-api-token
    sendinblue-api-token
    shippo-api-token
    shopify-access-token
    shopify-custom-access-token
    shopify-private-app-access-token
    shopify-shared-secret
    slack-app-token
    slack-bot-token
    slack-config-access-token
    slack-config-refresh-token
    slack-legacy-bot-token
    slack-legacy-token
    slack-legacy-workspace-token
    slack-user-token
    slack-webhook-url
    square-access-token
    twilio-api-key
    vault-batch-token
    vault-service-token
  )

  @parsed Toml.decode_file!(@gitleaks_config)

  @raw_rules Map.fetch!(@parsed, "rules")
  @raw_global [Map.fetch!(@parsed, "allowlist")]

  if @raw_rules == [] do
    raise "no secret scanning rules were loaded from #{@gitleaks_config}"
  end

  duplicate_ids =
    @raw_rules |> Enum.map(& &1["id"]) |> Enum.frequencies() |> Enum.filter(&(elem(&1, 1) > 1))

  if duplicate_ids != [] do
    raise "duplicate secret scanning rule ids: #{inspect(Enum.map(duplicate_ids, &elem(&1, 0)))}"
  end

  unknown_notify = @notify_rules -- Enum.map(@raw_rules, & &1["id"])

  if unknown_notify != [] do
    raise "@notify_rules names rules that do not exist: #{inspect(unknown_notify)}"
  end

  @doc "Every rule, compiled."
  def all, do: compiled().rules

  @doc """
  Rules that match on the file path alone, with no content regex.

  `scope` is `:notify` (only rules that send email, the production default) or
  `:all` (the whole ruleset, for the offline corpus tool).
  """
  def path_rules(scope \\ :notify), do: scope(compiled().path_rules, scope)

  @doc "The allowlists that apply to every rule."
  def global_allowlists, do: compiled().global_allowlists

  @doc "Whether a finding for this rule is allowed to send email."
  def notify?(rule_id), do: MapSet.member?(compiled().notify, rule_id)

  @doc """
  The content rules that apply to `path`, dropping those restricted elsewhere.

  A handful of rules only make sense in one kind of file — a NuGet password in
  `nuget.config`, a Terraform password in `.tf`. `scope` is `:notify` or `:all`.

  Production runs `:notify` only: the record-only rules cost far more CPU than
  the ones that send email (their backtracking patterns and common keywords),
  and their findings are never acted on. The corpus tool runs `:all` to measure
  every rule for tuning the notify list.
  """
  def for_path(path, scope \\ :notify) do
    compiled().content_rules
    |> scope(scope)
    |> Enum.filter(fn rule -> is_nil(rule.path) or Regex.match?(rule.path, path) end)
  end

  defp scope(rules, :all), do: rules
  defp scope(rules, :notify), do: Enum.filter(rules, &MapSet.member?(compiled().notify, &1.id))

  @doc """
  Narrows `rules` to those whose keywords appear in `content`.

  Every rule declares literal substrings that must be present for its regex to
  have any chance of matching, so one Aho-Corasick pass over the content
  usually leaves a handful of rules to actually run. On Elixir source that is
  1-5 of 222, and it is the difference between 2 seconds and 150 milliseconds
  per 256 KB.
  """
  def candidates(rules, content) do
    %{keyword_pattern: pattern} = compiled()
    lowered = ascii_downcase(content)

    %{keyword_containment: containment} = compiled()

    present =
      lowered
      |> :binary.matches(pattern)
      |> Enum.reduce(MapSet.new(), fn {start, length}, acc ->
        lowered
        |> binary_part(start, length)
        |> with_contained(containment)
        |> Enum.reduce(acc, &MapSet.put(&2, &1))
      end)

    Enum.filter(rules, fn rule ->
      rule.keywords == [] or Enum.any?(rule.keywords, &MapSet.member?(present, &1))
    end)
  end

  # `:binary.matches/2` is leftmost-longest and non-overlapping, so a hit on
  # "rapidapi" swallows the "api" inside it and a rule keyed only on "api"
  # would never run. gitleaks uses Aho-Corasick, which reports both. Closing
  # each matched keyword over the keywords contained in it restores that for
  # the nesting case, which is the one the ruleset actually has.
  defp with_contained(keyword, containment) do
    Map.get(containment, keyword, [keyword])
  end

  @doc "Shannon entropy of a string in bits per byte, as gitleaks measures it."
  def entropy(""), do: 0.0

  def entropy(string) do
    bytes = :binary.bin_to_list(string)
    total = length(bytes)

    bytes
    |> Enum.frequencies()
    |> Enum.reduce(0.0, fn {_byte, count}, acc ->
      probability = count / total
      acc - probability * :math.log2(probability)
    end)
  end

  @doc "Whether the global allowlist excludes this path from scanning entirely."
  def allowed_path?(path) do
    Enum.any?(compiled().global_allowlists, fn allowlist ->
      Enum.any?(allowlist.paths, &Regex.match?(&1, path))
    end)
  end

  @doc """
  Whether any allowlist suppresses this match.

  `regexes` test the allowlist's `regexTarget` (the secret by default, or the
  whole match, or the line it sits on), `paths` test the file path, `stopwords`
  are substrings of the secret. A `condition` of `AND` requires every
  configured criterion to hit; the default is any of them.
  """
  def allowed?(allowlists, targets) do
    Enum.any?(allowlists, &allowlist_matches?(&1, targets))
  end

  defp allowlist_matches?(allowlist, targets) do
    # Only criteria the allowlist actually configures count. An `AND` allowlist
    # that sets paths and regexes needs both, but must not be held to stopwords
    # it never declared.
    checks =
      [
        check(allowlist.paths != [], fn ->
          Enum.any?(allowlist.paths, &Regex.match?(&1, targets.path))
        end),
        check(allowlist.regexes != [], fn ->
          target = target(targets, allowlist.regex_target)
          Enum.any?(allowlist.regexes, &Regex.match?(&1, target))
        end),
        check(allowlist.stopword_pattern, fn ->
          :binary.match(ascii_downcase(targets.secret), allowlist.stopword_pattern) != :nomatch
        end)
      ]
      |> Enum.reject(&is_nil/1)

    case {allowlist.condition, checks} do
      {_condition, []} -> false
      {:and, checks} -> Enum.all?(checks)
      {:or, checks} -> Enum.any?(checks)
    end
  end

  defp check(configured, fun), do: if(configured, do: fun.(), else: nil)

  defp target(targets, :secret), do: targets.secret
  defp target(targets, :match), do: targets.match
  defp target(targets, :line), do: targets.line

  @doc """
  Lowercases ASCII letters, leaving offsets and every other byte alone.

  Keywords and stopwords are all ASCII, so this is enough to match them, and
  unlike `String.downcase/1` it doesn't care whether the input is valid UTF-8 —
  half the files in a package are not text at all.
  """
  def ascii_downcase(binary) do
    for <<byte <- binary>>, into: <<>> do
      if byte >= ?A and byte <= ?Z, do: <<byte + 32>>, else: <<byte>>
    end
  end

  defp compiled do
    case :persistent_term.get(@persistent_key, nil) do
      nil -> build()
      compiled -> compiled
    end
  end

  defp build do
    rules = Enum.map(@raw_rules, &compile_rule/1)
    {content_rules, path_rules} = Enum.split_with(rules, &(&1.regex != nil))
    keywords = rules |> Enum.flat_map(& &1.keywords) |> Enum.uniq()

    compiled = %{
      rules: rules,
      content_rules: content_rules,
      path_rules: path_rules,
      global_allowlists: Enum.map(@raw_global, &compile_allowlist/1),
      notify: MapSet.new(@notify_rules),
      keyword_pattern: :binary.compile_pattern(keywords),
      keyword_containment: containment(keywords)
    }

    :persistent_term.put(@persistent_key, compiled)
    compiled
  end

  defp containment(keywords) do
    Map.new(keywords, fn keyword ->
      {keyword, Enum.filter(keywords, &String.contains?(keyword, &1))}
    end)
  end

  defp compile_rule(raw) do
    regex = raw["regex"] && Regex.compile!(raw["regex"])

    %{
      id: raw["id"],
      description: raw["description"],
      regex: regex,
      path: raw["path"] && Regex.compile!(raw["path"]),
      keywords: raw |> Map.get("keywords", []) |> Enum.map(&ascii_downcase/1),
      entropy: raw["entropy"] && raw["entropy"] / 1,
      secret_group: raw["secretGroup"],
      allowlists: raw |> Map.get("allowlists", []) |> Enum.map(&compile_allowlist/1)
    }
  end

  defp compile_allowlist(raw) do
    stopwords = raw |> Map.get("stopwords", []) |> Enum.map(&ascii_downcase/1)

    %{
      paths: raw |> Map.get("paths", []) |> Enum.map(&Regex.compile!/1),
      regexes: raw |> Map.get("regexes", []) |> Enum.map(&Regex.compile!/1),
      stopword_pattern: stopwords != [] && :binary.compile_pattern(stopwords),
      regex_target: regex_target(raw["regexTarget"]),
      condition: condition(raw["condition"])
    }
  end

  defp regex_target(nil), do: :secret
  defp regex_target("secret"), do: :secret
  defp regex_target("match"), do: :match
  defp regex_target("line"), do: :line

  defp condition(nil), do: :or
  defp condition("OR"), do: :or
  defp condition("AND"), do: :and
end
