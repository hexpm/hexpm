## Package Transfer Policy

This document describes how ownership of a package on Hex changes hands: between owners who agree, to an author who lost access to their account, and for packages whose owners can't be reached. It also covers reports of name squatting and misleading names.

### Transferring a package you own

Owners at the full level can add and remove owners on the package's owners page or with `mix hex.owner`. Owners at the maintainer level can publish releases but can't manage owners. To hand a package over, transfer it on the owners page or with `mix hex.owner transfer`. A transfer makes the new owner the package's only owner.

Only add owners you trust. A new owner can publish releases that everyone who depends on the package installs when they update.

### If you lost access to your account

The Hex team doesn't restore access to accounts, as described in the [Account Recovery Policy](/policies/account-recovery). If you were the only owner of a package, we can add a new account of yours as an owner if you show that you control the package's source.

Email [support@hex.pm](mailto:support@hex.pm) with the names of the packages, your old and new usernames, and the source repository linked from each package's page. We will ask you to push a branch with a name we choose to that repository. We then check that the repository contains the source of the published releases.

Before adding the new account, we email every address on the old account. If nobody objects within 14 days, we add the new account as an owner at the full level. The change is recorded in the package's audit log.

### Packages whose owners can't be reached

You can ask to take over a package if both of the following are true:

1. No release of the package has been published in the past 12 months.
2. None of the package's owners respond to you or to the Hex team.

Try to contact the owners yourself first, using the email addresses on the package's page or on the owners' user pages. If they don't respond, email [support@hex.pm](mailto:support@hex.pm) with the package name, how you have tried to reach the owners, what you plan to do with the package, and why a fork under a different name doesn't work for you.

The Hex team then contacts every owner at least three times over six weeks, using the email addresses on their accounts. If an owner responds, the decision is theirs. We never transfer a package against the wishes of an owner who responds.

If no owner responds, the Hex team decides whether to transfer the package. We are more reluctant to transfer packages that many other packages depend on, and in those cases we usually recommend a fork under a different name.

A former owner who lost a package this way can ask for it back within one year of the transfer, and we will return it.

### After a transfer

Releases published before the transfer stay as they are, and the new owner can't replace them. The transfer is recorded in the package's audit log.

### Name squatting and misleading names

If you think a package exists only to reserve a name, or has a name that is intentionally confusing or misleading, report it with "Report package" on the package's page. Explain why the package violates the [Code of Conduct](/policies/codeofconduct) or the [Terms of Service](/policies/termsofservice). We may remove such packages.

### User and organization names

We are unlikely to transfer a user or organization name. Having a user or organization that has never published a package is valid, and they may own private packages that we can't disclose. Contact the user or organization directly and CC [support@hex.pm](mailto:support@hex.pm). We may consider a transfer in special circumstances.

### Copyright and trademarks

If you believe a package or its name infringes your copyright or trademark, follow the [Copyright Policy](/policies/copyright).

### Changes

This is a living document and may be updated from time to time. Please refer to the [git history](https://github.com/hexpm/hexpm/blob/main/lib/hexpm_web/templates/policy/package_transfer.html.md) for this document to view the changes.
