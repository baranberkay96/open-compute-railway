# NOTICE

This Railway template is a community package. It is not affiliated with, endorsed by or sponsored by Cloudflare, Inc., by the open-compute project or its author (github.com/elliothux), or by the project's sponsor. "Cloudflare" and "Workers" are used only to describe API compatibility, as upstream does; they are trademarks of Cloudflare, Inc.

## What this template runs

| Component | Version and source | License |
|---|---|---|
| open-compute `ocd` (control plane, scheduler, product bindings, Dashboard) | 0.4.0, release commit `213219468bd64d3c47138333817ead2f458c8eb0` (tag `v0.4.0`, published 2026-10-31). Taken from the official image `ghcr.io/elliothux/open-compute-init:0.4.0@sha256:519658d7d7aa71a1eb7062d75f65c0883dff0940905143108e05d892083de6ed`; its `/opt/open-compute/ocd` is byte-identical to the release asset `ocd-v0.4.0-linux-x64` (SHA-256 `75e85beb26a900af87f6d091e6efa620a176cf7411ba98be72be9aaa02a4e5f2`, from the release's `SHA256SUMS` and `release.json`) | Apache-2.0 (https://github.com/elliothux/open-compute/blob/v0.4.0/LICENSE) |
| workerd fork embedded in `ocd` | `v1.20260930.0-open-compute-r24.9de631551` (fork commit `9de631551791218aed0c4cd570163cece3c00590` of https://github.com/elliothux/workerd) | The packaged open-compute workerd fork remains under the applicable upstream Cloudflare workerd licensing (Apache-2.0, https://github.com/cloudflare/workerd/blob/main/LICENSE) |
| Caddy fork embedded in `ocd` (used only by open-compute's managed Gateway, which this template does not enable) | `v2.11.4-open-compute.2` from https://github.com/elliothux/open-compute-caddy | Apache-2.0 |
| Other inputs embedded in `ocd` | Pyodide bundle `314.0.6_2026-08-17_6`, Tesseract and Leptonica (static), `eng`/`chi_sim`/`chi_tra` tessdata, Xberg and the Rust crates in upstream's `Cargo.lock` | Their own licenses: Pyodide MPL-2.0; Tesseract and tessdata Apache-2.0; Leptonica BSD-2-Clause style ("Copyright (C) 2001-2020 Leptonica"); Xberg MIT ("Copyright (c) 2025-2026 Kreuzberg, Inc."). `ocd licenses` prints the bundled texts inside the container |
| Caddy (front proxy on `PORT`) | 2.11.7 release tarball `caddy_2.11.7_linux_{amd64,arm64}.tar.gz` from https://github.com/caddyserver/caddy/releases, SHA-512 checked against `caddy_2.11.7_checksums.txt` | Apache-2.0 (copy kept at `/usr/local/share/doc/caddy/LICENSE` in the image) |
| Ubuntu 24.04 base, `ca-certificates`, `curl`, `util-linux` (`setpriv`) | Installed by upstream's image Dockerfile from the Ubuntu archive | Their own licenses; see `/usr/share/doc/*/copyright` in the image |

The upstream image is used as published. This package adds Caddy, its own scripts under `/usr/local/bin` and `/usr/local/lib/oc-railway`, and a new entrypoint. No open-compute, workerd or Caddy file is modified, patched or rebuilt.

## Files in this package

| File | Origin |
|---|---|
| `services/open-compute/Dockerfile` | Written for this template. The Caddy download pattern follows this project's own `59-ubuntu-devbox` template |
| `services/open-compute/rootfs/usr/local/lib/oc-railway/setup-instance` | **Adapted** from `examples/container/init-volume.sh` in open-compute v0.4.0, Apache-2.0. Changes: runs inside the service instead of a separate init container, listens on 127.0.0.1:8787, leaves the instance configuration to `render-config`, and leaves markers and retries to the entrypoint. The file header states that it was modified |
| `services/open-compute/rootfs/usr/local/lib/oc-railway/common.sh` | Written for this template; `toml_string` is adapted from the same upstream script (Apache-2.0) |
| `oc-railway-entrypoint`, `oc`, `oc-info`, `render-config`, `render-caddyfile` | Written for this template from open-compute's documented configuration and source (listed below) |
| `template.json`, `TEMPLATE.md`, `README.md`, `NOTICE.md` | Written for this template. No upstream README or documentation prose is copied; the README's `npm install` line and the `cf` environment variables follow upstream's Get started guide and CI example |

Apache License 2.0 text: https://www.apache.org/licenses/LICENSE-2.0. The upstream repository's `LICENSE` carries no separate copyright line beyond the license text; the adapted files credit "the open-compute authors". There is no Railway marketplace template for open-compute to compare with (`_market/` is empty).

## Upstream material checked (open-compute v0.4.0, 2026-11-07)

The local copy in `_upstream/elliothux__open-compute` is the `v0.4.0` tag: the 17 source files this template relies on most were compared byte for byte with `gh api repos/elliothux/open-compute/contents/{path}?ref=v0.4.0` and are identical. `main` is 75 commits ahead (some of them touch `http.rs`, `instance_ops.rs`, `instance_registry.rs` and the S3 client); re-check those before bumping the version. Read for configuration facts only:

- `examples/container/{README.md,docker-compose.yml,docker-compose.external-s3.yml,docker-compose.build.yml,.env.example,init-volume.sh,Dockerfile}` and `test/container/smoke.sh` (init flow, tokens, S3 variables, `/health/live`, uid 65532, idempotence checks). The `init-volume.sh` inside the published init image was compared byte for byte with the local copy.
- `docs/releases/0.4.0.md`, `docs/references/single-binary.md`, `docs/implemented/p18-single-domain-public-gateway.md`, `docs/implemented/p8-local-s3-object-backend.md`, `docs/p26-external-proxy-worker-origins.md` (planned, issue #148 still open)
- Website docs in `apps/website/src/content/docs/docs/`: `get-started.mdx`, `develop/index.mdx`, `ocd/{configuration,dashboard,health,backup,instances,architecture}.md`, `gateway/index.md`, `operate/index.md`, `cli/index.md`, `platform/unsupported.md`, `workers/configuration/compatibility-dates.md`
- Source: `crates/service/src/http/shared.rs` (Host-based dispatch, loopback-only operator endpoints), `http.rs`, `workers_http.rs` (local ingress, `cf-connecting-ip`), `operator_session.rs`, `dashboard_auth.rs`, `run.rs` (listeners), `run/startup.rs` (object-storage and R2 preflights at every start), `instance_registry.rs` (system `OCD_DIR` and owner rule), `instance_ops.rs` (`instances --json`), `bin/ocd.rs` (tokio runtime, JSON logs); `crates/core/src/config.rs` and `config/{object_storage,product_limits,runtime_products}.rs` (fields, defaults, validation); `crates/artifacts/src/{preflight,r2_preflight,client}.rs` (conditional writes, SSE-C multipart check, AWS SDK settings); `crates/storage/src/worker_repository.rs` (Worker name rules, local hostname); `apps/dashboard/src/features/auth/*`, `routes/login.tsx`, `lib/management-client.ts`
- `packages/runtime/workerd.lock.json` (workerd release, maximum compatibility date 2026-10-07)

Image facts were read through the GHCR registry API without Docker: tag lists (`0.3.0`, `0.4.0` for both images), the OCI index digests (`open-compute:0.4.0` = `sha256:cbb02107d451b0f44e38b991f30295cf64acb3eb0dacc114e42d565c191f461d`, `open-compute-init:0.4.0` = `sha256:519658d7…de6ed`), the amd64 configs (user, entrypoint, `VOLUME` only on the runtime image, history), the init-script layer and the `ocd` layer (hash of the extracted binary).

Railway facts (checked 2026-11-07): https://docs.railway.com/storage-buckets (variables, virtual-hosted endpoint, "server-side encryption" listed as not supported, no bucket backups), https://docs.railway.com/networking/domains/working-with-domains (wildcard domains, custom domain limits per plan), https://docs.railway.com/volumes/backups. Tigris documentation (https://www.tigrisdata.com/docs/api/s3/, https://www.tigrisdata.com/docs/objects/conditionals) was read as background; Railway does not state which provider backs its buckets.

## Logo

The marketplace icon is open-compute's own favicon (`apps/website/public/favicon.svg` at the v0.4.0 release commit, served via jsDelivr). It is used only to identify the software.
