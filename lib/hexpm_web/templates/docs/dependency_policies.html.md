## Dependency policies and cooldowns

Two related features help organizations and projects defend against supply-chain attacks by gating which package versions Hex considers during dependency resolution. **Cooldown** is purely temporal — a minimum age a release must have before it becomes eligible. **Policies** are signed, org-published rules that can additionally block releases based on security advisories or retirement reasons.

The two features compose. A project can use either on its own, or both at once.

### Dependency cooldown

The `cooldown` setting tells Hex to ignore releases until they have been available for a configured amount of time. This creates a review window in which suspicious or broken releases may be reported before they are selected by dependency resolution.

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

A *policy* is a signed payload an organization admin publishes from the org's `Policies` dashboard. The Hex client honors the active policy at resolution time. A policy is configured *per repository* — one tab for `hexpm` (public packages) and one for the organization's own repository — so public and private dependencies can be governed independently.

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

A project has exactly one active policy. It is configured like any other Hex setting, with the usual precedence: the `HEX_POLICY` environment variable, then `mix.exs`, then the global config.

In `mix.exs`, with `org:` for a hexpm organization or `repo:` for any other configured repository:

```elixir
# mix.exs
defp project() do
  [
    app: :my_app,
    version: "0.1.0",
    hex: [
      policy: [org: "myorg", name: "strict-prod"]
    ]
  ]
end
```

Via environment variable, as a `REPO/NAME` pair. It overrides the other sources for the invocation, and an empty value disables the configured policy:

```nohighlight
$ HEX_POLICY=hexpm:myorg/strict-prod mix deps.get
$ HEX_POLICY= mix deps.get
```

Via `mix hex.config`:

```nohighlight
$ mix hex.config policy hexpm:myorg/strict-prod
```

Policies live under an organization repository (`hexpm:myorg`) or a self-hosted repository; the global `hexpm` repository itself has no policies.

#### Resolution output

After a successful resolution `mix deps.get` prints a summary with the active policy, the cooldown it imposes, and the candidate versions it hid, capped at the five newest per package:

```nohighlight
Active policy: hexpm:myorg/strict-prod
Effective cooldown: 14d (hexpm:myorg/strict-prod)
Policy hid 7 candidate versions:
  phoenix 1.8.1 — cooldown 14d; eligible 2026-06-18
  plug 1.18.0 — advisory ≥ high
  ...and 5 more — run `mix hex.policy why plug`
```

When resolution fails and the policy hid versions of an involved package, the solver's error message is followed by a note attributing the hidden versions, so a "no compatible versions" failure explains itself.

#### Inspecting the active policy

The `mix hex.policy` task summarizes the policy currently in effect:

```nohighlight
$ mix hex.policy
$ mix hex.policy show
$ mix hex.policy why PACKAGE
```

`show` (the default) prints the active policy's visibility, the restriction and overrides configured for each repository, and the effective cooldown across the policy and local config. `why PACKAGE` (or `why REPO/PACKAGE`) walks every version of the named package in the registry and prints which versions are blocked and for what reason — the uncapped view of what the resolution summary reports.

#### Caching and failure behavior

A policy is an enforcement feature, so Hex fails closed: a malformed policy configuration or a policy that cannot be loaded aborts resolution instead of resolving unenforced.

Fetched policies are stored in the local registry cache. When a refresh fails — network error, registry outage — and a previously fetched copy is cached, Hex prints an error and continues with the cached copy; without a cached copy resolution aborts. In offline mode the cached copy is used directly.

### How cooldown and policies interact

A project that uses both features gets the intersection. A policy that declares its own cooldown participates in the effective cooldown via strictest-wins — local config can only make it stricter, never weaker. Setting `HEX_COOLDOWN=0` only disables the local contribution and cannot override a cooldown imposed by an active policy.
