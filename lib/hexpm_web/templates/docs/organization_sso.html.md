## Organization single sign-on

Organization single sign-on (SSO) lets members sign in to an organization through an OpenID Connect (OIDC) identity provider. Customer-created Okta applications are the supported and documented integration. Microsoft Entra interoperability and Okta Integration Network distribution remain private validation targets until their live provider test matrices are complete.

Organization SSO and its domain-based features are currently available only to organizations enabled by Hexpm's runtime SSO gate. It is optional and scoped to one Hexpm organization, so conventional Hexpm login remains available. It does not create accounts, add organization members, or assign roles.

### Before you begin

You need:

* Administrator access to the Hexpm organization.
* Administrator access to your OIDC provider.
* A Hexpm account for every person who will use SSO.
* Existing organization membership for every person who will link an SSO identity.
* Control of public DNS for each domain that will use email discovery or confirmed account linking.

Open the Hexpm organization dashboard, select **SSO**, and keep the **Redirect URI** shown there available while configuring Okta.

### Create the Okta application

In the Okta Admin Console, follow Okta's [OIDC app-integration instructions](https://developer.okta.com/docs/guides/create-an-app-integration/openidconnect/main/) with these Hexpm settings:

1. Open **Applications**, select **Applications**, and create a new app integration.
2. Choose **OIDC - OpenID Connect** as the sign-in method and **Web Application** as the application type.
3. Select the **Authorization Code** grant type.
4. Add the exact **Redirect URI** from the Hexpm SSO dashboard as a sign-in redirect URI. Do not use a wildcard.
5. Leave the sign-out redirect URIs empty. This release does not use OIDC logout.
6. Select **App Only**. Custom provider-initiated settings remain limited to Hexpm's private validation.
7. Assign only the people or groups who should be able to use the Hexpm integration.
8. Save the application, then copy its **Client ID** and **Client secret**.

The application must allow the `openid` and `email` scopes. Hexpm uses the provider subject as the stable identity. The email claim can locate a possible existing account for confirmed first-login linking and is used for notifications; it never proves account ownership or grants organization membership.

### Configure Hexpm

On the organization's **SSO** dashboard:

1. Enter the exact Okta organization **Issuer URL**, `https://{yourOktaDomain}`. Do not use `/oauth2/default` for the supported dashboard and future OIN integration. Hexpm requires an HTTPS issuer with no query or fragment and requires the provider discovery document to return that exact issuer.
2. Enter the application's **Client ID** and **Client secret**.
3. Select **Save configuration**.
4. Select **Test connection** and complete the Okta sign-in as the same Hexpm administrator who saved the configuration.
5. After the test succeeds, select **Enable SSO login**.

The status changes from **Not tested** after saving, to **Tested, disabled** after a successful test, and to **Enabled** after SSO login is enabled.

Once enabled, Hexpm displays the organization's login URL. Share that URL with assigned organization members.

### Configure an Initiate Login URI

The **Organization / Initiate Login URI** is organization-bound; Hexpm never performs a global issuer lookup. It accepts HTTP `GET` initiation requests with the standard OIDC parameters:

* `iss` is required whenever any recognized third-party initiation parameter is present and must exactly equal the organization's configured issuer.
* `login_hint` is optional and is forwarded to the provider for that request only. Hexpm does not persist it.
* `target_link_uri` is optional and must use Hexpm's configured origin and an allowlisted location within that organization's dashboard.
* Unknown parameters are ignored.

Every accepted initiation creates fresh state, nonce, and PKCE values. Custom Okta dashboard tiles, OIN Wizard-generated instances, and public OIN listings are not supported launch claims until Hexpm completes the separate live validation and release prerequisites.

### Microsoft Entra private validation

Microsoft Entra uses the same provider-neutral OIDC connection, but it is not a generally available provider claim until Hexpm completes its live managed-user, guest-user, error, secret-rotation, and signing-key-rotation matrix.

For an approved private validation:

1. Register a Web application with the exact Hexpm redirect URI.
2. Use the tenant-specific v2 issuer, `https://login.microsoftonline.com/{tenant-id}/v2.0`. Do not use `common`, `organizations`, or a tenant-independent issuer.
3. Configure the application's client ID and client secret in Hexpm, test the connection, and enable it only for the validation organization.
4. Assign only the managed and guest test users included in the validation.

Hexpm uses the exact issuer and stable OIDC subject as the identity key. A missing `email` claim follows the conventional account-proof flow; Hexpm does not substitute `preferred_username` or UPN as an email address.

### Verify a domain

Domain verification is required only for email discovery and confirmed account linking. It is not required for the organization's direct SSO login URL.

1. Add the registrable domain under **Verified domains**.
2. Publish the exact challenge as a TXT record at `_hexpm-sso.{domain}`. Each organization receives a distinct challenge, including organizations that share a domain.
3. Select **Verify domain**.
4. After verification, enable **Email discovery**, **Confirmed account linking**, or both.

Email discovery can disclose the names of participating organizations to anyone who submits an address at the domain. Hexpm requires an administrator to acknowledge that disclosure before enabling discovery. Domain trust is rechecked daily and expires seven days after the last successful DNS check. A missing or malformed record invalidates trust; an administrator must generate a new challenge before the domain can be trusted again.

When the runtime SSO mode is fully enabled, the general login page links to email discovery. During a beta, enabled organizations can test the discovery route directly without exposing the control on the public login page. Discovery retains only the canonical email domain, never looks up accounts or memberships, and may present a chooser when more than one eligible organization shares the domain.

### Link a member's account

The first time a member uses the organization login URL:

1. The member signs in through the configured identity provider.
2. If confirmed account linking is enabled and the provider email exactly matches the member's current verified primary Hexpm email on the verified domain, Hexpm sends a short-lived confirmation code to that stored primary address.
3. The member enters the code in the same browser that started the login.
4. If the Hexpm account has personal two-factor authentication enabled, the member must complete it before the identity is linked.
5. The confirmation explains that later organization SSO logins do not prompt for the account's personal Hexpm two-factor authentication code.
6. If confirmed linking is not available, Hexpm asks the member to prove control of an existing Hexpm account with its password or an already-linked GitHub account, plus Hexpm two-factor authentication when enabled.

The Hexpm account must already be a member of the organization. If it is not, an organization administrator must add it before the member retries.

A provider email never establishes durable identity, creates an account, grants membership, or changes a Hexpm email address. Secondary, unverified, missing, malformed, nonmember, and conflicting matches use the same conventional account-proof flow. After linking, the connection, exact issuer, and stable provider subject are the identity key.

After linking, later uses of the organization login URL sign the member in directly. Members can continue to use conventional Hexpm login.

Okta controls authentication to the SSO application. Hexpm remains the source of truth for organization membership and roles. Removing an Okta assignment does not remove the member from Hexpm. Remove the member in Hexpm to revoke organization access.

Later SSO authentication does not prompt for the member's Hexpm password or Hexpm two-factor authentication. Hexpm can still require conventional account proof after sign-in before a sudo-protected dashboard destination or sensitive action. Configure the required MFA and conditional-access policy in Okta.

### Rotate the client secret

Open the Okta application's **General** settings and use **Client Credentials** to generate a new secret. Keep the old secret active during the overlap; Okta documents this process in [Client secret rotation](https://developer.okta.com/docs/guides/client-secret-rotation-key/main/).

On the Hexpm SSO dashboard:

1. Enter the new secret under **Client secret rotation** and select **Save replacement**.
2. Select **Test replacement** and complete the provider sign-in.
3. Select **Complete rotation** only after the replacement test succeeds.
4. Return to Okta and deactivate or delete the old secret.

The active secret continues serving logins until the tested replacement is promoted.

### Disable SSO or unlink an account

Select **Disable SSO login** to stop new SSO logins immediately. This does not remove the saved configuration or linked accounts, and conventional Hexpm login remains available.

Organization administrators can unlink an account from the **Linked accounts** section. Removing a member from the organization also removes that organization's SSO link. If the person is added again later, they must link again.

### Troubleshooting

The SSO dashboard shows recent failures using stable stage and error codes. Check these common causes:

* **Configuration cannot be saved:** confirm that the issuer is an exact HTTPS URL and that its discovery and key endpoints are publicly reachable over HTTPS.
* **Okta rejects the callback:** compare the Okta sign-in redirect URI with the **Redirect URI** shown by Hexpm, including the scheme, host, path, and port.
* **The user cannot open the Okta application:** confirm that the user or one of their groups is assigned to the application.
* **The connection test fails:** restart it from the same browser while signed in as the Hexpm administrator who saved the configuration and initiated the test. If that administrator is unavailable, disable SSO if it is enabled, have a current administrator save the existing configuration again, then test and re-enable it. Leaving the client secret blank while re-saving keeps the current secret.
* **Account linking says the account is not a member:** add the existing Hexpm account to the organization, then restart from the organization login URL.
* **A linked identity conflicts:** unlink the existing organization link before attempting to connect the same provider identity or Hexpm account again.

Do not send client secrets, authorization codes, tokens, cookies, or raw callback URLs to support. The stage and error code from **Recent failures**, the organization name, and the approximate time are sufficient for investigation.

### Release scope

Enabled Phase 2 organizations can use the organization login URL, verified-domain email discovery, and confirmed primary-email account linking. Custom Okta dashboard tiles, a public Okta Integration Network listing, and general Microsoft Entra support remain unavailable until their external validation and release gates are complete.

This release does not support SAML, account creation, invitations, just-in-time membership, SCIM, group or role synchronization, required SSO enforcement, or OIDC logout.
