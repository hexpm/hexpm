**Date:** 2026-06-05 (progress updated 2026-07-16)
**Status:** In progress — Hexdocs and Preview are consolidated and their
standalone repositories are archived; the Diff dark launch is implemented and
awaiting deployment while the standalone service remains live
**Repos affected:** `hexpm`, `hexpm-ops`, `hexpm_deploy`, `preview`, `diff`,
`hexdocs`

## Goal

Consolidate the standalone `preview`, `diff`, and `hexdocs` Phoenix apps:

- `preview` and `diff` fold into the hexpm monolith as internal sections that
  share hexpm's database, storage, HTTP client, CDN, and design system.
- `hexdocs` splits in two: its background processing folds into hexpm; its
  private-docs serving moves to a new `docs-private` Fastly Compute (Rust)
  edge worker, and its Phoenix app is removed entirely.

Introduce a two-mode hexpm release so all background queue work runs in dedicated
pods. Delete the remaining duplicated machinery across these apps.

Net result: the three standalone Phoenix apps are decommissioned; one hexpm
codebase with one image and two run modes; private-docs serving at the edge.

### Done so far (2026-07-16)

- **`docs-private` Compute service (§E.2): shipped.** Rust worker with the
  confidential-client OAuth flow (PKCE retained), AEAD-encrypted session
  cookie, local ES256 JWT verify with `docs:{org}` scope check, and
  SigV4-signed streaming from the private GCS bucket; dedicated ConfigStore
  injected via Terraform from KMS. Staging: hexpm-ops #178; prod:
  hexpm-ops #182; activated + purge token rotated: hexpm-ops #186.
- **hexorgs DNS cutover (§H, §J): done.** `hexorgs.pm` and `*.hexorgs.pm` are
  CNAMEs to the Fastly TLS endpoint in staging and prod; nothing routes
  private-docs traffic to the hexdocs Phoenix app anymore.
- **Private-docs CDN purging from the hexdocs queue: done.** hexdocs #137
  purges the `docs-private` Fastly service on private publishes (plus #138
  informative purge errors, #139 idempotent GCS deletes — see §B.7).
- **hexdocs HTTP layer removal (§E.3, serving half): shipped.**
  hexpm/hexdocs#140 deletes the entire Plug/Bandit stack, OAuth client,
  templates/static assets, `verify_key` auth path, and serving config —
  leaving the app as a pure background pipeline before its later removal.
  hexpm/hexpm-ops#187 removes
  the readiness probe, HTTP port, Service/Ingress/BackendConfig, the
  `hexdocs-ingress` global address, and the session/OAuth secrets.
- **Worker foundation (§A, §B.2, §J core): shipped.** hexpm/hexpm#1704 adds
  the `web`/`worker` supervision split, the Oban migration and periodic jobs;
  hexpm/hexpm-ops#188–#191 stage and then deploy the worker tier;
  hexpm/hexpm-ops#192 removes the old advisory-updater flag and makes config
  changes restart both roles; hexpm/hexpm_deploy#20 monitors web and worker as
  one rollout. Both environments run the same image for both roles, every role
  pod invokes migrations, workers stay outside the Erlang cluster, and billing
  and advisory jobs have completed successfully through Oban. Production runs
  three workers with a database pool of 5 and an 8 GiB memory limit; staging
  runs two workers with a pool of 3 against its 50-connection database limit.
- **Hexdocs processing (§B.1, §E.1, §F, §I): shipped.** hexpm/hexpm#1707
  ports the Hexdocs pipeline into the combined worker tier. Broadway is a thin
  transactional SQS reader; Upload, Search, Delete, and Sitemap execute as
  unique Oban jobs on the shared `heavy` queue. The port also adds streamed
  S3/GCS file operations, configurable HTTP retries, direct database-backed
  docs metadata and sitemap generation, mode-specific Fastly credentials, and
  worker-only docs configuration.
- **Preview processing (§B.1, §C, §F, §I): shipped.**
  hexpm/hexpm#1709 ports the Preview pipeline into the combined worker tier.
  Broadway transactionally converts S3 create/remove and custom sitemap
  messages into Upload, Delete, and Sitemap jobs on `heavy`; the workers retain
  archive filtering, size/path limits, direct database-backed release data,
  sitemap generation, bucket writes, and Fastly purges while reusing Hexpm
  infrastructure. hexpm/preview#181 added a queue-disabled transition mode, and
  hexpm/hexpm-ops#195 moved queue and bucket permissions to Hexpm workers. The
  pipeline was exercised in staging before the production rollout; both
  environments now run the same Hexpm worker implementation.
- **Preview web/UI and URL cutover (§C, §G–§J): shipped.** hexpm/hexpm#1714
  moves package file browsing, server-side syntax highlighting, Preview-backed
  README access, sitemaps, and legacy URL redirects into Hexpm. The canonical
  browser lives at `/packages/:package/:version/files/*filename` inside the
  package shell. hexpm/hexpm-ops#197–#200 prepared the shared certificate and
  configuration, routed both Preview hosts to Hexpm, removed the standalone
  Deployment and runtime infrastructure, and released both ingress addresses.
  `preview.hex.pm` and `preview.staging.hex.pm` now issue 301 redirects to the
  corresponding Hexpm hosts. hexpm/preview#182 documents the move and the
  repository is archived.
- **Diff dark launch (§D, §F, §I): implemented, not deployed.** The Hexpm
  `port-diff` branch adds the durable Oban generation path, shared-cache reader,
  package-shell UI, internal package links, and legacy host redirects. The
  hexpm-ops `configure-hexpm-diff` branch supplies the existing Diff bucket,
  shared cache version, IAM, and certificate coverage. Diff DNS and the
  standalone Deployment remain unchanged for the dark launch.
- **Standalone Hexdocs deployment (§E.3, §J): removed.** hexpm/hexpm-ops#194
  deletes the Deployment, PDB manifests, runtime ConfigMap/Secret, restart
  hook, obsolete AWS identity and settings, and splits the remaining GCP
  credentials by consumer. Queues, DLQs, buckets, Fastly services, Typesense,
  and `hexdocs-search` remain. hexpm/hexdocs#149 documents the repository move,
  and the GitHub repository is archived. No standalone Hexdocs workload or PDB
  remains in either staging or production.
- **Deploy command parsing: shipped.** hexpm/hexpm_deploy#21 parses commands
  from Slack `rich_text` blocks instead of flattened fallback text, so
  integration-added context blocks do not become deploy arguments. The fixed
  image is deployed in production.

Still open: deploy and validate the Diff dark launch, then separately cut the
legacy Diff host over to Hexpm and remove its standalone deployment and
repository-specific infrastructure.

### Current deployed state (2026-07-16)

- **Hexpm is current in both environments.** Staging is 2/2 and production is
  3/3 for both web and worker Deployments on `376b7ca`, the merged Preview web
  image. Preview background work runs only in Hexpm workers.
- **No standalone Preview or Hexdocs Kubernetes objects remain.** Both clusters
  have no matching Deployment, Service, Ingress, PDB, BackendConfig, ConfigMap,
  or Secret. The Preview and Hexdocs ingress addresses are also released.
- **Durable external dependencies remain intentionally.** Keep the Preview
  bucket, queue and DLQ, Hexpm worker IAM, Fastly read-only bucket identity, and
  legacy DNS redirect hosts. Keep the corresponding Hexdocs queues, buckets,
  Typesense, Fastly services and edge/search identities.
- **The Hexdocs and Preview repositories are archived.** README PRs
  hexpm/hexdocs#149 and hexpm/preview#182 document where their functionality
  moved.
- **Standalone Diff remains deployed.** `diff.hex.pm` and
  `diff.staging.hex.pm` still serve the standalone application; no Diff DNS or
  ingress cutover is part of the dark launch.
- **The deploy bot is current.** hexpm_deploy `0d7790e` is rolled out; Slack
  commands sent with separate context blocks are parsed structurally.

### Next slice

Apply the Diff ops configuration first, deploy Hexpm to staging, validate cache
hits and worker-generated misses, and then deploy production. Roll back the app
image before rolling back its required bucket/cache configuration. DNS remains
on standalone Diff until a later, separately validated host cutover and
teardown.

### What gets deleted (the DRY win)

The active Hexdocs and Preview copies have been removed. Diff still carries its
own copy of some subset of:

- an ETS package store + a 60s poller against the Hex repo API (diff),
- a storage abstraction over GCS for caching Diff results (`Diff.Storage`),
- a Finch + exponential-backoff HTTP client and a `hex_core` HTTP adapter,
- a Tailwind 4 design system — navbar, footer, theme toggle, layouts,
- syntax highlighting setup,
- tmp-dir handling,
- a Dockerfile + release config + CI.

All of these will collapse onto hexpm's existing equivalents.

## Non-goals / follow-ups

- No data migration of the preview/diff/hexdocs GCS buckets.
- No change to how packages/releases/docs are published.
- Public `hexdocs.pm` serving is unchanged — it already runs on the Fastly
  Compute `hexdocs` worker.

## A. Deployment modes

**Status: shipped for the role split, Oban, and Hexdocs/Preview ingress.** The
current worker child set contains both Broadway readers in staging and
production.

Single release and image. A new `HEXPM_MODE` env var (default `web`) decides what
`Hexpm.Application` starts, via a `children/1` split in the existing
supervision tree. Production accepts only `web` or `worker`; any other value
fails at boot rather than silently starting the wrong role. In dev, one node
starts the union of both child sets so the full system works locally. This
follows hexpm's current env-toggle pattern (`HEXPM_CLUSTER`,
`HEXPM_READ_ONLY_MODE`, `server: false`).

| Mode | Starts | Does not start |
|------|--------|----------------|
| `web` (default) | Phoenix Endpoint, LiveViews, `Hexpm.Cache` (node-local read cache), insert-only Oban, all request-serving infra | SQS consumers, Oban queues/plugins/peer |
| `worker` | Oban (+ cron, pruning, and Lifeline plugins), periodic jobs, and the Hexdocs and Preview Broadway SQS readers | HTTP Endpoint (`server: false`) |

The common child set contains the database, HTTP/storage clients, tmp-dir and
task infrastructure used by both roles. Runtime config is mode-aware: a worker
must not require web-only settings or secrets, and a web pod must not require
queue-only settings or credentials.

## B. Background processing (worker mode)

Broadway owns SQS ingestion; Oban owns durable execution, retries, uniqueness,
timeouts, and the shared memory-concurrency budget.

### B.1 Broadway / SQS — thin ingress into Oban

**Hexdocs and Preview: shipped.** Each pipeline consumes its existing SQS
queue, translates one message into one or more jobs, inserts all derived jobs in
a database transaction, and acknowledges SQS only after that transaction
commits. A failed insertion leaves the message retryable; redelivery finds the
same unique incomplete jobs instead of starting overlapping work.

- **`Hexpm.Hexdocs.Queue`** (shipped in hexpm/hexpm#1707):
  - ignores and acknowledges S3 test events;
  - `ObjectCreated:*` creates an Upload job and, for public Hex packages, a
    Search job;
  - `ObjectRemoved:*` creates a Delete job;
  - existing `hexdocs:upload`, `hexdocs:search`, and `hexdocs:sitemap` messages
    create the corresponding jobs;
  - Upload, Search, Delete, and Sitemap use the `heavy` queue, five attempts,
    a 270-second timeout, and uniqueness by worker + arguments across
    incomplete states for an infinite period.

- **`Hexpm.Preview.Queue`** (shipped in hexpm/hexpm#1709):
  - ignores and acknowledges S3 test events;
  - `ObjectCreated:*` creates an Upload job;
  - `ObjectRemoved:*` creates a Delete job;
  - `preview:sitemap` custom messages create Sitemap jobs;
  - malformed/unsupported messages fail and remain retryable, while irrelevant
    object keys are acknowledged without work;
  - Upload, Delete, and Sitemap use `heavy`, five attempts, a 270-second
    timeout, and uniqueness by worker + arguments across incomplete states for
    an infinite period;
  - path-traversal whitelisting, the 2 MB file cap, and the
    `hex_metadata.config` filter are preserved.

Development and tests use `Broadway.DummyProducer`. The reader starts only in
`worker` and `all`; web mode does not require SQS, Typesense, GitHub, private
bucket, or docs Fastly settings.

### B.2 Oban — scheduled / periodic work (singletons)

**Status: shipped.** The two periodic GenServers were converted directly into
Oban workers and moved off the web pods. With 3 production worker replicas a
plain timer would fire on every replica, so Oban cron schedules the jobs. It uses the
**`Oban.Peers.Database`** peer, so cron leadership is elected through Postgres
and one leader inserts scheduled jobs across the replicas **without Distributed
Erlang** — no hand-rolled advisory locks and no cluster dependency. Execution
is still at-least-once under retries, so the jobs remain idempotent.

- `Billing.Report` (was a 60s GenServer timer in web pods).
- `Security.Updater` (drops its custom advisory lock and the
  `HEXPM_ADVISORY_UPDATER` flag/timer).

The `periodic` queue has local concurrency 2. Billing is scheduled with
`* * * * *`; advisories with `*/30 * * * *`, both in UTC and without a
boot-triggered run. Both workers accept empty arguments, have five attempts,
and are unique across incomplete states for an infinite period so executions
cannot overlap. Transient failures return errors for Oban to record and retry.
The updater fetches the OSV archive through `Hexpm.HTTP` on every run; the
in-memory ETag and transaction-leader lock are gone, while replay-safe upserts
remain.

The existing k8s CronJobs are **left as-is** — they are one-shot `hexpm eval`
pods and do not need a long-running runner:

- `stats` (`Stats.run/0`) — heavy daily download-stats rollup. Stays a k8s
  CronJob.
- `check_names` (Levenshtein typosquat detection + email) — stays a k8s CronJob.
- `purge` (`purge_expired_records/0`) — Postgres cleanup of expired/revoked
  OAuth codes, tokens, sessions, plug sessions, password resets, and keys. Stays
  a k8s CronJob. (This is DB cleanup, unrelated to CDN purging.)

This does **not** replace the `hexpm-jobs` pod (see §J) — that is a separate
exec-in maintenance/console node, not a scheduled-work runner.

One Oban instance runs in every mode. Worker mode owns queues, plugins, and the
database peer; web mode starts an insert-only instance with queues, plugins,
and peer disabled so request paths can durably enqueue without executing jobs.

Production runs `periodic: 2` and `heavy: 3`; staging overrides `heavy` to 1
while keeping `periodic: 2`. Oban uses the database peer, seven-day pruning,
Lifeline with a 60-second interval and a six-minute rescue threshold, and a
300-second shutdown grace period. Heavy workers time out after 270 seconds, so
legitimate work completes or fails before Lifeline can classify it as orphaned.
`Security.Updater` has a five-minute timeout; Billing retains 20 seconds.
Development starts the queues without Cron; tests use manual mode.

### B.3 What stays on web

`Hexpm.Cache` is a node-local ETS cache read by web requests; its refresh must
run on the nodes that read it. It stays in web mode and is **not** moved to
worker.

### B.4 Worker scale, failure model, and clustering

**Status: worker Deployment and Hexdocs/Preview processing shipped.** Production
runs 3 replicas with a database pool of 5, a 2 GiB memory request, and an 8 GiB
limit. Staging runs 2 replicas with a database pool of 3, a 64 MiB request, and
a 512 MiB limit. The smaller staging pool leaves rollout headroom on its
50-connection Cloud SQL instance while still exceeding the periodic queue's
local concurrency of 2.

On current-main images, the Hexdocs and Preview Broadway readers and Oban run in
every worker pod in both environments. This is deliberately one combined worker
failure domain: if Preview, Hexdocs, or an Oban job crashes or OOMs the whole
BEAM, that pod may die. The work is designed to be repeatable, the other replicas continue
consuming, and Kubernetes restarts the failed pod. Splitting each queue into
its own Deployment would add operational machinery without improving the
required semantics.

An ordinary process crash is handled by OTP supervision. A container OOM cannot
be caught by OTP: Kubernetes kills and restarts the entire worker container. An
SQS message that was not acknowledged becomes visible again after its visibility
timeout and is processed by the same or another replica. Once its job
transaction commits, Oban owns processing independently of the SQS message. If
the acknowledgement is lost, redelivery resolves to the existing unique
incomplete jobs. External side effects remain idempotent because an Oban retry
may replay a partially completed upload, delete, index/sitemap write, or purge.
Alert on SQS DLQ depth and age, Oban retryable/discarded jobs, OOM restarts, and
worker restarts.

Concurrency settings are **per replica**, not fleet-wide. The shared `heavy`
queue is the per-pod memory budget: at most one heavy job executes on each
staging pod and three on each production pod, regardless of whether the job is
Hexdocs, Preview, or Diff. OSS Oban does not provide a global or weighted queue
limit, so scaling replicas multiplies the fleet-wide maximum. Size the local
limit from memory high-water marks, database pool capacity, and external-service
limits. SQS queue depth and oldest-message age remain the ingestion signals,
with Oban state, CPU, and memory as safeguards.

Oban owns the long-running process and its 270-second worker timeout; workers do
not wrap `perform/1` in another supervised Task. The 300-second Oban shutdown
grace and 330-second Kubernetes termination grace cover permitted work during a
rollout or scale-down. After a pod crash, Lifeline rescues an orphaned job about
six to seven minutes later. If a future worker needs more than 270 seconds, its
timeout, Lifeline threshold, Oban shutdown grace, and Kubernetes grace must be
raised together, with Lifeline always exceeding the longest permitted runtime.

Worker pods run with **`HEXPM_CLUSTER` unset** — they do not join the Erlang
cluster. The cluster's only real consumer is web-tier `Phoenix.PubSub` (the
`RateLimitPubSub` throttle broadcast); workers serve no requests and need no
cross-node PubSub. Oban (Postgres) and Broadway (SQS) coordinate without
Distributed Erlang. Keeping workers un-clustered shrinks the blast radius — a
worker netsplit or connection storm cannot perturb the web tier. The web
deployment keeps `HEXPM_CLUSTER=1` for global rate limiting.

### B.5 Shared heavy queue

**Status: shipped for Hexdocs and Preview; Diff pending.** Both Broadway readers
are thin and all processing runs in Oban. Diff must move into worker jobs rather
than running memory-heavy computation on web pods before it can share this
queue.

Rationale:

- **One job system.** Everything lives in Oban — uniform retries, backoff,
  observability/dashboard, and ops tooling — instead of split Broadway + Oban
  machinery.
- **Concurrency limits.** Oban queue limits bound concurrency on each worker.
  With OSS Oban the limit is local, so the fleet-wide maximum is
  `replicas × local_limit`; a true database-coordinated global limit requires
  Oban Pro's Smart engine or a separate application-level mechanism. Either way,
  diff concurrency is budgeted across the combined worker fleet to bound total
  compute and memory under bursts.

Concrete driver: diff has hit **OOM errors** when crawlers trigger many
concurrent `git diff` runs. Running that memory-heavy work in the web pods is
fragile; moving diff generation to an Oban queue with a bounded fleet maximum
derived from per-pod limits — off the web pods — is the robust fix.

All Hexdocs and Preview work and future Diff work use `heavy`, so no pod can
execute more than the configured number of memory-heavy jobs regardless of job
type.

### B.6 Future direction: package publish pipeline (not in this scope)

Once Oban exists (§B.2), parts of package publishing should move into it. The
publish request today runs: validate tarball → DB transaction → push tarball to
the repo bucket → build the per-package registry resource → email package
owners — all synchronous — while the repository-wide names/versions index
rebuild is **already async**, as a fire-and-forget `Task.Supervisor.start_child`
with no retries: a pod restart or GCS failure silently loses it. The split
below preserves the client-visible contract while making the async half
reliable.

**Stays synchronous** (the client-visible publish contract):

- **Tarball receive + validation.** The (16 MB-capped) body arrives on the web
  pod over the HTTP request regardless, and the client needs its 422 — nothing
  to offload.
- **Tarball upload.** After a 200 the artifact must be durable and immediately
  fetchable.
- **Per-package registry build.** Hex resolves dependencies via the per-package
  resource, so building it before the 200 is what makes
  publish-then-immediately-fetch work in CI and in scripts that publish packages
  in dependency order. It is cheap (one package's resource); making it
  eventually consistent would be an ecosystem regression for near-zero win. The
  real cost in this path is the **global `:registry` advisory lock** — concurrent
  publishes of unrelated packages serialize against each other and against 300s
  full rebuilds. Fix is lock granularity (per-resource lock keys), not async.

**Moves to Oban:**

- **Repository index rebuild** (names/versions). Already outside the response
  path; becoming an Oban job adds durability, retries, and observability with
  zero semantics change. A **unique job per repository** (unique on
  `available`/`scheduled` only, so an executing build does not swallow a new
  enqueue) coalesces N concurrent publishes into one rebuild. Jobs read current
  DB state rather than an event payload, so coalesced and out-of-order runs
  converge. Retire, revert, and advisory updates share this path.
- **Owner emails.** `Mailer.deliver!` runs after the transaction commits and the
  tarball is pushed — an email-provider outage turns successful publishes into
  500s today. Independent quick win.

**On awaiting Oban jobs from the request:** mechanically possible across the
un-clustered web/worker tiers since everything goes through Postgres — Oban Pro
`Relay` gives async/await on job results, or OSS via polling the job row /
`Oban.Notifier` (LISTEN/NOTIFY); web would run an insert-only Oban instance (no
queues, no plugins, no peer). But enqueue-then-await re-adds the latency
coupling plus queue latency, and under worker backlog publishes hit LB timeouts
for work that will succeed. If a job is fast enough to await inline, it is fast
enough to run inline. Await-with-deadline (wait ~10s, else 200 with a "registry
update in progress" note that old clients still treat as success) is the right
pattern only if the per-package build ever has to move off web, e.g. under a
§B.5 fleet-wide concurrency budget.

### B.7 Future direction: converge same-package docs processing

Concurrent docs uploads of the **same package** can race. The observed case —
two uploads both deleting the package-root `docs_config.js`, the loser crashing
on a GCS 404 — was made harmless by
idempotent deletes (hexdocs #139). The remaining window: two near-simultaneous
"latest" uploads (say 1.0.0 and 1.0.1) can both read the version list before
the other release is visible, both write the unversioned package-root files,
and the older upload's stale-file cleanup can delete root pages that exist only
in the newer version — torn package-root docs until the next latest-version
publish.

The shipped workers use infinite-period uniqueness across incomplete states,
keyed by worker and arguments. That coalesces redelivery of the same object key
while a matching job is available, scheduled, executing, or retryable. It does
not include completed jobs, and different version keys for the same package do
not serialize each other, so the package-root race remains.

The durable follow-up is to restructure the work so the race disappears.
Versioned uploads (`pkg/1.0.1/...`) never conflict across versions and stay
per-message jobs. The conflicting part — syncing the package root (unversioned
files + `docs_config.js`) to the latest release — becomes a **unique job per
`{repository, package}`** (unique on `available`/`scheduled`, the §B.6
index-rebuild pattern) that reads the current release set from Postgres and
re-syncs the root from the latest tarball. Concurrent publishes coalesce into
one converging run; ordering and locks stop mattering. OSS Oban uniqueness alone
does not serialize *execution*; it coalesces enqueues. The read-current-state
job design is what makes runs converge. Sourcing `docs_config.js` from Postgres
(§B.1) already removes the stale version read; the unique root-sync job removes
interleaved root writes.

Either way GCS deletes stay idempotent — SQS/Oban redelivery replays
partially-completed uploads regardless of serialization.

## C. Preview merge

**Status: shipped.** Hexpm owns the SQS reader and Upload/Delete/Sitemap jobs in
both environments, and the package file browser is part of the Hexpm web app.
The standalone application and its Kubernetes/runtime infrastructure are
removed; the repository is archived.

- **Canonical routes** are
  `/packages/:package/:version/files/*filename`, rendered inside the existing
  package shell. Preview sitemaps remain under `/preview/sitemap.xml` and
  `/preview/:package/sitemap.xml`.
- `SearchLive` and the standalone version list were **dropped** — entry is the
  existing files link from Hexpm package pages, which already have search and
  version navigation.
- `PreviewLive` keeps the file tree, fuzzy file finder, Lumis-highlighted file
  view, filename whitelist against the manifest, 2 MB cap, binary/large-file
  messages, version switching, raw-file links, and line highlighting while
  reusing Hexpm's package layout and styles.
- `ReadmeController` reads Preview files through `Hexpm.Preview`; the old
  `HEXPM_PREVIEW_URL` and `preview-files/{name}-{version}.json` HTTP API are
  removed.
- Legacy paths on both `preview.hex.pm` and `preview.staging.hex.pm` redirect
  permanently to the equivalent Hexpm package-file or sitemap URL.

## D. Diff merge

- **Status: implemented for dark launch, not deployed.** The standalone Diff
  host and DNS remain unchanged until the integrated path has been exercised in
  staging and production.
- **Routes** under `/diff/:package/:from..:to`, served by the hexpm web app.
- Entry is the package versions page's comparison control and adjacent-version
  links. There is no `/diff` landing page.
- `DiffLiveView` enqueues a unique Diff worker on the shared Oban `heavy` queue
  without executing `git diff` on the web process. Results use the histogram
  algorithm, cached to the diff bucket through `Hexpm.Store`, and rendered with
  the batched lazy-load UI. The **version-pair selector lives on the diff view
  itself** — changing from/to enqueues or loads the selected pair.
- `SearchLiveView` is dropped.
- The custom `git_diff` fork (`github: "ericmj/git_diff"`) is added to hexpm
  deps. `DIFF_CACHE_VERSION` cache-busting semantics are preserved.
- Diff moves only when the request flow can enqueue worker jobs and represent a
  queued/running result. This is required because crawler-driven concurrent
  `git diff` runs have caused web-pod OOMs; the shared queue provides the same
  per-pod memory budget as Hexdocs and Preview (§B.5).

## E. Hexdocs merge (split: background → hexpm, serving → edge)

Hexdocs is different from preview/diff. Its Phoenix app serves **only
private/org docs** (`*.hexorgs.pm`); public `hexdocs.pm` and package subdomains
are already served by the Fastly Compute `hexdocs` worker. We split it.

### E.1 Background processing → hexpm worker mode

**Status: shipped** in hexpm/hexpm#1707 and deployed in staging and production.

`Hexpm.Hexdocs.Queue` (§B.1) is the thin SQS reader; separate Upload, Search,
Delete, and Sitemap workers perform unpacking, `FileRewriter`, streamed bucket
downloads/uploads through `Hexpm.Store`, Typesense indexing, sitemap and
`docs_config.js` generation, and public/private Fastly purges. Package and
release metadata comes directly from Postgres; GitHub tag discovery remains for
special packages. The external Typesense service remains, while the standalone
`hex_core`/HTTP/storage/tmp duplication is removed. Converging same-package
root updates remains a follow-up (§B.7).

### E.2 Private docs serving → Fastly Compute (Rust)

**Status: shipped** — running in staging and prod with hexorgs DNS cut over
(hexpm-ops #178, #182, #186).

The **`docs-private`** Compute service is separate from the public
`hexdocs` worker — that serves private/org docs behind an OAuth login. A
separate service keeps every private-auth deploy decoupled from the service
carrying public `hexdocs.pm` traffic, scopes the private secrets to its own
ConfigStore, and matches the existing precedent of `repo` (authenticated) vs
`hexdocs` (public cache). Most primitives already exist in the `repo` worker
and `hex-shared` (ES256 JWT verify, `domain`/`scope` access checks, AWS-v4 GCS
signing, ConfigStore secrets, redirects, surrogate keys, auth-aware caching).

- **Confidential OAuth client.** `client_secret` lives in the service's
  dedicated ConfigStore (KMS-encrypted); PKCE is retained for defense in
  depth. This is a server-side worker, so a confidential client is the correct,
  more secure choice.
- **Login flow:** no valid session → 302 to hexpm `/oauth/authorize` with
  `scope=docs:{org}` and `redirect_uri` = edge callback; the callback exchanges
  the code at the hexpm token endpoint using the `client_secret`.
- **Session:** access token + **refresh token** stored in an AEAD-encrypted
  (`aes-gcm`) cookie. The encryption key is a ConfigStore secret.
- **Per request:** verify the access JWT (ES256, `hex-shared/jwt.rs`) and its
  `docs:{org}` scope (fast path, like the `repo` worker). **Refresh at the edge**
  using the refresh token when near expiry — no periodic re-login.
- **Serving:** stream from the private GCS bucket with AWS-v4 signing; reuse
  the subdomain routing, underscore→hyphen redirect, and surrogate-key
  patterns (shared helpers move to `hex-shared`). The org-fallback CSV lookup
  stays in the public worker, untouched.
- **Caching:** decouple the auth gate from the content cache. The auth check
  (step above) runs on **every** request *before* any cache read; only then is
  the content looked up, **keyed by org+path** (shared across users who can see
  the org, never per-user). A cache hit serves without touching GCS; an
  unauthorized requester is blocked before the cache is read, so nothing leaks
  across orgs. This is cheap because the gate is a **local** ES256 verify (no
  origin call) — cheaper than pass-through, since hits avoid the GCS fetch.
- **Revocation:** the design relies on the local JWT check alone, so revocation
  latency equals the access-token TTL — we do **not** add a per-request origin
  auth call. Access tokens are short-lived, which bounds the window. If
  near-instant revocation is ever required, it can be added as an origin
  `/api/auth?domain=docs` check cached with a short TTL; that affects only
  revocation freshness, not the content cache.

The edge code implements the browser OAuth flow, encrypted-cookie session and
refresh, and private-bucket gating, modeled on the existing `repo` worker auth.

### E.3 Drop the Phoenix app

**Status: application and infrastructure removed; repository archived.**
hexpm/hexdocs#140 removes the Bandit/Plug stack, hexpm/hexpm-ops#187 removes the
serving infrastructure, and hexpm/hexpm-ops#194 removes the remaining standalone
Deployment and runtime infrastructure. Serving now lives in hexpm-ops (Fastly)
and background processing lives in hexpm. hexpm/hexdocs#149 updates the README,
and the repository is archived.

## F. Shared / DRY layer

Collapse duplicated infrastructure onto hexpm's existing modules:

- **Package/version data → Postgres.** Hexdocs queries documented and retired
  versions, public package names, and sitemap entries directly. Preview
  processing and web routes use the existing `Repository.Packages`,
  `Repository.Releases`, and `Repository.Sitemaps` contexts. Diff still needs to
  delete its ETS store and 60-second repo poller and move lookups to those
  contexts.
- **Storage → `Hexpm.Store`.** Streamed S3 downloads and GCS file uploads are
  shipped for Hexdocs, including encoded object paths and idempotent deletes;
  Preview processing and web serving use the shared store through
  `Hexpm.Preview`. Keep the existing preview, diff, and docs buckets. Diff still
  needs to delete its storage wrapper and use the shared abstraction.
- **HTTP / tmp / hex_core.** Hexdocs and all active Preview code reuse Hexpm's
  HTTP, temporary-file, task, and `hex_core` infrastructure. HTTP retries are
  configurable, with the existing three transport-only attempts preserved by
  default and Hexdocs using five attempts for transport errors, 429, and 5xx
  responses. Diff still needs its copies removed at cutover.
- **CDN purging → `Hexpm.CDN.Fastly`.** There is no preview or diff Fastly
  service. preview purges the **`repo`** Fastly Compute service — the same one
  hexpm already purges (`HEXPM_FASTLY_HEXREPO = fastly_service_compute.repo.id`,
  identical to preview's `PREVIEW_FASTLY_REPO`) — only the surrogate keys differ
  (`preview/package/...`). The Hexpm Preview workers reuse that Fastly
  integration with the existing surrogate keys; the standalone identity and
  processing secret are removed. **diff has no CDN purging** (it serves cached
  diffs from GCS). Hexdocs now purges the
  dedicated public and private docs services through mode-specific
  `Hexpm.CDN.Fastly` configuration.
- **Syntax highlighting.** Preview reuses Hexpm's existing Lumis highlighter,
  linked-line formatter, supervised task infrastructure, and CSS tokens. Diff
  should reuse the same stack.

## G. Design language

Preview's standalone navbar, footer, layouts, and Tailwind configuration are
gone. Its file browser renders inside Hexpm's package shell and reuses Hexpm's
components and theme; only the file tree, code renderer, and Lumis syntax theme
were added. Apply the same approach to `DiffLiveView`: port only the diff
renderer (per-line +/- coloring and file status) and align it to Hexpm's tokens
and CSS classes.

Per project rules, no inline `style` attributes (CSP nonce enforcement) — styling
is via CSS classes only. (Hexdocs has no app UI to restyle — it serves doc HTML
from the bucket at the edge.)

## H. URL migration

- **preview: shipped.** Canonical file URLs are
  `hex.pm/packages/:package/:version/files/*filename`; sitemap URLs remain under
  `hex.pm/preview/...`. Host-scoped Hexpm routes issue app-level 301 redirects
  from legacy paths on `preview.hex.pm`, preserving sitemaps and deep links.
  Staging and production DNS point the old Preview hosts at Hexpm.
- **diff: pending.** Public URLs become `hex.pm/diff/...`; host-scoped Hexpm
  routes preserve old `diff.hex.pm` deep links with 301 redirects after DNS is
  cut over.
- **hexdocs:** public `hexdocs.pm` and package subdomains are unchanged (already
  on the edge). Private `*.hexorgs.pm` has moved from the Phoenix app to the
  `docs-private` Compute service, and its DNS points there.

## I. Config consolidation

- **preview (shipped):** Hexpm worker mode reads
  `HEXPM_PREVIEW_QUEUE_ID` and `HEXPM_PREVIEW_BUCKET`; Fastly purging reuses the
  existing Hexpm repository service/key. Web mode reads the shared Preview
  bucket through Hexpm's existing GCP identity. `HEXPM_PREVIEW_URL`, the
  standalone `PREVIEW_*` settings, JSON key, and runtime ConfigMap/Secret are
  removed.
- **diff:** remaining `DIFF_*` settings fold into the `HEXPM_*` namespace at
  cutover. Remove `HEXPM_DIFF_URL` when internal routes replace the standalone
  service.
- **worker foundation:** `HEXPM_ADVISORY_UPDATER` is removed. Oban Cron and
  database leadership now control advisory scheduling.
- **hexdocs background (shipped):** worker-only queue/storage/index settings use
  the Hexpm namespace: primarily `HEXPM_DOCS_*`, plus
  `HEXPM_PRIVATE_DOCS_HOST` and `HEXPM_FASTLY_*DOCS`, not the retired
  application's `HEXDOCS_*` namespace.
  Worker-only values cover the SQS queue, private docs bucket, Typesense, GitHub
  access for special packages, docs hosts, and public/private Fastly services;
  web mode does not read those values. The public docs bucket remains shared.
  The Hexpm GCP identity supplies Goth credentials.
- **hexdocs serving (→ Fastly ConfigStore):** a dedicated `docs-private`
  ConfigStore holds OAuth client id + secret, hexpm URL, JWT public key,
  session encryption key, private-bucket signing credentials, private host.
  Injected via Terraform from Google KMS, the existing ConfigStore pattern.

## J. hexpm-ops changes

- **`hexpm-worker` Deployment: shipped.** Base + prod/staging overlays use the
  same hexpm image as web with `HEXPM_MODE=worker`, no HTTP port or Service, and
  **`HEXPM_CLUSTER` unset** (workers do not join the Erlang cluster — see
  §B.4). The current-main image runs Oban and both Hexdocs and Preview Broadway
  readers in the same pods so all background work intentionally shares one
  failure domain. Staging and production both run `376b7ca`.
- The worker Deployment uses the web tier's zone spreading and host
  anti-affinity. Production uses 3 replicas, `maxUnavailable: 0`, and
  `maxSurge: 1`; staging uses 2 replicas and its existing rollout policy. The
  pod termination grace is 330 seconds, covering Oban's 300-second shutdown.
  Readiness checks the Oban `periodic` and `heavy` queues plus the Hexdocs and
  Preview Broadway readers. Process
  restarts/OOMs, queue age and depth, SQS DLQ depth, and Oban
  retryable/discarded state are the primary operational signals.
- Production worker pods request 2 GiB and may use 8 GiB so the combined tier
  has room for preview extraction, docs processing, and future diff work.
  Staging requests 64 MiB and may use 512 MiB. Production runs `heavy: 3` and
  staging `heavy: 1`. Scaling replicas multiplies OSS Oban local concurrency as
  well as database connections, so adjust them together rather than scaling
  replicas in isolation.
- Every web and worker pod invokes database migrations before starting. Ecto's
  migration lock lets the first pod apply pending migrations while the others
  wait or find that there is no pending work. Schema changes are additive for
  the duration of the two rolling updates, then old schema/code can be removed
  after both roles are live.
- `hexpm_deploy` monitors both the `hexpm-deployment` and
  `hexpm-worker-deployment`; a Hexpm rollout succeeds only when both use the
  requested image and all desired replicas are updated and ready with no old
  replicas remaining. *Done in hexpm/hexpm_deploy#20.*
- Slack event parsing uses user-authored `rich_text` blocks when present and
  ignores separate context blocks, while retaining fallback parsing for
  text-only events. *Done in hexpm/hexpm_deploy#21 and deployed as `0d7790e`.*
- Shared Terraform config/secret changes restart both web and worker
  Deployments, and `HEXPM_ADVISORY_UPDATER` has been removed from both
  environments. *Done in hexpm/hexpm-ops#192.*
- The Hexpm AWS identity has receive, delete, send, and batch-send access to the
  existing Hexdocs and Preview queues.
- The Hexpm GCP identity has object-admin access to the private docs bucket.
  The remaining edge/search credentials are intentionally separate: Fastly
  keeps the existing Hexdocs service account and HMAC key with read-only access
  to the public and private buckets; `hexdocs-search` has its own service account
  and key with object-admin access only to the public bucket.
- The Hexpm GCP identity also has object-admin access to the Preview bucket;
  Fastly's existing Preview bucket identity retains read-only access for the
  repository edge service.
- Worker-only ConfigMap and Secret resources carry docs and Preview queue/bucket
  settings plus the private bucket, Typesense, GitHub, host, and docs Fastly
  settings. Changes restart only `hexpm-worker-deployment`; web does not require
  them.
- **`docs-private` Fastly Compute service: shipped.** OAuth
  flow + private-bucket gating in Rust; dedicated ConfigStore (OAuth client
  id/secret, session encryption key, private-bucket credentials, hexpm URL)
  via Terraform from KMS; TLS + DNS for `hexorgs.pm`/`*.hexorgs.pm`.
  *Done (hexpm-ops #178, #182, #186).*
- `*.hexorgs.pm` DNS points to the `docs-private` service *(done)*. Both legacy
  Preview hosts point to Hexpm and redirect there *(done)*; Diff remains for its
  cutover.
- **Standalone Hexdocs teardown: shipped in hexpm-ops#194.** The Deployment,
  PDB manifests, runtime ConfigMap/Secret, restart hook, obsolete AWS user and
  policies, unused encrypted settings, dead GitHub variables, and completed
  Terraform state moves are removed. The queues and DLQs, docs buckets,
  Typesense, Fastly services and edge credentials, and `hexdocs-search`
  dependencies remain. Diff infrastructure stays until its cutover.
- **Preview processing cutover: shipped in hexpm-ops#195.** Queue access and
  object-admin bucket access moved to Hexpm workers; the standalone Preview
  consumer, AWS credentials, and processing Fastly secret were removed.
- **Preview web and teardown: shipped in hexpm-ops#197–#200.** The shared Hexpm
  certificate and web bucket configuration were prepared before the app
  rollout; DNS then moved both legacy hosts to Hexpm. The standalone Deployment,
  PDB, Service, Ingress, BackendConfig, runtime ConfigMap/Secret, GCP JSON key,
  encrypted settings, duplicate certificate, restart hook, and both reserved
  ingress addresses are removed. The queue and DLQ, bucket, worker IAM,
  Fastly read-only bucket identity, and redirect DNS remain intentionally.
- **Keep the three k8s CronJobs** (`stats`, `check_names`, `purge`) as-is — they
  remain one-shot `hexpm eval` pods, unaffected by the worker mode.
- **Keep `hexpm-jobs`** unchanged — it is the exec-in maintenance/console node
  (no BEAM running until an operator starts `eval`/`remote`; sized with large
  ephemeral storage for disk-heavy one-off jobs). It is *not* a scheduled-work
  runner and is *not* replaced by Oban. It remains the one deployment that wants
  `HEXPM_CLUSTER=1`, so a `remote` shell can attach to the live cluster.
