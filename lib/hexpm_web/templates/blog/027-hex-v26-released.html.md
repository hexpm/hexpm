## Hex v2.6 released

<div class="subtitle"><time datetime="2026-10-23T00:00:00Z">23 October, 2026</time> · by Eric Meadows-Jönsson</div>

[Hex 2.5](/blog/hex-v25-released) was about making it harder for a malicious or compromised release to reach your system, with security advisories in your terminal, a release-age cooldown and dependency policies. Hex 2.6 and hex.pm continue that work. Policy overrides can now accept a specific advisory, retirement reason or the cooldown for a package, and policies can check the packages already in `mix.lock`. Organizations can require two-factor authentication, and organization repositories use short-lived tokens instead of keys stored on your machine. Package builds are now reproducible, so you can check a release on hex.pm against its source.

Hex 2.6 changes how you authenticate to organization repositories, and hex.pm is starting to phase out user API keys with repository permissions. If you fetch private packages in CI, read [Organization authentication](#organization-authentication) before you upgrade.

`mix deps.get` is also about twice as fast when there's little or nothing to fetch. The [security fixes](#security-fixes-since-hex-25) made since Hex 2.5 are listed at the end.

### Dependency policies

A dependency policy is a set of rules for which package releases a project may use. Organization admins write policies on hex.pm, and a project selects one in its Hex options:

```elixir
# mix.exs
def project do
  [
    # ...
    hex: [policy: [org: "myorg", name: "strict-prod"]]
  ]
end
```

When `mix deps.get` or `mix deps.update` resolves dependencies, Hex skips the releases the policy rejects and picks from the rest. A policy can reject releases that have a security advisory at or above a severity you choose, releases retired for reasons you choose, and releases published more recently than a cooldown period, which gives time for a malicious or broken release to be reported before your projects install it. Overrides make exceptions for a package or a range of its versions: an allow override accepts the releases whatever the rules say, and a deny override rejects them. Public policies are free and any project can use them. Private policies need a paid organization, and only its members can use them.

Until now, accepting an advisory you'd reviewed took an allow override, which also accepts every other advisory and retirement for those releases and lets them skip the cooldown. An override can now accept one advisory, one retirement reason or the policy's cooldown, and the policy's other rules still apply to the releases it matches. The policy editor finds an advisory by its GHSA or CVE ID, and the override covers the versions the advisory affected when you created it, so versions it adds later are still rejected. Any override can have a comment saying why it's there, which `mix hex.policy show` prints. Hex 2.5 ignores the new override types and keeps rejecting the releases they would accept.

<img class="blog-img-light" src="/images/blog/027_policy_overrides.png" srcset="/images/blog/027_policy_overrides.png 2x" alt="Deny, advisory, retirement and cooldown overrides with comments in the hex.pm policy editor">
<img class="blog-img-dark" src="/images/blog/027_policy_overrides_dark.png" srcset="/images/blog/027_policy_overrides_dark.png 2x" alt="Deny, advisory, retirement and cooldown overrides with comments in the hex.pm policy editor">

A policy only checks a release when Hex picks it, so a release already in `mix.lock` stays there after it gets an advisory, is retired or gets a deny override. `mix hex.audit` checks every Hex package in `mix.lock` for advisories and retirements, and `mix hex.audit --policy` now applies the active policy to what it finds: its advisory severity, its retirement reasons and its overrides. It fails only for findings the policy rejects, lists the findings the policy accepts in their own sections and prints an override's comment next to each finding it accepted or denied. A locked package that a deny override matches fails the audit even if you've acknowledged its advisories with `ignore_advisories`. To apply only the overrides and report every other advisory and retirement, use `mix hex.audit --policy-overrides`. Neither checks the cooldown.

<img src="/images/blog/027_audit_policy.png" srcset="/images/blog/027_audit_policy.png 2x" alt="mix hex.audit --policy listing rejected, accepted and denied packages">

To make `mix deps.get` and `mix deps.update` fail when a package in `mix.lock` is rejected by the policy, add `policy_enforce_lock: true` next to `policy` in the Hex options. They then run the `mix hex.audit --policy` check after resolving dependencies and fail before they write `mix.lock` or fetch anything. [Dependency policies](/docs/dependency-policies) lists the other ways to enable it.

Errors caused by a policy now end with the command to run without it, `HEX_POLICY= mix deps.get`, so someone blocked by a policy they didn't write can see how to bypass it. `mix deps.get` and `mix deps.update` have also stopped warning about advisories and retirements of releases that an override in your policy accepts.

`mix hex.audit` can write its results as SARIF with `--format sarif --output hex-audit.sarif`. Upload the file to GitHub code scanning and the findings show up in the repository's Security tab and as annotations on the `mix.lock` lines of pull requests. Findings you've acknowledged with `ignore_advisories` or `ignore_retirements` are left out of the file, and so are findings your policy accepts when you run `mix hex.audit --policy`. Code scanning then closes their alerts as fixed. `mix help hex.audit` has a complete GitHub Actions workflow. SARIF output requires OTP 27 or later.

<img class="blog-img-light" src="/images/blog/027_code_scanning.png" srcset="/images/blog/027_code_scanning.png 2x" alt="A Hex advisory shown as a GitHub code scanning alert on mix.lock">
<img class="blog-img-dark" src="/images/blog/027_code_scanning_dark.png" srcset="/images/blog/027_code_scanning_dark.png 2x" alt="A Hex advisory shown as a GitHub code scanning alert on mix.lock">

### Two-factor authentication for organizations

Organization admins can now require two-factor authentication for every member, so signing in as one of them takes more than a stolen password. An admin with 2FA enabled sets the requirement on the organization's Members page, either right away or after a transition of 1 to 30 days, and the page shows which members have enabled 2FA. From the deadline, members without 2FA can't use the organization's dashboard pages, API, private packages or docs. They keep their membership and role, and get access back as soon as they enable 2FA. Keys owned by the organization aren't affected. [Organization two-factor authentication](/docs/organization-tfa) covers the emails members get, invitations and the rest of the details.

When `mix deps.get` or `mix deps.update` needs packages from an organization that requires 2FA and your `mix hex.user auth` session doesn't meet the requirement, Hex 2.6 names the organization and offers to open hex.pm in your browser so you can enable 2FA, then fetches its packages. Earlier Hex versions report the missing access as a missing package or missing permissions.

### Organization authentication

Hex 2.6 no longer stores keys for organization repositories, because a stored key and every copy of it work until someone revokes the key. Authenticate in one of these ways:

  * On your own machine, `mix hex.user auth` signs you in and gives you access to all your organizations.
  * In CI, generate an organization key with `mix hex.organization key ORGANIZATION generate` and run `mix hex.organization auth ORGANIZATION --key KEY`. Hex exchanges the key for a token that expires within 30 minutes and stores only the token. It uses the token for about 25 minutes and doesn't refresh it, so run the command right before fetching dependencies.

These no longer give access to organization repositories:

  * `mix hex.organization auth ORGANIZATION` without `--key`.
  * Keys that earlier Hex versions stored in `~/.hex/hex.config`.
  * `HEX_REPOS_KEY`. It still authenticates to the hexpm repository and to mirrors set with `HEX_TRUSTED_MIRROR`.

hex.pm is also phasing out user API keys with repository permissions, because organization admins can't see or revoke them. hex.pm no longer creates them, so `mix hex.user auth` and `mix hex.organization auth` don't work on older Hex versions that create one. On 21 January 2027, 90 days after this release, existing user keys stop giving access to organization repositories, whatever Hex version you run. Replace them with `mix hex.user auth` or an organization key before then. If `HEX_REPOS_KEY` holds a user key, remove it: from that date hex.pm refuses to exchange it, and every fetch fails, including public packages.

On 1 November 2026 hex.pm turns off Basic authentication on the API, as we [announced in July](/blog/deprecating-basic-auth), and stops letting API keys create API keys. From then on `mix hex.organization key ORGANIZATION generate` needs a sign-in with `mix hex.user auth`, with `HEX_API_KEY` unset. You can still create keys on the dashboard.

### Secret scanning

Anyone can download a published package, including any credentials packaged by mistake. hex.pm now scans published packages for leaked credentials, such as cloud provider keys and API tokens for services like GitHub, Slack and Stripe. When it finds one, it emails the package owners, the admins of an organization that owns the package and the publisher, so they can rotate the credential. The release isn't blocked or marked publicly, and hex.pm only stores a fingerprint and a masked preview of what it found.

If your package ships secret-like values on purpose, such as test fixtures, Hex 2.6 lets you exclude those paths with the `:secret_scan` package option. Earlier Hex versions leave the option out of the package.

```elixir
package: [
  # ...
  secret_scan: [ignore: ["test/fixtures/**"]]
]
```

API keys created on hex.pm now start with `hex_` and end with a checksum. The new format is in preparation for GitHub secret scanning, which hasn't been enabled for Hex keys yet. Once it is, hex.pm revokes keys that GitHub finds in public repositories and emails their owners. Older keys keep working.

### Reproducible package builds

To check that a release on hex.pm was built from the source it claims, you have to build the same package yourself and compare. Until now, building the same project on two machines could give two different tarballs. The order files were listed on disk, the umask, how the file system reported permissions and Unicode file names, VM flags like `+fnl` and the zlib that OTP was linked against all ended up in the package. Hex 2.6 builds identical packages from identical project files, whether you publish from macOS or Linux and whichever Elixir and OTP versions you run.

To verify one, check out the commit the release was built from, install the Hex version recorded in the package's `build_env` metadata with `mix local.hex VERSION`, run `mix hex.build`, and compare the package checksum it prints with the checksum on the release's hex.pm page. The checksum still depends on the Hex version, so packages now record the Hex version that built them in the `build_env` field of their metadata. `mix hex.package fetch PACKAGE VERSION --unpack` puts the metadata in `hex_metadata.config`.

This only works for packages built with Hex 2.6 or later. It also assumes your `mix.exs` gives the same package configuration each time, so a version or file list computed from git or environment variables has to come out the same on the second build. Docs tarballs aren't covered.

Hex 2.6 also changes which files go into a package. Files that operating systems, editors and version control leave behind, such as `.DS_Store`, `.git`, `*~` and `*.orig`, are left out at any depth unless `:files` names them without wildcards. `_build`, `deps` and the package tarball itself are always left out, so `files: ["*"]` no longer packages your previous build. If you publish from Windows, where the file system doesn't store execute permissions, list the executable files with the new `:executables` package option. Run `mix hex.build --unpack` before your next release to see what goes into the package.

### Faster mix deps.get

We measured hex.pm's own project, which has 158 entries in `mix.lock`, on macOS with Elixir 1.20.4 and OTP 29.1.1. These are medians, comparing Hex 2.5.2 with a Hex 2.6 development build:

  * `mix deps.get --check-locked` offline went from 945 ms to 414 ms
  * `mix deps.get --check-locked` online, with no registry changes, went from 1,450 ms to 643 ms
  * Resolving dependencies in `mix deps.update --all` offline went from 451 ms to 22 ms
  * `mix deps.get` with an empty Hex cache and no `deps` directory went from 8.86 s to 7.53 s

One cause was repeated registry lookups. Resolving hex.pm's dependencies asked the registry for package versions 10,006 times, and now asks once per package. A bug since Hex 2.1.0 also meant cached registry files were never revalidated, so every run downloaded all of them again. For hex.pm's project that was 128 requests and 473 KB on every `mix deps.get`. Now all 128 come back as "not modified" without a body, which saves the 473 KB.

Fetching a large package uses less memory. Packages are written to disk as they download instead of being held in memory, and unpacked while other packages are still downloading. In three runs fetching and unpacking rocksdb, a 7.4 MB package, from a local mirror with the default concurrency, peak memory use was 159 to 167 MB, down from 261 to 408 MB.

### Changes on hex.pm

Package diffs, the file browser and READMEs now work for packages in organization repositories, for members of the organization. Browse a release from the Files tab on its package page, or compare versions on the [diffs page](/diffs). Diffs and the file browser have moved to hex.pm, and links to diff.hex.pm and preview.hex.pm redirect there.

Package pages show the changelog, license, security policy and a few other documentation files next to the README, when the package has them in its root directory.

Every package page has a Report package link for reporting vulnerabilities, malware, spam and copyright infringement. Vulnerability reports go to the [Erlang Ecosystem Foundation CNA](https://cna.erlef.org), and other reports go to the hex.pm team.

Adding someone to an organization by username now sends them an invitation, and they only join if they accept it on their dashboard. Members can make their membership public in their profile settings, and it then shows on their profile and on the organization's Members tab. Every membership starts private.

We're testing single sign-on for organizations and Workload Identity, and each will get its own announcement when it's available to everyone. With single sign-on, organizations sign their members in through their identity provider and can provision members with SCIM. Workload Identity lets a GitHub Actions job exchange its OIDC token for a short-lived hex.pm token to publish packages and fetch private packages, without storing an API key.

### Security fixes since Hex 2.5

Hex 2.5.2 and hex_core 0.20.0, released on 12 October, fixed eight vulnerabilities. Hex 2.6 includes all of these fixes. Peter Ullrich found seven of them, and Zach Daniel reported the terminal escape sequence injection.

  * [CVE-2026-96612](https://github.com/hexpm/hex/security/advisories/GHSA-2vjj-c5hr-6xc3) (high): path traversal through dependency app names.
  * [CVE-2026-105668](https://github.com/hexpm/hex/security/advisories/GHSA-pqhp-5x9x-69h7) (high): the release-age cooldown was lifted for a whole package when the locked release was retired.
  * [CVE-2026-105280](https://github.com/hexpm/hex/security/advisories/GHSA-98jr-23pm-vj7c) (medium): `mix hex.package fetch` wrote unverified package tarballs to standard output.
  * [CVE-2026-103503](https://github.com/hexpm/hex/security/advisories/GHSA-rw8q-hg7m-cxgr) (medium): Hex trusted its bundled CA certificates even when `cacerts_path` was set.
  * [CVE-2026-103502](https://github.com/hexpm/hex_core/security/advisories/GHSA-p26c-h8c2-rwqj) (medium): hex_core's default HTTP adapter didn't verify TLS certificates on OTP 24 and 25.
  * [CVE-2026-96618](https://github.com/hexpm/hex/security/advisories/GHSA-gf42-pg2f-63jp) (low): oversized or compressed responses from an untrusted mirror could exhaust memory and disk.
  * [CVE-2026-105274](https://github.com/hexpm/hex_core/security/advisories/GHSA-7c4r-cgf9-9jmq) (low): hex_core decompressed registry and API responses without a size limit. rebar3 3.27.3 also has the fix.
  * [CVE-2026-81856](https://github.com/hexpm/hex/security/advisories/GHSA-fpmj-3cxg-p766) (low): terminal escape sequences in server responses weren't neutralized.

Hex 2.5.4, released on 20 October, stopped trusting three emSign root certificates, which Mozilla removed from its root store. The private keys of eight eMudhra intermediate CAs that chain to one of them were compromised.

hex.pm fixed three vulnerabilities on the server, so you don't need to do anything for them. [CVE-2026-75542](https://github.com/hexpm/hexpm/security/advisories/GHSA-rfx8-w654-8cpr) (high) and [CVE-2026-75554](https://github.com/hexpm/hexpm/security/advisories/GHSA-24ww-j3f4-p49c) (low) are described in [Private package authorization vulnerabilities](/blog/private-package-authorization-vulnerabilities). In [CVE-2026-86698](https://github.com/hexpm/hexpm/security/advisories/GHSA-vmw7-7g2w-gw2f) (low), found by Peter Ullrich, the CDN accepted refresh tokens as credentials for private repositories.

### Other changes

  * Warnings go to standard error, so `mix hex.outdated --json` and other machine-readable output stay clean on standard output.
  * The diffs link that `mix hex.outdated` prints shows the right diff for packages in organization repositories. Hex 2.5 linked them as public packages, which showed a public package with the same name or failed.
  * `mix deps.get` no longer lists dependencies that didn't change, unless they're retired or have security advisories.
  * When Hex writes `~/.hex/hex.config`, which holds your API keys and OAuth tokens, it makes the file readable only by your user.

### Upgrading

Update Hex to the latest version by running `mix local.hex`. For the full list of changes see the [release notes](https://github.com/hexpm/hex/releases/tag/v2.6.0).
