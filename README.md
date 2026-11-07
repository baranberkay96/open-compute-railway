# Deploy and Host open-compute with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/open-compute-v04-self-hosted-workers-pla?referralCode=20H68q)

open-compute is an open-source, self-hosted platform compatible with the Cloudflare Workers API. One daemon runs your module Workers with KV, D1, R2, Durable Objects, Queues, Workflows, Cron Triggers and static assets on a single machine. This community template runs open-compute 0.4 with a persistent volume, generated tokens and an HTTPS URL.

## About Hosting open-compute

open-compute ships the control plane, a pinned workerd runtime, SQLite metadata and local or S3-compatible object storage as one binary, `ocd`. Hosting it yourself means a Linux machine with durable disk, TLS, three API credentials and a way to route Worker hostnames. This template builds on the official 0.4.0 image, initialises the instance on first boot, keeps all state on a Railway volume and puts a small Caddy proxy in front, so the Dashboard, the `/client/v4` API and your Workers share Railway's domain. It is a community template, not affiliated with Cloudflare or with the open-compute author.

## Common Use Cases

- Run Workers code (APIs, webhooks, middleware, small sites) on infrastructure you control, deployed with the `cf` CLI
- Keep KV, D1, R2 and Durable Objects data inside your own Railway project
- A staging or test target for Workers apps with real bindings, deployed from CI
- Cron jobs, queue consumers and Workflows next to your other Railway services

## Dependencies for open-compute Hosting

- open-compute 0.4.0 (`ocd` with its bundled workerd fork) from the official image `ghcr.io/elliothux/open-compute-init:0.4.0`
- A Railway volume at `/var/lib/open-compute` (SQLite, keys, object bytes, runtime cache)
- Caddy 2.11.7 inside the container for routing
- Optional: the included Railway Bucket as S3 object storage (experimental, off by default)
- On your computer: Node.js 22.18+ and the `cf` CLI (`1.0.0-beta.12`)

### Deployment Dependencies

- open-compute: https://github.com/elliothux/open-compute
- Documentation: https://open-compute.dev/docs/
- Compatibility and differences: https://open-compute.dev/docs/platform/compatibility/
- Worker projects and CI: https://open-compute.dev/docs/get-started/ and https://open-compute.dev/docs/develop/
- Backups: https://open-compute.dev/docs/ocd/backup/
- Railway custom and wildcard domains: https://docs.railway.com/networking/domains/working-with-domains
- Railway volume backups: https://docs.railway.com/volumes/backups

### Implementation Details

| Service | Runs | Public | Storage |
|---|---|---|---|
| open-compute | `ocd` on 127.0.0.1:8787 (workerd child per instance), Caddy on `PORT` 8080 | HTTPS domain: Dashboard, API, Workers | Volume `/var/lib/open-compute` |
| Bucket | Railway Bucket, used only with `OC_STORAGE_BACKEND=s3` | No | Bucket |

**First login.** The first boot takes a minute or two. Open the service URL: it redirects to the Dashboard at `/operator/`. Sign in with `OPEN_COMPUTE_ADMIN_TOKEN` from the Variables tab. The deploy logs print the Dashboard URL, the API base URL and the account ID. The API and all Dashboard data require a token; only `/health/*`, the Dashboard's static files and your Workers answer without one.

**Deploy your first Worker from your computer.** Create a project as in upstream's Get started guide (`cloudflare.config.ts` with `name: "hello-worker"`, `vite.config.ts` with the Cloudflare Vite plugin, `src/index.ts`), then point `cf` at Railway:

```bash
npm install --save-dev cf@1.0.0-beta.12 @cloudflare/vite-plugin@2.0.0-beta.sha-52b0dc0e9 vite typescript
export CLOUDFLARE_API_BASE_URL=https://{your-domain}/client/v4
export CLOUDFLARE_ACCOUNT_ID={account-id-from-the-deploy-logs}
export CLOUDFLARE_API_TOKEN={OPEN_COMPUTE_DEPLOYER_TOKEN}
export CF_SEND_TELEMETRY=false DO_NOT_TRACK=1
npx cf build --mode production
npx cf deploy --prebuilt --mode production
curl https://{your-domain}/w/hello-worker/
```

`OC_API_BASE_URL` holds the first value. The account ID is also returned by `curl -H "Authorization: Bearer {deployer-token}" https://{your-domain}/client/v4/accounts`. CI uses the same three variables. Wrangler projects move to `cf` with `cf migrate ./wrangler.jsonc --bundler vite`. With `ocd` installed locally, `ocd target add` and `ocd cf --target {name} deploy` work too. Use a `compatibilityDate` no later than 2026-10-07, the newest date this workerd build accepts.

**How Workers are addressed.** open-compute 0.4 routes a Worker by the internal host `{worker}.{account-id}.localhost`. Its own public Gateway needs ports 443 and 53 and cannot run on Railway, so Caddy maps public requests to those hosts:

- `https://{your-domain}/w/{worker}/...`: works with the generated domain. The `/w/{worker}` prefix is removed and sent as `X-Public-Prefix`, so use relative links or read that header.
- `OC_WORKERS_DOMAIN=workers.example.com`: add the wildcard custom domain `*.workers.example.com` to the service (Railway shows the DNS records). Then `https://{worker}.workers.example.com/` serves that Worker with its full path.
- `OC_HOST_ROUTES=app.example.com=my-worker,api.example.com=api`: exact custom domains, one Worker each.

Inside a Worker, `request.url` shows the internal `.localhost` origin, and open-compute 0.4 removes all `X-Forwarded-*` headers. The public host, scheme and client IP are in `X-Public-Host`, `X-Public-Proto` and `X-Public-Client-IP`; `CF-Connecting-IP` is the proxy's address. Other services in the project can call `http://open-compute.railway.internal:8080/w/{worker}/` and the API privately.

**Storage.** By default open-compute keeps object bytes (bundles, static assets, R2 objects, cache bodies, snapshots) on the volume. `OC_STORAGE_BACKEND=s3` uses the included Railway Bucket instead and must be chosen before the first start. It is experimental: open-compute checks conditional writes, multipart uploads and encryption headers at every start, and Railway lists server-side encryption as unsupported. The backend cannot be switched later; there is no migration between local and S3.

**Backups.** Enable scheduled backups for the volume in the service's Backups tab; they hold the SQLite databases, keys and local objects together. For a snapshot taken with the instance stopped, run `railway ssh`, then `oc instance stop default`, `oc --instance default backup create --name manual`, `oc instance start default`, and take a manual Railway backup. `oc` runs `ocd --system` as the service user; `oc-info` prints the account ID and URLs. With S3 storage, also back up the Bucket.

**Upgrades.** The version is pinned by tag and digest in `services/open-compute/Dockerfile`. Back up first, read the release notes, then change the image and redeploy. Database migrations only go forward, so roll back by restoring that backup together with the previous image.

**Tokens and settings.** Changing a token variable and redeploying rotates it. `OC_PUBLIC_URL` must match the domain you use for the Dashboard when you add a custom domain. `OC_EXTRA_CONFIG` appends TOML, for example `[ai]` provider backends for AI Search.

**Limits.** One machine and one replica by design: scale up the service's CPU and memory, not out. Keep App Sleeping off, because cron, queues and alarms run inside the daemon. Not available here: open-compute's managed Gateway (public R2 bucket URLs, per-Worker TLS), Containers (needs a Docker host), Browser Run (no Chrome in the image), general Workers AI inference, Hyperdrive, Analytics Engine, Rate Limiting, Workers for Platforms and Tail Workers. There is no global edge network; behaviour can differ from Cloudflare in details listed in upstream's compatibility guide.

**Resources.** Expect roughly 0.3 to 0.5 GB of RAM at idle (about $5 per month with the volume) and 1 to 2 GB with a few busy Workers. Use the Hobby plan or higher: the runtime cache and free-space reserves need more than a 0.5 GB volume.

### Why Deploy open-compute on Railway?

Railway gives open-compute the persistent disk, HTTPS endpoint and private network it needs without managing a server, so a Workers-style platform is one click away. You keep your code and data in your own project, deploy with the familiar `cf` workflow, and pay only for the resources the daemon uses.
