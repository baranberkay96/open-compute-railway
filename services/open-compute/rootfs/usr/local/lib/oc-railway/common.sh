# shellcheck shell=bash
# Shared constants and helpers for the open-compute Railway wrapper.
# Sourced by oc-railway-entrypoint, setup-instance, render-config,
# render-caddyfile, oc and oc-info. Written for this template.

OC_ROOT=/var/lib/open-compute               # system OCD_DIR, the Railway volume
OC_BIN=/opt/open-compute/ocd
OC_UID=65532                                # "open-compute" user in the upstream image
OC_GID=65532
OC_INSTANCE_DIR="$OC_ROOT/instances/default"
OC_CONFIG="$OC_INSTANCE_DIR/compute.toml"
OC_DATA="$OC_INSTANCE_DIR/data"
OC_STATE="$OC_ROOT/.railway"                # this wrapper's own markers
OC_RUN=/tmp/oc-railway                      # Caddyfile and Caddy's scratch dirs
OC_LISTEN=127.0.0.1:8787                    # ocd's shared listener (container-local)
OC_LISTEN_PORT=8787

# Worker names in ocd 0.4.0 (storage/src/worker_repository.rs validate_worker_name).
OC_WORKER_RE='^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'
OC_HOST_RE='^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$'
OC_TOKEN_RE='^[A-Za-z0-9._~+/=-]{24,}$'   # plus a 512-byte cap in the entrypoint

log() { printf '[railway] %s\n' "$*" >&2; }

die() {
  # Exit code 78 (EX_CONFIG) for configuration errors, as in this project's
  # other templates; the message names the variable to fix.
  local code=${2:-78}
  printf '[railway] error: %s\n' "$1" >&2
  exit "$code"
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Run a command as the unprivileged open-compute user (no-op when already it).
run_as_oc() {
  if [ "$(id -u)" = "$OC_UID" ]; then
    "$@"
  else
    setpriv --reuid="$OC_UID" --regid="$OC_GID" --clear-groups --no-new-privs -- "$@"
  fi
}

# ocd CLI for the system scope, without the role tokens in its environment.
ocd_cli() {
  run_as_oc env -u OPEN_COMPUTE_ADMIN_TOKEN -u OPEN_COMPUTE_DEPLOYER_TOKEN \
    -u OPEN_COMPUTE_READ_ONLY_TOKEN HOME=/tmp \
    "$OC_BIN" --no-update-check --system "$@"
}

# TOML basic string: escape backslash and double quote (callers reject control
# characters before values reach this point). Adapted from upstream's
# examples/container/init-volume.sh (Apache-2.0).
toml_string() {
  printf '"'
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
  printf '"'
}

# Write a secret to an owner-only file atomically, without putting it in argv.
write_secret_file() {
  local path=$1 value=$2 dir tmp
  dir=$(dirname "$path")
  if [ -f "$path" ] && [ "$(cat "$path")" = "$value" ]; then
    return 0
  fi
  tmp=$(mktemp "$dir/.secret.XXXXXX")
  chmod 0600 "$tmp"
  printf '%s\n' "$value" > "$tmp"
  mv -f "$tmp" "$path"
}

# Replace a file only when its content changes (keeps mtimes stable).
install_if_changed() {
  local src=$1 dst=$2
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    rm -f "$src"
  else
    mv -f "$src" "$dst"
  fi
}

# Print the instance id (32 lowercase hex) from `ocd instances --json`.
instance_id_from_json() {
  grep -o '"instance_id":"[0-9a-f]\{32\}"' | head -n 1 | sed 's/.*:"\([0-9a-f]*\)"/\1/'
}
