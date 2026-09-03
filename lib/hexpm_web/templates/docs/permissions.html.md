## API Permissions and Scopes

When authorizing applications or generating API keys, you'll be asked to grant specific permissions (also called "scopes"). Understanding these permissions helps you make informed security decisions about what access you're granting.

### Overview

Hex uses a permission system that controls what actions an API key or authorized application can perform. Permissions follow a principle of least privilege: only grant the minimum permissions needed for the intended use case.

### Available Scopes

#### `api` - Complete API Access

**What it includes:**
- **Package Management:** Publish, unpublish, retire, and unretire packages
- **API Key Management:** Create, list, and revoke API keys
- **Account Settings:** Update profile information, email addresses, and account preferences
- **Read Access:** View all account information, packages, organizations, and audit logs

**What it excludes:**
- Account deletion
- Billing and payment information (view or modify)
- Two-factor authentication settings

**Security Requirements:**
- **Requires two-factor authentication (2FA)** to be enabled on your account
- This is the most privileged scope and should be used sparingly

**Common Use Cases:**
- CI/CD pipelines that need to publish packages
- Administrative tools that manage multiple aspects of your account
- Package maintainer workflows that require full control

---

#### `api:read` - Read-Only API Access

**What it includes:**
- **View Packages:** List and view details of all your packages
- **View Account Information:** Read your profile, organizations, and memberships
- **View Audit Logs:** Access audit logs for security monitoring
- **View API Keys:** List existing API keys (but cannot create or revoke them)

**What it excludes:**
- Any modification or write operations
- Cannot publish, unpublish, or modify packages
- Cannot create or revoke API keys
- Cannot update account settings

**Security Requirements:**
- No special requirements

**Common Use Cases:**
- Monitoring and analytics tools
- Package discovery and search applications
- Read-only dashboards and reporting tools
- Security audit and compliance tools

---

#### `api:write` - Read and Write API Access

**What it includes:**
- **Package Management:** Publish, unpublish, retire, and unretire packages
- **Package Metadata:** Update package descriptions, documentation, and other metadata
- **API Key Management:** Create, list, and revoke API keys
- **Read Access:** View all account information, packages, organizations, and audit logs

**What it excludes:**
- Account settings and profile modifications
- Account deletion
- Billing and payment information

**Security Requirements:**
- **Requires two-factor authentication (2FA)** to be enabled on your account

**Common Use Cases:**
- CI/CD pipelines focused on package publishing
- Package management tools that don't need account administration
- Automation scripts for package operations

---

#### `repositories` - Private Repository Access

**What it includes:**
- **Fetch Private Packages:** Download and install packages from private repositories you belong to
- **Repository Listing:** View the private repositories you have access to

**What it excludes:**
- Publishing packages (use `api:write` or `api` for this)
- Modifying repository settings
- Managing repository memberships
- Any operations outside of fetching packages

**Security Requirements:**
- No special requirements
- Access is limited to repositories where you already have membership

**Common Use Cases:**
- Development machines that need to fetch private dependencies
- CI/CD pipelines that only need to install (not publish) private packages
- Team members who consume private packages but don't publish them

**Relationship to Other Scopes:**
- This scope is independent of `api`, `api:read`, and `api:write`
- To both fetch AND publish to private repositories, you need both `repositories` and `api:write` (or `api`)
- The `api:read` scope does NOT grant access to fetch private packages; you need `repositories` for that

---

### Resource-Specific Scopes

In addition to the general scopes above, Hex supports fine-grained permissions for specific resources:

#### `package:{org}/{name}` - Manage Specific Package

Grants permission to manage a single package. Useful for creating limited-access API keys for specific packages.

**Example:** `package:acme/my_app` allows managing only the `acme/my_app` package

#### `repository:{name}` - Access Specific Private Repository

Grants access to fetch packages from a single private repository.

**Example:** `repository:acme` allows fetching packages from the `acme` private repository only

---

### Best Practices

#### 1. Use Least Privilege
Always grant the minimum permissions needed for the task:
- For CI/CD that only publishes: use `api:write`
- For fetching private packages: use `repositories` only
- For read-only monitoring: use `api:read`

#### 2. Enable Two-Factor Authentication
Before using `api` or `api:write` scopes, enable 2FA on your account for added security.

#### 3. Use Resource-Specific Scopes
When possible, use package-specific or repository-specific scopes instead of broad permissions. A key that manages one package needs `package:{org}/{name}` rather than `api:write`. Grant it by checking that package under "Packages" when you generate the key.

#### 4. Rotate API Keys Regularly
Regularly revoke old API keys and generate new ones, especially for CI/CD pipelines.

#### 5. Audit Your Permissions
Periodically review authorized applications and API keys in your [dashboard security settings](/dashboard/security).

#### 6. Use Separate Keys for Different Purposes
Create separate API keys for different tools and environments:
- One key for CI/CD
- One key for local development
- One key for each automation script

This allows you to revoke access for a specific purpose without affecting others.

---

### Managing API Keys

#### Generate a New Key

Keys are generated on the [keys page](/dashboard/keys) of your dashboard:

1. Select "Generate New Key".
2. Enter a key name, such as `publish-ci`.
3. Choose an expiration.
4. Under "Key permissions", check the scopes to grant. "Read" and "Write" sit beneath "API", private repositories beneath "All Repositories", and single packages beneath "Packages".
5. Select "Generate Key".

The key is shown once, when you generate it.

#### List Existing Keys

The keys page lists every key on your account with its name, permissions, expiration, and last use.

#### Revoke a Key

Select the revoke action in the key's row on the keys page.

#### For Organization Keys

```bash
# Generate organization key
$ mix hex.organization key acme generate --key-name publish-ci --permission api:write

# List organization keys
$ mix hex.organization key acme list

# Revoke organization key
$ mix hex.organization key acme revoke key-name
```

---

### Authorized Applications

When you authorize an application using the OAuth device flow, you can selectively grant permissions:

1. The application requests certain scopes
2. You can uncheck scopes you don't want to grant
3. The application receives only the permissions you approved

You can review and revoke authorized applications at any time in your [dashboard security settings](/dashboard/security).

---

### Security Considerations

#### Destructive Actions

While scopes like `api` and `api:write` are powerful, they do NOT allow:
- Deleting your account
- Modifying billing or payment information
- Disabling two-factor authentication
- Transferring package ownership (requires manual action)

These sensitive operations require direct user action through the web interface.

#### Scope Inheritance

Scopes do not inherit from each other:
- Having `api:write` does NOT grant `repositories` access
- Having `repositories` does NOT grant `api:read` access
- Each scope must be explicitly granted

#### Private Repository Access

The `repositories` scope grants access to ALL private repositories you belong to. For more granular control, use repository-specific scopes: `repository:name`

---

### Common Scenarios

#### Scenario 1: CI/CD Publishing Public Packages
**Recommended Scopes:** `api:write`

Check "Write" beneath "API".

#### Scenario 2: CI/CD Publishing to Private Repository
**Recommended Scopes:** `api:write` (publishing) + `repositories` (fetching private dependencies)

Check "Write" beneath "API", and check "All Repositories".

#### Scenario 3: Development Machine Fetching Private Packages
**Recommended Scopes:** `repositories` only

Check "All Repositories", or a single organization beneath it.

#### Scenario 4: Read-Only Monitoring Tool
**Recommended Scopes:** `api:read`

Check "Read" beneath "API".

#### Scenario 5: Single Package Management
**Recommended Scopes:** `package:org/name`

Check the package beneath "Packages".

---

### Further Reading

- [Publishing Packages](/docs/publish)
- [Private Packages and Organizations](/docs/private)
- [Security Settings](/dashboard/security)
- [API Documentation](https://github.com/hexpm/specifications/blob/main/apiary.apib)

---

### Questions?

If you have questions about permissions or need help choosing the right scopes for your use case, please:
- Check our [FAQ](/docs/faq)
- Ask in the [Hex category on the Elixir Forum](https://elixirforum.com/c/hex-pm/11)
- Contact support at [support@hex.pm](mailto:support@hex.pm)
