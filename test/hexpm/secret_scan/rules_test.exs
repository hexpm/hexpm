defmodule Hexpm.SecretScan.RulesTest do
  use ExUnit.Case, async: true

  alias Hexpm.SecretScan.Rules

  describe "the vendored ruleset" do
    test "loads every rule with a compiled pattern" do
      rules = Rules.all()

      # A refreshed gitleaks.toml that parsed into a different shape would
      # silently drop rules, so the count is asserted rather than assumed.
      assert length(rules) > 200
      assert Enum.all?(rules, &is_binary(&1.id))
      assert Enum.all?(rules, &(&1.regex != nil or &1.path != nil))

      for rule <- rules, rule.regex do
        assert %Regex{} = rule.regex
      end
    end

    test "has no duplicate ids" do
      ids = Enum.map(Rules.all(), & &1.id)
      assert ids == Enum.uniq(ids)
    end

    test "spells out no credential GitHub would alert on" do
      # gitleaks allowlists example keys by writing them in full, which makes
      # our copy of the config a secret-scanning alert on every push. The
      # refresh task rewrites them, so refreshing without it fails here.
      toml = File.read!("data/secret_scan/gitleaks.toml")

      assert Mix.Tasks.Hexpm.SecretScan.Refresh.defang(toml) == toml
    end

    test "carries the global allowlist" do
      assert [_ | _] = Rules.global_allowlists()
      assert Rules.allowed_path?("priv/static/logo.png")
      assert Rules.allowed_path?("assets/node_modules/left-pad/index.js")
      refute Rules.allowed_path?("lib/app.ex")
      refute Rules.allowed_path?("config/prod.exs")
    end

    test "only notifies for rules that exist" do
      ids = MapSet.new(Rules.all(), & &1.id)

      assert Rules.notify?("aws-access-token")
      refute Rules.notify?("generic-api-key")
      refute Rules.notify?("private-key")
      refute Rules.notify?("no-such-rule")

      # Nothing notifies that is not a vendored rule.
      for rule <- Rules.all(), Rules.notify?(rule.id) do
        assert MapSet.member?(ids, rule.id)
      end
    end
  end

  describe "for_path/1" do
    test "drops rules restricted to other file types" do
      terraform = Enum.find(Rules.all(), &(&1.id == "hashicorp-tf-password"))
      assert terraform.path

      ids = Rules.for_path("main.tf", :all) |> Enum.map(& &1.id)
      assert "hashicorp-tf-password" in ids

      ids = Rules.for_path("lib/app.ex", :all) |> Enum.map(& &1.id)
      refute "hashicorp-tf-password" in ids
    end
  end

  describe "candidates/2" do
    test "keeps only rules whose keywords are present" do
      rules = Rules.for_path("lib/app.ex")

      ids =
        rules
        |> Rules.candidates("token = AKIAIOSFODNN7EXAMPLE")
        |> Enum.map(& &1.id)

      assert "aws-access-token" in ids
      refute "cisco-meraki-api-key" in ids
    end

    test "matches keywords regardless of case" do
      rules = Rules.for_path("lib/app.ex")

      assert rules |> Rules.candidates("AKIA...") |> Enum.any?(&(&1.id == "aws-access-token"))
      assert rules |> Rules.candidates("akia...") |> Enum.any?(&(&1.id == "aws-access-token"))
    end

    test "leaves almost nothing for ordinary source" do
      rules = Rules.for_path("lib/app.ex")
      source = "defmodule App do\n  def hello, do: :world\nend\n"

      assert Rules.candidates(rules, source) == []
    end

    test "does not need valid UTF-8" do
      rules = Rules.for_path("priv/blob.bin")
      content = <<0xFF, 0xFE, 0x00>> <> "AKIAIOSFODNN7EXAMPLE" <> <<0x00, 0xC3>>

      assert rules |> Rules.candidates(content) |> Enum.any?(&(&1.id == "aws-access-token"))
    end
  end

  describe "entropy/1" do
    test "is zero for a single repeated byte and rises with variety" do
      assert Rules.entropy("") == 0.0
      assert Rules.entropy("aaaaaaaa") == 0.0
      assert Rules.entropy("ab") == 1.0
      assert Rules.entropy("kZfL0mQx8vT3pRw9YbN2sJhG") > 4.0
    end
  end

  describe "allowed?/2" do
    test "an OR allowlist needs one criterion, an AND allowlist needs all of them" do
      or_list = [allowlist(paths: [~r/_test\.exs$/], regexes: [~r/^never$/])]
      and_list = [allowlist(paths: [~r/_test\.exs$/], regexes: [~r/^never$/], condition: :and)]

      targets = targets(path: "lib/app_test.exs", secret: "sekrit")

      assert Rules.allowed?(or_list, targets)
      refute Rules.allowed?(and_list, targets)

      assert Rules.allowed?(and_list, %{targets | secret: "never"})
    end

    test "an AND allowlist ignores criteria it does not declare" do
      list = [allowlist(paths: [~r/_test\.exs$/], condition: :and)]

      assert Rules.allowed?(list, targets(path: "lib/app_test.exs", secret: "sekrit"))
      refute Rules.allowed?(list, targets(path: "lib/app.ex", secret: "sekrit"))
    end

    test "regexTarget picks what the regex is tested against" do
      list = fn target -> [allowlist(regexes: [~r/EXAMPLE/], regex_target: target)] end
      targets = targets(secret: "abc", match: "key = EXAMPLE_abc", line: "  key = EXAMPLE_abc")

      refute Rules.allowed?(list.(:secret), targets)
      assert Rules.allowed?(list.(:match), targets)
      assert Rules.allowed?(list.(:line), targets)
    end

    test "stopwords are substrings of the secret, case-insensitively" do
      list = [allowlist(stopwords: ["placeholder"])]

      assert Rules.allowed?(list, targets(secret: "my-PLACEHOLDER-value"))
      refute Rules.allowed?(list, targets(secret: "kZfL0mQx8vT3pRw9YbN2"))
    end

    test "an allowlist with nothing configured allows nothing" do
      refute Rules.allowed?([allowlist()], targets(secret: "anything"))
    end
  end

  defp allowlist(opts \\ []) do
    stopwords = Keyword.get(opts, :stopwords, [])

    %{
      paths: Keyword.get(opts, :paths, []),
      regexes: Keyword.get(opts, :regexes, []),
      stopword_pattern: stopwords != [] && :binary.compile_pattern(stopwords),
      regex_target: Keyword.get(opts, :regex_target, :secret),
      condition: Keyword.get(opts, :condition, :or)
    }
  end

  defp targets(opts) do
    secret = Keyword.get(opts, :secret, "secret")

    %{
      path: Keyword.get(opts, :path, "lib/app.ex"),
      secret: secret,
      match: Keyword.get(opts, :match, secret),
      line: Keyword.get(opts, :line, secret)
    }
  end
end
