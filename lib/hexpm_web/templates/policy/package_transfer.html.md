## Package Transfer Policy

This document describes how ownership of a public package on Hex changes hands: between owners who agree, to an author who lost access to their account, and for packages whose owners can't be reached. It also covers reports of name squatting and misleading names. Private packages belong to their organization, whose administrators manage them, and can't be transferred.

### Transferring a package you own

Owners at the full level can add and remove owners on the package's owners page or with `mix hex.owner`. Owners at the maintainer level can publish releases but can't manage owners. To hand a package over, transfer it on the owners page or with `mix hex.owner transfer`. A transfer makes the new owner the package's only owner.

Only add owners you trust. A new owner can publish releases that everyone who depends on the package installs when they update.

### If you lost access to your account

The Hex team doesn't restore access to accounts, as described in the [Account Recovery Policy](/policies/account-recovery). If you were the only owner at the full level of a package and your old account is linked to a GitHub account, we can add your new account as an owner if you show that you still control that GitHub account. We match the GitHub account by its account ID, so an account that later took over its username doesn't qualify.

Email [support@hex.pm](mailto:support@hex.pm) with the names of the packages and your old and new usernames. We will ask you to create a public gist containing a text we choose from the GitHub account linked to the old account.

Before changing the owners, we email every address on the old account. If nobody objects within 14 days, we add the new account as an owner at the full level and remove the old account as an owner. The change is recorded in the package's audit log.

If your old account isn't linked to a GitHub account, the package can only change hands as described in [Packages whose owners can't be reached](#packages-whose-owners-cant-be-reached).

### Packages whose owners can't be reached

You can ask to take over a package if both of the following are true:

1. No release of the package has been published in the past 12 months.
2. None of the package's owners respond to you or to the Hex team.

Try to contact the owners yourself first, using the email addresses on the package's page or on the owners' user pages. If they don't respond, email [support@hex.pm](mailto:support@hex.pm) with the package name, how you have tried to reach the owners, what you plan to do with the package, and why a fork under a different name doesn't work for you.

The Hex team then contacts every owner at least three times over six weeks, using the email addresses on their accounts. For an owner that is an organization, we contact the organization's administrators. If an owner responds, the decision is theirs, and we don't transfer the package under this section against their wishes.

If no owner responds, the Hex team decides whether to transfer the package. We are more reluctant to transfer packages that many other packages depend on, and in those cases we usually recommend a fork under a different name.

A former owner who lost a package this way can ask for it back from their account within one year of the transfer, and we will return it.

### After a transfer

A transfer doesn't change the releases published before it. A public release can only be replaced within one hour of being published, or within 24 hours of the package being created, and a transfer doesn't extend that. Like any owner, the new owner can publish new releases, retire releases and publish documentation. The transfer is recorded in the package's audit log.

### Name squatting and misleading names

If you think a package exists only to reserve a name, or has a name that is intentionally confusing or misleading, report it with "Report package" on the package's page. Explain why the package violates the [Code of Conduct](/policies/codeofconduct) or the [Terms of Service](/policies/termsofservice). We may remove such packages.

### User and organization names

We are unlikely to transfer a user or organization name. Having a user or organization that has never published a package is valid, and they may own private packages that we can't disclose. Contact the user or organization directly and CC [support@hex.pm](mailto:support@hex.pm). We may consider a transfer in special circumstances.

### Copyright and trademarks

If you believe a package or its name infringes your copyright or trademark, follow the [Copyright Policy](/policies/copyright).

### Changes

This is a living document and may be updated from time to time. Please refer to the [git history](https://github.com/hexpm/hexpm/blob/main/lib/hexpm_web/templates/policy/package_transfer.html.md) for this document to view the changes.
