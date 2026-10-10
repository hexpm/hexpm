## Workload Identity

Workload Identity, sometimes also known as "Trusted Publishing", lets CI jobs publish and fetch Hex packages without storing a long-lived API key. A GitHub Actions job presents a short-lived OpenID Connect (OIDC) identity token. Hex verifies it against a workload identity you configured and returns a short-lived, scoped access token that the normal publish path accepts.

Package workload identities are for packages in the public `hexpm` repository. An organization's workload identities publish the packages in its private repository and fetch them. See [Organization workload identities](#organization-workload-identities).

GitHub Actions is the only supported CI provider.

### How it works

1. A package owner configures a workload identity that names the GitHub repository, workflow file, and optional environment.
2. The CI job requests an OIDC token from GitHub with audience `hexpm`.
3. The job exchanges that token at Hex's OAuth token endpoint for a token for one package.
4. Hex verifies the token, matches a workload identity, and returns a Hex access token that expires in 15 minutes and can only publish that package.
5. The job publishes with `Authorization: Bearer <token>` (for Mix, `HEX_API_KEY="Bearer <token>"`, since Mix sends `HEX_API_KEY` as the raw `Authorization` header value).

The package must already exist. A package's workload identities can't create a new package or publish its first release, so do that once with a normal Hex account or API key.

Transferring a package (`mix hex.owner transfer`) removes its workload identities, so one that a previous owner set up can't keep publishing it. The new owners add their own. Adding or removing an owner without a transfer keeps them, and a removed owner who can still run one of their workflows on GitHub can still publish the package. Hex points this out when an owner is removed, in the confirmation on the Owners tab and in the email to the package's owners. Removing an organization member works the same way for organization workload identities.

### Before you begin

You need:

* Full ownership of the Hex package (`owner` level, not only `maintainer`).
* Two-factor authentication enabled on your Hex account, from `/dashboard/security`. A workload identity grants publish rights the same way a personal API key does, so configuring or removing one has the same requirement.
* A GitHub Actions workflow that will publish, with the `id-token: write` permission.

### Configure a workload identity

Open the package page and go to the "Workload identities" tab. Only full owners see the tab, and the page requires two-factor authentication.

Fill in the form:

<dl class="dl-horizontal">
  <dt><code>Repository owner</code></dt>
  <dd>GitHub user or organization login that owns the repository, for example <code>acme</code>. Case-insensitive, because GitHub logins are.</dd>
  <dt><code>Repository name</code></dt>
  <dd>The repository's name without the owner, for example <code>widget</code>. Case-insensitive.</dd>
  <dt><code>Workflow</code></dt>
  <dd>Workflow filename only, for example <code>release.yml</code> or <code>release.yaml</code>. Hex strips any path and matches the basename of the calling workflow in the configured repository. <strong>Case-sensitive</strong>, so <code>Release.yml</code> and <code>release.yml</code> are different workflows.</dd>
  <dt><code>Environment</code></dt>
  <dd>GitHub Actions environment name. Optional, but strongly recommended. A GitHub environment is where you can require reviewers, add a wait timer, or restrict which branches can deploy, so it's the only place to add a check before a publish. When it's set, the OIDC token must name the same environment, compared case-insensitively as GitHub compares environment names. When it's blank, Hex accepts any environment or none.</dd>
  <dt><code>Repository ID</code></dt>
  <dd>Numeric GitHub repository ID. Only required when Hex can't see the repository, as with a private repository. Leave it blank for a public repository and Hex looks up the ID itself. When Hex finds the ID, it uses that instead of anything entered here.</dd>
</dl>

When you create a workload identity, Hex pins the immutable GitHub IDs of both the owner and the repository, so a GitHub login or repository that's deleted and created again can't inherit it. Creating it fails if either ID is missing.

The owner ID always comes from GitHub, because an owner's profile is public even when their repositories aren't. The repository ID comes from GitHub for a repository Hex can see. For a private repository GitHub answers Hex with a 404, so you fill in the repository ID yourself:

```nohighlight
$ gh api repos/OWNER/NAME --jq .id
```

Because the workload identity is bound to the ID and not the name, deleting and recreating the GitHub repository invalidates it even under the same name. If that happens, delete the workload identity and create it again.

A package can have several workload identities, for example for several workflows or repositories. The same GitHub repository and workflow can be attached to several packages as separate workload identities, which covers monorepos that release several packages from one repository. When one workflow run publishes several packages, exchange once per package and request a new OIDC token for each exchange, because an OIDC token can only be exchanged once.

### Organization workload identities

An organization admin configures workload identities for the organization's private repository on the "Workload identities" page of the organization dashboard. Every member can see the page. Adding one requires the admin role, two-factor authentication on the admin's account, and an active organization billing state. Removing one has the same requirements except billing. Hex emails every organization admin when one is added or removed, and records the change in the organization's activity log. A private package's own "Workload identities" tab lists the organization workload identities that can publish it and links to the organization page.

Each organization workload identity has a role:

<dl class="dl-horizontal">
  <dt><code>read</code></dt>
  <dd>Fetches every package in the organization's repository, including docs tarballs, from repo.hex.pm.</dd>
  <dt><code>write</code></dt>
  <dd>Fetches like <code>read</code>, publishes releases and docs of packages in the repository, and creates new packages in it. The "Packages" field limits which package names it covers. Leave it empty to cover every package. A name in the list doesn't have to exist yet, so the workflow can create that package.</dd>
</dl>

The other fields are the same as for a package workload identity. The `write` role needs a repository name and a workflow. The `read` role can leave either empty:

* An empty workflow matches every workflow in the repository, including test workflows. Anyone who can push a workflow file to the repository can then fetch, the same as with an organization API key stored as a repository secret, so set an environment with protection rules when that matters.
* An empty repository name matches every repository owned by the repository owner, pinned by the owner's GitHub ID. Anyone who can create a repository under that owner, or push a workflow file to one of its repositories, can then fetch, the same as with an organization API key stored as a GitHub organization secret available to all repositories. The workflow and environment must be empty too, because whoever creates a repository also names its workflows and environments.

A common setup is one `read` workload identity with an empty repository name, so every repository in your GitHub organization can fetch private dependencies, and one `write` workload identity per repository that releases packages, naming its release workflow and environment.

Organization workload identities never cover the public `hexpm` repository. Public packages owned by an organization use package workload identities, and private packages only use organization workload identities.

Neither role can retire releases, revert, or change owners, keys, members, or settings. The organization's single sign-on and two-factor authentication requirements don't apply to organization workload identities, the same as for organization API keys.

To fetch, exchange the OIDC token for a repository token by setting the scope to the organization's repository:

```nohighlight
scope=repository:ORG
```

Send the access token to repo.hex.pm as `Authorization: Bearer <token>`. It can't call the Hex API.

Mix does this exchange itself when it fetches packages from an organization's repository in a GitHub Actions job with the `id-token: write` permission, and neither an organization key nor an authenticated user is configured.

To publish or create a package, use a package scope in the organization's repository, the same as for a package workload identity:

```nohighlight
scope=package:ORG/PACKAGE
```

Hex matches the organization's `write` workload identities whose package list covers the name. A package created this way has no owners, the same as one created with an organization API key. A job that fetches private dependencies and then publishes exchanges twice, once per scope, with a new OIDC token each time.

Removing a workload identity stops its tokens at the Hex API on the next request. repo.hex.pm verifies tokens without asking Hex, so a fetch token keeps working there until it expires, at most 15 minutes later. A lapsed billing subscription behaves the same, since Hex checks billing during the exchange.

### GitHub Actions workflow

Request an OIDC token with audience `hexpm`, exchange it for a Hex token for the package, then publish:

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
    # Optional: pin to a GitHub Environment that matches the workload identity.
    # environment: release
    steps:
      - uses: actions/checkout@v4

      - uses: erlef/setup-beam@v1
        with:
          otp-version: '27'
          elixir-version: '1.17'

      - name: Exchange the OIDC token and publish
        env:
          HEX_API_URL: https://hex.pm/api
        run: |
          set -euo pipefail

          AUDIENCE=$(curl -fsS "$HEX_API_URL/oidc/audience" | jq -r .audience)
          OIDC_TOKEN=$(curl -fsS \
            -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${AUDIENCE}" \
            | jq -r .value)

          RESPONSE=$(curl -fsS -X POST "$HEX_API_URL/oauth/token" \
            -H "content-type: application/x-www-form-urlencoded" \
            --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
            --data-urlencode "assertion=$OIDC_TOKEN" \
            --data-urlencode "scope=package:hexpm/PACKAGE")

          ACCESS_TOKEN=$(printf '%s' "$RESPONSE" | jq -r .access_token)

          mix deps.get
          HEX_API_KEY="Bearer $ACCESS_TOKEN" mix hex.publish --yes
```

Replace `PACKAGE` with the Hex package name. For a private package, see [Organization workload identities](#organization-workload-identities).

Notes:

* The job needs `permissions.id-token: write` to request an OIDC token.
* Discover the audience with `GET /api/oidc/audience` instead of hardcoding it. The current value is `hexpm`.
* Each OIDC token can be exchanged at most once, and Hex rejects a replayed `jti`. Hex refuses OIDC tokens that are valid for more than 15 minutes, because it keeps the record of a used token for that long. GitHub's are valid for 5 minutes.
* The Hex token can only publish the package named in the `scope` parameter. It isn't a general-purpose API key.
* Prefer matching on a GitHub Environment for production release workflows, so only that environment can get a token.

### Token exchange API

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

No `client_id` is needed, because the OIDC token is the credential. `scope` names exactly one package as `package:REPOSITORY/PACKAGE`. An [organization workload identity](#organization-workload-identities) uses its organization's repository (`package:ORG/PACKAGE`), or requests `repository:ORG` to fetch. Successful response:

```nohighlight
{
  "access_token": "<hex-access-token>",
  "token_type": "bearer",
  "expires_in": 900,
  "scope": "package:hexpm/PACKAGE"
}
```

Errors use OAuth-style bodies (`error`, `error_description`), for example missing fields (`invalid_request`), a malformed or missing `scope` (`invalid_scope`), bad or replayed OIDC tokens (`invalid_grant`), or no matching workload identity (`access_denied`). An unknown package, repository, or organization returns the same `access_denied` as no matching workload identity. A matching workload identity of an organization without an active billing state also gets `access_denied`, with a description saying so.

The grant is public, since the OIDC token is the credential. Exchanges are limited to 1,000 a minute per address, far above what CI runners sharing an address send, and beyond that the endpoint answers `429`. Exchanges that fail after the OIDC token is verified count toward a limit per GitHub repository. Once a repository exceeds it, the endpoint answers `429` with `slow_down` for that repository only. Tokens from rejected events and replayed tokens don't count, because a pull request from a fork can produce them.

To revoke a Hex token before it expires, for example at the end of the job, send it to the standard revocation endpoint ([RFC 7009](https://www.rfc-editor.org/rfc/rfc7009)), again without a `client_id`:

```nohighlight
POST /api/oauth/revoke
Content-Type: application/x-www-form-urlencoded

token=<hex-access-token>
```

### Security model

* Hex verifies the GitHub OIDC signature with discovery and JWKS, rejects `none` and HMAC algorithms, and checks `iss`, `aud`, `exp`, `nbf`, and `iat`.
* Matching requires the configured repository, the workflow basename from a workflow ref inside that repository, the immutable `repository_owner_id` and `repository_id`, and the optional environment. A token without a `repository_id` claim never matches. The workflow is compared exactly, including casing. The repository, owner, and environment are compared case-insensitively, and the repository and owner are pinned by their immutable GitHub IDs. A reusable workflow from another repository doesn't satisfy the workflow match by having the same basename.
* Pinning the repository ID as well as the owner ID matters inside an organization. If the configured repository is deleted, anyone who can create a repository in that organization could otherwise recreate the name, add the configured workflow, and get a token. The owner ID alone wouldn't stop that.
* Hex tokens issued this way expire after 15 minutes, cover one package or one organization repository, and are attributed to the workload identity. The release has no publishing user, and the audit log records the publish.
* Hex rejects tokens from `pull_request_target` and `workflow_run` workflows. A `workflow_run` run gets write permissions even when a pull request from a fork triggered the run that started it, and no OIDC claim says whether one did.
* Configuring or removing a package workload identity requires full package ownership and two-factor authentication, because a workload identity grants publish rights the same way a personal API key does. Hex emails every package owner when a workload identity is added or removed, and the email can't be turned off. Transferring the package removes its workload identities. The CI exchange and publish don't require two-factor authentication, because the grant has no interactive user.
* Hex records an allowlisted snapshot of the verified OIDC claims (repository, workflow ref, commit SHA, run id, and similar) on the Hex token and attaches it to the release published with that token. The release API exposes it as `oidc_claims`. The package page shows it in a Provenance card that links to the source commit, build file, branch or tag, environment, triggering actor, and workflow run, so anyone using the package can see that a release was published with Workload Identity and which workflow produced it.

### Limitations

* Only GitHub Actions can act as a workload identity. GitLab, CircleCI, and custom OIDC issuers aren't supported.
* A package's workload identities can't create a package or publish its first release from CI. Publish once manually, then attach a workload identity. For a private package, use an organization workload identity, which can create it.

### Troubleshooting

* **The form reports the GitHub repository could not be resolved:** the GitHub owner doesn't exist or is misspelled. Hex could read neither the repository nor the owner profile.
* **The form reports that a repository ID is required:** Hex couldn't see the repository, so it can't pin the ID itself. For a private repository, fill in the repository ID field. For a public one, this usually means the repository name is misspelled, because GitHub answers 404 both for a repository that doesn't exist and for one Hex can't see, so a typo looks the same as a private repository. A wrong repository name combined with a repository ID you fill in is created but never matches, and the exchange returns no matching workload identity.
* **The form reports that GitHub could not be reached:** GitHub was unreachable, rate-limited, or answered with something unexpected. Nothing was stored, so you can submit the same form again.
* **The exchange returns no matching workload identity:** check the package name, Hex repository, GitHub `owner/repo`, workflow **filename**, and optional environment against the configured workload identity, including the exact casing of the workflow filename. The workflow file that requests the OIDC token must be in the configured repository.
* **The exchange rejects the OIDC token:** confirm `id-token: write`, audience `hexpm`, and that you aren't reusing a JWT that was already exchanged.
* **The exchange rejects a token from a `pull_request_target` or `workflow_run` workflow:** both events run with the base repository's permissions when a pull request from a fork triggered them, so code from a fork could request an OIDC token. Publish from `push`, `release`, or `workflow_dispatch` instead.
* **Publish fails with package ownership or scope errors:** the Hex token only covers the package named in the exchange. Exchange again for that package name.
* **The "Workload identities" tab is missing, or the token endpoint returns `unsupported_grant_type`:** Workload Identity may be disabled on that Hex deployment, or your account isn't a full owner of the package.
