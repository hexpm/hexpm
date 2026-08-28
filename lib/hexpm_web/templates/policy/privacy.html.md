## Privacy Policy

Six Colors AB ("we", "us") is a Swedish company that operates the [hex.pm](https://hex.pm), [hexdocs.pm](https://hexdocs.pm) and [hexorgs.pm](https://hexorgs.pm) websites, the hex.pm API and the package repository. We're the data controller for the processing described in this policy. You can reach us at <support@hex.pm>.

Account and package data is stored in the United States on Google Cloud Platform and Amazon AWS servers. The third party providers we use to operate the service process personal data on our behalf and are listed on the [Subprocessors](/policies/subprocessors) page.

One part of the service works differently: an organization's private packages and documentation, its membership and its audit log are controlled by that organization, and we process them on its instructions under the [Data Processing Agreement](/policies/dpa). Request logs are ours; see "Logs and security" below.

### Accounts

To register you have to provide a username and an email address, and a password unless you sign up with GitHub; without them we can't create an account. You can add profile information, such as a full name and social media handles, if you want to. If you choose to sign in with GitHub we receive your GitHub account identity.

Your profile is public: your username always, and your email address, which is shown by default and which you can hide in your dashboard. Your full name is shown only if you choose to show it. The public packages you own are also public. Your organization memberships and the private packages those organizations own aren't. Nothing else about your account is made public. Non-public data is shared only with the providers on the [Subprocessors](/policies/subprocessors) page and in the cases described under "Vulnerability reports" and "Disclosure" below.

We send transactional email, such as address verification and password resets, through the email provider on the [Subprocessors](/policies/subprocessors) page.

We process account data to operate your account and deliver the service, so the legal basis is our contract with you. We keep it for as long as your account exists. You can delete your account in the dashboard. After deletion, public packages you published stay public, your username stays reserved so nobody else can take it over, and audit log entries and billing records aren't deleted with the account.

### Public packages and documentation

Packages published to the public repository are public. Anyone can download the full contents of a package without an account, the metadata is shown on hex.pm, and the documentation is published on hexdocs.pm. Publishing requires an account; downloading doesn't.

Package contents and metadata may contain personal data the publisher chose to include, for example author names and email addresses. If a package contains personal data about you, it came from the publisher, not from us collecting it from you; see "Your rights" below.

We process public packages to run the registry, on the basis of our contract with the publisher. Published packages stay available indefinitely, including after the publisher deletes their account, unless removed under our policies.

### Private packages

Packages published to an organization's private repository aren't public. They're available only to members of that organization, and so is their documentation. The organization is the controller of this content and we process it under the [Data Processing Agreement](/policies/dpa); it's also covered by the confidentiality terms of the [Terms of Service](/policies/termsofservice). When a subscription ends we keep the organization's content for 90 days so the organization can retrieve it. After that we may delete it at any time, and we delete it on request.

### Logs and security

The package repository at repo.hex.pm writes an access log for every request. Each entry contains the client IP address, the time, the request method and path, the response status, the user agent and the request size. The image proxy at img.hex.pm, which serves images embedded in package readmes, writes the same log. These logs are available to our administrators and to the infrastructure providers on the [Subprocessors](/policies/subprocessors) page. We use them for security, for investigating abuse and to compute the aggregate download counts shown on hex.pm. We archive them daily and keep the archives, because the download counts we publish for every past day are derived from them.

Requests to the hex.pm website and API are logged with the client IP address, user agent and referrer. We don't write access logs for hexdocs.pm or hexorgs.pm.

When you take an action that changes something, such as publishing a package, generating a key or changing account settings, we record it in an audit log together with the IP address and user agent of the request that performed it. You can see your own audit log in the dashboard, and organization administrators can see their organization's. We keep audit log entries indefinitely, because their purpose is to be a permanent record of what changed. Entries about public packages and other public content are kept even after the account or organization that made them is deleted, and they keep a copy of who acted. Entries about an organization's private content are part of that organization's data under the [Data Processing Agreement](/policies/dpa) and are deleted with the rest of it. On request we can remove the identifying details from your entries.

Sign up, password reset, email verification and the package report form are protected by hCaptcha, which receives your IP address and browser data to tell people from bots. Application errors are reported to the error tracking provider on the [Subprocessors](/policies/subprocessors) page and can include the request data that was in scope when the error happened; they're deleted on that provider's retention schedule.

The legal basis for all of this is our legitimate interest in securing the service, preventing abuse and knowing how the service is used. The measures we use to protect this data are described on the [Security](/policies/security) page.

### Analytics

The websites use [Plausible Analytics](https://plausible.io) to measure aggregate usage, such as which pages are visited and where visitors arrive from. Plausible receives the page URL, the referrer and your IP address. It doesn't use cookies and doesn't track you across sites or over time, and it doesn't retain your IP address, so there's nothing about you for us to keep. The legal basis is our legitimate interest in understanding how the websites are used.

### Cookies

We use a session cookie to keep you logged in on hex.pm; it expires after 30 days. hexorgs.pm sets its own session cookie to authenticate you as an organization member when you read private documentation. The session cookie is also set before you log in, on any page with a form, because it carries the token that protects those forms from cross-site request forgery.

### Resources loaded by your browser

Some pages load resources directly from third parties, so your browser contacts them and they see your IP address: Google Fonts on every page, Gravatar wherever a profile picture is shown, Stripe on billing pages, and hCaptcha on sign up, password reset and email verification. Gravatar also receives a hash of the email address the picture is derived from.

### Billing

Organizations with a paid subscription provide billing details such as the billing name, address and VAT number. Payments are processed by Stripe. We also record the IP address the payment details were entered from and the country it resolves to, because the VAT rate depends on the country you give us and we have to be able to show it was the right one. The legal bases are our contract with the organization, for charging for the service, and legal obligation, because Swedish accounting and tax law requires us to keep billing, payment and tax records. We keep those records for as long as that law requires.

### Vulnerability reports

When someone submits a vulnerability report for a package, we send the report to the [Erlang Ecosystem Foundation CNA](https://cna.erlef.org), which triages vulnerabilities in the ecosystem and contacts the people involved. The submission contains the report's summary and description, the name, username and primary email address of the reporter, and the same three fields for each of the package's owners. For a package owned by an organization it also includes its administrators, or all its members if no administrator has a verified email address. The primary email address is sent even if you've hidden your email address on your public profile.

The Foundation decides for itself how it uses this data, so it's a separate controller and a recipient of the data rather than a provider acting on our behalf. The legal basis for the disclosure is our legitimate interest, shared with the ecosystem, in coordinated handling of security vulnerabilities.

### Communication

Emails to `@hex.pm` addresses are stored, including the sender's address and the contents. They're available internally and to the mail provider on the [Subprocessors](/policies/subprocessors) page. We keep correspondence for as long as it's needed to handle the matter and to keep a record of it, on the basis of our legitimate interest in running support and documenting what was agreed.

### Disclosure

We may disclose personal data when required by law, for example to comply with a subpoena, or when your actions violate the [Terms of Service](/policies/termsofservice). This doesn't apply to an organization's private content, where disclosure is governed by the [Data Processing Agreement](/policies/dpa) and the confidentiality terms of the Terms of Service.

### International transfers

The service runs on infrastructure located in the United States, so operating it involves transferring personal data there.

Six Colors is the exporter for those transfers and is responsible for the transfer mechanism. For each provider in the United States we rely on either the European Commission's adequacy decision for the EU-US Data Privacy Framework, where that provider is certified, or the Standard Contractual Clauses adopted by the European Commission, together with the UK Addendum and the Swiss amendments where those apply. For a copy of the clauses, contact <support@hex.pm>. Backups of the package repository are encrypted before they leave our infrastructure and the keys are held only by us, so the backup provider cannot read them.

### Your rights

You can ask us for access to the personal data we hold about you, and for rectification, erasure, restriction of processing, or a copy of the data you provided in a portable format. You can object to any processing we base on legitimate interests. Where processing is based on consent, you can withdraw it at any time without affecting what was done before. Some of this you can do yourself in the dashboard: edit your profile and email addresses, review your audit log, and delete your account. For everything else, email <support@hex.pm>.

Erasure has limits: published public packages stay public, a deleted account's username stays reserved, audit log entries about public content are kept as a permanent record, and we keep records the law requires us to keep, such as accounting records.

For personal data inside an organization's private packages, direct your request to that organization; it's the controller, and we forward requests we receive to it.

If you believe we're processing your personal data unlawfully you can lodge a complaint with a supervisory authority. Our supervisory authority is the Swedish one, [Integritetsskyddsmyndigheten (IMY)](https://www.imy.se), but you can also complain to the authority where you live or work.

### Questions

Any questions about this Privacy Policy should be addressed to <support@hex.pm>.

### Changes

We may change this Privacy Policy from time to time. The detailed history of changes can be found in the [git repository](https://github.com/hexpm/hexpm/blob/main/lib/hexpm_web/templates/policy/privacy.html.md) history for this document.

### Credit and License

Parts of this policy document were originally based on [npm's Privacy Policy](https://www.npmjs.com/policies/privacy) which in turn is partly based on the [WordPress.org privacy policy](https://wordpress.org/about/privacy).

This document may be reused under a [Creative Commons Attribution-ShareAlike License](http://creativecommons.org/licenses/by-sa/4.0).
