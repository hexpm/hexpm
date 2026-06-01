## New HexDocs URLs: per-package subdomains

<div class="subtitle"><time datetime="2026-06-01T00:00:00Z">1 June, 2026</time> · by Eric Meadows-Jönsson and Jonatan Männchen</div>

HexDocs URLs are changing. Public package docs move from `hexdocs.pm/package` to `package.hexdocs.pm`, and private organization docs move from `org.hexdocs.pm/package` to `org.hexorgs.pm/package` (note the new top-level domain). This isolates packages from each other in the browser, addressing a finding from our recent [security audit](/blog/security-audit).

* Public packages: `hexdocs.pm/package` → `package.hexdocs.pm`
* Organization packages: `org.hexdocs.pm/package` → `org.hexorgs.pm/package`

Because DNS labels do not allow underscores, packages whose name contains `_` will have it replaced with `-` in the subdomain. For example, `hexdocs.pm/ecto_sql` now lives at `ecto-sql.hexdocs.pm`.

### Why we did this

HexDocs pages are essentially user-controlled websites. They can contain any HTML, CSS, and JavaScript a maintainer chooses to ship, and we want to keep that flexibility:

* Different documentation tools (ExDoc, Gleam's docs, etc.) produce different output.
* Maintainers embed things like Mermaid diagrams, KaTeX math, interactive examples, and more.
* New tools and ideas should not be blocked by a restrictive sandbox.

That flexibility is also a risk. Under the previous scheme, every public package was served from the same origin, so a malicious or compromised package could in principle interact with content from other packages hosted under `hexdocs.pm`. Organization docs sat under a subdomain of the same registrable domain, so they were not as cleanly separated from public docs either.

Rather than restrict what maintainers can put in their docs, we chose to isolate packages from one another using the [same-origin policy](https://developer.mozilla.org/en-US/docs/Web/Security/Same-origin_policy). Giving each public package its own subdomain, and moving organization docs to a separate registrable domain (`hexorgs.pm`), lets the browser enforce separation between them.

A nice side effect: we think the new URLs read a bit more naturally too.

### What maintainers should do

* Update any links pointing at your docs (READMEs, websites, blog posts, social profiles) to the new form: `package.hexdocs.pm` for public packages, `org.hexorgs.pm/package` for organization docs.
* If your package name contains `_`, remember to replace it with `-` in the public subdomain.
* Old URLs will keep redirecting, so existing links will not break, but please update them when convenient.

We redirect the old URLs for every public package and for every organization, with one exception: organizations whose name is also the name of a public package. Because that public package now owns the `<name>.hexdocs.pm` subdomain, the matching organization's old `<name>.hexdocs.pm/package` URLs can no longer be redirected. If your organization shares its name with a public package, update those links to `org.hexorgs.pm/package` directly.

### Thanks

This work was funded by [Alpha-Omega](https://alpha-omega.dev/), as part of the same engagement that supported the [security audit](/blog/security-audit), through the [Erlang Ecosystem Foundation's Ægis initiative](https://security.erlef.org/aegis/).