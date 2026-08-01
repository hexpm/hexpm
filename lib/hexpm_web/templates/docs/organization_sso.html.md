## Organization single sign-on

Organization single sign-on (SSO) lets members sign in to an organization through an OpenID Connect (OIDC) identity provider. Customer-created Okta applications are the supported and documented integration. Microsoft Entra has been validated privately against the same connector but is not a supported provider, and there is no Okta Integration Network listing to install the integration from.

Organization SSO is currently available only to organizations enabled by Hexpm's runtime SSO gate. It is optional and scoped to one Hexpm organization. It does not create accounts, add organization members, or assign roles.

SSO is not a way to sign in to Hexpm. Two separate sessions carry the split, and only the first is a login:

* The **account session** is the person's login to Hexpm, established by a password, GitHub, or another credential the account itself owns, together with the account's own two-factor authentication where enrolled. An identity provider never establishes it.
* The **organization access session** is what an SSO authentication produces. It is scoped to one organization and lasts 24 hours. It records that the provider authenticated the member. Nothing at Hexpm requires one yet, so it does not currently gate access to the organization.

So the shape of the flow is: sign in to Hexpm as yourself, then authenticate to the organization's provider.

### Before you begin

You need:

* Administrator access to the Hexpm organization.
* Administrator access to your OIDC provider.
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
6. Under **Login initiated by**, select **App Only** if members will always start from the organization login URL. To let them start from Okta instead, select **Either Okta or App** and set the **Initiate login URI** described below. Custom Okta dashboard tiles are not supported either way.
7. Assign only the people or groups who should be able to use the Hexpm integration.
8. Save the application, then copy its **Client ID** and **Client secret**.

The application must allow the `openid` and `email` scopes. Hexpm uses the provider subject as the stable identity. The email claim is display data and is used for notifications; it never proves account ownership or grants organization membership.

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

Every accepted initiation creates fresh state, nonce, and PKCE values. Custom Okta dashboard tiles, OIN Wizard-generated instances, and public OIN listings are not supported launch claims. Hexpm has exercised all three, so this is a decision about what Hexpm will document and answer for, not a gap in what has been tried.

### Microsoft Entra private validation

Microsoft Entra uses the same provider-neutral OIDC connection. Hexpm has validated it privately across managed users, guest users, missing and unexpected claims, secret rotation, and signing-key rotation. That validation is not a support claim: supporting a second provider is a separate decision covering documentation, fixtures, and what Hexpm will answer for when a customer's provider misbehaves, and it has not been taken.

The steps below describe an approved private validation, not general use:

1. Register a Web application with the exact Hexpm redirect URI.
2. Use the tenant-specific v2 issuer, `https://login.microsoftonline.com/{tenant-id}/v2.0`. Do not use `common`, `organizations`, or a tenant-independent issuer.
3. Configure the application's client ID and client secret in Hexpm, test the connection, and enable it only for the validation organization.
4. Assign only the managed and guest test users included in the validation.

Hexpm uses the exact issuer and stable OIDC subject as the identity key. Hexpm does not substitute `preferred_username` or UPN as an email address.

### Link a member's account

Following the organization login URL requires a Hexpm account session. Without one, Hexpm sends the member to conventional login first and resumes afterwards, so the same URL works signed in or signed out.

The first time a member uses the organization login URL:

1. The member signs in to Hexpm with their own credential, completing their personal two-factor authentication if they have it enrolled.
2. The member authenticates through the configured identity provider.
3. Hexpm asks the member to confirm the link between the returned provider identity and the account they are signed in as.

Being signed in is the proof, so there is no confirmation code and no email matching. The Hexpm account must already be a member of the organization. If it is not, an organization administrator must add it before the member retries.

A provider email never establishes durable identity, selects an account, creates one, grants membership, or changes a Hexpm email address. After linking, the connection, exact issuer, and stable provider subject are the identity key. The account's verified primary address is notified when the link is created; an account with no verified primary address is not notified at all.

After linking, later uses of the organization login URL establish a 24-hour organization access session for that browser session. Signing out of Hexpm, or revoking the browser session, ends the organization access with it.

### MFA and step-up

The two MFA policies do not compete, because they protect different things. The organization's provider enforces the organization's policy on every organization access session. Hexpm's own two-factor authentication enforces the account holder's policy on every account login. A member with both completes both, at different moments, and neither substitutes for the other.

An SSO authentication never suppresses a personal Hexpm two-factor prompt, because it never establishes the account session in the first place. It also never satisfies step-up re-authentication (sudo), which stays on credentials the account itself owns: password, GitHub, or a recovery code. Configure the required MFA and conditional-access policy for organization access in your provider.

Okta controls authentication to the SSO application. Hexpm remains the source of truth for organization membership and roles. Removing an Okta assignment does not remove the member from Hexpm. Remove the member in Hexpm to revoke organization access.

### Rotate the client secret

Open the Okta application's **General** settings and use **Client Credentials** to generate a new secret. Keep the old secret active during the overlap; Okta documents this process in [Client secret rotation](https://developer.okta.com/docs/guides/client-secret-rotation-key/main/).

On the Hexpm SSO dashboard:

1. Enter the new secret under **Client secret rotation** and select **Save replacement**.
2. Select **Test replacement** and complete the provider sign-in.
3. Select **Complete rotation** only after the replacement test succeeds.
4. Return to Okta and deactivate or delete the old secret.

The active secret continues serving logins until the tested replacement is promoted.

### Disable SSO, unlink an account, or remove the configuration

Select **Disable SSO login** to stop new SSO logins immediately and revoke every organization access session the connection has granted. This does not remove the saved configuration or linked accounts, and conventional Hexpm login remains available.

Organization administrators can unlink an account from the **Linked accounts** section, which also ends that member's current organization access. Removing a member from the organization does the same and removes the SSO link. If the person is added again later, they must link again.

**Remove SSO configuration** deletes the connection itself, with the stored client secret, every linked account, and the recorded failures. SSO has to be disabled first. Members keep their Hexpm accounts and their organization membership, and anyone who wants SSO afterwards links again against a newly saved configuration.

**Linked accounts** shows when each member last authenticated through the connection.

### Troubleshooting

The SSO dashboard shows recent failures using stable stage and error codes. Check these common causes:

* **Configuration cannot be saved:** confirm that the issuer is an exact HTTPS URL and that its discovery and key endpoints are publicly reachable over HTTPS.
* **Okta rejects the callback:** compare the Okta sign-in redirect URI with the **Redirect URI** shown by Hexpm, including the scheme, host, path, and port.
* **The user cannot open the Okta application:** confirm that the user or one of their groups is assigned to the application.
* **The connection test fails:** restart it from the same browser while signed in as the Hexpm administrator who saved the configuration and initiated the test. If that administrator is unavailable, disable SSO if it is enabled, have a current administrator save the existing configuration again, then test and re-enable it. Leaving the client secret blank while re-saving keeps the current secret.
* **Account linking says the account is not a member:** add the existing Hexpm account to the organization, then restart from the organization login URL.
* **A linked identity conflicts:** unlink the existing organization link before attempting to connect the same provider identity or Hexpm account again.
* **The login says you are signed in as the wrong account:** the provider identity belongs to a different Hexpm account. Sign in as that account, or ask an administrator to unlink it.

Do not send client secrets, authorization codes, tokens, cookies, or raw callback URLs to support. The stage and error code from **Recent failures**, the organization name, and the approximate time are sufficient for investigation.

### Release scope

Enabled organizations can use the organization login URL and third-party-initiated login. Custom Okta dashboard tiles, a public Okta Integration Network listing, and general Microsoft Entra support are unavailable. None of the three is waiting on validation, which is complete for all of them: the OIN integration was built and exercised but never submitted for review, and supporting Entra or dashboard tiles is an open release decision rather than an untested path.

Nothing yet requires an organization access session. This release does not support SAML, account creation, invitations, just-in-time membership, domain verification, SCIM, group or role synchronization, required SSO enforcement, or OIDC logout.
