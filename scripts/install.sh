#!/bin/bash
# Horizon - Pterodactyl install script (runs in the installer container, server folder = /mnt/server).
# Downloads the server build of the GitHub release named by HORIZON_VERSION, verifies its SHA-256
# and writes horizon-start.sh. The world, server.toml and resources/ are kept on reinstall.
# Set HORIZON_INSTALL_DIR to install somewhere else (e.g. for a local dry run).
set -eu
set -o pipefail
DIR="${HORIZON_INSTALL_DIR:-/mnt/server}"
REPO=horizon-rust/horizon
ASSET=horizon-server-linux-x86_64.tar.gz
TAG="${HORIZON_VERSION:-nightly}"
[ -n "$TAG" ] || TAG=nightly
die() { echo "[Horizon] ERROR: $*" >&2; exit 1; }

if ! command -v curl >/dev/null || ! command -v jq >/dev/null; then
  apt-get update -qq && apt-get install -y -qq curl jq ca-certificates tar coreutils >/dev/null
fi

mkdir -p "$DIR"
cd "$DIR"
# Stage inside the server folder: the installer container's /tmp is a small tmpfs
# (about 100 MB by default on Wings), too small for the ~200 MB unpacked release.
TMP="$DIR/.horizon-install"
rm -rf "$TMP"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

echo "[Horizon] Looking up release '$TAG' on GitHub..."
JSON=$(curl -fsSL -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG") || die "release '$TAG' not found"
URL=$(printf '%s' "$JSON" | jq -r --arg a "$ASSET" '.assets[] | select(.name==$a) | .browser_download_url')
DIGEST=$(printf '%s' "$JSON" | jq -r --arg a "$ASSET" '.assets[] | select(.name==$a) | .digest // empty' | sed 's/^sha256://')
[ -n "$URL" ] && [ "$URL" != null ] || die "release '$TAG' has no $ASSET"

# Stream the download straight into tar (the archive is never stored), hashing it on the way.
# Peak disk use is the unpacked size (~210 MB) instead of archive + unpacked.
# Remove the previous program first so a reinstall doesn't need room for two copies.
# (Only ./horizon/ is touched; worlds, server.toml and resources/ stay.)
rm -rf "$DIR/horizon"

NEED_KB=$((260 * 1024))
FREE_KB=$(df -Pk "$DIR" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "$FREE_KB" ] && [ "$FREE_KB" -lt "$NEED_KB" ]; then
  die "only $((FREE_KB / 1024)) MB free in the server folder, about 260 MB needed: raise the server's disk limit (1 GB or more) and reinstall"
fi

mkdir -p "$TMP/x"
mkfifo "$TMP/hash.fifo"
sha256sum < "$TMP/hash.fifo" | cut -d' ' -f1 > "$TMP/hash.txt" &
HASH_PID=$!
echo "[Horizon] Downloading and unpacking $ASSET (about 210 MB unpacked)..."
if ! curl -fL --progress-bar "$URL" | tee "$TMP/hash.fifo" | tar -xzf - -C "$TMP/x" --strip-components=1; then
  wait "$HASH_PID" 2>/dev/null || true
  die "download or unpacking failed - out of disk space? Raise the server's disk limit (1 GB or more) and reinstall"
fi
wait "$HASH_PID"
GOT=$(cat "$TMP/hash.txt")
if [ -n "$DIGEST" ]; then
  [ "$GOT" = "$DIGEST" ] || die "SHA-256 mismatch (got $GOT, expected $DIGEST): not installed"
  echo "[Horizon] SHA-256 OK."
else
  echo "[Horizon] Warning: the release publishes no SHA-256, skipping verification."
fi
[ -x "$TMP/x/horizon-server" ] || die "$ASSET contains no horizon-server"

mv "$TMP/x" "$DIR/horizon"
mkdir -p "$DIR/resources"
printf '%s\n' "$TAG" > "$DIR/horizon/.installed-tag"

cat > "$DIR/horizon-start.sh" <<'START'
#!/bin/sh
# Starts Horizon inside the Pterodactyl container. Program: ./horizon/, game files: ./resources/.
# The first start creates server.toml with "horizon-server init" from the panel variables;
# after that the port follows the panel allocation (SERVER_PORT) on every start.
cd "$(dirname "$0")" || exit 1
PORT="${SERVER_PORT:-25565}"
BIN=./horizon/horizon-server

if [ ! -x "$BIN" ]; then
  echo "[Horizon] ./horizon/horizon-server is missing - reinstall the server from the panel."
  exit 1
fi

if [ -z "$(ls -A resources 2>/dev/null)" ] && [ -z "${HORIZON_RESOURCES:-}" ]; then
  echo "[Horizon] The resources/ folder is empty."
  echo "[Horizon] Prepare the Minecraft 26.3 game files locally with 'horizon-prepare'"
  echo "[Horizon] and upload them to resources/ via SFTP (see https://playhorizon.dev/docs/hosting)."
  exit 1
fi

if [ ! -f server.toml ]; then
  if [ "${HORIZON_EULA:-false}" != "true" ]; then
    echo "[Horizon] The Minecraft EULA (https://aka.ms/MinecraftEULA) has not been accepted."
    echo "[Horizon] Set the 'Accept the Minecraft EULA' variable to true on the Startup tab."
    exit 1
  fi
  set -- init --yes --eula --port "$PORT"
  [ -n "${HORIZON_WORLD:-}" ] && set -- "$@" --world "$HORIZON_WORLD"
  [ -n "${HORIZON_SEED:-}" ]  && set -- "$@" --seed "$HORIZON_SEED"
  if [ "${HORIZON_WHITELIST:-true}" = "true" ]; then set -- "$@" --whitelist; else set -- "$@" --no-whitelist; fi
  [ -n "${HORIZON_OP:-}" ] && set -- "$@" --op "$HORIZON_OP"
  [ "${HORIZON_ONLINE:-true}" = "false" ] && set -- "$@" --offline
  # HORIZON_PLAYERS (comma-separated) is read by init straight from the environment.
  echo "[Horizon] First start: creating server.toml..."
  "$BIN" "$@" || exit 1
fi

# Always follow the panel allocation (only the [server] line starts with "port =").
sed -i "s/^port = .*/port = ${PORT}/" server.toml

exec "$BIN" run
START
chmod +x "$DIR/horizon-start.sh"

echo "[Horizon] Installed: $TAG"
echo "[Horizon] Next: upload the prepared 26.3 game files to resources/,"
echo "[Horizon] set the EULA variable to true and start the server."
