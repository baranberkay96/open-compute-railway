# open-compute 0.4.0 for Railway.
#
# Base: upstream's published init image. It carries the same checksum-verified
# `ocd` release executable as the runtime image (ocd-v0.4.0-linux-x64,
# sha256 75e85beb26a900af87f6d091e6efa620a176cf7411ba98be72be9aaa02a4e5f2),
# plus util-linux, and it runs as root with no volume declaration. Railway
# cannot run upstream's separate one-shot init container against a shared
# volume, so this image folds the init step into its own entrypoint
# (oc-railway-entrypoint), which runs it idempotently before the daemon.
#
# Pinned by tag and by the multi-arch OCI index digest published for v0.4.0
# (release commit 213219468bd64d3c47138333817ead2f458c8eb0, image built 2026-10-31).
FROM ghcr.io/elliothux/open-compute-init:0.4.0@sha256:519658d7d7aa71a1eb7062d75f65c0883dff0940905143108e05d892083de6ed

# Caddy fronts open-compute on $PORT: Railway's edge sends every domain of the
# service to one port, and Caddy maps public hosts and /w/{worker}/ paths to the
# Worker origins that ocd 0.4.0 routes ({worker}.{instance-id}.localhost).
# Static release tarball, SHA-512 from caddy_2.11.7_checksums.txt.
# PIN_ prefix keeps build args from colliding with the tools' own variables.
ARG PIN_CADDY=2.11.7
ARG PIN_CADDY_SHA512_AMD64=a7a433a1b133efc3c8d10eb0b99d52a24b5ef5c322dc77f5282182b1c0402139ab83f3a99f0c52409df77d20123fb0b523edad8a66d8f5e49136197bf61ef0e7
ARG PIN_CADDY_SHA512_ARM64=3db36ba90c7a6e8dda40ee3dd71fa08844c76b5fb08f61b31e5e78d2ed38e71c51dc7baed875e50d1ca1279196e84302967237386ae87c91ae9f2aaceada682e

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN case "$(dpkg --print-architecture)" in \
      amd64) caddy_arch=amd64; caddy_sha="${PIN_CADDY_SHA512_AMD64}" ;; \
      arm64) caddy_arch=arm64; caddy_sha="${PIN_CADDY_SHA512_ARM64}" ;; \
      *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac \
 && curl -fsSL --retry 5 --retry-all-errors -o /tmp/caddy.tar.gz \
      "https://github.com/caddyserver/caddy/releases/download/v${PIN_CADDY}/caddy_${PIN_CADDY}_linux_${caddy_arch}.tar.gz" \
 && echo "${caddy_sha}  /tmp/caddy.tar.gz" | sha512sum -c - \
 && install -d -m 0755 /usr/local/share/doc/caddy \
 && tar -xzf /tmp/caddy.tar.gz -C /usr/local/bin --no-same-owner caddy \
 && tar -xzf /tmp/caddy.tar.gz -C /usr/local/share/doc/caddy --no-same-owner LICENSE \
 && rm -f /tmp/caddy.tar.gz \
 && chmod 0755 /usr/local/bin/caddy \
 && caddy version

# /usr/local/bin exists in the base image; /usr/local/lib/oc-railway is new, so
# it is copied with 0755 (a 0644 mode would make the new directory unreadable).
COPY --chmod=0755 rootfs/usr/local/bin/ /usr/local/bin/
COPY --chmod=0755 rootfs/usr/local/lib/oc-railway/ /usr/local/lib/oc-railway/

# Fail the build early if the image layout this template relies on changes:
# script syntax, the pinned ocd version, the unprivileged user, setpriv, and a
# Caddyfile rendered with sample values that Caddy itself accepts.
RUN for f in /usr/local/bin/oc-railway-entrypoint /usr/local/bin/oc /usr/local/bin/oc-info \
             /usr/local/lib/oc-railway/*; do bash -n "$f"; done \
 && /opt/open-compute/ocd --version \
 && /opt/open-compute/ocd --version | grep -qF '0.4.0' \
 && [ "$(id -u open-compute)" = 65532 ] && [ "$(id -g open-compute)" = 65532 ] \
 && command -v setpriv \
 && PORT=8080 OC_INSTANCE_ID=0190f0f0f0f07000800000000000abcd OC_PATH_ROUTES=true \
    OC_WORKERS_DOMAIN=workers.example.com OC_HOST_ROUTES='app.example.com=hello,api.example.com=api' \
    /usr/local/lib/oc-railway/render-caddyfile > /tmp/Caddyfile.check \
 && caddy validate --config /tmp/Caddyfile.check --adapter caddyfile \
 && rm -f /tmp/Caddyfile.check

# Only the Caddy port is used by Railway. ocd listens on 127.0.0.1:8787 inside
# the container. Persistence (/var/lib/open-compute) is declared in
# template.json, never in this Dockerfile.
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/oc-railway-entrypoint"]
CMD []
