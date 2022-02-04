## FAQ

### Contact

#### How do I contact Hex?

To report an issue in Hex or its services open an issue on the appropriate repository in the [GitHub organization](https://github.com/hexpm) or on the [hexpm repository](https://github.com/hexpm/hexpm/issues).
To get in direct contact with Hex core team email [support@hex.pm](mailto:support@hex.pm).

### How do I report a security issue?

Security vulnerabilities should be disclosed to [security@hex.pm](mailto:security@hex.pm).

### Accounts

#### Can I change my username?

For security reasons, your username cannot be changed. However, if you would like to adopt a new
username we recommend [creating a new account](/signup).

You can transfer ownership of your packages using the [`mix hex.owner`](https://hexdocs.pm/hex/Mix.Tasks.Hex.Owner.html) task.

#### Password security

When you type a password to sign in, create an account, or change your password, we will check if the password you entered is considered weak according to [HaveIBeenPwned](https://haveibeenpwned.com/). The password may be identified as weak even if you have never used that password before.

We only inspect the password at the time you type it, and never store your password in plain text.

### Packages

#### Why is my package documentation returning "page not found"?

This could be for a number of reason. When you run [`mix hex.publish [docs]`](https://hexdocs.pm/hex/Mix.Tasks.Hex.Publish.html) the documentation is
generated on your machine and then uploaded to Hex. Issues with documentation usually stem from
the documentation generation. First verify that your documentation works locally by running
[`mix docs`](https://hexdocs.pm/ex_doc/Mix.Tasks.Docs.html) and then opening the generated files locally, typically `doc/index.html`, also verify
that there are no differences in letter casing since Hexdocs is case-sensitive but your machine
may be case-insensitive.

You can always republish old documentation with [`mix hex.publish docs`](https://hexdocs.pm/hex/Mix.Tasks.Hex.Publish.html) to update it. Finally make
sure you clear your browser cache to ensure you are viewing the latest version.

#### Can packages be removed from the repository?

The Hex repository is immutable, this means that in general you cannot remove or change an already
published package. This restriction exists to ensure a stable and reliable ecosystem where
depended on packages can't suddenly disappear.

There are exceptions to the immutability rule, a package can be changed or unpublished within 60
minutes of the package version release or within 24 hours of initial release of the package.
Packages are unpublished with [`mix hex.publish --revert VERSION`](https://hexdocs.pm/hex/Mix.Tasks.Hex.Publish.html#module-reverting-a-package) and republished by running
`mix hex.publish` for the same version again. If you revert the last version, the package is deleted.
Private packages can be modified and deleted at any time since those changes only affect the user's
own repository.

Instead of unpublishing we recommend to instead retire a package or release. This should be done
if the maintainers no longer recommend its use, because it does not work, has security issues,
been deprecated or any other reason. A package is retired with the [`mix hex.retire`](https://hexdocs.pm/hex/Mix.Tasks.Hex.Retire.html) task. A
retired package will still be resolvable and fetchable but users of the package will get a warning
message and the website will show the release as retired.

Additionally, we reserve the right to remove any package for legal or security reasons at any
time, this decision is made at the sole discretion of the Hex team.

Package checksums ensure that if a package was changed within the 60 minute window that end-users
are informed if they get a changed version of a package that they have already fetched and locked
in their lockfile. Packages or package versions that are removed by admins get automatically
reserved and can never be reused by users.

#### Can I transfer ownership of a package?

Yes, if you would like to reassign ownership of a package to a different user or to another
username, you can use the [`mix hex.owner`](https://hexdocs.pm/hex/Mix.Tasks.Hex.Owner.html) task.

#### How should I name my packages?

Please follow these simple rules when choosing the name of the package you're publishing on Hex.

1. **Prefix extension packages with the original package name**. If your package extends the
functionality of the plug package, then its name should be something like `plug_extension`.
2. **Never use another package's namespace**. For example, the namespace of the plug library is
`Plug.`: if your project extends plug, then its modules should be called `PlugExtension` instead
of `Plug.Extension`.

### Organizations

#### Can I publish public packages with an organization?

Yes, you can publish public packages through your organization and manage permissions the same way
you do for private packages. Unlike when using private packages, which is a paid feature, you can
publish public packages through your organization for free.

Keep in mind that in contrast to private packages your public organization packages will be
published to the global repository namespace like all other public packages.

The first time you publish a package you will be asked if one of your organizations should manage
the package or if you wish to own it yourself:

```
You are a member of organizations, select if you wish to publish the package with
yourself as owner or an organization as owner. If you publish with an organization
as owner your package will be public but managed by the organization.

  [1] Yourself
  [2] acme

Your selection: _
```

You can also transfer ownership to an organization after the package has been published by
running:

[`mix hex.owner transfer PACKAGE ORGANIZATION`](https://hexdocs.pm/hex/Mix.Tasks.Hex.Owner.html)

#### Are self-hosted or "enterprise" solutions available?

The easiest way to run your own Hex repository is to build it with
[`mix hex.registry build`](https://hexdocs.pm/hex/Mix.Tasks.Hex.Registry.html),
see ["Self-hosting"](/docs/self_hosting) guide for more information.

We are currently gauging interest in a solution more appropriate for enterprises, please contact
[support@hex.pm](mailto:support@hex.pm) if you are interested.

### Billing

#### How are organizations billed?

Organizations on the monthly plan are billed each month on the day of the month the subscription
was started. The subscription is invoiced and charged in advance when the next billing period
starts. Changes in the number of open seats in the plan are pro-rated on the next invoice.

Organizations on the annual plan are billed each year from the day the subscription was started.
The subscription is invoiced and charged in advance when the next billing period starts. Changes
in the number of open seats in the plan are pro-rated and charged when the number of seats change.

Invoices are sent by the company Six Colors AB, see the [about page](/about) for more information.

#### Do listed prices include VAT?

All prices are listed excluding VAT. Private EU citizens and Swedish companies are required to pay
VAT based on the VAT rate of their country of origin. EU companies registered for VAT need to
supply a valid VAT number. VAT is not included for customers outside of the EU.

#### Can I cancel at any time?

Yes, you can cancel your subscription at any time. When your subscription is cancelled you can
continue to use the organization until the end of the current billing period.

#### What happens if I fail to pay?

Failed invoice payments will be retried three times. After 15 days your subscription will be
cancelled and you will not be able to access packages or documentation. When you pay the invoice
and start the subscription again your organization will again be enabled.

We will keep all your data for a minimum of 90 days. You can contact
[support@hex.pm](mailto:support@hex.pm) to retrieve a dump of all your packages and documentation.

#### Can I pay annually instead of monthly?

Yes, we offer an annual plan that is billed once a year and includes a 2 month discount over the
monthly plan for a price of $70 / per user / per year.
