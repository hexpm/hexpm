defmodule Hexpm.SecretScan.ScannerTest do
  use ExUnit.Case, async: true

  alias Hexpm.SecretScan.Scanner

  @github_token "ghp_" <> "016Cq2mKvXbNzR8dLpWyTuAeH3jFgS4iOU7Q"
  @other_token "ghp_" <> "9zXwVuTsRqPoNmLkJiHgFeDcBa87654321Zy"
  @slack_token "xoxb-" <> "2839471028374-2938471029384-KdmSlwoeIrufJdnPqoWzLamx"
  @chunk_size 262_144
  @carry_size 65_536

  setup do
    dir = Path.join(System.tmp_dir!(), "secret-scan-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  describe "scan_files/2" do
    test "finds credentials and reports where they are", %{dir: dir} do
      write(dir, ".env", """
      GITHUB_TOKEN=#{@github_token}
      NOTHING=hello-world
      SLACK=#{@slack_token}
      """)

      assert {findings, false} = Scanner.scan_files(dir, [".env"])
      assert [github, slack] = findings

      assert github.rule == "github-pat"
      assert github.file_path == ".env"
      assert github.line == 1
      assert slack.rule == "slack-bot-token"
      assert slack.line == 3
    end

    test "never keeps the credential itself", %{dir: dir} do
      write(dir, ".env", "GITHUB_TOKEN=#{@github_token}\n")

      assert {[finding], false} = Scanner.scan_files(dir, [".env"])

      refute finding.preview =~ @github_token
      assert finding.preview == "ghp_************OU7Q"

      secret = Application.fetch_env!(:hexpm, :secret)
      assert finding.fingerprint == :crypto.mac(:hmac, :sha256, secret, @github_token)
      refute inspect(finding) =~ @github_token
    end

    test "leaves documented example values alone", %{dir: dir} do
      write(dir, "README.md", """
      Set your key:

          export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
      """)

      assert {[], false} = Scanner.scan_files(dir, ["README.md"])
    end

    test "still suppresses the example keys the refresh task rewrote", %{dir: dir} do
      # These live in gitleaks' gcp-api-key allowlist, which the refresh task
      # rewrites a byte of so GitHub does not alert on our copy of the config.
      # The rewrite is regex-equivalent only if the entry still suppresses.
      allowlisted = "AIza" <> "Syabcdefghijklmnopqrstuvwxyz1234567"
      other = "AIza" <> "SyC7vK2mQpX9dLnR4tW8jH3bF6gY1sA0eZu"

      write(dir, "allowlisted.ex", ~s|key = "#{allowlisted}"\n|)
      write(dir, "other.ex", ~s|key = "#{other}"\n|)

      assert {[], false} = Scanner.scan_files(dir, ["allowlisted.ex"], scope: :all)

      assert {[%{rule: "gcp-api-key"}], false} =
               Scanner.scan_files(dir, ["other.ex"], scope: :all)
    end

    test "skips paths the global allowlist excludes", %{dir: dir} do
      write(dir, "logo.png", "GITHUB_TOKEN=#{@github_token}")
      write(dir, "node_modules/pkg/index.js", "const t = \"#{@github_token}\"")

      assert {[], false} = Scanner.scan_files(dir, ["logo.png", "node_modules/pkg/index.js"])
    end

    test "reports one finding per credential, not one per rule", %{dir: dir} do
      # generic-api-key matches the same value as the specific rule.
      write(dir, ".env", "GITHUB_TOKEN=#{@github_token}\n")

      assert {[finding], false} = Scanner.scan_files(dir, [".env"])
      assert finding.rule == "github-pat"
    end

    test "reports one finding for a credential pasted into several files", %{dir: dir} do
      write(dir, ".env", "GITHUB_TOKEN=#{@github_token}\n")
      write(dir, "config/prod.exs", "token = \"#{@github_token}\"\n")

      assert {[finding], false} = Scanner.scan_files(dir, [".env", "config/prod.exs"])
      assert finding.file_path == ".env"
    end

    test "scans bytes that are not text", %{dir: dir} do
      write(dir, "priv/blob.dat", <<0, 1, 2, 0xFF>> <> @github_token <> <<0, 0xFE>>)

      assert {[finding], false} = Scanner.scan_files(dir, ["priv/blob.dat"])
      assert finding.rule == "github-pat"
    end

    test "matches rules that fire on the filename alone", %{dir: dir} do
      write(dir, "certs/keystore.p12", "not really a keystore")

      assert {[finding], false} = Scanner.scan_files(dir, ["certs/keystore.p12"], scope: :all)
      assert finding.rule == "pkcs12-file"
      assert finding.line == 1
    end

    test "caps findings and says so", %{dir: dir} do
      body =
        Enum.map_join(1..120, "\n", fn n ->
          "TOKEN_#{n}=ghp_016Cq2mKvXbNzR8dLpWyTuAeH3jFg#{String.pad_leading("#{n}", 4, "0")}"
        end)

      write(dir, ".env", body)

      assert {findings, true} = Scanner.scan_files(dir, [".env"], scope: :all)
      assert length(findings) == 100
    end
  end

  describe "window boundaries" do
    test "a credential is found exactly once wherever it falls", %{dir: dir} do
      line = "GITHUB_TOKEN=#{@github_token}\n"

      offsets = [
        0,
        @chunk_size - byte_size(line) - 1,
        @chunk_size - 20,
        @chunk_size - 1,
        @chunk_size,
        @chunk_size + 5,
        2 * @chunk_size - 20
      ]

      for offset <- offsets do
        path = "at_#{offset}.txt"
        write(dir, path, String.duplicate("x", offset) <> line <> String.duplicate("y", 100_000))

        assert {findings, false} = Scanner.scan_files(dir, [path])
        assert [finding] = findings, "expected one finding with the token at byte #{offset + 13}"
        assert finding.byte_offset == offset + 13
        assert finding.rule == "github-pat"
      end
    end

    test "line numbers keep counting across windows", %{dir: dir} do
      filler = String.duplicate("padding\n", div(@chunk_size, 8))
      write(dir, "big.txt", filler <> "GITHUB_TOKEN=#{@github_token}\n")

      assert {[finding], false} = Scanner.scan_files(dir, ["big.txt"])
      assert finding.line == div(@chunk_size, 8) + 1
    end

    test "a match too long to fit in a window is the documented blind spot", %{dir: dir} do
      # private-key matches from BEGIN to END, so an absurd block cannot fit in
      # any single window and is missed. Anything under the carry is guaranteed
      # to be found; between the two it depends on where the block lands.
      pem = fn lines ->
        "-----BEGIN RSA PRIVATE KEY-----\n" <>
          String.duplicate("QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVowMTIzNDU2Nzg5\n", lines) <>
          "-----END RSA PRIVATE KEY-----\n"
      end

      # An RSA-4096 key is about 3 KB, so a real one is always in this range.
      small = pem.(40)
      assert byte_size(small) < @carry_size
      write(dir, "small.pem", small)
      assert {[finding], false} = Scanner.scan_files(dir, ["small.pem"], scope: :all)
      assert finding.rule == "private-key"

      huge = pem.(10_000)
      assert byte_size(huge) > @chunk_size + @carry_size
      write(dir, "huge.pem", huge)
      assert {[], false} = Scanner.scan_files(dir, ["huge.pem"], scope: :all)
    end
  end

  describe "resource limits" do
    test "one repeated credential does not build a finding per occurrence", %{dir: dir} do
      # ~6000 matches in one file. Both the finding list and the seen set have
      # to stay bounded by the answer, not by the file.
      write(dir, "keys.txt", String.duplicate("AKIA" <> "Q2ZW7XKL3M4NPRSU\n", 6_000))

      assert {findings, true} = Scanner.scan_files(dir, ["keys.txt"])
      # All the same value, so it dedupes to one.
      assert [%{rule: "aws-access-token"}] = findings
    end

    test "an unreadable file does not take the release's scan with it", %{dir: dir} do
      write(dir, "good.env", "GITHUB_TOKEN=#{@github_token}\n")
      File.mkdir_p!(Path.join(dir, "adirectory"))

      log =
        Hexpm.TestHelpers.capture_debug_log(fn ->
          assert {[finding], _} = Scanner.scan_files(dir, ["good.env", "adirectory"])
          assert finding.rule == "github-pat"
        end)

      assert log =~ "could not read adirectory"
    end

    test "refuses a path that leaves the release", %{dir: dir} do
      log =
        Hexpm.TestHelpers.capture_debug_log(fn ->
          assert Scanner.scan_file(dir, "../../../etc/passwd") == []
        end)

      assert log =~ "not a relative path inside the release"
    end
  end

  describe "values that are not text" do
    test "a preview never carries a control byte or a broken code point" do
      secret = <<0, 1, 0xFF, 0xFE>> <> String.duplicate("a", 20) <> <<9, 0, 0xC3, 0x28>>
      preview = Scanner.redact(secret)

      assert String.valid?(preview)
      refute preview =~ ~r/[[:cntrl:]]/u
    end

    test "a file name with a newline in it cannot write its own email line", %{dir: dir} do
      # The name comes from a tar entry the publisher chose and the finding goes
      # into a plain text mail to the owners.
      path = "ke\nystore.p12"
      write(dir, path, "not really a keystore")

      assert {[finding], _} = Scanner.scan_files(dir, [path], scope: :all)
      assert finding.rule == "pkcs12-file"
      assert finding.file_path == "ke�ystore.p12"
      assert finding.preview == "ke�ystore.p12"
    end
  end

  describe "ignore globs and scope" do
    test "ignore globs suppress matching paths", %{dir: dir} do
      write(dir, "lib/app.ex", "T=#{@github_token}\n")
      write(dir, "test/fixtures/leak.env", "T=#{@github_token}\n")

      assert {[finding], _} =
               Scanner.scan_files(dir, ["lib/app.ex", "test/fixtures/leak.env"],
                 ignore: ["test/fixtures/**"]
               )

      assert finding.file_path == "lib/app.ex"
    end

    test "a /**/ glob matches the directory it names as well", %{dir: dir} do
      write(dir, "src/a.env", "T=#{@github_token}\n")
      write(dir, "src/nested/b.env", "T=#{@slack_token}\n")
      write(dir, "lib/c.env", "T=#{@other_token}\n")

      assert {[finding], _} =
               Scanner.scan_files(dir, ["src/a.env", "src/nested/b.env", "lib/c.env"],
                 ignore: ["src/**/*.env"]
               )

      assert finding.file_path == "lib/c.env"
    end

    test "a leading **/ glob reaches the root as well", %{dir: dir} do
      write(dir, "a.pem", "T=#{@github_token}\n")
      write(dir, "priv/certs/b.pem", "T=#{@slack_token}\n")
      write(dir, "c.env", "T=#{@other_token}\n")

      assert {[finding], _} =
               Scanner.scan_files(dir, ["a.pem", "priv/certs/b.pem", "c.env"],
                 ignore: ["**/*.pem"]
               )

      assert finding.file_path == "c.env"
    end

    test "a notify finding survives truncation ahead of non-notify noise", %{dir: dir} do
      noise =
        Enum.map_join(1..300, "\n", fn n ->
          value = :md5 |> :crypto.hash("#{n}") |> Base.encode16()
          ~s|password_#{n} = "#{value}"|
        end)

      write(dir, "bundle.js", noise)
      write(dir, "config/prod.exs", "aws = \"AKIA" <> "3NFXBQ7ZK2VYWLDM\"\n")

      assert {findings, true} =
               Scanner.scan_files(dir, ["bundle.js", "config/prod.exs"], scope: :all)

      assert length(findings) == 100
      assert Enum.any?(findings, &(&1.rule == "aws-access-token"))
    end
  end

  describe "gitleaks compatibility" do
    test "uses the first non-empty capture group, not group one", %{dir: dir} do
      # atlassian-api-token is an alternation with a group per branch. Taking
      # group 1 unconditionally dropped every modern ATATT3 token, and that
      # rule sends email.
      token =
        "ATATT3" <> binary_part(String.duplicate("aB3xY7zQ9wE2rT5yU8iO1pA4sD6fG0hJ", 6), 0, 186)

      write(dir, "config/prod.exs", ~s|token = "#{token}"\n|)

      assert {findings, _} = Scanner.scan_files(dir, ["config/prod.exs"], scope: :all)
      assert Enum.any?(findings, &(&1.rule == "atlassian-api-token"))
    end

    test "honours an inline gitleaks:allow", %{dir: dir} do
      write(dir, "fixtures.txt", "TOKEN=#{@github_token} # gitleaks:allow\n")

      assert {[], false} = Scanner.scan_files(dir, ["fixtures.txt"])
    end

    test "the entropy floor is exclusive", %{dir: dir} do
      # curl-auth-header's floor is 2.75 and this secret is exactly 2.75.
      write(dir, "deploy.sh", ~s|curl -H "Authorization: Basic aabcdefg" https://e.com\n|)

      assert {[], false} = Scanner.scan_files(dir, ["deploy.sh"])
    end

    test "a path finding cannot collapse into a content finding", %{dir: dir} do
      write(dir, "Xk7Qm2Pw9v.p12", "binary")
      write(dir, "a.exs", ~s|api_key = "Xk7Qm2Pw9v.p12"\n|)

      assert {findings, _} = Scanner.scan_files(dir, ["Xk7Qm2Pw9v.p12", "a.exs"], scope: :all)
      assert length(findings) == 2
    end
  end

  describe "scan_content/2" do
    test "agrees with reading the same bytes off disk", %{dir: dir} do
      line = "GITHUB_TOKEN=#{@github_token}\n"

      bodies = [
        {"empty.txt", ""},
        {"one_line.txt", line},
        {"clean.ex", "defmodule App do\nend\n"},
        {"binary.dat", <<0, 0xFF>> <> line <> <<0xFE>>},
        {"straddles.txt", String.duplicate("x", @chunk_size - 20) <> line},
        {"multi.txt",
         String.duplicate("padding\n", 40_000) <> line <> String.duplicate("z\n", 40_000)}
      ]

      for {path, body} <- bodies do
        write(dir, path, body)

        assert Scanner.scan_file(dir, path) == Scanner.scan_content(path, body),
               "disk and memory disagreed on #{path}"
      end
    end
  end

  describe "redact/1" do
    test "keeps the ends and fixes the width of the mask" do
      # Nothing at all from a short secret: the row also carries a sha256 HMAC,
      # so revealing both ends of a ten character value leaves two characters
      # to brute force against it.
      assert Scanner.redact("short") == "*****"
      assert Scanner.redact("123456789") == "*********"
      assert Scanner.redact("0123456789ab") == "01************ab"
      assert Scanner.redact(String.duplicate("a", 500)) == "aaaa************aaaa"
    end
  end

  defp write(dir, path, contents) do
    full = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, contents)
  end
end
