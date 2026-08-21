## Security

These are the technical and organizational measures we use to protect the data described in the [Privacy Policy](/policies/privacy), and the measures referred to in section 5 of the [Data Processing Agreement](/policies/dpa). We update this page as the measures change. The change history is available in the [git repository](https://github.com/hexpm/hexpm/blob/main/lib/hexpm_web/templates/policy/security.html.md).

### Encryption in transit

The websites, the API and the package repository are served over TLS, with HTTP Strict Transport Security.

### Encryption at rest

Data at rest is encrypted by the storage services described on the [Subprocessors](/policies/subprocessors) page. Backups of the package repository are encrypted before leaving our infrastructure, with keys held solely by Six Colors.

### Access control

Private packages and private documentation are served only to authenticated members of the owning organization, enforced both at the edge and in the application. Private documentation is served from hexorgs.pm, a separate registrable domain from public documentation, so that the browser same-origin policy isolates it. Administrative access to production systems is limited to Six Colors personnel who need it and is authenticated separately from user accounts.

### Credentials

Passwords are stored using bcrypt. API keys carry a defined scope and can be revoked individually. Two-factor authentication is available on user accounts.

### Resilience and recovery

The package repository is backed up daily to encrypted offsite storage. The database is backed up daily with point-in-time recovery.

### Logging and monitoring

Access to the package repository is logged. Actions taken within an organization are recorded in an audit log available to its administrators. Application errors and infrastructure metrics are collected to detect faults and abuse.

### Reporting a vulnerability

If you find a security problem in hex.pm itself, email <security@hex.pm>. Please don't open a public issue for it.

If you find a vulnerability in a package published on Hex, use the report form on that package's page. You need to be signed in with a verified email address. Vulnerability reports are sent to the [Erlang Ecosystem Foundation CNA](https://cna.erlef.org), which triages them and contacts the people involved. The [Privacy Policy](/policies/privacy) describes what the submission contains.

### Ecosystem security

The security model, practices and controls for the Hex package ecosystem, including the threat model, the development and build process, and supply chain integrity, are documented in the [specifications repository](https://github.com/hexpm/specifications/tree/main/security). That documentation covers the ecosystem as a whole. The measures Six Colors commits to are the ones on this page.
