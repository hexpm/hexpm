## Dependency policies and cooldowns

Two related features help organizations and projects defend against supply-chain attacks by gating which package versions Hex considers during dependency resolution. **Cooldown** is purely temporal — a minimum age a release must have before it becomes eligible. **Policies** are signed, org-published rules that can additionally block releases based on security advisories or retirement reasons.

The two features compose. A project can use either on its own, or both at once.

### Dependency cooldown

The `cooldown` setting tells Hex to ignore releases that haven't been visible long enough for the community to flag them as malicious or broken. Newly-published versions only become eligible for resolution once they reach the configured minimum age.

#### Configuration

Set the `cooldown` key in your `mix.exs`, via the `HEX_COOLDOWN` environment variable, or with `mix hex.config`. Valid values are durations like `"7d"`, `"2w"`, `"1mo"`, or `"0d"` (the default — no cooldown).

```elixir
# mix.exs
defp project() do
  [
    hex: [cooldown: "7d"]
  ]
end
```

```nohighlight
$ HEX_COOLDOWN=14d mix deps.get
```

```nohighlight
$ mix hex.config cooldown 7d
```

#### Excluding repositories

The `cooldown_exclude_repos` setting lists repositories that bypass cooldown entirely — useful when an organization publishes hotfixes to its own repository and wants to consume them without delay.

```elixir
# mix.exs
defp project() do
  [
    hex: [cooldown_exclude_repos: ["hexpm:myorg"]]
  ]
end
```

```nohighlight
$ HEX_COOLDOWN_EXCLUDE_REPOS=hexpm:myorg mix deps.get
```

#### Behavior

Cooldown filters candidates at resolution time. The lockfile is trusted on install — versions in the lockfile are not re-filtered. Versions held back by cooldown are reported in the resolution summary, so it is always clear which versions were filtered and why.

### Dependency policies

A *policy* is a signed payload an organization admin publishes from the org's `Policies` dashboard. The Hex client honors the active policy set at resolution time. A policy is configured *per repository* — one tab for `hexpm` (public packages) and one for the organization's own repository — so public and private dependencies can be governed independently.

Public policies are free on hex.pm and may be referenced by any project. Private policies require a paid organization and are only visible to organization members.

#### What a policy can declare

A policy has a **visibility** (`public` so any project can opt in, or `private` for organization members only). For each repository it governs, the policy carries a **restriction** and a list of **overrides**.

The **restriction** applies to every release from that repository:

  * **Advisory rule** — block releases with a security advisory at or above a chosen severity (`low`, `medium`, `high`, `critical`).
  * **Retirement rule** — block releases retired for any of the selected reasons (`security`, `invalid`, `deprecated`, `renamed`, `other`).
  * **Cooldown** — a minimum release age contributed by the policy.

**Overrides** are the final say for individual packages and take priority over the restriction:

  * An **allow** override installs the package and skips the restriction entirely. With no version requirement it lets every release through, so add a requirement (e.g. `== 1.7.10`) to limit it to specific releases.
  * A **deny** override blocks the package.
  * When several overrides match a release, the one with the most specific version requirement wins.

#### How a release is resolved

For each candidate release, the matching repository tab is evaluated in order:

  1. **Overrides** — an allow override installs the release and skips the restriction; a deny override blocks it.
  2. **Restriction** — any release not settled by an override must clear the cooldown, advisory, and retirement limits.

Releases already in a project's lockfile are trusted and are never filtered.

#### Creating a policy

Org admins create and edit policies under the `Policies` tab in the [organization dashboard](/dashboard). Each repository is configured on its own tab. Every change is recorded in the org's audit log and re-uploaded as a signed payload that travels with every developer who opts in.

#### Opting in

A project opts in via one of three sources. All three compose via AND — no source can subtract policies contributed by another.

In `mix.exs`:

```elixir
# lib/<app>/mix.exs
defp project() do
  [
    app: :my_app,
    version: "0.1.0",
    hex: [
      policy: [repo: "myorg", name: "strict-prod"]
    ]
  ]
end
```

Via environment variable (comma-separated for multiple policies):

```nohighlight
$ HEX_POLICY=myorg/strict-prod mix deps.get
```

Via `mix hex.config`:

```nohighlight
$ mix hex.config policy myorg/strict-prod
```

#### Inspecting the active set

The `mix hex.policy` task summarizes the policies currently in effect:

```nohighlight
$ mix hex.policy
$ mix hex.policy show
$ mix hex.policy why PACKAGE
```

`show` (the default) prints the per-policy state — visibility, source, and the restriction and overrides configured for each repository — along with the effective cooldown across all policies plus local config. `why PACKAGE` walks every version of the named package in the registry and prints which versions are blocked, by which policy, and for what reason.

#### Caching and fail-open

Each policy is cached on disk independently. On fetch failure — network blip, registry outage, signature mismatch — Hex falls back to the last-known-good cached payload and prints a stale warning. A per-policy maximum staleness of 30 days hard-fails resolution for that policy, capping how long a network adversary could suppress a refresh.

### How cooldown and policies interact

A project that uses both features gets the intersection. Policies that declare their own cooldown participate in the effective cooldown via strictest-wins — local config can only make it stricter, never weaker. Setting `HEX_COOLDOWN=0` only disables the local contribution and cannot override a cooldown imposed by an active policy.
