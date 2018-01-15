## FAQ

### Packages

#### Why is my package documentation returning "page not found"?

This could be for a number of reason. When you run `mix hex.publish [docs]` the documentation is
generated on your machine and then uploaded to Hex. Issues with documentation usually stem from
the documentation generation. First verify that your documentation works locally by running
`mix docs`, also verify that there are no differences in letter casing since Hexdocs is
case-sensitive but your machine may be case-insensitive.

You can always republish old documentation with `mix hex.publish docs` to update it. Finally make
sure you clear your browser cache to ensure you are viewing the latest version.

#### How do I delete a release of my package?

A package version can be reverted with `mix hex.publish --revert VERSION`. A version can only be
deleted after an hour of the last release or within 24 hours of the first release of the package.
This restriction is to ensure the stability of the package ecosystem and so that important,
depended upon packages are not removed from the repository.

A package release can be retired if you do not recommend its use because it does not work, has
security issues, been deprecated or any other reason. A package is retired with the
`mix hex.retire` task. I retired package will still be resolvable and fetchable but users of
the package will get a warning a message and the website will show the release as retired.

#### How should I name my packages?

Please follow these simple rules when choosing the name of the package you're publishing on Hex.

1. **Never use another package's namespace**. For example, the namespace of the plug library is
`Plug.`: if your project extends plug, then its modules should be called `PlugExtension` instead
of `Plug.Extension`.
2. **Prefix extension packages with the original package name**. If your package extends the
functionality of the plug package, then its name should be something like `plug_extension`.

### Billing

#### How are organizations billed?

Organizations are billed monthly on the day of the month the subscription was started. The
subscription is invoiced and charged for the in advance when the next billing period starts.
Changes in the number of members in the organizations are pro-rated on the next invoice.

#### Do listed prices include VAT?

All prices are listed excluding VAT. Private EU citizens are required to pay VAT based on the VAT
rate of their country of origin. EU companies registered for VAT need to supply a valid VAT number.

#### Can I cancel at any time?

Yes, you can cancel your subscription at any time. When your subscription is cancelled you can
continue to use the organization until the end of the current billing period.

#### What happens if I fail to pay?

Failed invoice payments will be retried three times. After 15 days your subscription will be
cancelled and you will not be able to access packages or documentation. When you pay the invoice
and start the subscription again your organization will again be enabled.

We will keep all your data for a minimum of 90 days. You can contact
[support@hex.pm](mailto:support@hex.pm) to retrieve a dump of all your packages and documentation.

### Organizations

#### Can I publish public packages to an organization?

No, organizations are only for private packages, public packages should be published to the global
repository.
