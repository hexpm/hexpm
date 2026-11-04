## Announcing Workload Identity and staged publishing

<div class="subtitle"><time datetime="2026-11-03T00:00:00Z">3 November, 2026</time> · by Eric Meadows-Jönsson</div>

In the [Hex 2.6 announcement](/blog/hex-v26-released) we said we were testing Workload Identity. It's now available to every package and organization on hex.pm. Workload Identity, sometimes also known as "Trusted Publishing", lets a GitHub Actions job publish packages and fetch an organization's private packages without storing an API key. It comes with staged publishing, which holds releases published with an API key or a workload identity until a person with two-factor authentication approves them on hex.pm.

When you publish with your own account through `mix hex.user auth`, Hex asks for your 2FA code on every publish, so a stolen session can't publish by itself. An API key has no second factor. Anyone who gets the key can publish a release that `mix deps.get` picks up as soon as the registry is updated. In September 2025 the [Shai-Hulud worm](https://github.blog/security/supply-chain-security/our-plan-for-a-more-secure-npm-supply-chain/) spread through npm this way. It stole npm tokens and other secrets, and used compromised maintainer accounts to add malicious install scripts to popular packages.

Workload Identity takes the key out of CI. Anyone who can push to the repository can still run the release workflow unless its GitHub environment requires a reviewer, so staged publishing adds a second factor: a release published with a key or a workload identity stays private until a person approves it with 2FA. Staged publishing is on by default for new packages, and existing packages have it off until an owner turns it on.

That includes the first release of a new package published with an API key. If you create packages from CI with an API key, read [Staged publishing](#staged-publishing) before you publish the next one.

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

To add a workload identity, open the package on hex.pm and go to Settings > Workload identities. You need to be a full owner of the package and have 2FA enabled. Enter the GitHub user or organization that owns the repositories, the repositories, the workflow file and a GitHub environment. The environment is required when a repository is public. It's where GitHub lets you require reviewers, add a wait timer or restrict which branches can deploy, so those checks run before the job gets its token. hex.pm pins the GitHub IDs of the owner and the repositories, so a repository that's deleted and created again under the same name doesn't match.

<img class="blog-img-light" src="/images/blog/028_workload_identity.png" srcset="/images/blog/028_workload_identity.png 2x" alt="The Add workload identity form on a package's settings, with repository owner acme, repository widget, workflow release.yml and environment release">
<img class="blog-img-dark" src="/images/blog/028_workload_identity_dark.png" srcset="/images/blog/028_workload_identity_dark.png 2x" alt="The Add workload identity form on a package's settings, with repository owner acme, repository widget, workflow release.yml and environment release">

A workload identity can't create a public package, so publish the first release of a new public package with your account or a key as before. hex.pm emails every owner of the package when a workload identity is added, removed or changed to trust more, and transferring the package removes its workload identities.

A release published with a workload identity shows a Provenance card on its package page. It links to the source commit, the workflow file, the branch or tag, the environment, the GitHub user who triggered the run and the run itself. The release API returns the same information in `oidc_claims`.

GitHub Actions is the only CI provider we support for now. We plan to add more providers based on interest from users and the community.

### Organization workload identities

Organization admins configure workload identities for the whole organization on the Workload identities page of the organization dashboard. Each one has a role:

  * `read` fetches every package in the organization's repository.
  * `write` publishes the packages it covers, which can be the organization's private packages, the public packages the organization owns, or both. With private packages it can also fetch them and create new packages in the organization's repository.

When a job with `id-token: write` fetches packages from an organization's repository and neither an organization key nor a `mix hex.user auth` session is configured, Hex 2.6 exchanges the OIDC token for a token that can fetch them. With a `read` workload identity, CI jobs don't need an organization key to fetch private dependencies.

A common setup is one `read` workload identity without repositories, so every repository under your GitHub organization can fetch private dependencies, and one `write` workload identity naming the repositories that release packages. The `read` role and private packages need an active subscription. A `write` workload identity that only publishes public packages doesn't, so an organization can publish the public packages it owns without a subscription.

Neither role can retire releases, revert, or change owners, keys, members or settings. [Workload Identity](/docs/workload-identity) covers the rest, including the matching rules and the token exchange API.

### Staged publishing

Staged publishing holds releases and documentation published with an API key or a workload identity until a person approves them. Releases you publish with your own account, where Hex asks for your 2FA code, are never held.

It's a setting on each package, under Settings > Staged publishing. It's on by default for new packages and off for existing ones, so nothing changes for your current packages until you turn it on. Organization admins can also turn on staged publishing for every package in the organization's private repository, whatever the package setting, on the Staged publishing page of the organization dashboard. Changing either setting requires 2FA. Turning staged publishing off for a package emails its full owners and the admins of an organization that owns it, and turning it off for an organization emails its admins.

A release that waits for approval is a staged release. It isn't in the registry, so `mix deps.get` can't fetch it, and hex.pm emails everyone who can approve it: the package's owners and maintainers, and for a package owned by an organization, its admins and members with write access. Only users with 2FA enabled can approve. Staged releases are listed under Staged releases on your dashboard and expire after seven days.

The staged release page shows the credential that published it and, for a workload identity, the repository, workflow, git ref and commit with a link to the workflow run. It lists the package's dependencies and files, has links to download the package and documentation, and shows their SHA-256 checksums so you can compare them with what the publishing command printed. Opening the page and approving or rejecting the release ask for a fresh 2FA code.

<img class="blog-img-light" src="/images/blog/028_staged_release.png" srcset="/images/blog/028_staged_release.png 2x" alt="A staged release of widget 1.1.0 awaiting approval, with the repository, workflow, git ref and commit of the workload identity that published it">
<img class="blog-img-dark" src="/images/blog/028_staged_release_dark.png" srcset="/images/blog/028_staged_release_dark.png 2x" alt="A staged release of widget 1.1.0 awaiting approval, with the repository, workflow, git ref and commit of the workload identity that published it">

Hex 2.6.1 adds `mix hex.publish --wait`, which opens the staged release page and waits until the release is approved, rejected or expires. The command fails if the release is rejected or expires, so a CI job running it fails too, and a workload identity token that expires while waiting is exchanged again. With Hex 2.6.0 and earlier, `mix hex.publish` succeeds when the release is staged and prints the staged release page as the URL the package was published to.

Staged publishing doesn't cover adding owners or members. A key with the `api:write`, `owners`, `package:name` or `members` permission can add an owner or organization member, who can then publish with their own account without approval. We recommend publishing from CI with Workload Identity. If you have to use a key, give it only `publish:name` and `api:read`.

### Emergency publishing mode

If stolen keys are being used to publish packages, we can turn on emergency publishing mode. Releases and documentation of public packages published with an API key or a workload identity then wait for approval whatever the package setting, and those credentials can't revert public releases or documentation. A banner at the top of hex.pm shows when the mode is on. Publishing with your own account and 2FA code works as usual, and packages in organization repositories keep their package and organization settings.

### Thanks

Thanks to [Yordis Prieto](https://github.com/yordis), who built the first version of Workload Identity on hex.pm, then called Trusted Publishing, and its support in Hex and hex_core. Thanks also to [Jonatan Männchen](https://github.com/maennchen) for reviewing it and the design of organization workload identities.

### Upgrading

Update Hex to the latest version by running `mix local.hex`. [Workload Identity](/docs/workload-identity) and [staged publishing](/docs/publish#staged-publishing) in the docs have the details.
