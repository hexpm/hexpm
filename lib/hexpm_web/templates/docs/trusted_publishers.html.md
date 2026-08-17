## Trusted publishers

Trusted publishers let CI publish Hex packages without storing a long-lived API key. A GitHub Actions job presents a short-lived OpenID Connect (OIDC) identity token; Hex verifies it against a publisher you configured for the package and returns a short-lived, package-scoped access token that the normal publish path accepts.

This release supports GitHub Actions only. There is no web UI yet: configure publishers through the API. Native Mix / Rebar3 helpers are not required for the server flow, but until the Hex clients add first-class support you exchange the OIDC token yourself (examples below).

### How it works

1. A package owner configures a trusted publisher that names the GitHub repository, workflow file, and optional environment.
2. The CI job requests an OIDC token from GitHub with audience `hexpm`.
3. The job posts that token to Hex's mint endpoint for one target package.
4. Hex verifies the token, matches a publisher, and returns a Hex access token that expires in 15 minutes and can only publish that package.
5. The job publishes with `Authorization: Bearer <token>` (or `HEX_API_KEY` set to the minted token).

The package must already exist. Trusted publishers cannot create a new package or publish its first release; do that once with a normal Hex account or API key.

### Before you begin

You need:

* Full ownership of the Hex package (`owner` level, not only `maintainer`).
* An API key or OAuth token with `api:write` to create or remove publishers. Package-scoped keys cannot manage trusted publishers.
* A GitHub Actions workflow that will publish, with `id-token: write` permission.
* For private organization packages, an active organization billing state (same requirement as other publish paths).

### Configure a trusted publisher

Create a publisher for an existing package on the public repository:

```nohighlight
$ curl -X POST https://hex.pm/api/packages/PACKAGE/trusted_publishers \
  -H "authorization: KEY" \
  -H "content-type: application/json" \
  -d '{
    "provider": "github",
    "repository_owner": "acme",
    "github_repository": "widget",
    "workflow": "release.yml",
    "environment": "release"
  }'
```

For a package in a private organization repository, use the repository-prefixed path:

```nohighlight
$ curl -X POST https://hex.pm/api/repos/ORG/packages/PACKAGE/trusted_publishers \
  -H "authorization: KEY" \
  -H "content-type: application/json" \
  -d '{ ... }'
```

Fields:

<dl class="dl-horizontal">
  <dt><code>provider</code></dt>
  <dd>Must be <code>github</code>.</dd>
  <dt><code>repository_owner</code></dt>
  <dd>GitHub user or organization login that owns the repository (for example <code>acme</code>). Case-insensitive, because the GitHub namespace is.</dd>
  <dt><code>github_repository</code></dt>
  <dd>Repository name (<code>widget</code>) or full name (<code>acme/widget</code>). Hex normalizes this to <code>owner/name</code>. Case-insensitive.</dd>
  <dt><code>workflow</code></dt>
  <dd>Workflow filename only, for example <code>release.yml</code> or <code>release.yaml</code>. Paths are stripped; matching uses the basename of the calling workflow in the trusted repository. <strong>Case-sensitive</strong>, so <code>Release.yml</code> and <code>release.yml</code> are different workflows.</dd>
  <dt><code>environment</code></dt>
  <dd>GitHub Actions environment name. Optional, but strongly recommended: an environment is where GitHub lets you require reviewers, add a wait timer, or restrict which branches can deploy, so it is the only place you can put a gate in front of a publish. When set, the OIDC token must include the same environment, matched <strong>case-sensitively</strong>. When omitted, any environment (or none) is accepted.</dd>
  <dt><code>repository_id</code></dt>
  <dd>Numeric GitHub repository ID. Required only when Hex cannot see the repository, which is the case for private repositories. Omit it for public repositories and Hex resolves the ID itself; if Hex does resolve it, the resolved value wins over anything sent here.</dd>
</dl>

You may also send `repository` instead of `github_repository` in the JSON body; Hex treats that body field as the GitHub repository and does not confuse it with the Hex repository in the URL.

On create, Hex pins immutable GitHub IDs so that a deleted-and-recreated GitHub login or repository cannot inherit the publisher. Both the owner ID and the repository ID are always pinned, and creation fails if either is missing.

The owner ID always comes from GitHub, because an owner's profile is public even when their repositories are not. The repository ID comes from GitHub for a repository Hex can see. For a private repository Hex gets a 404 and cannot read the ID, so you supply it in `repository_id`:

```nohighlight
$ gh api repos/OWNER/NAME --jq .id
```

```nohighlight
$ curl -X POST https://hex.pm/api/repos/ORG/packages/PACKAGE/trusted_publishers \
  -H "authorization: KEY" \
  -H "content-type: application/json" \
  -d '{
    "provider": "github",
    "repository_owner": "acme",
    "github_repository": "widget",
    "workflow": "release.yml",
    "repository_id": 123456789
  }'
```

Because the binding is by ID rather than by name, deleting and recreating the GitHub repository invalidates the publisher even under the same name. Delete the trusted publisher and create it again if that happens.

List and delete:

```nohighlight
$ curl https://hex.pm/api/packages/PACKAGE/trusted_publishers \
  -H "authorization: KEY"

$ curl -X DELETE https://hex.pm/api/packages/PACKAGE/trusted_publishers/ID \
  -H "authorization: KEY"
```

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
        run: |
          set -euo pipefail

          AUDIENCE=$(curl -fsS "$HEX_API_URL/oidc/audience" | jq -r .audience)
          OIDC_TOKEN=$(curl -fsS \
            -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${AUDIENCE}" \
            | jq -r .value)

          BODY=$(jq -n \
            --arg token "$OIDC_TOKEN" \
            --arg package "PACKAGE" \
            '{token: $token, package: $package}')

          MINT=$(curl -fsS -X POST "$HEX_API_URL/oidc/mint-token" \
            -H "content-type: application/json" \
            -d "$BODY")

          export HEX_API_KEY=$(printf '%s' "$MINT" | jq -r .token)
          mix deps.get
          mix hex.publish --yes
```

Replace `PACKAGE` with the Hex package name. For a private organization package, pass the Hex repository when minting:

```nohighlight
{"token":"<oidc-jwt>","repository":"ORG","package":"PACKAGE"}
```

Notes:

* `permissions.id-token: write` is required so the job can request an OIDC token.
* Discover the audience with `GET /api/oidc/audience` rather than hardcoding it. Today the value is `hexpm`.
* Each OIDC token may be minted at most once (`jti` replay is rejected).
* The minted Hex token is scoped to exactly the package named in the mint request and is publish-oriented; it is not a general-purpose API key.
* Prefer matching on a GitHub Environment for production release workflows so only that environment can mint.

### Mint API

Discover the expected OIDC audience:

```nohighlight
GET /api/oidc/audience

{"audience":"hexpm"}
```

Exchange a CI OIDC token for a Hex access token:

```nohighlight
POST /api/oidc/mint-token
Content-Type: application/json

{
  "token": "<github-oidc-jwt>",
  "repository": "hexpm",
  "package": "PACKAGE"
}
```

`repository` defaults to `hexpm` when omitted. Successful response:

```nohighlight
{
  "token": "<hex-access-token>",
  "token_type": "bearer",
  "expires_in": 900,
  "expires_at": "2026-07-30T12:00:00Z"
}
```

Errors use OAuth-style bodies (`error`, `error_description`), for example missing fields (`invalid_request`), bad or replayed OIDC tokens (`invalid_grant`), or no matching publisher (`access_denied`). The mint endpoint is public (the OIDC token is the credential) and rate-limited by IP.

### Security model

* Hex verifies the GitHub OIDC signature via discovery and JWKS, rejects `none` and HMAC algorithms, and checks `iss`, `aud`, `exp`, `nbf`, and `iat`.
* Matching requires the configured repository, workflow basename from a workflow ref inside that repository, the immutable `repository_owner_id` and `repository_id`, and optional environment. A token that carries no `repository_id` claim never matches. Workflow and environment are compared exactly, including casing; repository and owner are compared case-insensitively and pinned by their immutable GitHub IDs. Cross-repository reusable workflow basenames alone cannot satisfy the workflow match.
* Pinning the repository ID as well as the owner ID matters inside an organization: if the trusted repository is deleted, anyone who can create a repository in that organization could otherwise recreate the name, add the configured workflow, and mint. The owner ID alone would not stop that.
* Minted tokens are short-lived (15 minutes), single-package, and attributed as a package-scoped trusted-publisher principal (release publisher user is unset; audit logs record the mint and publish).
* Configuring or removing a publisher requires full package ownership and `api:write`. Two-factor authentication is not required for CI mint/publish because the trusted-publisher grant has no interactive user.
* Hex records an allowlisted snapshot of the verified OIDC claims (repository, workflow ref, commit SHA, run id, and similar) on the minted token and attaches it to the release published with that token. The release API exposes this as `oidc_claims`, so consumers can see that a release was published via trusted publishing and which workflow produced it.

### Limitations

* GitHub Actions only in this release. GitLab, CircleCI, and custom issuers are not supported yet.
* No dashboard UI; use the management API.
* No Mix / Rebar3 built-in trusted-publisher commands yet. Clients should request the CI OIDC token with audience from `/api/oidc/audience`, call `/api/oidc/mint-token`, and publish with the returned bearer token.
* Cannot create a package or land the first release from CI. Publish once manually, then attach a trusted publisher.
* Provenance / attestations, pending publishers, and a package setting to disallow long-lived tokens are deferred.

### Troubleshooting

* **Create fails with 422 and `github_repository` could not be resolved:** the GitHub owner does not exist or is misspelled. Hex could read neither the repository nor the owner profile.
* **Create fails with 422 and `repository_id` is required:** Hex could not see the repository, so it cannot pin the ID itself. For a private repository, send `repository_id`. For a public one, this usually means the repository name is misspelled, because GitHub answers 404 both for a repository that does not exist and for one Hex cannot see, which makes a typo indistinguishable from a private repository. Note that a wrong repository name combined with a supplied `repository_id` is created but never matches, and mint returns no matching trusted publisher.
* **Create fails with 503:** GitHub was unreachable, rate-limited, or answered with something unexpected. Nothing was stored, so the same request can be retried.
* **Mint returns no matching trusted publisher:** check package name, Hex repository, GitHub `owner/repo`, workflow **filename**, and optional environment against the configured publisher, including the exact casing of the workflow filename and environment. The workflow file that calls `mint-token` must live in the trusted repository.
* **Mint rejects the OIDC token:** confirm `id-token: write`, audience `hexpm`, and that you are not reusing a JWT that was already minted.
* **Publish fails with package ownership / scope errors:** the minted token only covers the package named at mint time; mint again for that package name.
* **Endpoints return 404:** trusted publishers may be disabled on that Hex deployment.
