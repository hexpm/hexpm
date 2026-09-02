## Organization single sign-on

Organization single sign-on (SSO) lets members sign in to an organization through an OpenID Connect (OIDC) identity provider. Customer-created Okta applications are the supported and documented integration. Microsoft Entra has been validated privately against the same connector but is not a supported provider, and there is no Okta Integration Network listing to install the integration from.

Organization SSO is currently available only to organizations enabled by Hexpm's runtime SSO gate. It is optional and scoped to one Hexpm organization. It does not create accounts, add organization members, or assign roles.

SSO is not a way to sign in to Hexpm. Two separate sessions carry the split, and only the first is a login:

* The **account session** is the person's login to Hexpm, established by a password, GitHub, or another credential the account itself owns, together with the account's own two-factor authentication where enrolled. An identity provider never establishes it.
* The **organization access session** is what an SSO authentication produces. It is scoped to one organization and records that the provider authenticated the member. An organization decides whether reaching it requires one, and how long one lasts.

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
6. Under **Login initiated by**, select **App Only** if members will always start from the organization login URL. To let them start from Okta instead, select **Either Okta or App** and set the **Initiate login URI** described below. The URI appears on the Hexpm SSO dashboard only after SSO login is enabled, so this step needs a second pass through Okta once setup is finished.
7. Assign only the people or groups who should be able to use the Hexpm integration.
8. Save the application, then copy its **Client ID** and **Client secret**.

The application must allow the `openid` and `email` scopes. Hexpm uses the provider subject as the stable identity. The email claim is display data and is used for notifications; it never proves account ownership or grants organization membership.

### Configure Hexpm

On the organization's **SSO** dashboard:

1. Enter the exact Okta organization **Issuer URL**, `https://{yourOktaDomain}`. Use the organization issuer rather than a custom authorization server such as `/oauth2/default`; Hexpm is tested and documented against the organization issuer. Hexpm requires an HTTPS issuer with no query or fragment and requires the provider discovery document to return that exact issuer.
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

Every accepted initiation creates fresh state, nonce, and PKCE values. Custom Okta dashboard tiles, OIN Wizard-generated instances, and public OIN listings are not supported launch claims. Tiles and a Wizard-generated instance both work and have been exercised, so for those this is a decision about what Hexpm will document and answer for rather than a gap in what has been tried. A public listing has never been submitted for review, so it does not exist.

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

After linking, later uses of the organization login URL establish an organization access session for that browser session. Signing out of Hexpm, or revoking the browser session, ends the organization access with it.

### Require SSO to reach the organization

Enforcement is set on the organization's **SSO** dashboard and has three modes:

* **Optional** is the default. Members can authenticate through the provider and nothing changes if they do not.
* **Pilot** enforces only the members an administrator marks as enforced, one at a time, so a team can try it on itself before turning it on for everyone.
* **Required** enforces every member except the ones marked exempt, from a date you pick.

The per-member control has three states in both modes: enforced, exempt, and following the organization. Moving from pilot to required does not reassign anybody. The people you piloted with stay enforced, the people you never touched start being enforced because the organization now is, and only an explicit exemption opts anyone out.

Setting a required-by date is a grace period, not a reminder. Until it passes the organization behaves exactly as it does in pilot. Members who have not linked an identity are emailed in the two weeks before the date, once each.

Hexpm refuses to switch an organization to required unless at least one administrator is exempt or has already linked an identity, so a misconfigured provider cannot lock every administrator out of the settings that would fix it.

### Which credentials work under enforcement

The credential decides, not the account, and each one answers differently:

| Credential | Under enforcement |
| --- | --- |
| Browser session | Needs a current organization access session for the organization. Hexpm sends you to the provider and back to the page you asked for. |
| Hex CLI (`mix hex.user auth`) | The session established when you authorized the CLI carries organization access. Hexpm asks you to re-authenticate in a browser when it lapses. |
| hexdocs and other OAuth clients | Same, established when you approve the client. |
| Organization API key | Never enforced. It authenticates as the organization rather than as a person, so there is no one for the provider to vouch for. |
| Personal API key | Allowed unless the organization chose to block them. |
| Username and password against the API | Refused. There is nothing for an organization access session to attach to. |

Enforcement is per organization and evaluated against the resource. Your Hexpm account, your own packages, the public repository, and every other organization you belong to are unaffected.

### The organization access session

An administrator sets how long one lasts: one hour, eight hours, one day (the default), one week, or thirty days. The same number governs every path. A browser session and a CLI session that have both authenticated expire on the same clock, so the setting means what it says rather than being the shorter half of two different windows.

When one lapses in the browser you are sent to the provider and back, and unless the provider asks you something the round trip is invisible. At the terminal, `mix` asks you to authenticate in a browser and then carries on with the same CLI session; you do not have to run `mix hex.user auth` again.

Shorter is stricter and more interruptive. The lifetime is what bounds how long someone your provider has deactivated keeps reaching the organization, so it is the number to pick deliberately.

### Provisioning (SCIM)

Provisioning lets your provider create and deactivate members here as you assign and deactivate them there. It is separate from SSO login: SSO proves a person may authenticate now, provisioning changes who is a member.

On the organization's **SSO** dashboard, under **Provisioning (SCIM)**, choose what happens when the seats run out and the role provisioned members join with, then generate the bearer token. The token is shown once; regenerate it to replace it, and it is revoked automatically if the connection is pointed at a different provider. In your provider's SCIM integration, use the **SCIM base URL** from the dashboard with that token. For Okta, enable the provisioning features you want: **Create Users**, **Update User Attributes**, and **Deactivate Users** each work on their own, so you can start with deactivation only.

What each operation does:

* **Assigning a person** whose Hexpm account has a verified email matching the SCIM `userName` adds them as a member with the role you chose, taking a seat. If the seats are full, the create is refused or a seat is added to the subscription, per your choice.
* **Assigning an address with no Hexpm account** sends a pending invitation to that address instead. Nothing creates a Hexpm account, and the seat is spent when the invitation is accepted, not when it is sent.
* **Deactivating or unassigning** removes the membership, with the member's organization access sessions and SSO link, or revokes the pending invitation. The seat is freed for reuse; the billed quantity changes only when an administrator changes it.
* **Reactivating** joins the person again with the provisioned role. A role an administrator granted by hand before the deactivation is not remembered.

Membership stays manageable in Hexpm either way. A member you remove by hand reads as deactivated on the provider's next sync, and a member you add by hand is matched by the provider's import through their verified email. One thing to know before connecting it: a full import lists each member's primary email address (or the address your provider already knows them by) to your provider, which is more than the member list on hex.pm shows.

CI is unaffected: organization API keys are not members and never appear on this surface.

### The Hex CLI

When a CLI session's authentication lapses, the next `mix deps.get` asks:

```
acme requires SSO authentication. Authenticate now? [Yn]
```

It names only the organizations the project actually depends on. Hex knows the whole set before it fetches anything, because a published package's dependencies can only come from the public repository or from that package's own organization, so a member of ten SSO organizations who depends on two is asked about two and asked once.

Saying yes opens a page bound to the CLI session you are already signed in on. Completing SSO there renews that session: the same session, the same refresh token, and resolution carries on. Saying no continues without the organization's packages.

CI is unaffected. It authenticates with an organization API key, which is the organization rather than a person, so there is nobody for your provider to vouch for and nothing to lapse.

### Personal API keys

A personal API key is a static credential. There is no session behind it, nothing expires it unless its owner set an expiry, and your provider never sees it used. Whether one may reach an enforced organization is the organization's choice, and the default is to allow them:

* **Block** removes this organization's permissions from members' personal keys on the required-by date, and refuses new ones. Their owners are emailed, and the rest of each key keeps working. Members publishing by hand run `mix hex.user auth` instead, and automation moves to an organization key.

    Blocking follows the same members enforcement does. A pilot turns personal keys away for the members you marked enforced and for nobody else, and it refuses new ones rather than removing what is already there, so a pilot shows you what required mode will do without taking anything away yet. An exempt member's keys are never touched.
* **Allow** leaves them alone, and is what you get if you change nothing. It is the right answer if your publishing workflow depends on them. It means required mode has a standing exception: those keys reach the organization with no session, no expiry, and no exposure to your provider's conditional-access policy. A key still stops working when its owner is removed from the organization here, because its permissions are checked against current membership on every request, and a provider deactivation counts as removal once provisioning is connected; without provisioning, a provider-only deactivation does not touch it.

    An organization API key has the same properties and is never enforced at all, so allowing personal keys widens a path that is already open rather than opening a new one. What blocking buys that removing the member does not is your provider's conditional-access policy, which no static credential evaluates.

Either way the SSO dashboard lists the members holding personal keys that reach the organization, and when each was last used, before you turn enforcement on. For a key whose permissions name the organization the list is exact. For one carrying every repository, or plain API access, it says the key could reach the organization rather than that it did; Hexpm records when a key was used and not what it was used against.

### Exemptions

An exempt member reaches the organization on their Hexpm credential alone. That is the point of the setting and it is also worth being blunt about: a required organization with exemptions has an enumerated set of accounts that your provider's policy does not cover. The members tab names every one of them and states how many there are, so the list can be reviewed rather than discovered.

### Break-glass

Three things stay reachable for a governed member with no current organization access session: **Billing**, the **SSO** settings themselves, and **leaving the organization**. Everything else on the organization dashboard, and every private package, is refused as usual.

The first two stay open because an organization whose client secret expired, or whose administrator was deactivated in the provider by mistake, has to be able to repair the connection and keep paying. If those screens sat behind the gate they are the only way to unlock, nothing could ever fix it. So while the provider is down, a required organization can fix its connection and keep its subscription, and cannot publish or fetch privately until the provider is back.

Leaving is open because it removes the member's own access rather than granting any, and it is the only lever someone deactivated at the provider has. Gating it would leave them unable to authenticate, unable to leave, and still a billed seat.

Reaching any of the three that way is recorded in the organization's audit log, which names the screen, and emailed to its administrators, at most once an hour per member.

The SSO screen is reachable so the connection can be repaired, and turning enforcement off for the organization counts as repairing it. Exempting individual members does not: it outlives the outage and leaves the organization reading as enforced, so that control needs a current organization access session like everything else.

### The residual bypasses

A required organization has exactly five ways in that do not involve its identity provider, and they are all deliberate:

1. **Exemptions**, one per member, listed on the members tab.
2. **Organization API keys**, which authenticate as the organization. This is the audited automation exception; enforcement constrains and monitors it but cannot close it.
3. **Personal API keys**, unless the organization chose to block them.
4. **Break-glass** on the billing and SSO settings screens, audited and mailed.
5. **Readme URLs.** A private package's readme renders on a separate host that never receives your Hexpm session cookie, so the package page signs a URL for it after taking its own authorization decision, and signs one for each image the readme contains. That URL renders that one readme for thirty minutes to anyone holding it. Nothing about it is checked against enforcement, the session it was minted from, or the member's membership, and reaching a readme this way is not audited. It carries no other access: one package, one version, and the images in that readme.

There is no sixth. If you are evaluating Hexpm against a compliance requirement, this is the list. Leaving the organization is open on the same break-glass terms and audited the same way, but it is not on the list: it takes the member's access away rather than giving them any.

### Offboarding

Two windows, and they are different:

* **Removing a member in Hexpm** takes effect within thirty minutes. The CLI's access token is a capability the edge verifies without a database lookup, so it keeps its scopes until it is next refreshed. Web access ends immediately.
* **Deactivating someone in your provider** removes their membership here when provisioning is connected, which is the same as removing them by hand. Without provisioning, it takes effect when their organization access session expires, which is the lifetime you set; Hexpm does not learn about a provider-side deactivation until then.

Without provisioning, the session lifetime is what bounds a provider-side deactivation, which is the reason to pick that number deliberately rather than take the default, and removing the member in Hexpm is what revokes access; removing their provider assignment is not.

### Seats and billing

Configuring SSO takes an active subscription. Being governed by it does not. If a payment fails, enforcement stays exactly as you set it: an organization that requires SSO keeps requiring it, and its members keep being able to authenticate. A lapsed card does not quietly turn your access control off, and does not lock your team out either. The SSO settings and billing screens stay reachable throughout, which is the same break-glass path described above.

Just-in-time membership and provisioning are the only parts of SSO that can change a seat count, and each asks you to choose its behavior first: when the seats are full, the organization either adds a seat to the subscription or refuses the admission, depending on what you chose under **When the seats run out**. Enforcement on its own never adds, removes, or bills a seat.

### Before you turn on required mode

1. Link the administrators, or exempt at least one.
2. Review the members tab and decide who, if anyone, is exempt.
3. Check the personal-key list and decide whether to leave them allowed or block them.
4. Pick a session lifetime.
5. Set a required-by date far enough out for the grace-period email to reach people.

Turning enforcement on revokes nothing that already exists. Organization access sessions run out their lifetime and access tokens keep their scopes until they are next refreshed.

### MFA and step-up

The two MFA policies do not compete, because they protect different things. The organization's provider enforces the organization's policy on every organization access session. Hexpm's own two-factor authentication enforces the account holder's policy on every account login. A member with both completes both, at different moments, and neither substitutes for the other.

An SSO authentication never suppresses a personal Hexpm two-factor prompt, because it never establishes the account session in the first place. It also never satisfies step-up re-authentication (sudo), which stays on credentials the account itself owns: password, GitHub, an authenticator code, or a recovery code. Configure the required MFA and conditional-access policy for organization access in your provider.

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

Enabled organizations can use the organization login URL and third-party-initiated login. Custom Okta dashboard tiles and Microsoft Entra are not supported, and there is no public Okta Integration Network listing. Tiles and Entra both work and have been exercised privately; supporting them is an open release decision rather than an untested path. The OIN listing is different in kind: the integration was built and exercised, but it was never submitted for review, so no listing exists to install from.

This release supports SCIM provisioning of members (the Users resource). It does not support SAML, account creation, group or role synchronization, or OIDC logout.
