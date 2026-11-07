# open-compute v0.4 Self-Hosted Workers Platform: Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **open-compute v0.4 Self-Hosted Workers Platform** (46 chars; major.minor of the pinned 0.4.0; no "Cloudflare" in the name) |
| Description | Self-hosted Workers platform with KV, D1, R2, Durable Objects and Queues. (73 chars) |
| Category | Other |
| Tags | open-compute, workers, serverless, workerd, edge-functions, kv, d1, r2, durable-objects, self-hosted |
| Icon | `https://cdn.jsdelivr.net/gh/elliothux/open-compute@213219468bd64d3c47138333817ead2f458c8eb0/apps/website/public/favicon.svg` (200, image/svg+xml, 3,256 bytes) |
| Template repo | `baranberkay96/open-compute-railway` (this folder), service root `/services/open-compute` |
| Expected template code | `open-compute-v04-self-hosted-workers-pla` (40-character truncation, as in earlier publishes; `ship.py finish` rewrites the README button) |

There is no `LISTINGS.md` entry for this app; the name follows the brief. Everything in the description is delivered: KV, D1, R2, Durable Objects and Queues are all "99%" surfaces upstream and need no extra service. The README says "compatible with the Cloudflare Workers API" and that this is a community template, not affiliated with Cloudflare or the author.

## Base market templates

None. `_market/` is empty and no open-compute template exists on Railway (checked by the brief). The design follows upstream's own container deployment (`examples/container/`: init container + daemon on one named volume) translated to Railway's primitives.

## Pinned versions

| Component | Source | Version / digest | Released | Checked |
|---|---|---|---|---|
| open-compute `ocd` | `ghcr.io/elliothux/open-compute-init:0.4.0@sha256:519658d7d7aa71a1eb7062d75f65c0883dff0940905143108e05d892083de6ed` (OCI index, amd64 + arm64) | 0.4.0, commit `213219468bd6`; binary = release asset `ocd-v0.4.0-linux-x64`, SHA-256 `75e85beb…a4e5f2` (layer extracted and hashed) | 2026-10-31 (release and image) | 2026-11-07 |
| workerd (embedded) | open-compute fork | `v1.20260930.0-open-compute-r24.9de631551`, max compatibility date 2026-10-07 | 2026-10-30 | 2026-11-07 |
| Caddy | GitHub release tarball, SHA-512 pinned (`PIN_CADDY_*` build args) | 2.11.7 | 2026-10-03 | 2026-11-07 |

GHCR tags for both images: `0.3.0`, `0.4.0` (no `latest`). The runtime image `ghcr.io/elliothux/open-compute:0.4.0` (`sha256:cbb02107…191f461d`) shares the same `ocd` layer; it is not used because it declares `VOLUME` and runs as uid 65532, while the wrapper needs root to fix the volume owner. Caddy 2.11.8/2.11.9 (2026-11-04/05) fix mostly FastCGI issues that do not apply here; 2.11.7 is the version this project's other templates already build.

## Architecture

```
 Browser / cf CLI / CI ── HTTPS (Railway edge) ──┐
 Railway private network (other services) ───────┤
                                                 ▼
 ┌─ open-compute service (repo build, Dockerfile in services/open-compute) ───────────────┐
 │ Railway init (PID 1) → oc-railway-entrypoint (root: validate, volume owner, setup)       │
 │   ├─ Caddy :$PORT (8080, uid 65532)                                                      │
 │   │    /health/*                         → ocd (Host 127.0.0.1:8787)                     │
 │   │    OC_HOST_ROUTES host → worker      → ocd (Host {worker}.{id}.localhost)            │
 │   │    {w}.OC_WORKERS_DOMAIN             → ocd (Host {w}.{id}.localhost)                 │
 │   │    /w/{w}/… (prefix stripped)        → ocd (Host {w}.{id}.localhost)                 │
 │   │    /operator/api/*, /client/v4/accounts|memberships → ocd (Host 127.0.0.1:8787)     │
 │   │    /  → 302 /operator/;  everything else → ocd (public Host kept)                  │
 │   └─ ocd --system run on 127.0.0.1:8787 (uid 65532)                                     │
 │        ├─ instance "default": SQLite, master key, tokens, Local objects                  │
 │        └─ workerd child (supervised by ocd)                                              │
 │ Volume /var/lib/open-compute = system OCD_DIR                                            │
 └──────────────────────────────────────────────────────────────────────────────────────────┘
 Railway Bucket "Bucket" ← only with OC_STORAGE_BACKEND=s3
```

One service plus one (optional) Bucket. open-compute is single-machine by design: one daemon owns the instance's SQLite authority and data-directory lock, so there are no workers or replicas to add.

## Design decisions

### Init folded into the service

Upstream runs a one-shot `open-compute-init` container that writes `ocd.toml`, runs `ocd instance setup`, rewrites `compute.toml`, validates a full start and marks the volume. Railway volumes cannot be shared between services, so the image is built `FROM` the init image (it contains the same `ocd` binary, `util-linux` and no `VOLUME`) and the entrypoint runs the init steps idempotently before the daemon:

- **First boot** (`setup-instance`, adapted from `init-volume.sh`): `ocd.toml` with `public_bind = "127.0.0.1:8787"` and `admin_auth = { file = … }`, bootstrap daemon, `ocd instance setup --name default --config …/compute.toml --data-dir …/data --autostart=true --start=false`, stop. Markers in `/var/lib/open-compute/.railway/`: `setup-started` → `setup-done`.
- **Every start** (`render-config`): the three token files are rewritten from the variables (so changing a variable rotates a token; upstream's compose deliberately does not do this) and `compute.toml` is regenerated from variables, then `ocd --system --config … config check`.
- **Marker semantics:** upstream marks the volume only after a validated start. Here `initialized` is written after the first time the real daemon reports the instance `running`; it records the storage backend (and S3 authority) and later starts refuse a different one (exit 78 with both values), mirroring ocd's own fail-closed authority binding with a readable message.
- **Interrupted setup:** if `setup-started` exists without `setup-done`, the wrapper prints the tail of `init-daemon.log` and wipes the volume (except `lost+found`) before retrying. This is safe because setup never starts the instance or touches S3. A failed *first start* is retried without wiping (same instance id, so S3 authority markers stay valid). A volume with unknown data is refused.

### Worker routing on Railway

ocd 0.4.0 routes Workers only by the Host `{worker}.{instance-id}.localhost` on its listener (`http/shared.rs` `local_origin_instance`, `workers_http.rs` `local_ingress`). Public hostnames need the managed Gateway, which runs its own Caddy with ACME DNS-01 and requires public TCP 443 plus delegated UDP/TCP 53 (`docs/gateway`), which Railway cannot provide. Upstream's external-proxy mode for custom domains (`docs/p26-external-proxy-worker-origins.md`, issue #148) is still planned. So the template puts Caddy in front and rewrites Host:

- **Default (generated domain):** `/w/{worker}/…` with the prefix stripped and `X-Forwarded-Prefix` set; `/w/{worker}` redirects (308) to the slash form. Works with Railway's single `*.up.railway.app` domain.
- **Wildcard:** `OC_WORKERS_DOMAIN` + Railway wildcard custom domain → `{worker}.{domain}` with full paths. Validation refuses Railway's shared domains and a domain that would capture the control host.
- **Exact:** `OC_HOST_ROUTES=host=worker,…`, one custom domain per Worker (Railway: Trial 1, Hobby 2, Pro 20 custom domains per service).
- **What Workers see:** `request.url` uses the `.localhost` origin. Caddy sets `X-Forwarded-Host`, `X-Forwarded-Proto` (preserved from Railway's edge; `trusted_proxies` = private ranges + 100.64.0.0/10) and `X-Forwarded-For`. ocd overwrites `cf-connecting-ip` with the TCP peer (127.0.0.1). Worker names follow ocd's rule `[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?`, so they are valid DNS labels.
- Caddy uses `flush_interval -1` (streaming, SSE) and passes WebSocket upgrades (Live Tail, Durable Object WebSockets).

### Control plane and authentication

- **Tokens:** `OPEN_COMPUTE_ADMIN_TOKEN`, `_DEPLOYER_TOKEN`, `_READ_ONLY_TOKEN`, each `secret(48)` alphanumeric; the entrypoint requires 24-512 safe characters and distinct values (ocd also rejects equal tokens). They reach ocd only as owner-only files (`keys/admin.token`, `data/keys/{deployer,read-only}.token`, mode 0600); they are unset in the environment of ocd, workerd (ocd clears its env anyway), Caddy and every `ocd` CLI call, and never appear in argv.
- **Dashboard:** `[dashboard] enabled = true`; sign-in with the admin token on `/operator/login` (`POST /operator/session` mints an 8-hour browser session; same-origin check passes through `Sec-Fetch-Site`, and the public Host is kept for that path so the Origin fallback also matches). ocd answers `/operator/api/instances`, `/client/v4/accounts` and `/client/v4/memberships` only for loopback Host names (`shared.rs`); Caddy sends exactly those paths with `Host: 127.0.0.1:8787`, otherwise the Dashboard cannot resolve its account. These endpoints still require the admin token, a deployer/read-only token or a Dashboard session; the loopback restriction is upstream's defence in depth for a local listener, and this is a deliberate deviation for a hosted deployment (see Open questions).
- **Unauthenticated surface on the public domain:** `/health/live`, `/health/ready`, the Dashboard's static shell, Workers, `/v2` (401 challenge). `/metrics`, `/client/v4/*`, `/operator/api/*` and Git (`/git/*`, repository tokens) require credentials.
- No TCP proxy. ocd is not reachable except through Caddy.

### Object storage: local by default, Bucket optional

Requirement check of open-compute's S3 mode (`crates/artifacts`): at **every instance start** `preflight_object_storage` and `preflight_r2` run PUT/HEAD (user metadata, MD5 ETag, content type)/ranged GET/DELETE, `If-None-Match: *` (create-only must fail on an existing key), `If-Match` (wrong ETag rejected, right ETag accepted), `ListObjectsV2` pagination, `DeleteObjects` visibility, and a **multipart upload with SSE-C customer keys**. Railway's bucket docs list "server-side encryption" as not supported and say nothing about conditional writes; Tigris (which the endpoint appears to be, unconfirmed) accepts SSE-C headers without applying them and documents conditional headers. Our HydraDB template's deploy showed create-only PUTs and user metadata working on a Railway Bucket (2026-10-30). That is not enough to promise the full preflight, and a failed preflight leaves the instance unable to start, so:

- **Default `OC_STORAGE_BACKEND=local`:** objects under `<data>/objects` on the volume, as upstream's default. Railway volume backups capture SQLite, keys and objects together.
- **Option `s3`:** the template provisions a Railway Bucket and wires `OC_S3_*` to it (`force_path_style = false` for virtual-hosted buckets; `region = auto`; prefixes `open-compute/system/` and `open-compute/tenant/r2/` as upstream's compose). Must be set before the first start; fixed afterwards. Gains: object bytes not limited by the volume, off-host `ocd backup` snapshots, `backup restore` (S3 only). Costs: S3 latency for assets and cache bodies, uploads billed as service egress. The S3 keys are passed to ocd only in s3 mode.

### Disk, CPU and memory sizing (Rule 8.15)

ocd's defaults assume a large disk (1 GiB soft / 256 MiB hard free-space reserves, 10 GiB artifact cache, 1 GiB logs database). The entrypoint sizes them from the volume (`df`): reserves 10% (128 MiB-1 GiB) and 4% (128-256 MiB), cache 15% (256 MiB-10 GiB, artifact max 512 MiB), observability DB 10% (64 MiB-1 GiB); local storage uses the same reserves. On a 5 GB Hobby volume: 512/204 MiB reserves, 768 MiB cache, 512 MiB logs. `TOKIO_WORKER_THREADS` (tokio reads it because ocd builds `new_multi_thread()` without a fixed count) and `MALLOC_ARENA_MAX` come from the cgroup CPU quota, capped at 8 (`OC_CPU_LIMIT` overrides).

### Process supervision (Rule 8.3)

Railway's init is PID 1. The entrypoint stays as parent of `ocd` and Caddy (both via `setpriv --reuid=65532 --regid=65532 --clear-groups --no-new-privs`, as in the HydraDB template), polls both, and on SIGTERM stops both and waits; if either exits, it stops the other and exits 1 so Railway's `ALWAYS` policy restarts the pair. `RAILWAY_DEPLOYMENT_DRAINING_SECONDS=60` matches upstream's `stop_grace_period`. ocd supervises workerd itself.

### Healthcheck (Rules 8.1, 8.5)

`PORT=8080` (Caddy) and `/health/ready` (ocd's shared readiness: 200 once an instance is ready). Caddy starts only after `ocd instances --json` reports `running`, so the healthcheck passes only when the instance serves. Timeout 900 s: first boot runs the bootstrap daemon, materialises the embedded runtime (workerd, Pyodide, OCR data) on the volume and installs the Dashboard version.

## Services

### open-compute

- Source: repo `baranberkay96/open-compute-railway`, root `/services/open-compute` (Dockerfile build `FROM ghcr.io/elliothux/open-compute-init:0.4.0@sha256:519658d7…`)
- Start command: none (image entrypoint `oc-railway-entrypoint`); pre-deploy: none
- Healthcheck: `/health/ready` on `PORT` 8080, timeout 900 s
- Public domain: yes, target port 8080; TCP proxy: none
- Volume: `/var/lib/open-compute` (system `OCD_DIR`: `ocd.toml`, `keys/`, `instances/default/{compute.toml,data/}`, `cache/packages/`, `init-daemon.log`, `.railway/`)
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Default | Notes |
|---|---|---|
| `PORT` | `8080` | Caddy port; must be 1024-65535 and not 8787 |
| `OPEN_COMPUTE_ADMIN_TOKEN` | `${{secret(48, "a-zA-Z0-9")}}` | Global admin: Dashboard, instance control, metrics |
| `OPEN_COMPUTE_DEPLOYER_TOKEN` | `${{secret(48, …)}}` | `CLOUDFLARE_API_TOKEN` for `cf`/CI |
| `OPEN_COMPUTE_READ_ONLY_TOKEN` | `${{secret(48, …)}}` | Read-only API |
| `OC_PUBLIC_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | `artifacts.public_origin` and `observability.external_control_origin` (Live Tail WebSocket URLs, Git remotes). Empty → `http://127.0.0.1:8787` with a warning |
| `OC_API_BASE_URL` | `${{OC_PUBLIC_URL}}/client/v4` | Informational, for `CLOUDFLARE_API_BASE_URL` |
| `OC_PRIVATE_URL` | `http://${{RAILWAY_PRIVATE_DOMAIN}}:${{PORT}}` | Informational, for other services |
| `OC_PATH_ROUTES` | `true` | `/w/{worker}/` routing |
| `OC_WORKERS_DOMAIN` | empty | Wildcard Worker domain |
| `OC_HOST_ROUTES` | empty | `host=worker` pairs |
| `OC_DASHBOARD` | `true` | `[dashboard] enabled` |
| `OC_STORAGE_BACKEND` | `local` | `local` or `s3`; fixed after first start |
| `OC_S3_ENDPOINT`, `OC_S3_BUCKET`, `OC_S3_REGION`, `OC_S3_ACCESS_KEY_ID`, `OC_S3_SECRET_ACCESS_KEY` | `${{Bucket.ENDPOINT}}` etc. | Used only in s3 mode |
| `OC_S3_FORCE_PATH_STYLE` | `false` | Virtual-hosted (current Railway Buckets) |
| `OC_S3_PREFIX`, `OC_S3_R2_PREFIX` | `open-compute/system/`, `open-compute/tenant/r2/` | Must be disjoint |
| `OC_EXTRA_CONFIG` | empty | Raw TOML appended to `compute.toml` (e.g. `[ai]`); rendered sections are refused |
| `OC_CPU_LIMIT` | `auto` | Thread sizing |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Graceful stop |

Read by the entrypoint but not in the template: `OC_START_TIMEOUT_SECONDS` (900), `OC_SETUP_TIMEOUT_SECONDS` (300), `MALLOC_ARENA_MAX`. No required inputs.

### Bucket

Railway Bucket `Bucket` (private, S3-compatible). Unused unless `OC_STORAGE_BACKEND=s3`; an empty bucket costs nothing. Layout in s3 mode: `open-compute/system/` (authority marker, bundles, assets, snapshots, cache bodies) and `open-compute/tenant/r2/` (tenant R2 buckets). Railway Buckets have no versioning or backups.

### Files

| File | Purpose |
|---|---|
| `services/open-compute/Dockerfile` | `FROM` the digest-pinned init image; Caddy 2.11.7 (SHA-512); scripts; build-time checks (`bash -n`, `ocd --version` = 0.4.0, uid/gid 65532, `setpriv`, a sample Caddyfile through `caddy validate`); no `VOLUME` |
| `rootfs/usr/local/bin/oc-railway-entrypoint` | Validation, volume owner, setup/retry, storage lock, sizing, ocd + Caddy start, supervision |
| `rootfs/usr/local/lib/oc-railway/setup-instance` | First-boot setup (adapted upstream `init-volume.sh`, Apache-2.0) |
| `rootfs/usr/local/lib/oc-railway/render-config` | Token files and `compute.toml` |
| `rootfs/usr/local/lib/oc-railway/render-caddyfile` | Caddyfile from routing variables and the instance id |
| `rootfs/usr/local/lib/oc-railway/common.sh` | Paths, regexes, helpers |
| `rootfs/usr/local/bin/oc`, `oc-info` | `ocd --system` as uid 65532 and a deploy-info printout, for `railway ssh` |

## Deploying a first Worker (laptop)

1. Read the deploy logs: `Account ID: {32 hex}`; or `curl -H "Authorization: Bearer $DEPLOYER" https://{domain}/client/v4/accounts`.
2. Project per upstream's Get started guide (`cf@1.0.0-beta.12`, `@cloudflare/vite-plugin@2.0.0-beta.sha-52b0dc0e9`, `cloudflare.config.ts` with `workersDev: false` and `compatibilityDate` ≤ 2026-10-07).
3. `CLOUDFLARE_API_BASE_URL=https://{domain}/client/v4 CLOUDFLARE_ACCOUNT_ID={id} CLOUDFLARE_API_TOKEN={deployer} CF_SEND_TELEMETRY=false DO_NOT_TRACK=1 npx cf build --mode production && npx cf deploy --prebuilt --mode production` (the same three variables upstream's GitHub Actions example uses).
4. `curl https://{domain}/w/{worker}/`. Alternatively `ocd target add railway --api-base-url https://{domain}/client/v4 --instance-id {id} --token-file {file}` and `ocd cf --target railway deploy --prebuilt --mode production`.

## Backups, upgrades and restoring data

- **Volume backups** (Railway Backups tab): crash-consistent copy of SQLite (WAL), keys, local objects and the runtime cache. Restores are staged as a new volume and need a redeploy.
- **Application-consistent snapshot:** `railway ssh` → `oc instance stop default` → `oc --instance default backup create --name {label}` → `oc --instance default backup inspect --snapshot {id} --verify` → `oc instance start default`, then a manual volume backup. With Local storage the snapshot lives on the same volume (upstream: a consistency snapshot, not an off-host backup). With S3 storage it lands in the Bucket and `oc backup restore` can use it (stop the daemon first per upstream's incident guide).
- **Upgrades:** change the `FROM` tag and digest in the Dockerfile (both from GHCR for the new release), read the release notes (0.4.0's upgrade preflight rejects 0.3.0 instances that retain older Worker versions), take a volume backup, redeploy. `ocd upgrade` is not used inside the container. Control-database migrations are forward-only (upstream: keep a backup made with the previous binary, never edit migration rows), so a rollback means restoring that backup together with the previous image. How a newer `ocd` behaves when it starts directly on incompatible data (rather than through `ocd upgrade`) is not verified.
- **Restoring data:** the entrypoint refuses a volume that contains files it did not create. To adopt an open-compute system scope from elsewhere, copy it to the volume with the same layout (`/var/lib/open-compute/ocd.toml`, `instances/default/compute.toml` and `data/`), make it owned by 65532, and create `.railway/setup-done` (and `.railway/initialized` containing the exact storage line the entrypoint logs, if the backend is already bound). The entrypoint then rewrites `compute.toml` and the token files from the variables, so the deployer and read-only tokens become the variables' values.

## Improvements over upstream defaults

There is no market template, so this compares with upstream's compose example:

1. **Init on Railway:** one service instead of an init container plus daemon sharing a volume (impossible on Railway), with the same steps, an interrupted-setup recovery and a first-start marker.
2. **Worker routing on a hosted domain:** `/w/{worker}/`, wildcard and exact custom domains, without the managed Gateway (which needs ports 443/53). Upstream's compose only exposes `127.0.0.1:8787` and `.localhost` hostnames.
3. **Remote Dashboard and API** on HTTPS with upstream's own token/session auth, public origin wired into Live Tail and Git URLs (upstream's init hardcodes `http://127.0.0.1:{port}`).
4. **Generated, distinct tokens** with rotation by variable; tokens never in env of ocd/workerd/Caddy or in argv.
5. **Disk budgets sized to the volume** and thread pools to the CPU quota.
6. **Storage lock with a readable error** before ocd's own fail-closed check.
7. **Railway Bucket pre-wired** for the S3 mode, off by default until verified.
8. Validation of every input with exit code 78 and the variable name.

## Resource estimate

Not measured (no container run). ocd is one Rust process, workerd one child per instance, Caddy a small Go process.

| Profile | RAM | vCPU | Volume | $/month |
|---|---|---|---|---|
| Idle (Dashboard only, no traffic) | ~0.3-0.5 GB | ~0.02 | ~1 GB (runtime cache ~0.3 GB, SQLite) | ≈ $5 |
| Typical (a handful of Workers, KV/D1, some cron and queues, light traffic) | ~1.2 GB | ~0.2 | ~3 GB | ≈ $17 |
| Busy (many Workers, Durable Objects, steady traffic) | ~3 GB | ~1 | ~20 GB | ≈ $53 |

Prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month; egress extra. Minimum plan: **Hobby** (5 GB volume). Trial's 0.5 GB volume cannot hold the runtime cache plus free-space reserves. **Pro** for large R2/asset volumes or the busy profile.

## Verification checklist

1. Build log: Caddy SHA-512 OK, `ocd 0.4.0` printed, `Valid configuration` from the Caddyfile check.
2. First boot logs, in order: `first boot: setting up…`, `setup: done`, `disk: volume … MiB …`, `cpu: N core(s)…` (record N and the volume size), `ocd started`, ocd JSON lines, `first successful start; object storage is now fixed to: backend=local`, `Caddy started`, the summary with Dashboard/API/Account ID. Healthy within 900 s; note the actual first-boot time.
3. `GET /` → 302 `/operator/`; Dashboard login with `OPEN_COMPUTE_ADMIN_TOKEN` works and the account loads (proves the loopback rewrite); a wrong token is rejected.
4. Without a token: `GET /client/v4/accounts` → 401/404 JSON error, `/metrics` → not 200, `/operator/api/instances` → 401. `/health/ready` → 200.
5. `curl -H "Authorization: Bearer $DEPLOYER" https://{domain}/client/v4/accounts` lists one account with the logged id.
6. From a laptop, the README's `cf build`/`cf deploy` succeeds; `GET /w/hello-worker/` returns the Worker's JSON with `"path":"/"`; `GET /w/hello-worker` redirects (308).
7. Dashboard: the Worker appears; Live Tail connects over `wss://{domain}` and shows a request.
8. A Worker using KV and D1 and a cron trigger: data persists and cron fires.
9. Redeploy: same account id, Worker still served, logs show no setup step; token files unchanged unless variables changed.
10. Rotate `OPEN_COMPUTE_DEPLOYER_TOKEN`, redeploy: old token rejected, new accepted.
11. Optional: a wildcard custom domain with `OC_WORKERS_DOMAIN` serves `https://{worker}.{domain}/`; `OC_HOST_ROUTES` likewise.
12. Separate test project with `OC_STORAGE_BACKEND=s3` before first deploy: does the instance reach `running` (S3 + R2 preflight on the Railway Bucket)? Record the error if not; if it passes, deploy a Worker with an R2 binding and static assets.
13. `railway ssh`: `oc instances`, `oc-info`, and the stop/backup create/start sequence work.

## Open questions

- **Not built or run** (no Docker by instruction). Verified: GHCR tags, index and amd64 configs; the `ocd` binary in the image hashed against the release's `SHA256SUMS`; the init script layer byte-identical to upstream; Caddy checksums; every script `bash -n`; the rendered Caddyfile through `caddy validate` and a live routing test with Caddy 2.11.7 against an echo server (health, `/w/` strip + redirect, wildcard, exact host, loopback rewrite paths, private host with port, root redirect); 24 input-validation cases; an end-to-end simulation of the entrypoint with fake `ocd`/`caddy`/`setpriv` (fresh boot, rejected config, restart, storage switch refused, ocd crash, Caddy crash, failed instance, interrupted setup wiped, unknown data refused, s3 mode, SIGTERM during setup and while running; no leftover processes, no tokens in child env or argv); `compute.toml` parsed as TOML and checked field by field against ocd 0.4.0's config structs.
- **workerd on Railway's runtime:** no special kernel features are used outside Containers (seccomp only in the Docker Broker), but V8 under Railway's container runtime, and an executable data directory on the volume (ocd requires it), are unverified.
- **Loopback Host rewrite** for `/operator/api/*`, `/client/v4/accounts`, `/client/v4/memberships` relies on upstream's current dispatch; a future release could tighten it (e.g. by checking the TCP peer). Re-test the Dashboard on every upgrade.
- **Worker `request.url`** shows the `.localhost` origin. Apps that build absolute URLs must use `X-Forwarded-*`. Upstream's p26 (external proxy origins) would remove this; switch when it ships.
- **S3 mode on Railway Buckets** is unverified (SSE-C multipart, If-Match, DeleteObjects with CRC32 checksums) — checklist item 12. If it passes, consider making it the default for new deploys.
- **Disk and memory numbers** are estimates; record real usage after a day.
- **`lost+found`** (if Railway's volume has one) stays root-owned inside `OCD_DIR`; ocd does not scan `OCD_DIR`, but this is not tested.
- **Dashboard** is labelled "in development" by upstream (0.4.0 shows an alert after login).
- **Repo name** `baranberkay96/open-compute-railway` per the brief; the deploy-button code is predicted.
