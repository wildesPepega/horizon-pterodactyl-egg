#!/bin/bash
# Horizon - Pterodactyl install script (runs in the installer container, server folder = /mnt/server).
# Downloads the server build of the GitHub release named by HORIZON_VERSION, verifies its SHA-256
# and writes horizon-start.sh. The world, server.toml and resources/ are kept on reinstall.
# Set HORIZON_INSTALL_DIR to install somewhere else (e.g. for a local dry run).
set -eu
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
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "[Horizon] Looking up release '$TAG' on GitHub..."
JSON=$(curl -fsSL -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG") || die "release '$TAG' not found"
URL=$(printf '%s' "$JSON" | jq -r --arg a "$ASSET" '.assets[] | select(.name==$a) | .browser_download_url')
DIGEST=$(printf '%s' "$JSON" | jq -r --arg a "$ASSET" '.assets[] | select(.name==$a) | .digest // empty' | sed 's/^sha256://')
[ -n "$URL" ] && [ "$URL" != null ] || die "release '$TAG' has no $ASSET"

echo "[Horizon] Downloading $ASSET..."
curl -fL --progress-bar -o "$TMP/$ASSET" "$URL"
if [ -n "$DIGEST" ]; then
  GOT=$(sha256sum "$TMP/$ASSET" | cut -d' ' -f1)
  [ "$GOT" = "$DIGEST" ] || die "SHA-256 mismatch (got $GOT, expected $DIGEST)"
  echo "[Horizon] SHA-256 OK."
else
  echo "[Horizon] Warning: the release publishes no SHA-256, skipping verification."
fi

mkdir -p "$TMP/x"
tar -xzf "$TMP/$ASSET" -C "$TMP/x" --strip-components=1
[ -x "$TMP/x/horizon-server" ] || die "$ASSET contains no horizon-server"

# Replace only the program, keep the server's own data.
rm -rf "$DIR/horizon"
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
