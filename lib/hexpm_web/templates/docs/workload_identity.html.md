## Workload Identity

Workload Identity, sometimes also known as "Trusted Publishing", lets CI jobs publish and fetch Hex packages without storing a long-lived API key. A GitHub Actions job presents a short-lived OpenID Connect (OIDC) identity token. Hex verifies it against a workload identity you configured and returns a short-lived, scoped access token that the normal publish path accepts.

Package workload identities are for packages in the public `hexpm` repository. An organization's workload identities publish the packages in its private repository and fetch them, and can also publish the public packages the organization owns. See [Organization workload identities](#organization-workload-identities).

GitHub Actions is the only supported CI provider.

### How it works

1. A package owner configures a workload identity that names the GitHub repository, workflow file, and environment. The environment is optional for a private repository.
2. The CI job requests an OIDC token from GitHub with audience `hexpm`.
3. The job exchanges that token at Hex's OAuth token endpoint for a token for one package.
4. Hex verifies the token, matches a workload identity, and returns a Hex access token that expires in 15 minutes and can only publish that package.
5. The job publishes with `Authorization: Bearer <token>` (for Mix, `HEX_API_KEY="Bearer <token>"`, since Mix sends `HEX_API_KEY` as the raw `Authorization` header value).

The package must already exist. Workload identities can't create a public package or publish its first release, so do that once with a normal Hex account or API key. This is the same for an organization's workload identities, which only publish public packages the organization already owns.

Transferring a package (`mix hex.owner transfer`) removes its workload identities, so one that a previous owner set up can't keep publishing it. The new owners add their own. Adding or removing an owner without a transfer keeps them, and a removed owner who can still run one of their workflows on GitHub can still publish the package. Hex points this out when an owner is removed, in the confirmation on the Owners tab and in the email to the package's owners. Removing an organization member works the same way for organization workload identities.

An organization that owns a public package publishes it with its own workload identities that cover public packages. Transferring the package to the organization makes them publish it, and removing the organization as an owner or transferring the package away stops them. The email to the package's owners lists the organization workload identities that start or stop publishing the package, and so does the confirmation on the Owners tab when an organization is removed.

### Before you begin

You need:

* Full ownership of the Hex package (`owner` level, not only `maintainer`).
* Two-factor authentication enabled on your Hex account, from `/dashboard/security`. A workload identity grants publish rights the same way a personal API key does, so adding, changing or removing one has the same requirement.
* A GitHub Actions workflow that will publish, with the `id-token: write` permission.

### Configure a workload identity

Open the package page and go to the "Workload identities" tab. Only full owners see the tab, and the page requires two-factor authentication.

Fill in the form:

<dl class="dl-horizontal">
  <dt><code>Repository owner</code></dt>
  <dd>GitHub user or organization login that owns the repositories, for example <code>acme</code>. Case-insensitive, because GitHub logins are.</dd>
  <dt><code>Repositories</code></dt>
  <dd>The names of the repositories whose workflows can publish, without the owner, one per line, for example <code>widget</code>. Case-insensitive. A workload identity names at most 50 repositories. For a private repository, add its numeric repository ID after the name, see below.</dd>
  <dt><code>Workflow</code></dt>
  <dd>Workflow filename only, for example <code>release.yml</code> or <code>release.yaml</code>. Hex strips any path and matches the basename of the calling workflow in each of the repositories. <strong>Case-sensitive</strong>, so <code>Release.yml</code> and <code>release.yml</code> are different workflows.</dd>
  <dt><code>Environment</code></dt>
  <dd>GitHub Actions environment name. Required when one of the repositories is public, and strongly recommended otherwise. A GitHub environment is where you can require reviewers, add a wait timer, or restrict which branches can deploy, so it's the only place to add a check before a publish. GitHub <a href="https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments">offers environments</a> in public repositories on every plan and in private repositories only on paid plans, which is why Hex doesn't require one for a private repository. When it's set, the OIDC token must name the same environment, compared case-insensitively as GitHub compares environment names. When it's blank, Hex accepts any environment or none from a private repository, and no token from a public one.</dd>
</dl>

When you add a workload identity, Hex pins the immutable GitHub IDs of the owner and of each repository, so a GitHub login or repository that's deleted and created again can't inherit it. Adding it fails if an ID is missing.

The owner ID always comes from GitHub, because an owner's profile is public even when their repositories aren't. A repository ID comes from GitHub for a repository Hex can see, and Hex uses it instead of an ID typed after the name. For a private repository GitHub answers Hex with a 404, so you type the repository ID after the name, for example <code>gadget 123456</code>. Find it with:

```nohighlight
$ gh api repos/OWNER/NAME --jq .id
```

Because the workload identity is bound to the ID and not the name, deleting and recreating a GitHub repository stops it from matching that repository, even under the same name. If that happens, remove the repository from the workload identity and save, then add it again.

The "Edit" button on a workload identity changes its repositories, workflow and environment, and for an organization's, the packages it covers. Its repository owner and role stay, so add a new workload identity for a different owner or role. A repository it already names keeps its pinned ID, and saving fails if GitHub reports a different ID for it. Saving a change that removes a repository or changes the workflow or the environment revokes the tokens the workload identity issued. Hex emails a change to everyone it emails about an added workload identity, with what it trusted before and what it trusts now.

A package can have several workload identities, for example for several workflows, and one workload identity can name several repositories that publish with the same workflow and environment. The same GitHub repository and workflow can be attached to several packages as separate workload identities, which covers monorepos that release several packages from one repository. When one workflow run publishes several packages, exchange once per package and request a new OIDC token for each exchange, because an OIDC token can only be exchanged once.

### Organization workload identities

An organization admin configures workload identities for the organization's private repository, and for the public packages the organization owns, on the "Workload identities" page of the organization dashboard. Every member can see the page. Adding one requires the admin role and two-factor authentication on the admin's account, and changing or removing one has the same requirements. The `read` role and private packages also need an active billing subscription. A `write` workload identity that only covers public packages doesn't, the same as an organization API key publishing public packages, so the page stays usable without one and offers only public packages. Hex emails every organization admin when one is added, changed or removed, and records it in the organization's activity log. A package's own "Workload identities" tab lists the organization workload identities that can publish it and links to the organization page.

Each organization workload identity has a role:

<dl class="dl-horizontal">
  <dt><code>read</code></dt>
  <dd>Fetches every package in the organization's repository, including docs tarballs, from repo.hex.pm.</dd>
  <dt><code>write</code></dt>
  <dd>Publishes releases and docs of the packages it covers, as set by "Private packages" and "Public packages" below. With private packages it also fetches like <code>read</code> and creates new packages in the organization's repository.</dd>
</dl>

A `write` workload identity covers private packages, public packages or both:

<dl class="dl-horizontal">
  <dt><code>Private packages</code></dt>
  <dd>Packages in the organization's repository, checked by default. The list of package names limits which ones it covers. Leave it empty to cover every package in the repository. A name in the list doesn't have to exist yet, so the workflow can create that package.</dd>
  <dt><code>Public packages</code></dt>
  <dd>Public packages on hex.pm that the organization owns. Leave the list empty to cover every public package the organization owns, including packages it becomes an owner of later. The list can only name public packages the organization owns when the workload identity is added. It never creates a public package, so publish a package's first release with a user account or an API key, and transfer it to the organization with <code>mix hex.owner transfer</code>. Each public release shows the GitHub repository, workflow and actor that published it in its Provenance card and in the release API, also when the repository is private.</dd>
</dl>

The `read` role covers the organization's repository only, because public packages need no credentials to fetch.

The other fields are the same as for a package workload identity. The `write` role needs at least one repository and a workflow, and an environment when a repository is public. The `read` role can leave the repositories and the workflow empty, and never needs an environment:

* An empty workflow matches every workflow in the repositories, including test workflows. Anyone who can push a workflow file to one of them can then fetch, the same as with an organization API key stored as a repository secret, so set an environment with protection rules when that matters.
* No repositories match every repository owned by the repository owner, pinned by the owner's GitHub ID. Anyone who can create a repository under that owner, or push a workflow file to one of its repositories, can then fetch, the same as with an organization API key stored as a GitHub organization secret available to all repositories. The workflow and environment must be empty too, because whoever creates a repository also names its workflows and environments.

The `write` role always names its repositories, because publishing reaches everyone who depends on the packages, and an environment can't narrow a workload identity that matches every repository: whoever creates a repository also creates its environments and their protection rules.

A common setup is one `read` workload identity without repositories, so every repository in your GitHub organization can fetch private dependencies, and one `write` workload identity naming the repositories that release packages with the same release workflow and environment.

A public package is published by its own package workload identities and by the workload identities with public packages of the organizations that own it. Hex checks the organization's ownership at the exchange and again at publish, the same as for an organization API key, which needs the owner level "maintainer" or "full". Removing the organization as an owner or transferring the package away stops its workload identities from publishing the package at once, and the identities stay on the organization's page. Private packages only use organization workload identities.

Adding or removing a workload identity with public packages also emails the other owners of the public packages it covers, one email per person naming their packages, the same as adding a package workload identity emails every package owner.

Neither role can retire releases, revert, or change owners, keys, members, or settings. The organization's single sign-on and two-factor authentication requirements don't apply to organization workload identities, the same as for organization API keys.

To fetch, exchange the OIDC token for a repository token by setting the scope to the organization's repository:

```nohighlight
scope=repository:ORG
```

Send the access token to repo.hex.pm as `Authorization: Bearer <token>`. It can't call the Hex API.

Mix does this exchange itself when it fetches packages from an organization's repository in a GitHub Actions job with the `id-token: write` permission, and neither an organization key nor an authenticated user is configured.

To publish or create a private package, use a package scope in the organization's repository, the same as for a package workload identity:

```nohighlight
scope=package:ORG/PACKAGE
```

Hex matches the organization's `write` workload identities with private packages whose list covers the name. A package created this way has no owners, the same as one created with an organization API key. A job that fetches private dependencies and then publishes exchanges twice, once per scope, with a new OIDC token each time.

To publish a public package the organization owns, use the public repository's package scope:

```nohighlight
scope=package:hexpm/PACKAGE
```

Hex matches the package's own workload identities, and the `write` workload identities with public packages of the organizations that own it whose list is empty or names the package. A name no public package has gets the same `access_denied` as no matching workload identity.

Removing a workload identity stops its tokens at the Hex API on the next request. repo.hex.pm verifies tokens without asking Hex, so a fetch token keeps working there until it expires, at most 15 minutes later. A lapsed billing subscription behaves the same, since Hex checks billing during the exchange for the organization's repository. Publishing public packages doesn't need an active subscription.

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
    # The GitHub Environment the workload identity names. Required for a public
    # repository.
    environment: release
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
* A workload identity for a public repository names a GitHub Environment, so only jobs in that environment can get a token. For a private repository the environment is optional, and still the only way to put protection rules in front of a publish.

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

No `client_id` is needed, because the OIDC token is the credential. `scope` names exactly one package as `package:REPOSITORY/PACKAGE`. An [organization workload identity](#organization-workload-identities) uses its organization's repository (`package:ORG/PACKAGE`) for a private package and `package:hexpm/PACKAGE` for a public one, or requests `repository:ORG` to fetch. Successful response:

```nohighlight
{
  "access_token": "<hex-access-token>",
  "token_type": "bearer",
  "expires_in": 900,
  "scope": "package:hexpm/PACKAGE"
}
```

Errors use OAuth-style bodies (`error`, `error_description`), for example missing fields (`invalid_request`), a malformed or missing `scope` (`invalid_scope`), bad or replayed OIDC tokens (`invalid_grant`), or no matching workload identity (`access_denied`). An unknown package, repository, or organization returns the same `access_denied` as no matching workload identity. A matching workload identity of an organization without an active billing state also gets `access_denied` for the organization's repository, with a description saying so.

The grant is public, since the OIDC token is the credential. Exchanges are limited to 1,000 a minute per address, far above what CI runners sharing an address send, and beyond that the endpoint answers `429`. Exchanges that fail after the OIDC token is verified count toward a limit per GitHub repository. Once a repository exceeds it, the endpoint answers `429` with `slow_down` for that repository only. Tokens from rejected events and replayed tokens don't count, because a pull request from a fork can produce them.

To revoke a Hex token before it expires, for example at the end of the job, send it to the standard revocation endpoint ([RFC 7009](https://www.rfc-editor.org/rfc/rfc7009)), again without a `client_id`:

```nohighlight
POST /api/oauth/revoke
Content-Type: application/x-www-form-urlencoded

token=<hex-access-token>
```

### Security model

* Hex verifies the GitHub OIDC signature with discovery and JWKS, rejects `none` and HMAC algorithms, and checks `iss`, `aud`, `exp`, `nbf`, and `iat`.
* Matching requires one of the configured repositories, the workflow basename from a workflow ref inside that repository, the immutable `repository_owner_id` and `repository_id`, and the environment when one is configured. A token without a `repository_id` claim never matches. A workload identity that can publish and has no environment matches no token whose `repository_visibility` claim is `public`. The workflow is compared exactly, including casing. The repository, owner, and environment are compared case-insensitively, and the repository and owner are pinned by their immutable GitHub IDs. A reusable workflow from another repository doesn't satisfy the workflow match by having the same basename.
* Pinning the repository ID as well as the owner ID matters inside an organization. If the configured repository is deleted, anyone who can create a repository in that organization could otherwise recreate the name, add the configured workflow, and get a token. The owner ID alone wouldn't stop that.
* Hex tokens issued this way expire after 15 minutes, cover one package or one organization repository, and are attributed to the workload identity. The release has no publishing user, and the audit log records the publish.
* Hex rejects tokens from `pull_request_target` and `workflow_run` workflows. A `workflow_run` run gets write permissions even when a pull request from a fork triggered the run that started it, and no OIDC claim says whether one did.
* Adding, changing or removing a package workload identity requires full package ownership and two-factor authentication, because a workload identity grants publish rights the same way a personal API key does. Hex emails every package owner when a workload identity is added, changed or removed, and the email can't be turned off. Transferring the package removes its workload identities. An organization workload identity with public packages emails the owners of the public packages it covers in the same way. The CI exchange and publish don't require two-factor authentication, because the grant has no interactive user.
* Hex records an allowlisted snapshot of the verified OIDC claims (repository, workflow ref, commit SHA, run id, and similar) on the Hex token and attaches it to the release published with that token. The release API exposes it as `oidc_claims`. The package page shows it in a Provenance card that links to the source commit, build file, branch or tag, environment, triggering actor, and workflow run, so anyone using the package can see that a release was published with Workload Identity and which workflow produced it.

### Limitations

* Only GitHub Actions can act as a workload identity. GitLab, CircleCI, and custom OIDC issuers aren't supported.
* Workload identities can't create a package or publish its first release from CI, except an organization workload identity creating a package in the organization's repository. Publish a public package once manually, then attach a workload identity, or transfer the package to an organization whose workload identities cover public packages.

### Troubleshooting

* **The form reports the GitHub repository could not be resolved:** the GitHub owner doesn't exist or is misspelled. Hex could read neither the repository nor the owner profile.
* **The form reports that a repository needs its repository ID after the name:** Hex couldn't see the repository, so it can't pin the ID itself. For a private repository, type its ID after the name. For a public one, this usually means the repository name is misspelled, because GitHub answers 404 both for a repository that doesn't exist and for one Hex can't see, so a typo looks the same as a private repository. A wrong repository name combined with a repository ID you type is saved but never matches, and the exchange returns no matching workload identity.
* **The form reports that a repository was deleted and created again on GitHub:** GitHub reports a different ID for a repository the workload identity already names. Remove the repository and save, then add it again to pin the new repository.
* **The form reports that the environment is required because a repository is public:** a workload identity that can publish from a public repository must name a GitHub environment. Create one under the repository's Settings, Environments, add protection rules such as required reviewers, set `environment:` on the publishing job, and enter the environment's name in the form.
* **The form reports that public package names must be public packages the organization owns:** a listed name isn't a public package, or the organization isn't one of its owners. Publish the package's first release and transfer it to the organization first, or remove the name from the list.
* **The form reports that private packages or the read role need an active billing subscription:** the organization's subscription isn't active. Set up billing on the organization's Billing page, or add a `write` workload identity that only covers public packages.
* **The form reports that GitHub could not be reached:** GitHub was unreachable, rate-limited, or answered with something unexpected. Nothing was stored, so you can submit the same form again.
* **The exchange returns no matching workload identity:** check the package name, Hex repository, GitHub `owner/repo`, workflow **filename**, and environment against the configured workload identity, including the exact casing of the workflow filename. The workflow file that requests the OIDC token must be in the configured repository. A workload identity that publishes without an environment stops matching a repository that's made public, so add an environment to it.
* **The exchange rejects the OIDC token:** confirm `id-token: write`, audience `hexpm`, and that you aren't reusing a JWT that was already exchanged.
* **The exchange rejects a token from a `pull_request_target` or `workflow_run` workflow:** both events run with the base repository's permissions when a pull request from a fork triggered them, so code from a fork could request an OIDC token. Publish from `push`, `release`, or `workflow_dispatch` instead.
* **Publish fails with package ownership or scope errors:** the Hex token only covers the package named in the exchange. Exchange again for that package name.
* **The "Workload identities" tab is missing, or the token endpoint returns `unsupported_grant_type`:** Workload Identity may be disabled on that Hex deployment, or your account isn't a full owner of the package.
