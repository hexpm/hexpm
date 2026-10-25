## Keys

Keys authenticate the Hex client, CI jobs and other tools with Hex.pm. They're used for the API, for fetching packages from private repositories and for private documentation. Each key carries one or more permissions, and a key can only do what its permissions allow.

There are two kinds of keys:

* A **personal key** belongs to your account. It can never do more than your account can, so each permission is limited by your own package ownership and organization roles at the time the key is used.
* An **organization key** belongs to an organization and authenticates as the organization, not as the member who created it. It keeps working when that member leaves, and when the organization requires [single sign-on](/docs/organization-sso) or two-factor authentication. Its permissions are limited when it's created, by the role of the member who creates it.

Use an organization key for automation that acts for an organization, and a personal key for your own use.

`api:write` includes every write permission, so a key with `api:write` can do everything the narrower write permissions below allow. Neither `api:write` nor `api:read` allows fetching from private repositories, which needs an organization key with `repository:acme` or `repositories`.

### Personal keys

Create a personal key on the [keys page](/dashboard/keys) of your dashboard and pick its permissions under "Key permissions".

| Permission | Allows |
|---|---|
| `api:read` | Every API read your account can make. |
| `api:write` | Every API action your account can make, including all the write permissions below. |
| `publish` | Publishing, reverting, retiring and unretiring releases, and publishing documentation, on packages you maintain. It can't change package owners. |
| `publish:name` | The same as `publish`, for one package. Use `publish:acme/name` for a package in an organization. |
| `owners` | Adding and removing owners on packages you fully own. |
| `owners:name` | The same as `owners`, for one package. |
| `package:name` | Publishing and changing owners for one package, and every API read. The dashboard calls this "Manage". |
| `keys` | Revoking keys. A key can't create other keys, create them on the keys page. |
| `members` | Adding and removing members and changing their roles, in organizations where you're an admin. |
| `administration` | Changing the number of seats, in organizations where you're an admin. |

An organization that requires single sign-on can turn personal keys away.

### Organization keys

Members create organization keys on the organization's keys page in the dashboard, or with `mix hex.organization key` after signing in with `mix hex.user auth`:

```nohighlight
$ mix hex.organization key acme generate
126d49fb3014bd26457471ebae97c625
```

The key gets `repository:acme` unless you pass `--permission`, which you can repeat:

| Permission | Allows |
|---|---|
| `api:read` | Every API read the organization can make. |
| `repository:acme` | Fetching packages from the organization's repository. |
| `docs:acme` | Fetching the organization's documentation from hexdocs.pm. |
| `publish` | Publishing, reverting, retiring and unretiring releases, and publishing documentation, on any package the organization can act on. It can't change package owners. |
| `publish:acme/name` | The same as `publish`, for one package. |
| `keys` | Revoking the organization's keys. A key can't create other keys. |
| `owners` | Adding and removing owners on any package the organization can act on. |
| `owners:acme/name` | The same as `owners`, for one package. |
| `package:acme/name` | Publishing and changing owners for one package, and every API read. |
| `members` | Adding and removing members and changing their roles. |
| `administration` | Changing the number of seats. |
| `api:write` | Every API action, including all the permissions above except repository and documentation fetches. |

For example, a CI job that only publishes one package can use:

```nohighlight
$ mix hex.organization key acme generate --key-name ci-publish --permission api:read --permission publish:acme/mypackage
```

A member can only give a key the permissions their organization role allows them to use themselves:

| Role | Can grant |
|---|---|
| read | `api:read`, `repository:acme`, `docs:acme` |
| write | The above, and `publish`, `publish:acme/name` and `keys` |
| admin | Every permission |

When a write member asks for `api` or `api:write`, the key gets `api:read`, `publish` and `keys`. A read member gets `api:read`. A member's sign-in never grants more than the member's role allows. Revoking keys requires the write role.
