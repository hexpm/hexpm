## Trusted publishers

Trusted publishers let CI publish Hex packages without storing a long-lived API key. A GitHub Actions job presents a short-lived OpenID Connect (OIDC) identity token; Hex verifies it against a publisher you configured for the package and returns a short-lived, package-scoped access token that the normal publish path accepts.

Hex exchanges the OIDC token through the standard OAuth 2.0 token endpoint using the JWT bearer grant defined in [RFC 7523](https://www.rfc-editor.org/rfc/rfc7523), rather than a dedicated mint endpoint.

This release supports GitHub Actions only. Native Mix / Rebar3 helpers are not required for the server flow, but until the Hex clients add first-class support you exchange the OIDC token yourself (examples below).

### How it works

1. A package owner configures a trusted publisher that names the GitHub repository, workflow file, and optional environment.
2. The CI job requests an OIDC token from GitHub with audience `hexpm`.
3. The job exchanges that token at Hex's OAuth token endpoint for one target package.
4. Hex verifies the token, matches a publisher, and returns a Hex access token that expires in 15 minutes and can only publish that package.
5. The job publishes with `Authorization: Bearer <token>` (for Mix, `HEX_API_KEY="Bearer <token>"`, since Mix sends `HEX_API_KEY` as the raw `Authorization` header value).

The package must already exist. Trusted publishers cannot create a new package or publish its first release; do that once with a normal Hex account or API key.

### Before you begin

You need:

* Full ownership of the Hex package (`owner` level, not only `maintainer`).
* Two-factor authentication enabled on your Hex account, from `/dashboard/security`. A trusted publisher grants publish rights the same way a personal API key does, so configuring or removing one carries the same requirement.
* A GitHub Actions workflow that will publish, with `id-token: write` permission.
* For private organization packages, an active organization billing state (same requirement as other publish paths).

### Configure a trusted publisher

Open the package page and go to the "Trusted publishers" tab. The tab is visible only to full owners, and the page requires two-factor authentication.

Fill in the form:

<dl class="dl-horizontal">
  <dt><code>Repository owner</code></dt>
  <dd>GitHub user or organization login that owns the repository (for example <code>acme</code>). Case-insensitive, because the GitHub namespace is.</dd>
  <dt><code>GitHub repository</code></dt>
  <dd>Repository name (<code>widget</code>) or full name (<code>acme/widget</code>). Hex normalizes this to <code>owner/name</code>. Case-insensitive.</dd>
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
          HEX_TRUSTED_PUBLISHER_CLIENT_ID: a1111111-1111-4111-8111-111111111111
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
            --data-urlencode "client_id=$HEX_TRUSTED_PUBLISHER_CLIENT_ID" \
            --data-urlencode "assertion=$OIDC_TOKEN" \
            --data-urlencode "scope=package:hexpm/PACKAGE")

          ACCESS_TOKEN=$(printf '%s' "$MINT" | jq -r .access_token)

          mix deps.get
          HEX_API_KEY="Bearer $ACCESS_TOKEN" mix hex.publish --yes
```

Replace `PACKAGE` with the Hex package name. For a private organization package, use the Hex repository in the scope:

```nohighlight
scope=package:ORG/PACKAGE
```

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
client_id=a1111111-1111-4111-8111-111111111111&
assertion=<github-oidc-jwt>&
scope=package:hexpm/PACKAGE
```

`client_id` is the fixed, public trusted-publisher client shown above. `scope` names exactly one package as `package:REPOSITORY/PACKAGE`; use the Hex repository name (for example `package:ORG/PACKAGE`) for a private organization package. Successful response:

```nohighlight
{
  "access_token": "<hex-access-token>",
  "token_type": "bearer",
  "expires_in": 900,
  "scope": "package:hexpm/PACKAGE"
}
```

Errors use OAuth-style bodies (`error`, `error_description`), for example missing fields (`invalid_request`), a malformed or missing `scope` (`invalid_scope`), bad or replayed OIDC tokens (`invalid_grant`), or no matching publisher (`access_denied`). The grant is public (the OIDC token is the credential). It has no per-address rate limit, so CI runners sharing an address never throttle each other. Mints that fail after the OIDC token is verified count toward a limit per GitHub repository; once it is exceeded the endpoint answers `429` with `slow_down` for that repository only.

### Security model

* Hex verifies the GitHub OIDC signature via discovery and JWKS, rejects `none` and HMAC algorithms, and checks `iss`, `aud`, `exp`, `nbf`, and `iat`.
* Matching requires the configured repository, workflow basename from a workflow ref inside that repository, the immutable `repository_owner_id` and `repository_id`, and optional environment. A token that carries no `repository_id` claim never matches. The workflow is compared exactly, including casing; repository, owner, and environment are compared case-insensitively, and repository and owner are pinned by their immutable GitHub IDs. Cross-repository reusable workflow basenames alone cannot satisfy the workflow match.
* Pinning the repository ID as well as the owner ID matters inside an organization: if the trusted repository is deleted, anyone who can create a repository in that organization could otherwise recreate the name, add the configured workflow, and mint. The owner ID alone would not stop that.
* Minted tokens are short-lived (15 minutes), single-package, and attributed as a package-scoped trusted-publisher principal (release publisher user is unset; audit logs record the publish).
* Configuring or removing a publisher requires full package ownership and two-factor authentication, because a publisher grants publish rights the same way a personal API key does. Every package owner is emailed when a publisher is added or removed, and the email cannot be turned off. Two-factor authentication is not required for CI mint/publish itself, because the trusted-publisher grant has no interactive user.
* Hex records an allowlisted snapshot of the verified OIDC claims (repository, workflow ref, commit SHA, run id, and similar) on the minted token and attaches it to the release published with that token. The release API exposes this as `oidc_claims`, so consumers can see that a release was published via trusted publishing and which workflow produced it.

### Limitations

* GitHub Actions only in this release. GitLab, CircleCI, and custom issuers are not supported yet.
* No Mix / Rebar3 built-in trusted-publisher commands yet. Clients should request the CI OIDC token with audience from `/api/oidc/audience`, exchange it at `/api/oauth/token` with the JWT bearer grant, and publish with the returned bearer token.
* Cannot create a package or land the first release from CI. Publish once manually, then attach a trusted publisher.

### Troubleshooting

* **The form reports the GitHub repository could not be resolved:** the GitHub owner does not exist or is misspelled. Hex could read neither the repository nor the owner profile.
* **The form reports that a repository ID is required:** Hex could not see the repository, so it cannot pin the ID itself. For a private repository, fill in the repository ID field. For a public one, this usually means the repository name is misspelled, because GitHub answers 404 both for a repository that does not exist and for one Hex cannot see, which makes a typo indistinguishable from a private repository. Note that a wrong repository name combined with a supplied repository ID is created but never matches, and mint returns no matching trusted publisher.
* **The form reports that GitHub could not be reached:** GitHub was unreachable, rate-limited, or answered with something unexpected. Nothing was stored, so the same submission can be retried.
* **Mint returns no matching trusted publisher:** check package name, Hex repository, GitHub `owner/repo`, workflow **filename**, and optional environment against the configured publisher, including the exact casing of the workflow filename. The workflow file that requests the OIDC token must live in the trusted repository.
* **Mint rejects the OIDC token:** confirm `id-token: write`, audience `hexpm`, and that you are not reusing a JWT that was already minted.
* **Mint rejects a token from a `pull_request_target` workflow:** that event runs with the base repository's permissions, so a workflow that checks out the pull request head would let code from a fork request an OIDC token. Publish from `push`, `release`, or `workflow_dispatch` instead.
* **Publish fails with package ownership / scope errors:** the minted token only covers the package named at mint time; mint again for that package name.
* **The "Trusted publishers" tab is missing, or the token endpoint returns `unsupported_grant_type`:** trusted publishers may be disabled on that Hex deployment, or your account is not a full owner of the package.
