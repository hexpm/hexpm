## Subprocessors

Six Colors AB operates the hex.pm, hexdocs.pm and hexorgs.pm websites, the hex.pm API, and the package repository. To run these services we use the third party providers listed below. Most of them are processors in the sense of the [Privacy Policy](/policies/privacy) and the [Data Processing Agreement](/policies/dpa): they handle personal data on our behalf and under our instructions. Two are not. The European Commission's VIES is a public authority we send VAT numbers to for validation, and GitHub decides for itself what it does with the account you sign in with. They are listed because they receive data, not because they act on our instructions.

The Terms column links to each provider's own data processing terms.

The list is kept current as providers change. The change history for this document is available in the [git repository](https://github.com/hexpm/hexpm/blob/main/lib/hexpm_web/templates/policy/subprocessors.html.md).

| Provider | Purpose | Data processed | Terms |
| --- | --- | --- | --- |
| Google Cloud Platform | Application hosting, primary database, documentation storage, access log and backup storage, invoice storage | Account and package data, public and private documentation, request logs including IP address, invoices including name, address and VAT number | [DPA](https://cloud.google.com/terms/data-processing-addendum) |
| Amazon Web Services | Package and documentation storage, job queues, metrics | Package tarballs and documentation including private packages, object event metadata | [DPA](https://d1.awsstatic.com/legal/aws-gdpr/AWS_GDPR_DPA.pdf) |
| Fastly | CDN and edge compute for the package repository, hexdocs.pm and hexorgs.pm, including authentication of private documentation requests | Request metadata including IP address and user agent, package and documentation content including private packages, and the API keys and tokens presented to authenticate those requests | [DPA](https://www.fastly.com/data-processing) |
| Tarsnap | Encrypted offsite backup of the package repository storage | Package tarballs and documentation, including private packages | [DPA](https://www.tarsnap.com/legal-dpa.html) |
| Twilio SendGrid | Transactional email such as verification and password reset, and invoice delivery | Email address, email contents, invoices including name, address and VAT number | [DPA](https://www.twilio.com/en-us/legal/data-protection-addendum) |
| Google Workspace | Mail for @hex.pm addresses, including support@hex.pm | Email address and contents of correspondence with us | [DPA](https://cloud.google.com/terms/data-processing-addendum) |
| Stripe | Payment and subscription processing for paid organizations | Billing name, email, address, payment details | [DPA](https://stripe.com/legal/dpa) |
| Sentry | Application error tracking | Error reports, which carry whatever data was in scope when the error occurred, including request metadata and user identifiers | [DPA](https://sentry.io/legal/dpa/) |
| Plausible Analytics | Website usage analytics | Page URLs, referrers and IP address, without cookies or cross-site identifiers | [DPA](https://plausible.io/dpa) |
| Typesense | Search on hexdocs.pm, public documentation only | Search queries | [DPA](https://cloud.typesense.org/legal/dpa) |
| hCaptcha | Abuse prevention on sign up, password reset and email verification | IP address, browser data | [DPA](https://newassets.hcaptcha.com/dpa/IMI_Data_Processing_Addendum_4.20.2023.pdf) |
| European Commission VIES | Validating VAT numbers | Company name, VAT number | [About](https://ec.europa.eu/taxation_customs/vies/) |
| GitHub | Optional sign in with GitHub | GitHub account identity for users who choose this method | [DPA](https://docs.github.com/en/site-policy/privacy-policies/github-data-protection-agreement) |

Some pages load resources directly from third parties, so your browser contacts them and they receive your IP address. We do not send them anything ourselves. These are Google Fonts on every page, Gravatar wherever a profile picture is shown, Stripe on billing pages, and hCaptcha on sign up, password reset and email verification. Gravatar additionally receives a hash of the email address the picture is derived from.

### Questions

Questions about this list should be addressed to <support@hex.pm>.
