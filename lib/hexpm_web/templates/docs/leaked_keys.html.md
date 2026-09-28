## Leaked API keys

If you reached this page from a GitHub secret scanning alert, your Hex.pm API key was found in a public location — a public GitHub repository, a public Gist, or a public npm package — and has been automatically revoked.

Hex.pm API keys carry a `hex_` prefix followed by 40 hexadecimal characters (for example `hex_0123456789abcdef0123456789abcdef0123abcd`). GitHub detects this pattern, forwards the matching token to Hex.pm, and we revoke it before it can be used by anyone who found it.

### What Hex.pm did automatically

* Verified the leaked token's checksum to confirm it was a real Hex.pm key.
* Revoked the key immediately. Subsequent requests using it return `401 Unauthorized`.
* Sent an email to the key's owner with the GitHub URL where it was found.

No further action is required from Hex.pm. The steps below are for you, the key owner.

### Step 1. Confirm the revocation

Open the [API keys page](/dashboard/keys) on your dashboard. The leaked key will appear with a revocation timestamp. If you do not see it as revoked, contact [support@hex.pm](mailto:support@hex.pm) — do not continue using the key.

### Step 2. Generate a replacement key

Create a new key on the [API keys page](/dashboard/keys). Scope it to the smallest permission set that the consumer actually needs — see [Permissions](/docs/permissions) for the available scopes. If you only need the key for publishing or for read access to a single repository, do not issue a full-access key.

For locally-stored credentials used by the Mix client, the simplest path is:

```nohighlight
mix hex.user auth
```

This generates and stores a new client-scoped key without you needing to copy a token by hand.

### Step 3. Update everywhere the leaked key was used

Replace the revoked key in every location it appears, including:

* `~/.hex/hex.config` and any other developer machines that authenticated with the old key.
* CI/CD secret stores — the conventional environment variable is `HEX_API_KEY`. Common locations: GitHub Actions repository and organization secrets, GitLab CI variables, CircleCI contexts, Jenkins credentials.
* Container images, Helm charts, or deployment manifests that bake in the token.
* `mix.exs` or release scripts that pass `--key` to `mix hex.publish`.

If you are unsure where the key was used, search your codebase, secret stores, and CI logs for the prefix `hex_` to find any references.

### Step 4. Review the audit log for unauthorized activity

Open the [audit log](/users/me/audit-logs) for your account and review the period between when the key was created and when it was revoked. Look for actions you did not perform yourself — new package releases, ownership changes, or key creation. For organization-owned keys, the relevant log is on the organization page.

If you find activity you did not authorize, contact [security@hex.pm](mailto:security@hex.pm) right away.

### Step 5. Clean the secret from your repository

Removing the file or pushing a follow-up commit is not enough — the leaked key is still present in your git history and can be recovered from the repository's reflog, from forks, and from clones already made by other people.

Because the key has been revoked, scrubbing it from history is no longer required for security. It can still be worth doing for hygiene; GitHub's guide [Removing sensitive data from a repository](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository) covers the available options.

### Step 6. Prevent future leaks

* **Use scoped keys.** A publish-only or read-only key cannot be used to take over your account. See [Permissions](/docs/permissions).
* **Set an expiry on CI keys.** Keys can be issued with an expiration date so a forgotten secret eventually stops working on its own.
* **Never commit a key.** Use your CI provider's secret store and read the value from an environment variable at runtime. Pre-commit hooks that grep for `hex_[0-9a-f]{40}` are a cheap second line of defense.
* **Rotate periodically.** A regular rotation cadence makes the impact of a future leak smaller.

### False positives or questions

If you believe the alert was a false positive, or you have questions about the revocation, contact [support@hex.pm](mailto:support@hex.pm). To report a security issue separately from a leaked key, email [security@hex.pm](mailto:security@hex.pm).
