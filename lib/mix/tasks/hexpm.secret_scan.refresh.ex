defmodule Mix.Tasks.Hexpm.SecretScan.Refresh do
  @shortdoc "Refreshes the vendored gitleaks secret-scanning ruleset"

  @moduledoc """
  Rewrites `data/secret_scan/gitleaks.toml` and `LICENSE.gitleaks` from the
  latest gitleaks release and prints the commit it pulled.

  Update the commit line in `data/secret_scan/README.md` to match, then run the
  tests; `rules_test.exs` fails loudly if the config changed shape.

      mix hexpm.secret_scan.refresh
  """
  use Mix.Task

  @dir "data/secret_scan"
  @raw "https://raw.githubusercontent.com/gitleaks/gitleaks/master"
  @commits "https://api.github.com/repos/gitleaks/gitleaks/commits?path=config/gitleaks.toml&per_page=1"

  # Shapes GitHub secret scanning reports. Each one is anchored tightly enough
  # that it only matches a written-out key, never a rule's regex: every rule
  # puts a metacharacter straight after its prefix.
  @literals [
    ~r/AIza[0-9A-Za-z_-]{35}/,
    ~r/gh[oprsu]_[0-9A-Za-z]{36}/,
    ~r/xox[baprs]-[0-9A-Za-z]{10,}-[0-9A-Za-z-]{10,}/,
    ~r/AKIA[0-9A-Z]{16}/
  ]

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:req)

    write("#{@raw}/config/gitleaks.toml", Path.join(@dir, "gitleaks.toml"), &defang/1)
    write("#{@raw}/LICENSE", Path.join(@dir, "LICENSE.gitleaks"))

    Mix.shell().info("Vendored gitleaks ruleset from #{latest_commit()}.")
    Mix.shell().info("Update the commit in #{@dir}/README.md and run `mix test`.")
  end

  @doc """
  Wraps the last byte of any literal credential in a character class.

  gitleaks allowlists example keys by writing them out in full, so vendoring
  the config puts strings like a GCP key into our repository and GitHub's own
  secret scanning opens an alert for each one. The entries are regexes, so
  `[7]` and `7` are the same pattern and the allowlist keeps working, but the
  file no longer holds a contiguous literal for a scanner to match.

  A shape upstream adds that is not listed here gets alerted on again, and the
  fix is another entry.
  """
  def defang(toml) do
    Enum.reduce(@literals, toml, fn pattern, acc ->
      Regex.replace(pattern, acc, fn match ->
        {head, <<last::binary-size(1)>>} = String.split_at(match, -1)
        "#{head}[#{last}]"
      end)
    end)
  end

  defp write(url, path, transform \\ & &1) do
    %{status: 200, body: body} = Req.get!(url, decode_body: false)
    body = transform.(body)
    File.write!(path, body)
    Mix.shell().info("wrote #{path} (#{byte_size(body)} bytes)")
  end

  defp latest_commit do
    case Req.get(@commits) do
      {:ok, %{status: 200, body: [%{"sha" => sha, "commit" => commit} | _]}} ->
        "#{String.slice(sha, 0, 12)} (#{commit["committer"]["date"]})"

      _ ->
        "an unknown commit"
    end
  end
end
