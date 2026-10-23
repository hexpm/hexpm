## Dependency security

Hex has three controls for dependency risk: project settings, dependency policies, and lockfile audits. Project settings apply to one project. A dependency policy is a signed set of organization-managed rules. `mix hex.audit` checks the complete lockfile for security advisories and retired releases.

### Which dependencies each command checks

`mix deps.get` and `mix deps.update` first resolve dependencies and then report findings for the result. Resolution and warning output use different parts of the policy:

| Operation | What it checks |
| --- | --- |
| Dependency resolution | Candidate releases needed by the current operation. The active policy and project cooldown filter those candidates. Existing locked releases that remain unchanged aren't re-evaluated as candidates. |
| Resolution warnings | Advisories and retirements for dependencies reported by the current resolution. On Hex v2.6 or later, matching Allow, Advisory, and Retirement overrides suppress their corresponding warnings. Policy severity and retirement settings don't suppress these warnings. |
| Whole-lock audit | Every Hex dependency in `mix.lock`, including dependencies that didn't change in the last resolution. Use `mix hex.audit` in CI to check the complete lockfile against newly published advisories and retirement metadata. |

To fail `mix deps.get` or CI when a locked release is rejected, see [Checking the lockfile](#checking-the-lockfile).

### Choosing an audit mode

Every `mix hex.audit` mode checks the complete lockfile for advisories and retirements. The active policy changes the result only when a policy flag is passed. The policy flags require Hex v2.6 or later. Earlier versions ignore them and run a plain `mix hex.audit`. Run `mix hex.info` to see the installed version.

| Command | Findings reported |
| --- | --- |
| `mix hex.audit` | All advisory and retirement findings, regardless of the active policy. |
| `mix hex.audit --policy-overrides` | All findings except those accepted by a matching Allow, Advisory, or Retirement override. Policy severity and retirement settings aren't applied. |
| `mix hex.audit --policy` | Findings rejected after applying the active policy's advisory severity, retirement reasons, and overrides. |

Use `--policy-overrides` when every advisory and retirement should remain actionable unless an organization administrator explicitly accepted it. Use `--policy` when the audit should check compliance with the organization's full advisory and retirement policy.

Both policy flags require an active policy and can't be used together. Both fail when a locked package is matched by a Deny override. Project `ignore_advisories` and `ignore_retirements` settings are applied after policy evaluation and can't clear a Deny override. A denied package stays rejected until the policy changes. Policy-accepted and project-ignored findings appear in separate output sections and don't affect the exit status. `mix hex.audit --format sarif` leaves them out of the report, so GitHub code scanning closes their alerts. Audit modes don't check cooldown eligibility or general lockfile validity.

### Project controls

#### Release cooldown

The `cooldown` setting excludes releases from dependency resolution until they have been available for a configured amount of time. This creates time for a suspicious or broken release to be reported before Hex selects it.

Set `cooldown` in `mix.exs`, with `HEX_COOLDOWN`, or with `mix hex.config`. Valid durations include `"7d"`, `"2w"`, `"1mo"`, and `"0d"`. The default is `"0d"`, which disables the project cooldown.

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
$ mix hex.config cooldown 7d
```

`cooldown_exclude_repos` lists repositories that don't use the project cooldown. This can be used when an organization needs to consume releases from its own repository without delay.

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

Cooldown filters candidate releases during resolution. Existing locked releases aren't filtered. Versions excluded by cooldown are reported in the resolution summary.

If the version locked in `mix.lock` has a security advisory, the cooldown doesn't apply to that package or to the direct dependencies of the locked version. This lets `mix deps.update` move to the release that fixes the advisory, and to newer versions of the dependencies that release needs, while they're still inside the cooldown, so a project isn't held on a vulnerable version. A cooldown set by a dependency policy still applies.

#### Ignoring findings in one project

Use `ignore_advisories` and `ignore_retirements` (Hex v2.5.1 or later) when a finding has been reviewed for one project. These settings suppress matching warnings from `mix deps.get`, `mix deps.update`, and `mix hex.audit`. They are applied after policy evaluation, so they remain effective in both policy audit modes. They don't change which new releases the policy accepts.

```elixir
# mix.exs
defp project() do
  [
    hex: [
      ignore_advisories: ["CVE-2026-32686"],
      ignore_retirements: [:decimal, phoenix: "1.0.0"]
    ]
  ]
end
```

`ignore_advisories` matches an advisory's primary ID or any alias without regard to case. `ignore_retirements` accepts a package name or a package and exact version. An unused entry produces a warning during `mix hex.audit` so stale acknowledgements can be removed.

The same settings can be supplied as comma-separated environment variables. Retirement entries use `NAME` or `NAME@VERSION`.

```nohighlight
$ HEX_IGNORE_ADVISORIES=CVE-2026-32686 mix hex.audit
$ HEX_IGNORE_RETIREMENTS=decimal,phoenix@1.0.0 mix hex.audit
```

### Dependency policies

A dependency policy is a signed payload published by an organization admin from the organization's `Policies` dashboard. Hex applies the active policy during dependency resolution. Each policy has a tab for public `hexpm` packages and a tab for the organization's repository, so they can use different rules.

Public policies are free on hex.pm and can be selected by any project. Private policies require a paid organization and are available only to organization members.

#### Restrictions

A repository tab can declare these restrictions:

  * **Advisory severity:** block releases affected by an advisory at or above `low`, `medium`, `high`, or `critical`.
  * **Retirement reasons:** block releases retired as `security`, `invalid`, `deprecated`, `renamed`, or `other`.
  * **Policy cooldown:** require releases to have reached a minimum age.

When a project and its active policy both configure a cooldown, Hex uses the stricter duration. A project can increase a policy cooldown but can't reduce it. `HEX_COOLDOWN=0` disables the project contribution only.

#### Overrides

Overrides are package-scoped policy decisions. Allow, Deny, Retirement, and Cooldown overrides can include a version requirement. Every override can include an optional comment. Comments in public policies are included in the public signed policy.

  * **Allow** accepts matching releases without applying the policy restriction.
  * **Deny** rejects matching releases.
  * **Advisory** accepts one matching advisory for matching releases. The selected CVE or advisory ID matches the advisory's primary ID and aliases without regard to case. Its version scope is copied from the advisory when the override is created, so later expansions of the same advisory remain blocked outside the recorded scope.
  * **Retirement** accepts one retirement reason for matching releases.
  * **Cooldown** bypasses the policy cooldown for matching releases. It doesn't bypass a project cooldown.

Advisory, Retirement, and Cooldown overrides require Hex v2.6 or later. Hex v2.5 applies Allow and Deny overrides but ignores the other override types without a warning, so the restriction they would bypass still applies.

Advisory version scopes use Hex version-requirement syntax. A range uses `and` between its bounds, separate ranges use `or`, and `and` binds before `or`. Parentheses aren't supported.

Allow and Deny are evaluated first. When several matching Allow or Deny overrides exist, one with a version requirement is preferred over one without a requirement. When neither decides the release, advisory, retirement, and cooldown overrides remove only the restriction they name. Every other restriction still applies.

For example, an advisory override for `CVE-2026-4242` and package `decimal` accepts that advisory within the affected version ranges recorded when the override was created. If that CVE later expands to another version, the new range remains blocked. If `CVE-2026-4243` affects an already accepted version, the new advisory also remains active and the release is rejected when it meets the policy's advisory threshold.

A retirement override also matches the retirement reason. If a release changes from `deprecated` to `security`, an override for `deprecated` no longer accepts it. Editing the retirement message without changing its reason doesn't invalidate the override.

Malformed or unknown overrides are ignored. They can't accept a release. Hex v2.6 and later warn when a loaded policy contains override actions the installed client doesn't support, and `mix hex.policy show` lists the affected package, version scope, and numeric action.

#### Creating a policy

Organization admins create and edit policies under the `Policies` tab in the [organization dashboard](/dashboard). Each change is recorded in the organization's audit log and published as a new signed policy revision.

#### Selecting a policy

A project has at most one active policy. Configuration precedence is `HEX_POLICY`, then `mix.exs`, then global Hex configuration.

In `mix.exs`, use `org:` for a hex.pm organization or `repo:` for another configured repository:

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

`HEX_POLICY` uses a `REPO/NAME` value. An empty value disables the configured policy for that invocation.

```nohighlight
$ HEX_POLICY=hexpm:myorg/strict-prod mix deps.get
$ HEX_POLICY= mix deps.get
$ mix hex.config policy hexpm:myorg/strict-prod
```

Policies are stored under an organization repository such as `hexpm:myorg`, or under a self-hosted repository. The public `hexpm` repository doesn't own policies.

#### Resolution output

After dependency resolution, Hex prints the active policy, its cooldown contribution, and candidate versions excluded by the policy. The summary shows at most the five newest excluded versions for each package.

```nohighlight
Active policy: hexpm:myorg/strict-prod
Effective cooldown: 14d (hexpm:myorg/strict-prod)
Policy hid 7 candidate versions:
  phoenix 1.8.1 - cooldown 14d; eligible 2026-06-18
  plug 1.18.0 - advisory >= high
  ...and 5 more - run `mix hex.policy why plug`
```

If resolution fails because the policy excluded compatible versions, the solver error includes the relevant policy reasons.

#### Inspecting the active policy

```nohighlight
$ mix hex.policy
$ mix hex.policy show
$ mix hex.policy why PACKAGE
```

`show`, which is the default, prints the policy visibility, restrictions, overrides, and effective cooldown. Hex v2.6 and later also print override comments. `why PACKAGE` or `why REPO/PACKAGE` evaluates every known version of the package and explains each policy decision.

#### Checking the lockfile

A release can become rejected after it was locked, when it gets a security advisory, is retired, or the policy adds a Deny override for it. Resolution keeps trusting the lockfile, so `mix deps.get` still installs it. `mix hex.audit --policy` reports it, see [Choosing an audit mode](#choosing-an-audit-mode).

To make `mix deps.get` and `mix deps.update` fail instead, enable `policy_enforce_lock`. After resolving dependencies they run the same check as `mix hex.audit --policy`, and when it reports anything they fail before writing `mix.lock` or fetching packages. `policy_enforce_lock` requires Hex v2.6 or later. Earlier versions ignore it, so `mix deps.get` doesn't fail.

```elixir
# mix.exs
defp project() do
  [
    hex: [
      policy: [org: "myorg", name: "strict-prod"],
      policy_enforce_lock: true
    ]
  ]
end
```

```nohighlight
$ HEX_POLICY_ENFORCE_LOCK=1 mix deps.get
$ mix hex.config policy_enforce_lock true
```

An empty `HEX_POLICY_ENFORCE_LOCK` disables the check for one invocation. The setting has no effect without an active policy.

#### Caching and failures

Hex fails the command when the `policy` or `policy_enforce_lock` configuration is malformed or the active policy can't be loaded. In Hex v2.6 and later, every error the policy causes ends with how to run a single command without it, by setting `HEX_POLICY` to an empty value. If refreshing a policy fails and a previously fetched copy is cached, Hex reports the refresh failure and uses the cached copy. Without a cached copy, resolution aborts. Offline mode uses the cached copy.
