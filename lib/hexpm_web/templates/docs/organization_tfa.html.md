## Organization two-factor authentication

Administrators can see each member's 2FA enrollment status on the Members page and in authenticated member API responses. Other members can't see this information. The statuses are enrollment pending, enrollment overdue, and 2FA enabled. Session expiry doesn't change enrollment status.

### Scheduling enforcement

An administrator with 2FA verified within the last five minutes can configure the policy on the Members page. Choose immediate enforcement or a transition of 1 to 30 days. The initial transition selection is 14 days. The page displays the exact UTC deadline. Existing organizations have enforcement disabled. During the beta rollout, policy controls are available only to participating organizations. An existing policy remains enforced and can still be managed if the organization leaves the beta.

Existing members retain access during the transition. After the deadline, a member without 2FA loses access to the organization. Their membership, role, package ownership, and billed seat remain. Enabling 2FA restores eligibility; browsers and Hex clients must still hold verified sessions.

You can edit the deadline during the transition. After enforcement starts, disable the policy before scheduling another transition. Changing the reauthentication interval doesn't change the original verification timestamp.

### Sessions and automation

The default interval is seven days, with 24 hours and 30 days also available. Successful authenticator verification, recovery-code authentication, or completed enrollment establishes 2FA proof. Password authentication and SSO authentication don't establish that proof. Existing sessions receive no inferred proof.

At enforcement, personal API keys, tokens exchanged from personal keys, and password-only API access can't access this organization, including through general API permissions. Enabling account 2FA doesn't make these credentials eligible. Organization-owned credentials remain available for automation. Other organizations' access is evaluated under their own policies.

This organization policy is independent of [global user-key deprecation](https://github.com/hexpm/hexpm/pull/1747) and [global user-key removal](https://github.com/hexpm/hexpm/pull/1748).

### Invitations and admission

Administrators can invite users who haven't enabled 2FA. Once a policy is scheduled, enrollment is required before accepting an invitation, adding a user directly, or creating membership through SSO. Invitation acceptance returns the user to enrollment without consuming the invitation or allocating a seat. Returning to acceptance rechecks the invitation, the current policy, and available seats.

### Recovery and leaving

Recovery codes and account security settings remain accessible. You can't disable account 2FA while any organization requires it, including during a transition. Replacing an authenticator keeps the existing credentials until the new authenticator has been verified. Replacement invalidates older session proof.

You can leave an organization while suspended. Removing members, demoting administrators, and deleting accounts must preserve an eligible administrator. Eligibility includes enrollment and any applicable SSO identity requirement.

### Separate SSO requirements

When an organization enforces both SSO and 2FA, its members must satisfy both. SSO renewal doesn't renew 2FA proof, and 2FA verification doesn't renew SSO authentication. SSO exemptions and its setting allowing personal keys don't override the 2FA policy.

Hex clients display “2FA verification required” or “SSO authentication required”, with the affected organization names. When both are missing, both appear. The shared browser flow completes outstanding requirements before the client refreshes permissions and resumes fetching. It retains the OAuth session's original absolute expiry. Private documentation redirects to Hexpm for verification and returns to the original documentation page after refreshing permissions. Cancelling shows an explicit retry link and doesn't restart verification automatically. Cancelling, using an expired request, signing in as another account, or revoking the target session doesn't grant access.

### Notifications

Scheduling enforcement notifies every member, including members whose personal-key automation will stop working. Members with outstanding enrollment or personal-key workflows receive reminders seven days and one day before enforcement. Stages already elapsed when scheduling are skipped. After the deadline, members without 2FA receive suspension notices and administrators receive a summary.

Notification deduplication uses the policy revision, recipient, and stage. Policy changes, enrollment, and membership removal cancel obsolete queued notices. Notices already being delivered may still arrive. Policy changes and notification enqueueing are audited. Enforcement doesn't depend on notification delivery or a worker running.

### Download authorization

CDN validators verify access tokens offline. Newly issued access tokens have a default lifetime of 30 minutes, capped by applicable authentication expiries, source-session expiry, the OAuth session's absolute expiry, and scheduled enforcement deadlines. Refreshing a token doesn't move verification timestamps or extend the session's absolute lifetime.

A previously issued access token may remain usable until its signed expiry, plus the CDN verifier's 60-second tolerance. This includes tokens issued before a policy change, session revocation, or credential replacement. Refresh tokens and tokens without an explicit access-token purpose are refused as download credentials.

Repository API-key authorization can remain cached for 600 seconds after a successful check. Denials are cached for 10 seconds; server errors for five seconds. These are separate from the access-token lifetime and verifier tolerance.
