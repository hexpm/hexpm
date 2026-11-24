## Security incident on hex.pm

<div class="subtitle"><time datetime="2026-11-24T00:00:00Z">24 November, 2026</time> · by Peter Ullrich, Jonatan Männchen, and Eric Meadows-Jönsson</div>

On November 23, 2026, an unauthorized third party exploited a vulnerability in hex.pm that let them run commands on our web servers. We blocked the traffic and deployed a fix within 20 minutes. Shortly afterwards we received a report of this exact vulnerability.

We found no evidence of unauthorized package modifications, or database changes, or that the attacker maintained access to our systems. However, because database reads are not logged, we cannot rule out that the attacker accessed data stored in the database, including email addresses, password hashes, API key hashes, 2FA secrets, sessions, and audit logs.

Because email addresses may have been exposed, be careful with emails that claim to come from Hex. Please double-check that the links they contain lead to `hex.pm`. Please forward suspicious emails to [security@hex.pm](mailto:security@hex.pm).

We checked every file written to package storage during the incident against our database and found nothing unexpected. Reads of private packages in that period came from our own servers and coincide with releases the same organizations published at the time. A read made from a compromised server would look like one of ours, so we can't fully rule one out, and reads of private documentation aren't logged. We will contact affected organizations directly.

The attacker's commands could read the credentials our servers use, so we replaced them: the storage, CDN, email and database credentials, and the keys that sign sessions and access tokens. This logged everyone out of hex.pm and Hex clients. We're building a new registry signing system that supports key rotation, with new Hex client releases in the coming days. Until then, don't trust third-party mirrors and fetch packages only from repo.hex.pm. We already deployed fixes for the vulnerability and are working on further hardening fixes.

### What you should do

1. **Change your password** at [hex.pm](https://hex.pm).
2. **Reset your 2FA** at [hex.pm/dashboard/security](https://hex.pm/dashboard/security): under "Authenticator App", choose "Setup New App" and verify a code from the new entry. You get a new secret and new recovery codes, so store the new codes. This works when an organization requires 2FA, where disabling it is refused.
3. **Update your Hex client** when the release with the new signing system is out in the coming days. Until then, use only repo.hex.pm, not mirrors. To update, run `mix local.hex --force`, and update rebar3 or Gleam if you use them.

### Timeline

All times are in UTC.

**November 23, 2026**

* **18:16 - 18:29**: The attacker sent 69 malicious requests to hex.pm, six of our web servers were affected. Our error tracker Sentry recorded its first error at 18:16:00 and recorded an error for each request.
* **18:27**: We added a firewall rule to block the attacker's traffic, which took full effect between 18:30 and 18:33.
* **18:30 - 18:31**: All hex.pm servers were replaced with a patched build that rejects these payloads.
* **18:33 - 18:38**: All further requests from the attacking address were denied.
* **18:35**: We began investigating production logs and the database.
* **18:49**: We deactivated the AWS access key the affected servers used, after creating a replacement at 18:47.
* **19:07**: We received an email with a security report that described the same vulnerability.
* **20:21**: Most infrastructure credentials were rotated. The database password followed on November 24.
* **22:58**: We reported a personal data breach to IMY, the Swedish data protection authority.
* **23:05**: We reported the incident to CISA, the US Cybersecurity and Infrastructure Security Agency, which confirmed receipt at 23:43.
* **23:26**: We submitted an early warning to ENISA, the EU Agency for Cybersecurity.

**November 24, 2026**

* **By 10:42**: We had rotated every credential the attacker could have read, including the database password, except the registry signing key and a few low-impact secrets.
* **13:48**: We published [CVE-2026-129514](https://cna.erlef.org/cves/CVE-2026-129514.html).

### The vulnerability

The vulnerability in Hex.pm is tracked as [CVE-2026-129514](https://cna.erlef.org/cves/CVE-2026-129514.html).

hex.pm decoded unauthenticated request bodies in Erlang term format with `Plug.Crypto.non_executable_binary_to_term/2` which blocks most potentially harmful terms, but allows struct values through. These decoded struct values, when chained together correctly, turned into a remote command execution (RCE). This is the detailed playbook of the attack:

1. **The entry point.** A custom parser in the endpoint handled the `application/vnd.hex+erlang` content type using `Plug.Crypto.non_executable_binary_to_term/2` with `[:safe]`. Because the endpoint runs this parser before routing and authentication, any unauthenticated POST with that content type reached it on every route.
2. **Fake structs got through.** The decoder rejected functions and new atoms, but it never checked maps. An Elixir struct is just a map with a `__struct__` key naming a module. That meant the attacker could send a value the runtime treats as a real struct, with every field set to whatever they chose.
3. **Converting the structs into an error.** The decoded struct became the request's body parameters. `Plug.MethodOverride` then read `body_params["_method"]`, which on a struct calls `fetch/2` on the struct's module. That function didn't exist, so the request raised an `UndefinedFunctionError` with the attacker's struct in the stack trace.
4. **Error reporting runs inspect.** Sentry, Bandit's error logging, and the JSON log formatter call `inspect` on request data and stack-frame arguments. `Inspect` is a protocol, so for a struct it runs the implementation of the module named in `__struct__`, which let the attacker choose which code ran next. They chose `Ecto.Query.DynamicExpr`.
5. **The Ecto hop.** The `Inspect` implementation for `Ecto.Query.DynamicExpr` enumerated the `binding` field without checking that it was a list. Enumeration is itself a protocol call, so a struct placed in that field is dispatched to another implementation.
6. **The DBConnection hop.** The struct placed in `binding` was a `DBConnection.Stream`. Its `Enumerable` implementation calls `DBConnection.reduce/3`, which then calls `declare/4`. Encoding the query failed before any connection was checked out, but the error path still ran the stream's `:log` option. That option was a `{module, function, args}` tuple taken from the request, and db_connection applied it with the log entry prepended.
7. **Command execution.** An attacker-supplied `{module, function, args}` tuple that the server runs gives access to functions in loaded libraries and the standard library, which led to OS command execution as the BEAM's user.

While investigating, we found the same class of vulnerability in Ash: its keyset pagination accepted crafted structs in client-supplied cursors, which could lead to command execution or SQL injection. We reported it and the Ash team released a fix in ash 3.38.0 on November 24. It is tracked as [CVE-2026-124283](https://cna.erlef.org/cves/CVE-2026-124283.html).

### The fix

**hexpm** commit [379b0a2](https://github.com/hexpm/hexpm/commit/379b0a29bcc95164249f38ad7d772a37a8ff9533) makes the decoder reject any term containing a map with a `__struct__` key, returning a 400. Because the check sits in the one decoder used for this format, it covers every route that accepts it. That closes the entry point: an attacker can no longer get a fake struct into the request params. Every hex.pm server was running the patched build by 18:31 UTC.

### The future hardening fixes

We are working on hardening fixes for these libraries which should prevent such an attack in the future on multiple levels, not just one decoder check in the request pipeline:

1. **plug_crypto:** Document that the decoder is only safe for authenticated payloads, and add an option to reject structs.
2. **plug:** Refuse struct values as body params.
3. **ecto:** Check that the binding is a list before enumerating it in `Inspect`.
4. **db_connection:** Don't apply `:log` callbacks taken from stream structs.

### How we investigated

Every finding in this post is based on the checks below. Where a check is still running or something can't be verified from our logs, we say so.

* **69 exploit requests, 18:16–18:29 UTC:** we reviewed load balancer logs for both attacker addresses from their first request until 19:05. Their first request of any kind was at 18:14:21. The first exploit request arrived at 18:16:00 and the last one to reach a server at 18:29:33. No exploit request from either address succeeded after 18:29:33.
* **Commands ran on six web servers:** we matched files created on each server to exploit request timestamps. The first appeared 3 ms after a request at 18:16:46. Six servers were hit because a restart at 18:28 brought up three new servers still on the vulnerable build.
* **Detection:** our error tracker recorded the errors raised by the exploit requests between 18:16:00 and 18:29:33 UTC. Our first response on the servers followed at 18:23:55.
* **Firewall block:** we checked the firewall change log and denied requests in the load balancer logs. The rule was added at 18:27, took effect between 18:30 and 18:33, and denied every request from 18:33:48 on.
* **Patched build everywhere:** we checked the deployment pipeline and listed every server with its creation time and build. All web, worker and job servers were created between 18:30 and 18:31 from the fix. A local reproduction confirmed the old build runs the command and the fixed build rejects the request.
* **No lasting access:** we listed running processes on the affected servers before replacing them and found no shells. Cloud audit logs show no new keys, accounts or API calls from the attacker's addresses, and no writes by hex.pm's Kubernetes service accounts.
* **No database writes:** we restored a copy of the database from 18:13:59, before the attacker's first request, and compared every row of every table with the live database. Every row added, changed or removed since then is explained by an audit log entry from another address, by our background jobs, or by our own actions during the response. We found no unexpected change to tables, functions, roles or permissions. A row that was changed and then changed back, or one that a later legitimate change overwrote, would not show up in this comparison.
* **No modified packages:** all 23 releases published during the incident match a publish or stage entry in our audit log, and no older release changed. Storage writes came only from our own services. All 62 package files written since 18:00 match the checksums in our database, and all 186 registry files written since 18:00 match the database contents. Documentation archives have no stored checksum to compare against.
* **Credentials not used from outside:** Access logs, extended to 11,379 log objects and 15,635 records (record times 14:56-20:59): each of the 288 versions and markers listed for 18:00-20:00 has a log record for the same key within 3 seconds (231 hexpm-prod, 33 elixir_ghactions, 24 bob), and every logged write has a listed version. All 6,279 hexpm-prod requests came from the three node IPs. The logs hold no DELETE.OBJECT, no request with a version ID, no ACL or tagging write, no copy and no bucket listing by hexpm-prod.
* **Private packages and docs:** CDN logs show no requests from either attacker address to private docs in the last 30 days. Direct reads from cloud storage aren't logged, so we can't fully rule them out.
* **Possible database reads:** these can't be ruled out, because database reads, environment variable reads and shell commands aren't logged. Network traffic stayed within normal levels, except one worker server that peaked at 0.47 MB/s against a usual maximum of 0.29 MB/s.
* **Activity since November 19:** we reviewed request logs for hex.pm, repo.hex.pm, builds.hex.pm and hexdocs.pm for both attacker addresses. We found repeated downloads of hex.pm's own dependencies which suggests the attacker built a local copy of hex.pm to test against.
* **Present since 2016:** the git history of the request decoder shows the safety check was removed on February 23, 2016.
* **API key hashes can't be reversed:** we reviewed how hex.pm generates and stores secrets. API keys are 128-bit random values stored as HMAC-SHA256. We consider 128 bits of randomness far beyond the reach of brute force, so we don't see a need to rotate API keys because of the exposed hashes. Passwords are hashed with bcrypt, which slows guessing but doesn't prevent it for a weak password, so we ask you to change yours.

### Questions

We're sorry for the inconvenience these precautions cause. If you have questions or notice anything unusual in your account, contact us at [support@hex.pm](mailto:support@hex.pm). Security reports can be sent to [security@hex.pm](mailto:security@hex.pm). We'll update this post as our investigation continues.
