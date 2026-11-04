## Announcing Workload Identity and staged publishing

<div class="subtitle"><time datetime="2026-11-03T00:00:00Z">3 November, 2026</time> · by Eric Meadows-Jönsson</div>

In the [Hex 2.6 announcement](/blog/hex-v26-released) we said we were testing Workload Identity. It's now available to every package and organization on hex.pm. Workload Identity, sometimes also known as "Trusted Publishing", lets a GitHub Actions job publish packages and fetch an organization's private packages without storing a key. It comes with staged publishing, which holds releases published with a key or a workload identity until a person with two-factor authentication approves them on hex.pm.

When you publish with your own account through `mix hex.user auth`, Hex asks for your 2FA code on every publish, so a stolen session can't publish by itself. A key has no second factor. Anyone who gets the key can publish a release that `mix deps.get` picks up as soon as the registry is updated. In September 2025 the [Shai-Hulud worm](https://github.blog/security/supply-chain-security/our-plan-for-a-more-secure-npm-supply-chain/) spread through npm this way. It stole npm tokens and other secrets, and used compromised maintainer accounts to add malicious install scripts to popular packages.

Workload Identity takes the key out of CI. Anyone who can push to the repository can still run the release workflow unless its GitHub environment requires a reviewer, so staged publishing holds what CI publishes until a person approves it with 2FA. We recommend publishing from CI with Workload Identity and turning on staged publishing for your packages, instead of publishing with keys.

### Workload Identity

A GitHub Actions job can request an OpenID Connect (OIDC) token from GitHub that names the repository, workflow and environment the job runs in. hex.pm checks the token against a workload identity you configured on the package, and returns a token that expires after 15 minutes and can only publish that package. There's no key in your repository secrets to leak or rotate.

Hex 2.6 does the exchange for you. When the job has the `id-token: write` permission and no `HEX_API_KEY` or other Hex credential is set, `mix hex.publish` exchanges the job's OIDC token and publishes with the token it gets back. This requires OTP 27 or later.

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: read
  id-token: write

jobs:
  publish:
    runs-on: ubuntu-latest
    # The GitHub environment the workload identity names
    environment: release
    steps:
      - uses: actions/checkout@v7
      - uses: erlef/setup-beam@v1
        with:
          otp-version: '28'
          elixir-version: '1.20'
      - run: mix deps.get
      - run: mix hex.publish --yes
```

To add a workload identity, open the package on hex.pm and go to Settings > Workload identities.

<img class="blog-img-light" src="/images/blog/028_workload_identity.png" srcset="/images/blog/028_workload_identity.png 2x" alt="The Add workload identity form on a package's settings, with repository owner acme, repository widget, workflow release.yml and environment release">
<img class="blog-img-dark" src="/images/blog/028_workload_identity_dark.png" srcset="/images/blog/028_workload_identity_dark.png 2x" alt="The Add workload identity form on a package's settings, with repository owner acme, repository widget, workflow release.yml and environment release">

A workload identity can't create a public package, so publish the first release of a new public package with your account or a key as before. Releases published with a workload identity show a Provenance card on the package page that links to the commit and the workflow run that published them.

GitHub Actions is the only CI provider we support for now. We plan to add more providers based on interest from users and the community.

### Organization workload identities

Organization admins configure workload identities for the whole organization on the Workload identities page of the organization dashboard. A `read` workload identity fetches the organization's private packages, and a `write` workload identity publishes its private packages, the public packages it owns, or both.

Hex 2.6 uses a `read` workload identity to fetch private dependencies in CI without an organization key. When a job with `id-token: write` has no organization key or `mix hex.user auth` session configured, Hex exchanges the job's OIDC token for a token that can fetch the organization's packages.

A recommended setup is one `read` workload identity without repositories, so every repository under your GitHub organization can fetch private dependencies, and one `write` workload identity naming the repositories that release packages. [Workload Identity](/docs/workload-identity) covers the rest.

### Staged publishing

Staged publishing holds releases and documentation published with a key or a workload identity until a person approves them. Releases you publish with your own account, where Hex asks for your 2FA code, are never held.

It's a setting on each package, under Settings > Staged publishing. It's on by default for new packages, including when a key publishes their first release, and off for existing ones, so nothing changes for your current packages until you turn it on. Organization admins can also turn it on for every package in the organization's private repository.

A staged release isn't in the registry until someone approves it, and hex.pm emails the people who can. They review it under Staged releases on their dashboard, and approving or rejecting it asks for a fresh 2FA code. Staged releases expire after seven days.

<img class="blog-img-light" src="/images/blog/028_staged_release.png" srcset="/images/blog/028_staged_release.png 2x" alt="A staged release of widget 1.1.0 awaiting approval, with the repository, workflow, git ref and commit of the workload identity that published it">
<img class="blog-img-dark" src="/images/blog/028_staged_release_dark.png" srcset="/images/blog/028_staged_release_dark.png 2x" alt="A staged release of widget 1.1.0 awaiting approval, with the repository, workflow, git ref and commit of the workload identity that published it">

Hex 2.6.1 adds `mix hex.publish --wait`, which opens the staged release page, waits until the release is approved, rejected or expires, and fails unless it's approved. With Hex 2.6.0 and earlier, `mix hex.publish` succeeds when the release is staged and prints the staged release page as the URL the package was published to.

### Key permissions

Keys can now have narrower permissions than API read and write, such as publishing a single package. [Keys](/docs/keys) describes each permission.

<img class="blog-img-light" src="/images/blog/028_key_permissions.png" srcset="/images/blog/028_key_permissions.png 2x" alt="The Generate New Key form with API, write and per-package key permissions">
<img class="blog-img-dark" src="/images/blog/028_key_permissions_dark.png" srcset="/images/blog/028_key_permissions_dark.png 2x" alt="The Generate New Key form with API, write and per-package key permissions">

If you publish with a key, give it only `publish:name` and `api:read`. A key that can change package owners or organization members can add an account that publishes without approval.

### Emergency publishing mode

If stolen keys are being used to publish packages, we can globally turn on emergency publishing mode for all packages. This is intended as a cooldown period to contain potential lateral movement between packages while we investigate. Releases and documentation of public packages published with a key or a workload identity then wait for approval, whatever the package setting, and a banner on hex.pm shows that the mode is on.

### Thanks

Thanks to [Yordis Prieto](https://github.com/yordis), who built the first version of Workload Identity on hex.pm, then called Trusted Publishing, and its support in Hex and hex_core. Thanks also to [Jonatan Männchen](https://github.com/maennchen) for reviewing it and the design of organization workload identities.

### Upgrading

Update Hex to the latest version by running `mix local.hex`. [Workload Identity](/docs/workload-identity) and [staged publishing](/docs/publish#staged-publishing) in the docs have the details.
