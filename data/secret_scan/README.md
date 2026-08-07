# Secret scanning rules

`gitleaks.toml` is vendored from
[gitleaks](https://github.com/gitleaks/gitleaks), MIT licensed, see
`LICENSE.gitleaks`. Never hand-edit it, and do not add rules of our own
alongside it. A rule nobody upstream has validated is where false positives
come from, and a rule that decides by consulting our own data, checking a
candidate against the `keys` table say, turns the scanner into an oracle that
answers questions about that data for whoever chooses the input.

One mechanical rewrite is applied on the way in. gitleaks allowlists example
keys by spelling them out in full, so vendoring the file unchanged puts real
credential shapes in this repository and GitHub's secret scanning opens an
alert for each one. The refresh task wraps the last byte of each in a character
class: `[7]` and `7` are the same regex, so the allowlists keep working, and
the file holds no contiguous literal. `rules_test.exs` fails if a refresh skips
it.

Vendored from `config/gitleaks.toml` at commit
`09242ce9c8a60d9b051fc2d166f9e849b88c7ac0` (2025-11-20), gitleaks v8.30.1.

## Refreshing

```sh
mix hexpm.secret_scan.refresh
```

This rewrites `gitleaks.toml` and `LICENSE.gitleaks` from the latest gitleaks
release and prints the commit it pulled. Update the commit line above to match,
then run the tests. `rules_test.exs` asserts every regex compiles and that the
rule count is in range, so a config that changed shape fails loudly rather than
silently dropping rules.

New rule ids do not send email until they are added to `@notify_rules` in
`Hexpm.SecretScan.Rules`. Everything else is recorded silently.

## Compatibility

The regexes are written for Go's RE2. RE2 has no lookaround or backreferences,
so every pattern is inside what Erlang's PCRE accepts, and all of them compile
unmodified. The two engines differ in performance, not in what they match: PCRE
backtracks, so the keyword prefilter is what keeps the scan affordable.
