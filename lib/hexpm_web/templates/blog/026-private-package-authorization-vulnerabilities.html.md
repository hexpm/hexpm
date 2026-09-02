## Private package authorization vulnerabilities

<div class="subtitle"><time datetime="2026-09-01T00:00:00Z">1 September, 2026</time> · by Eric Meadows-Jönsson</div>

On 24 August 2026 we found and fixed two vulnerabilities in how hex.pm issues
OAuth tokens. Both could give an account read access to private packages of an
organization it was not entitled to. Neither was being exploited when we found
them: no active token carried a scope for an organization its holder could not
access. Whether either had been used earlier we cannot say, because the
records that would settle that had been deleted by routine cleanup. This post
describes both vulnerabilities, what we could and could not establish, and
what we changed in authorization and in logging. Organization admins are also
being notified by email.

### CVE-2026-75542: token exchange for organizations the key holder could not access

Any hex.pm account can create an API key with the `repositories` permission,
which means "every repository this account has access to". Since 18 October
2025 such a key could be exchanged, through the OAuth `client_credentials`
grant, for an access token. The exchange admitted a requested scope if the
key held `repositories` and the scope string began with `repository:`. The
organization name after the colon was never resolved against the account's
memberships, so the key could be exchanged for a token scoped to any
organization on hex.pm.

Our CDN authorizes private package downloads from the signed token alone,
without a database lookup. A token created this way was therefore working read
access to the named organization's private packages for its 30-minute
lifetime, and it could be created again at will. No request reached the
application, so nothing there could have refused or recorded it. From
15 March 2026 the same was true of organization keys.

The advisory is
[GHSA-rfx8-w654-8cpr](https://github.com/hexpm/hexpm/security/advisories/GHSA-rfx8-w654-8cpr).

### CVE-2026-75554: organization scopes surviving removal from the organization

When a token is created with the plain `repositories` scope, which is what the
Hex client requests, hex.pm expands it into one scope per organization the
account is currently a member of, and expands it again on every refresh. A
session granted an explicit `repository:<org>` or `docs:<org>` scope instead,
which is how the authorization screen stores a selection, was not expanded
again: every refresh reproduced the scope as granted. Since 10 October 2025
a user removed from an organization could keep downloading its private
packages and private docs for as long as they kept refreshing, up to the
30-day refresh token lifetime, instead of losing access within the 30-minute
access token lifetime.

The advisory is
[GHSA-24ww-j3f4-p49c](https://github.com/hexpm/hexpm/security/advisories/GHSA-24ww-j3f4-p49c).

### What we could establish

We found both vulnerabilities on 24 August 2026 and deployed the fixes the
same day, shortly after 13:46 UTC. The advisories were published that
evening.

When we found the vulnerabilities we checked every active token against its
holder's access. No token carried a scope for an organization its holder
could not access, so neither vulnerability was being exploited at the time.
Since the fix, every token issued is checked the same way at the
moment it is created. Of the 92,968 tokens on record as of 30 August 2026,
none carried a scope its holder was not entitled to.

For the period before the fix we cannot say. The database rows recording
which token was issued to whom, with which scopes, were deleted by a nightly
cleanup job once the token could no longer be used, which for a
`client_credentials` token is within a day of its issue. The CDN access logs
for repo.hex.pm cover the whole period and record the client IP, time,
path, status and user agent of every download, but not the account behind
it. Between 18 October 2025 and 24 August 2026 we can neither confirm nor
exclude that an account outside an organization downloaded its private
packages.

### What we changed in authorization

Requested organization scopes are now resolved against the requesting
principal's actual access every time a token is created, including refreshes.
A user's scopes are held against current memberships and an organization key's
against its own organization. Scopes the principal is not entitled to are
dropped, and every grant type goes through one token builder, so no grant can
skip the check. The public repository stays available to everyone.

### What we changed in logging

The token records were deleted by the nightly cleanup job, and the access
logs did not record which account made a request. We made four changes:

1. **Authorization records are archived before deletion.** The cleanup job
   now writes every row it deletes, including OAuth tokens, API keys and
   sessions, to write-once storage with a ten-year retention policy, with
   the secret material removed. The archive records who was granted which
   scopes, when, and through which key or session.
2. **A standing entitlement check.** A query over the archive and the live
   records lists every token whose organization scopes were not covered by
   membership at the time it was created, judged against the membership
   history in the organization audit log. It is the check reported above,
   and it can be run again under a different rule later.
3. **Identity in the CDN access log.** Each repo.hex.pm access-log line now
   ends with the id of the token or API key that authorized the request,
   never the credential itself, so a private package download can be
   attributed to the account behind it.
4. **Origin and application logs.** Requests to the storage bucket behind
   repo.hex.pm are logged again, which they had not been since 2018,
   application logs are kept for ten years, and every audit-log entry
   written from a request carries the id of that request, so it can be
   matched to the request log.

### For organization admins

The fix needs no change on your side. If you want to assess the period
before the fix for your organization, we can extract from the CDN logs the
client IPs, times and user agents of every download of your organization's
private packages between 18 October 2025 and 24 August 2026, for you to
compare against your own team. Email [security@hex.pm](mailto:security@hex.pm)
from an admin account of the organization.

We take the trust organizations place in hex.pm seriously. When
vulnerabilities are found, we will fix them quickly, investigate their
impact, and be transparent about what we know and what we cannot establish.
