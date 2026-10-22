## Hex v2.6 released

<div class="subtitle"><time datetime="2026-10-22T00:00:00Z">22 October, 2026</time> · by Eric Meadows-Jönsson</div>

In Hex 2.6, a dependency policy override can accept a specific advisory, retirement reason or the cooldown for a package while the policy's other checks still apply, and you add these overrides in the policy editor on hex.pm. Policies can also check the packages already in `mix.lock`, in CI or on every `mix deps.get`. On hex.pm, organizations can now require two-factor authentication for their members.

This release also removes the ways of authenticating to organization repositories that Hex 2.5 deprecated, and hex.pm is starting to phase out user API keys with repository permissions. If you fetch private packages in CI, read [Organization authentication](#organization-authentication) before you upgrade.

Package builds are now reproducible, so the same project files give the same tarball on macOS and Linux, and `mix deps.get` is about twice as fast when there's little or nothing to fetch.

### Dependency policies

[Hex 2.5](/blog/hex-v25-released) added dependency policies, which decide what `mix deps.get` may add to a project. An allow override skips all of the policy's checks for the releases it matches, so before Hex 2.6 accepting one advisory in a policy also accepted every other advisory, retirement and cooldown for those releases. A policy override can now accept a specific advisory, a specific retirement reason or the cooldown for a package, and the policy's other checks still apply to it. Any override can have a comment saying why it's there.

Add them in the policy editor on hex.pm, which finds an advisory by its GHSA or CVE ID. An advisory override accepts the versions the advisory affected when you created the override, so versions the advisory adds later are still rejected. `mix hex.policy show` lists the overrides with their comments. Hex 2.5 ignores the new override types, so on Hex 2.5 the advisory, retirement or cooldown they accept is still enforced.

<img class="blog-img-light" src="/images/blog/027_policy_overrides.png" srcset="/images/blog/027_policy_overrides.png 2x" alt="Deny, advisory, retirement and cooldown overrides with comments in the hex.pm policy editor">
<img class="blog-img-dark" src="/images/blog/027_policy_overrides_dark.png" srcset="/images/blog/027_policy_overrides_dark.png 2x" alt="Deny, advisory, retirement and cooldown overrides with comments in the hex.pm policy editor">

Packages already in `mix.lock` were never checked against a policy. Hex 2.6 adds two ways to do that.

`mix hex.audit --policy` checks every Hex package in `mix.lock` against the active policy, including its advisory severity threshold, its retirement reasons and its overrides. It fails only for findings the policy rejects, lists the findings the policy accepts in their own sections and prints an override's comment next to each finding it accepted or denied. A locked package that a deny override matches fails the audit even if you've acknowledged its advisories with `ignore_advisories`. If you only want the overrides applied and every other advisory and retirement reported, use `mix hex.audit --policy-overrides` instead. Neither checks the cooldown.

<img src="/images/blog/027_audit_policy.png" srcset="/images/blog/027_audit_policy.png 2x" alt="mix hex.audit --policy listing rejected, accepted and denied packages">

To make `mix deps.get` and `mix deps.update` fail when a package in `mix.lock` is rejected by the policy, for example after it gets a new advisory, enable `policy_enforce_lock`. They then run the same check after resolving dependencies and fail before they write `mix.lock` or fetch anything:

```elixir
# mix.exs
def project do
  [
    # ...
    hex: [
      policy: [org: "myorg", name: "strict-prod"],
      policy_enforce_lock: true
    ]
  ]
end
```

You can also set it with `HEX_POLICY_ENFORCE_LOCK=1` or `mix hex.config policy_enforce_lock true`. Errors caused by a policy now end with the command to run without it, `HEX_POLICY= mix deps.get`, so someone blocked by a policy they didn't write can see how to bypass it. `mix deps.get` and `mix deps.update` have also stopped warning about advisories and retirements of releases that an override in your policy accepts.

`mix hex.audit` can write its results as SARIF with `--format sarif --output hex-audit.sarif`. Upload the file to GitHub code scanning and the findings show up in the repository's Security tab and as annotations on the `mix.lock` lines of pull requests. Findings you've acknowledged with `ignore_advisories` or `ignore_retirements`, or that your policy accepts, are left out of the file, so code scanning closes their alerts. `mix help hex.audit` has a complete GitHub Actions workflow. SARIF output requires OTP 27 or later.

<img class="blog-img-light" src="/images/blog/027_code_scanning.png" srcset="/images/blog/027_code_scanning.png 2x" alt="A Hex advisory shown as a GitHub code scanning alert on mix.lock">
<img class="blog-img-dark" src="/images/blog/027_code_scanning_dark.png" srcset="/images/blog/027_code_scanning_dark.png 2x" alt="A Hex advisory shown as a GitHub code scanning alert on mix.lock">

### Two-factor authentication for organizations

Organization admins can now require two-factor authentication for every member. An admin with 2FA enabled sets the requirement on the organization's Members page, either right away or after a transition of 1 to 30 days, and the page shows admins which members have enabled 2FA. Members without 2FA get an email when a transition is scheduled, reminders seven days and one day before the deadline, and an email when they lose access. From the deadline, a member without 2FA can't use the organization's dashboard pages or its API, and can't fetch its private packages and docs once their current token expires, within 30 minutes. They keep their membership and role, and get access back as soon as they enable 2FA. Once the requirement is scheduled, new members have to enable 2FA before they can accept an invitation. Keys owned by the organization aren't affected. See [Organization two-factor authentication](/docs/organization-tfa) for the details.

When `mix deps.get` or `mix deps.update` needs packages from an organization that requires 2FA and your `mix hex.user auth` session doesn't meet the requirement, Hex 2.6 names the organization and asks once whether to authenticate now. If you confirm, it opens hex.pm in your browser, and after you've enabled 2FA and pressed Enter it fetches the organization's packages. If you decline, it warns that the organization's packages won't be available. Earlier Hex versions report the missing access as a missing package or missing permissions.

### Organization authentication

[Hex 2.5](/blog/hex-v25-released) deprecated `mix hex.organization auth` without `--key`, and authenticating to organization repositories with keys stored on your machine or read from `HEX_REPOS_KEY`. Hex 2.6 drops support for all three:

  * `mix hex.organization auth ORGANIZATION` requires `--key`. It exchanges the key for a short-lived token and stores only the token, which Hex uses for about 25 minutes and doesn't refresh, so in CI run it right before fetching dependencies.
  * Keys that earlier Hex versions stored in `~/.hex/hex.config` are no longer used for organization repositories.
  * `HEX_REPOS_KEY` no longer gives access to organization repositories. It still authenticates to the hexpm repository and to mirrors set with `HEX_TRUSTED_MIRROR`.

For development, `mix hex.user auth` gives you access to all your organizations. For CI, generate an organization key with `mix hex.organization key ORGANIZATION generate` and pass it to `mix hex.organization auth ORGANIZATION --key KEY`.

With a mirror set with `HEX_MIRROR`, Hex 2.6 fetches organization packages from repo.hex.pm. With a mirror set with `HEX_TRUSTED_MIRROR`, it fetches them through the mirror.

hex.pm is also phasing out user API keys with repository permissions, because organization admins can't see or revoke them. hex.pm no longer creates new ones, so `mix hex.user auth` in Hex 2.3 and earlier and `mix hex.organization auth` without `--key` in Hex 2.5 and most earlier versions stop working, since both create one. When you use an existing key, Hex 2.4 and later print a warning with the date it stops working. On 20 January 2027, 90 days after this release, user keys stop giving access to organization repositories, whatever Hex version you run. Replace them with `mix hex.user auth` or an organization key before then. If `HEX_REPOS_KEY` holds a user key, remove it: from that date hex.pm refuses to exchange it, and every fetch fails, including public packages.

On 1 November 2026 hex.pm turns off Basic authentication on the API, as we [announced in July](/blog/deprecating-basic-auth), and stops letting API keys create API keys. From then on `mix hex.organization key ORGANIZATION generate` needs a sign-in with `mix hex.user auth`, with `HEX_API_KEY` unset. You can still create keys on the dashboard.

### Secret scanning

hex.pm scans published packages for leaked credentials, such as cloud provider keys and API tokens for services like GitHub, Slack and Stripe. When it finds one, it emails the package owners, the admins of an organization that owns the package and the publisher, so they can rotate the credential. The release isn't blocked or marked publicly, and hex.pm only stores a fingerprint and a masked preview of what it found.

If your package ships secret-like values on purpose, such as test fixtures, Hex 2.6 lets you exclude those paths with the `:secret_scan` package option. Earlier Hex versions leave the option out of the package.

```elixir
package: [
  # ...
  secret_scan: [ignore: ["test/fixtures/**"]]
]
```

API keys created on hex.pm now start with `hex_` and end with a checksum. The new format is in preparation for GitHub secret scanning, which hasn't been enabled for Hex keys yet. Once it is, hex.pm revokes keys that GitHub finds in public repositories and emails their owners. Older keys keep working.

### Reproducible package builds

Building the same project on two machines could give two different tarballs. The order files were listed on disk, the umask, how the file system reported permissions and Unicode file names, VM flags like `+fnl` and the zlib that OTP was linked against all ended up in the package. Hex 2.6 builds identical packages from identical project files, whether you publish from macOS or Linux and whichever Elixir and OTP versions you run.

That makes it possible to check a release on hex.pm against its source. Check out the commit the release was built from, install the Hex version recorded in the package's `build_env` metadata with `mix local.hex VERSION`, run `mix hex.build`, and compare the package checksum it prints with the checksum on the release's hex.pm page. The checksum still depends on the Hex version, so packages now record the Hex version that built them in the `build_env` field of their metadata. `mix hex.package fetch PACKAGE VERSION --unpack` puts the metadata in `hex_metadata.config`.

This only works for packages built with Hex 2.6 or later. It also assumes your `mix.exs` gives the same package configuration each time, so a version or file list computed from git or environment variables has to come out the same on the second build. Docs tarballs aren't covered.

Hex 2.6 also changes which files go into a package. Files that operating systems, editors and version control leave behind, such as `.DS_Store`, `.git`, `*~` and `*.orig`, are left out at any depth unless `:files` names them without wildcards. `_build`, `deps` and the package tarball itself are always left out, so `files: ["*"]` no longer packages your previous build. If you publish from Windows, where the file system doesn't store execute permissions, list the executable files with the new `:executables` package option. Run `mix hex.build --unpack` before your next release to see what goes into the package.

### Faster mix deps.get

We measured hex.pm's own project, which has 158 entries in `mix.lock`, on macOS with Elixir 1.20.4 and OTP 29.1.1. These are medians, comparing Hex 2.5.2 with a Hex 2.6 development build:

  * `mix deps.get --check-locked` offline went from 945 ms to 414 ms
  * `mix deps.get --check-locked` online, with no registry changes, went from 1,450 ms to 643 ms
  * Resolving dependencies in `mix deps.update --all` offline went from 451 ms to 22 ms
  * `mix deps.get` with an empty Hex cache and no `deps` directory went from 8.86 s to 7.53 s

One cause was repeated registry lookups. Resolving hex.pm's dependencies asked the registry for package versions 10,006 times, and now asks once per package. A bug since Hex 2.1.0 also meant cached registry files were never revalidated, so every run downloaded all of them again. For hex.pm's project that was 128 requests and 473 KB on every `mix deps.get`. Now all 128 come back as "not modified" without a body, which saves the 473 KB.

Fetching a large package uses less memory. Packages are written to disk as they download instead of being held in memory, and unpacked while other packages are still downloading. In three runs fetching and unpacking rocksdb, a 7.4 MB package, from a local mirror with the default concurrency, peak memory use was 159 to 167 MB, down from 261 to 408 MB. `http_concurrency` (`HEX_HTTP_CONCURRENCY`) now only limits package downloads, and registry files are fetched with four times that limit, 32 by default.

### Changes on hex.pm

Package diffs, the file browser and READMEs now work for packages in organization repositories, for members of the organization. Browse a release from the Files tab on its package page, or compare versions on the [diffs page](/diffs). Diffs and the file browser have moved to hex.pm, and links to diff.hex.pm and preview.hex.pm redirect there.

Package pages show the changelog, license, security policy and a few other documentation files next to the README, when the package has them in its root directory.

Every package page has a Report package link for reporting vulnerabilities, malware, spam and copyright infringement. Vulnerability reports go to the [Erlang Ecosystem Foundation CNA](https://cna.erlef.org), and other reports go to the hex.pm team.

Adding someone to an organization by username now sends them an invitation, and they only join if they accept it on their dashboard. Members can make their membership public in their profile settings, and it then shows on their profile and on the organization's Members tab. Every membership starts private.

We're testing single sign-on for organizations and Workload Identity, and each will get its own announcement when it's available to everyone. With single sign-on, organizations sign their members in through their identity provider and can provision members with SCIM. Workload Identity lets a GitHub Actions job exchange its OIDC token for a short-lived hex.pm token to publish packages and fetch private packages, without storing an API key.

### Other changes

  * Warnings go to standard error, so `mix hex.outdated --json` and other machine-readable output stay clean on standard output.
  * The diffs link that `mix hex.outdated` prints shows the right diff for packages in organization repositories. Hex 2.5 linked them as public packages, which showed a public package with the same name or failed.
  * `mix deps.get` no longer lists dependencies that didn't change, unless they're retired or have security advisories.
  * When Hex writes `~/.hex/hex.config`, which holds your API keys and OAuth tokens, it makes the file readable only by your user.

### Upgrading

Update Hex to the latest version by running `mix local.hex`. For the full list of changes see the [release notes](https://github.com/hexpm/hex/releases/tag/v2.6.0).
