## Hex.pm Security Audit: Results and Next Steps

<div class="subtitle"><time datetime="2026-04-08T00:00:00Z">8 April, 2026</time> · by Eric Meadows-Jönsson and Jonatan Männchen</div>

Over the past months, we conducted the first comprehensive third-party security audit of Hex.pm and its surrounding ecosystem. This work was made possible by [Alpha-Omega](https://alpha-omega.dev/), an initiative under the OpenSSF that funds security improvements for critical open source projects. The audit was carried out as part of the [Erlang Ecosystem Foundation's Ægis initiative](https://security.erlef.org/aegis/).

We worked with two independent security firms:

* [Paraxial.io](https://paraxial.io/) (white-box penetration testing)
* [zentrust partners GmbH](https://zentrust.partners/) (adversarial / red-team style assessment)

Both teams reviewed the Hex registry, clients, documentation infrastructure, and supporting systems across the Erlang, Elixir, and Gleam ecosystem.

We are publishing the full reports today:

<!-- TODO: Add final reports -->

* [Paraxial report](/reports/2026/paraxial.pdf)
* [zentrust report](/reports/2026/zentrust.pdf)
* [Alpha-Omega engagement overview](https://github.com/ossf/alpha-omega/tree/main/alpha/engagements/2026/Erlang%20Ecosystem%20Foundation%2C%20Inc.%20%28EEF%29)

### Why this audit

Hex is critical infrastructure for the BEAM ecosystem. It underpins package distribution for Erlang, Elixir, and Gleam, and is used in production systems across thousands of organizations.

Until now, no comprehensive external audit had been performed. The goal of this work was to:

* validate the current security posture
* identify real-world attack paths
* remediate issues quickly
* establish a baseline for future work

This was explicitly scoped as a review of the current system, not future roadmap items like attestations or SLSA, which will follow later.

### What was found

Across both audits, a number of issues were identified, ranging from high severity vulnerabilities to low-severity hardening gaps.

Examples include:

* Unsafe deserialization in `hex_core` that could lead to RCE under certain conditions
* A denial of service condition during package uploads
* Weaknesses in authentication flows and API key handling
* Gaps in CI/CD hardening (GitHub Actions)
* Missing or incomplete security controls in some areas

Importantly, the audits focused on realistic attack scenarios such as:

* cross-account package tampering
* bypassing integrity checks
* injection in public-facing features
* CI/CD compromise

### What we fixed

Most findings have been remediated during the engagement and confirmed in re-tests.

Highlights:

* Fixed unsafe deserialization in `hex_core` ([CVE-2026-21619](https://cna.erlef.org/cves/CVE-2026-21619.html))
* Fixed API key privilege escalation ([CVE-2026-21621](https://cna.erlef.org/cves/CVE-2026-21621.html))
* Fixed password reset issues ([CVE-2026-21622](https://cna.erlef.org/cves/CVE-2026-21622.html))
* Fixed XSS in OAuth device flow ([CVE-2026-21618](https://cna.erlef.org/cves/CVE-2026-21618.html))
* Fixed denial of service in package upload ([CVE-2026-23940](https://cna.erlef.org/cves/CVE-2026-23940.html))
* Removed sensitive credentials from repositories
* Hardened authentication flows (including "sudo mode" for sensitive actions)
* Disabled legacy TLS versions
* Improved CSP and other browser security controls

Re-tests by both firms confirmed that the majority of vulnerabilities were successfully remediated.

Several remaining items are either:

* accepted risks with clear rationale (for example UX trade-offs or staged migrations), or
* dependent on ecosystem-wide changes (for example client updates)

### What we decided not to change (yet)

Some findings reflect intentional trade-offs or transitional states rather than vulnerabilities.

Examples:

* Basic authentication and optional 2FA are still supported for compatibility with existing clients. Both will be phased out once all clients support the OAuth2 device flow.
* Certain features (like documentation hosting) intentionally allow user-provided content and are being isolated rather than restricted.

These decisions were reviewed jointly by the Hex.pm team and the EEF.

### What's next

We are wrapping up a few remaining items:

* Finish the transition away from Basic Auth by adding OAuth2 Device Grant support to Rebar3
* Add stronger isolation for HexDocs package documentation
* Expand security documentation and threat modeling for the ecosystem
* Implement API key expiry

### Thanks

A big thank you to [Alpha-Omega](https://alpha-omega.dev/) for funding this work, and to [Paraxial.io](https://paraxial.io/) and [zentrust partners](https://zentrust.partners/) for the thorough reviews.

This was the first audit of its kind for Hex and the BEAM ecosystem. It surfaced real issues, led to concrete fixes, and gives us a solid baseline to build on. We plan to continue this kind of work going forward.