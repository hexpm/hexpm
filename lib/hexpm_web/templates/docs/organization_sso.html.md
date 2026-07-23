## Organization single sign-on

Organization single sign-on (SSO) lets members sign in to an organization through an OpenID Connect (OIDC) identity provider. Okta is the officially supported, documented, and tested provider for this release.

Organization SSO is currently available only to enabled pilot organizations. It is optional and scoped to one Hexpm organization, so conventional Hexpm login remains available. It does not automatically create accounts, add organization members, or assign roles.

### Before you begin

You need:

* Administrator access to the Hexpm organization.
* Administrator access to your Okta tenant.
* A Hexpm account for every person who will use SSO.
* Existing organization membership for every person who will link an SSO identity.

Open the Hexpm organization dashboard, select **SSO**, and keep the **Redirect URI** shown there available while configuring Okta.

### Create the Okta application

In the Okta Admin Console, follow Okta's [OIDC app-integration instructions](https://developer.okta.com/docs/guides/create-an-app-integration/openidconnect/main/) with these Hexpm settings:

1. Open **Applications**, select **Applications**, and create a new app integration.
2. Choose **OIDC - OpenID Connect** as the sign-in method and **Web Application** as the application type.
3. Select the **Authorization Code** grant type.
4. Add the exact **Redirect URI** from the Hexpm SSO dashboard as a sign-in redirect URI. Do not use a wildcard.
5. Leave the sign-out redirect URIs empty. This release does not use OIDC logout.
6. Under login initiation, select **App Only**. This release does not support an Okta dashboard tile.
7. Assign only the people or groups who should be able to use the Hexpm integration.
8. Save the application, then copy its **Client ID** and **Client secret**.

The application must allow the `openid` and `email` scopes. Hexpm uses the provider subject as the stable identity. The email claim is displayed for confirmation and notifications; it is not used to match Hexpm accounts or grant organization membership.

### Configure Hexpm

On the organization's **SSO** dashboard:

1. Enter the exact Okta **Issuer URL**. For ordinary OIDC SSO, use the [Okta org authorization server](https://developer.okta.com/docs/concepts/auth-servers/): `https://{yourOktaDomain}`. If your organization intentionally uses a custom authorization server, copy its **Issuer URI** from **Security > API > Authorization Servers** and make sure it has an access policy that permits this application. Do not assume that the custom server named `default` is the org authorization server.
2. Enter the application's **Client ID** and **Client secret**.
3. Select **Save configuration**.
4. Select **Test connection** and complete the Okta sign-in as the same Hexpm administrator who saved the configuration.
5. After the test succeeds, select **Enable SSO login**.

The status changes from **Not tested** after saving, to **Tested, disabled** after a successful test, and to **Enabled** after SSO login is enabled.

Once enabled, Hexpm displays the organization's login URL. Share that URL with assigned organization members.

### Link a member's account

The first time a member uses the organization login URL:

1. The member signs in through Okta.
2. Hexpm asks the member to prove control of an existing Hexpm account with its password or an already-linked GitHub account, plus Hexpm two-factor authentication when enabled.
3. Hexpm shows the organization and provider email for confirmation.
4. The member confirms the link.

The Hexpm account must already be a member of the organization. If it is not, an organization administrator must add it before the member retries.

After linking, later uses of the organization login URL sign the member in directly. Members can continue to use conventional Hexpm login.

Okta controls authentication to the SSO application. Hexpm remains the source of truth for organization membership and roles. Removing an Okta assignment does not remove the member from Hexpm. Remove the member in Hexpm to revoke organization access.

Later SSO logins do not prompt for the member's Hexpm password or Hexpm two-factor authentication. Configure the required MFA and conditional-access policy in Okta.

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

This release supports only logins started from the organization login URL shown by Hexpm. It does not support an Okta dashboard tile, identity-provider-initiated login, an Okta Integration Network application, SAML, email-domain discovery, automatic account linking, account creation, invitations, just-in-time membership, SCIM, group or role synchronization, required SSO enforcement, or OIDC logout.
