## Account Recovery Policy

This document describes how you can regain access to your Hex account, and what the Hex team does when you can't.

### Recovering access yourself

#### Lost password

Request a reset link on the [password reset page](/password/reset). The link is sent to your primary email address only and is valid for 24 hours. Resetting your password signs out all your sessions, and you can choose to revoke your API keys at the same time.

If your account is linked to GitHub you can sign in with GitHub instead. Two-factor authentication is still required after signing in with a password or with GitHub.

#### Lost authenticator app

Sign in and choose to use a recovery code instead of a code from your authenticator app. You received ten recovery codes when you enabled two-factor authentication, and each code can be used once. After signing in, set up a new authenticator app and generate new recovery codes on your [security settings](/dashboard/security).

#### Lost access to your email address

If you can still sign in, add a new email address and make it your primary address in your [email settings](/dashboard/email). Password reset links are only sent to your primary email address, so keep it current.

### When you can't recover access yourself

The Hex team doesn't restore access to accounts. We won't disable two-factor authentication, reset a password, or change the email addresses of an account on request, whatever proof is offered, including identity documents. Accounts on Hex can publish packages that other people install, and any manual recovery process could also be used by someone pretending to be you.

If you have permanently lost access to your account:

1. Create a new account. If you want to use the same email address, email [support@hex.pm](mailto:support@hex.pm) and we will remove it from the old account after you confirm a message we send to that address.
2. Ask the other owners of your packages to add your new account as an owner. If you were the only owner, follow [If you lost access to your account](/policies/package-transfer#if-you-lost-access-to-your-account) in the Package Transfer Policy.
3. Ask an administrator of each organization you were a member of to add your new account.

The old account and the releases it published stay as they are.

### Avoiding a lockout

Store your recovery codes somewhere other than the device that runs your authenticator app. Link your GitHub account in your [security settings](/dashboard/security) so you can sign in without your password. Add a second owner to the packages you maintain so someone else can add your new account if you lose access.

### Changes

This is a living document and may be updated from time to time. Please refer to the [git history](https://github.com/hexpm/hexpm/blob/main/lib/hexpm_web/templates/policy/account_recovery.html.md) for this document to view the changes.
