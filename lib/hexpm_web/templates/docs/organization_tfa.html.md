## Organization two-factor authentication

Administrators can see each member's 2FA enrollment status on the Members page and in authenticated member API responses. Other members can't see this information. The statuses are enrollment pending, enrollment overdue, and 2FA enabled.

### Scheduling enforcement

An administrator with 2FA enabled on their own account can configure the policy on the Members page. Choose immediate enforcement or a transition of 1 to 30 days. The initial transition selection is 14 days. The page displays the exact UTC deadline. Existing organizations have enforcement disabled. During the beta rollout, policy controls are available only to participating organizations. An existing policy remains enforced and can still be managed if the organization leaves the beta.

Existing members retain access during the transition. After the deadline, a member without 2FA loses access to the organization. Their membership, role, package ownership, and billed seat remain. Enabling 2FA restores access immediately.

You can edit the deadline during the transition. After enforcement starts, disable the policy before scheduling another transition.

### Credentials and automation

The requirement applies to the account, not to individual sessions or credentials. Once 2FA is enabled, browser sessions, Hex client sessions, and personal API keys reach the organization again without further steps. Organization-owned credentials aren't affected by the policy. Other organizations' access is evaluated under their own policies.

API write operations continue to require a one-time code from members with 2FA enabled, as they do for every account.

### Invitations and admission

Administrators can invite users who haven't enabled 2FA. Once a policy is scheduled, enrollment is required before accepting an invitation, adding a user directly, or creating membership through SSO. Invitation acceptance returns the user to enrollment without consuming the invitation or allocating a seat. Returning to acceptance rechecks the invitation, the current policy, and available seats.

### Recovery and leaving

Recovery codes and account security settings remain accessible. You can't disable account 2FA while any organization requires it, including during a transition. Replacing an authenticator keeps the existing credentials until the new authenticator has been verified.

You can leave an organization while suspended. Removing members, demoting administrators, and deleting accounts must preserve an eligible administrator. Eligibility includes enrollment and any applicable SSO identity requirement.

### Separate SSO requirements

When an organization enforces both SSO and 2FA, its members must satisfy both. SSO exemptions and its setting allowing personal keys don't override the 2FA policy.

Hex clients display "2FA enrollment required" or "SSO authentication required", with the affected organization names. When both are missing, both appear. The shared browser flow completes outstanding requirements before the client refreshes permissions and resumes fetching. Using an expired request, signing in as another account, or revoking the target session doesn't grant access.

### Notifications

Scheduling enforcement notifies every member. Members with outstanding enrollment receive reminders seven days and one day before enforcement. Stages already elapsed when scheduling are skipped. After the deadline, members without 2FA receive suspension notices and administrators receive a summary.

Notification deduplication uses the policy revision, recipient, and stage. Policy changes, enrollment, and membership removal cancel obsolete queued notices. Notices already being delivered may still arrive. Policy changes and notification enqueueing are audited. Enforcement doesn't depend on notification delivery or a worker running.

### Download authorization

CDN validators verify access tokens offline. A token issued before the deadline can keep reaching the organization until it expires, normally 30 minutes after issue, plus the verifier's 60-second tolerance. Tokens issued after the deadline don't carry the organization for members without 2FA.

Repository API-key authorization can remain cached for 600 seconds after a successful check. Denials are cached for 10 seconds; server errors for five seconds.
