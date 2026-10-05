## Trusted publishers

Trusted publishers let CI publish Hex packages without storing a long-lived API key. A GitHub Actions job presents a short-lived OpenID Connect (OIDC) identity token; Hex verifies it against a publisher you configured for the package and returns a short-lived, package-scoped access token that the normal publish path accepts.

Package publishers are for packages in the public `hexpm` repository. Packages in an organization's private repository are published by the organization's publishers, which also fetch its packages, see [Organization publishers](#organization-publishers).

GitHub Actions is the only supported CI provider.

### How it works

1. A package owner configures a trusted publisher that names the GitHub repository, workflow file, and optional environment.
2. The CI job requests an OIDC token from GitHub with audience `hexpm`.
3. The job exchanges that token at Hex's OAuth token endpoint for one target package.
4. Hex verifies the token, matches a publisher, and returns a Hex access token that expires in 15 minutes and can only publish that package.
5. The job publishes with `Authorization: Bearer <token>` (for Mix, `HEX_API_KEY="Bearer <token>"`, since Mix sends `HEX_API_KEY` as the raw `Authorization` header value).

The package must already exist. A package's trusted publishers cannot create a new package or publish its first release; do that once with a normal Hex account or API key.

Transferring a package (`mix hex.owner transfer`) removes its trusted publishers, so a publisher a previous owner set up can't keep publishing it. The new owners add their own. Adding or removing an owner without a transfer keeps them.

### Before you begin

You need:

* Full ownership of the Hex package (`owner` level, not only `maintainer`).
* Two-factor authentication enabled on your Hex account, from `/dashboard/security`. A trusted publisher grants publish rights the same way a personal API key does, so configuring or removing one carries the same requirement.
* A GitHub Actions workflow that will publish, with `id-token: write` permission.

### Configure a trusted publisher

Open the package page and go to the "Trusted publishers" tab. The tab is visible only to full owners, and the page requires two-factor authentication.

Fill in the form:

<dl class="dl-horizontal">
  <dt><code>Repository owner</code></dt>
  <dd>GitHub user or organization login that owns the repository (for example <code>acme</code>). Case-insensitive, because the GitHub namespace is.</dd>
  <dt><code>Repository name</code></dt>
  <dd>The repository's name without the owner, for example <code>widget</code>. Case-insensitive.</dd>
  <dt><code>Workflow</code></dt>
  <dd>Workflow filename only, for example <code>release.yml</code> or <code>release.yaml</code>. Paths are stripped; matching uses the basename of the calling workflow in the trusted repository. <strong>Case-sensitive</strong>, so <code>Release.yml</code> and <code>release.yml</code> are different workflows.</dd>
  <dt><code>Environment</code></dt>
  <dd>GitHub Actions environment name. Optional, but strongly recommended: an environment is where GitHub lets you require reviewers, add a wait timer, or restrict which branches can deploy, so it is the only place you can put a gate in front of a publish. When set, the OIDC token must include the same environment, matched case-insensitively, as GitHub treats environment names. When left blank, any environment (or none) is accepted.</dd>
  <dt><code>Repository ID</code></dt>
  <dd>Numeric GitHub repository ID. Required only when Hex cannot see the repository, which is the case for private repositories. Leave it blank for public repositories and Hex resolves the ID itself; if Hex does resolve it, the resolved value wins over anything entered here.</dd>
</dl>

On create, Hex pins immutable GitHub IDs so that a deleted-and-recreated GitHub login or repository cannot inherit the publisher. Both the owner ID and the repository ID are always pinned, and creation fails if either is missing.

The owner ID always comes from GitHub, because an owner's profile is public even when their repositories are not. The repository ID comes from GitHub for a repository Hex can see. For a private repository Hex gets a 404 and cannot read the ID, so you fill in the repository ID yourself:

```nohighlight
$ gh api repos/OWNER/NAME --jq .id
```

Because the binding is by ID rather than by name, deleting and recreating the GitHub repository invalidates the publisher even under the same name. Delete the trusted publisher and create it again if that happens.

A package may have multiple publishers (for example several workflows or repositories). The same GitHub repository and workflow may be attached to several packages as separate rows, which covers monorepos that release several packages from one repository. When a single workflow run publishes several packages, mint once per package and request a fresh OIDC token for each mint, because an OIDC token can only be minted once.

### Organization publishers

An organization admin configures publishers for the organization's private repository on the organization dashboard's "Trusted publishers" page. Every member can see the page. Adding one requires the admin role, two-factor authentication on the admin's account, and an active organization billing state, and removing one requires the same except billing. Every organization admin is emailed when one is added or removed, and the change is recorded in the organization's activity log. A private package's own "Trusted publishers" tab lists the organization publishers that can publish it and links to the organization page.

Each publisher has a role:

<dl class="dl-horizontal">
  <dt><code>read</code></dt>
  <dd>Fetches every package in the organization's repository, including docs tarballs, from repo.hex.pm.</dd>
  <dt><code>write</code></dt>
  <dd>Fetches like <code>read</code>, and also publishes releases and docs of packages in the repository and creates new packages in it. The "Packages" field limits which package names it covers; leave it empty to cover every package. A name in the list doesn't have to exist yet, so the workflow can create that package.</dd>
</dl>

The other fields are the same as for a package publisher. The `write` role needs a repository name and a workflow. The `read` role can leave either empty:

* **An empty workflow** matches every workflow in the repository, including test workflows. Anyone who can push a workflow file to the repository can then fetch, the same as with an organization API key stored as a repository secret, so set an environment with protection rules when that matters.
* **An empty repository name** matches every repository owned by the repository owner, pinned by the owner's GitHub ID. Anyone who can create a repository under that owner, or push a workflow file to one of its repositories, can then fetch, the same as with an organization API key stored as a GitHub organization secret available to all repositories. The workflow and environment must be empty too, because whoever creates a repository also names its workflows and environments.

A common setup is one `read` publisher with an empty repository name, so every repository in your GitHub organization can fetch private dependencies, and one `write` publisher per repository that releases packages, naming its release workflow and environment.

Organization publishers never cover the public `hexpm` repository. Public packages owned by an organization use package publishers, and private packages only use organization publishers.

Retiring releases, reverting, and changing owners, keys, members, or settings aren't available to either role. Organization publishers aren't governed by the organization's single sign-on or two-factor authentication requirements, the same as organization API keys.

To fetch, exchange the OIDC token for a repository token by setting the scope to the organization's repository:

```nohighlight
scope=repository:ORG
```

Send the access token to repo.hex.pm as `Authorization: Bearer <token>`. It can't call the Hex API.

To publish or create a package, use a package scope in the organization's repository, the same as for a package publisher:

```nohighlight
scope=package:ORG/PACKAGE
```

Hex matches the organization's `write` publishers whose package list covers the name. A package created this way has no owners, the same as one created with an organization API key. A job that fetches private dependencies and then publishes exchanges twice, once per scope, with a fresh OIDC token each time.

Removing a publisher stops its tokens at the Hex API on the next request. repo.hex.pm verifies tokens without asking Hex, so a fetch token keeps working there until it expires, at most 15 minutes. A lapsed billing subscription behaves the same, since billing is checked when exchanging.

### GitHub Actions workflow

Request an OIDC token with audience `hexpm`, mint a Hex token for the package, then publish. Example:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  id-token: write
  contents: read

jobs:
  publish:
    runs-on: ubuntu-latest
    # Optional: pin to a GitHub Environment that matches the publisher config.
    # environment: release
    steps:
      - uses: actions/checkout@v4

      - uses: erlef/setup-beam@v1
        with:
          otp-version: '27'
          elixir-version: '1.17'

      - name: Mint Hex token and publish
        env:
          HEX_API_URL: https://hex.pm/api
        run: |
          set -euo pipefail

          AUDIENCE=$(curl -fsS "$HEX_API_URL/oidc/audience" | jq -r .audience)
          OIDC_TOKEN=$(curl -fsS \
            -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${AUDIENCE}" \
            | jq -r .value)

          MINT=$(curl -fsS -X POST "$HEX_API_URL/oauth/token" \
            -H "content-type: application/x-www-form-urlencoded" \
            --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
            --data-urlencode "assertion=$OIDC_TOKEN" \
            --data-urlencode "scope=package:hexpm/PACKAGE")

          ACCESS_TOKEN=$(printf '%s' "$MINT" | jq -r .access_token)

          mix deps.get
          HEX_API_KEY="Bearer $ACCESS_TOKEN" mix hex.publish --yes
```

Replace `PACKAGE` with the Hex package name. For a private package, see [Organization publishers](#organization-publishers).

Notes:

* `permissions.id-token: write` is required so the job can request an OIDC token.
* Discover the audience with `GET /api/oidc/audience` rather than hardcoding it. Today the value is `hexpm`.
* Each OIDC token may be minted at most once (`jti` replay is rejected).
* The minted Hex token is scoped to exactly the package named in the `scope` parameter and is publish-oriented; it is not a general-purpose API key.
* Prefer matching on a GitHub Environment for production release workflows so only that environment can mint.

### Mint API

Discover the expected OIDC audience:

```nohighlight
GET /api/oidc/audience

{"audience":"hexpm"}
```

Exchange a CI OIDC token for a Hex access token with the JWT bearer grant ([RFC 7523](https://www.rfc-editor.org/rfc/rfc7523)) on the standard OAuth token endpoint:

```nohighlight
POST /api/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&
assertion=<github-oidc-jwt>&
scope=package:hexpm/PACKAGE
```

No `client_id` is needed, because the OIDC token is the credential. `scope` names exactly one package as `package:REPOSITORY/PACKAGE`. An [organization publisher](#organization-publishers) uses its organization's repository (`package:ORG/PACKAGE`), or requests `repository:ORG` to fetch. Successful response:

```nohighlight
{
  "access_token": "<hex-access-token>",
  "token_type": "bearer",
  "expires_in": 900,
  "scope": "package:hexpm/PACKAGE"
}
```

Errors use OAuth-style bodies (`error`, `error_description`), for example missing fields (`invalid_request`), a malformed or missing `scope` (`invalid_scope`), bad or replayed OIDC tokens (`invalid_grant`), or no matching publisher (`access_denied`). An unknown package, repository, or organization returns the same `access_denied` as no matching publisher. A matching publisher of an organization without an active billing state also gets `access_denied`, with a description saying so. The grant is public (the OIDC token is the credential). It has no per-address rate limit, so CI runners sharing an address never throttle each other. Mints that fail after the OIDC token is verified count toward a limit per GitHub repository; once it is exceeded the endpoint answers `429` with `slow_down` for that repository only. Tokens from rejected events and replayed tokens don't count, because a pull request from a fork can produce them.

To revoke a minted token before it expires, for example at the end of the job, send it to the standard revocation endpoint ([RFC 7009](https://www.rfc-editor.org/rfc/rfc7009)), again without a `client_id`:

```nohighlight
POST /api/oauth/revoke
Content-Type: application/x-www-form-urlencoded

token=<hex-access-token>
```

### Security model

* Hex verifies the GitHub OIDC signature via discovery and JWKS, rejects `none` and HMAC algorithms, and checks `iss`, `aud`, `exp`, `nbf`, and `iat`.
* Matching requires the configured repository, workflow basename from a workflow ref inside that repository, the immutable `repository_owner_id` and `repository_id`, and optional environment. A token that carries no `repository_id` claim never matches. The workflow is compared exactly, including casing; repository, owner, and environment are compared case-insensitively, and repository and owner are pinned by their immutable GitHub IDs. Cross-repository reusable workflow basenames alone cannot satisfy the workflow match.
* Pinning the repository ID as well as the owner ID matters inside an organization: if the trusted repository is deleted, anyone who can create a repository in that organization could otherwise recreate the name, add the configured workflow, and mint. The owner ID alone would not stop that.
* Minted tokens are short-lived (15 minutes), cover one package or one organization repository, and are attributed to the trusted publisher (release publisher user is unset; audit logs record the publish).
* Tokens from `pull_request_target` and `workflow_run` workflows are rejected. A `workflow_run` run gets write permissions even when a pull request from a fork triggered the run that started it, and no OIDC claim says whether one did.
* Configuring or removing a package publisher requires full package ownership and two-factor authentication, because a publisher grants publish rights the same way a personal API key does. Every package owner is emailed when a publisher is added or removed, and the email cannot be turned off. Transferring the package removes its publishers. Two-factor authentication is not required for CI mint/publish itself, because the trusted-publisher grant has no interactive user.
* Hex records an allowlisted snapshot of the verified OIDC claims (repository, workflow ref, commit SHA, run id, and similar) on the minted token and attaches it to the release published with that token. The release API exposes this as `oidc_claims`, and the package page shows it in a Provenance card linking to the source commit, build file, branch or tag, environment, triggering actor, and workflow run, so consumers can see that a release was published via trusted publishing and which workflow produced it.

### Limitations

* Only GitHub Actions can act as a trusted publisher. GitLab, CircleCI, and custom OIDC issuers are not supported.
* A package's publishers can't create a package or land the first release from CI. Publish once manually, then attach a trusted publisher. For a private package, use an organization publisher, which can create it.
* Mix and rebar3 don't request repository tokens with an OIDC token, so an organization publisher's `read` role only serves tools that call repo.hex.pm directly. Publishing works with the `package:ORG/PACKAGE` scope as shown above.

### Troubleshooting

* **The form reports the GitHub repository could not be resolved:** the GitHub owner does not exist or is misspelled. Hex could read neither the repository nor the owner profile.
* **The form reports that a repository ID is required:** Hex could not see the repository, so it cannot pin the ID itself. For a private repository, fill in the repository ID field. For a public one, this usually means the repository name is misspelled, because GitHub answers 404 both for a repository that does not exist and for one Hex cannot see, which makes a typo indistinguishable from a private repository. Note that a wrong repository name combined with a supplied repository ID is created but never matches, and mint returns no matching trusted publisher.
* **The form reports that GitHub could not be reached:** GitHub was unreachable, rate-limited, or answered with something unexpected. Nothing was stored, so the same submission can be retried.
* **Mint returns no matching trusted publisher:** check package name, Hex repository, GitHub `owner/repo`, workflow **filename**, and optional environment against the configured publisher, including the exact casing of the workflow filename. The workflow file that requests the OIDC token must live in the trusted repository.
* **Mint rejects the OIDC token:** confirm `id-token: write`, audience `hexpm`, and that you are not reusing a JWT that was already minted.
* **Mint rejects a token from a `pull_request_target` or `workflow_run` workflow:** both events run with the base repository's permissions when a pull request from a fork triggered them, so code from a fork could request an OIDC token. Publish from `push`, `release`, or `workflow_dispatch` instead.
* **Publish fails with package ownership / scope errors:** the minted token only covers the package named at mint time; mint again for that package name.
* **The "Trusted publishers" tab is missing, or the token endpoint returns `unsupported_grant_type`:** trusted publishers may be disabled on that Hex deployment, or your account is not a full owner of the package.
