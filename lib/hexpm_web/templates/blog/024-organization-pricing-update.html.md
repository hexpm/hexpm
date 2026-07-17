## Updating organization pricing

<div class="subtitle"><time datetime="2026-07-16T00:00:00Z">16 July, 2026</time> · by Eric Meadows-Jönsson</div>

We are updating the price of Hex.pm organizations to **$9 per user / month** or
**$90 per user / year**. This is the first price increase since paid organizations
and private packages went live in 2018.

Private packages first entered beta in 2017, and when organizations went live the
following year the price was $7 per user / month. Since then, we have added private
HexDocs, organization-owned keys for CI, annual billing, management of public packages,
organization audit logs, and signed dependency policies. We are also about to ship
file previews and package diffs for private packages. Throughout this time, we have
continued to develop Hex and operate the package infrastructure used by the Erlang,
Elixir, and Gleam communities.

### What is changing

New organization subscriptions will use the new pricing immediately. Existing
subscriptions will keep their current price for at least 60 days and move to the new
price at their first regular renewal after that grace period.

The increase will not be applied in the middle of a billing period, and it will not
change an organization's renewal date. Existing customers will see their current
price, new price, and the date of the change in the organization billing dashboard.

### Investing in Hex

We are grateful to our [sponsors](/sponsors) and to the organizations paying for
private packages. Recent grants have also funded specific security projects.
[Alpha-Omega](https://alpha-omega.dev/) funded our
[first comprehensive third-party security audit](/blog/security-audit) through the
[Erlang Ecosystem Foundation's Ægis initiative](https://security.erlef.org/aegis/).

Grants and sponsorships make important projects like the audit possible, but
organization subscriptions primarily fund Hex.pm's ongoing infrastructure,
operations, and development. That work has grown substantially, particularly as we
spend more time reviewing vulnerability reports, coordinating fixes, and improving
package publishing and supply chain security.

Recent improvements include requiring two-factor authentication for publishing,
OAuth-based CLI authentication, and additional protection for sensitive account
actions. Following the security audit, we also addressed many of the vulnerabilities
and hardening gaps it uncovered.

Hex 2.5 added security advisory warnings directly to dependency fetching, release-age
cooldowns, and signed dependency policies that organizations can enforce consistently
across their projects. These features help teams reduce the chance that a vulnerable,
malicious, or newly compromised release reaches production.

The new pricing helps us sustain that work while keeping Hex free for public packages
and open source users. Thank you to every organization that supports Hex.pm and the
BEAM ecosystem.
