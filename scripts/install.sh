#!/bin/bash
# Horizon - Pterodactyl install script (runs in the installer container, server folder = /mnt/server).
#
# 1. Downloads the server build of the GitHub release named by HORIZON_VERSION and verifies its SHA-256.
# 2. Unless HORIZON_PREPARE=off, prepares the Minecraft 26.3 game files into resources/: it downloads the
#    pinned 26.3 client, server, libraries and assets from Mojang (exactly what the official launcher
#    downloads, each file checked against Mojang's SHA-1) and a Java 25 JDK (Eclipse Temurin), runs
#    horizon-prepare, then deletes everything it downloaded for that.
# 3. Writes horizon-start.sh.
#
# The world, server.toml and backups are kept on reinstall.
# Set HORIZON_INSTALL_DIR to install somewhere else (e.g. for a local dry run).
set -eu
set -o pipefail
DIR="${HORIZON_INSTALL_DIR:-/mnt/server}"
REPO=horizon-rust/horizon
ASSET=horizon-server-linux-x86_64.tar.gz
TAG="${HORIZON_VERSION:-nightly}"
[ -n "$TAG" ] || TAG=nightly
PREPARE="${HORIZON_PREPARE:-auto}"
log() { echo "[Horizon] $*"; }
die() { echo "[Horizon] ERROR: $*" >&2; exit 1; }

case "$PREPARE" in auto|always|off) ;; *) die "HORIZON_PREPARE must be auto, always or off (got '$PREPARE')" ;; esac

need_tools() {
  local missing=""
  for t in curl jq sha1sum sha256sum tar mkfifo; do command -v "$t" >/dev/null || missing=1; done
  if [ -n "$missing" ]; then
    apt-get update -qq && apt-get install -y -qq curl jq ca-certificates tar coreutils >/dev/null
  fi
}
need_tools

free_mb() { df -Pk "$1" 2>/dev/null | awk 'NR==2 {print int($4 / 1024)}'; }
require_free() { # require_free MB WHAT
  local free; free=$(free_mb "$DIR")
  if [ -n "$free" ] && [ "$free" -lt "$1" ]; then
    die "only $free MB free in the server folder, about $1 MB needed for $2: raise the server's disk limit and reinstall"
  fi
}

# fetch_tar URL SHA256 DEST: stream a .tar.gz into DEST (top folder stripped) while hashing it, so the
# archive itself never lands on disk. DEST is removed again if the hash doesn't match.
fetch_tar() {
  local url="$1" want="$2" dest="$3" fifo="$TMP/hash.fifo" got pid
  rm -f "$fifo"; mkfifo "$fifo"
  sha256sum < "$fifo" | cut -d' ' -f1 > "$TMP/hash.txt" &
  pid=$!
  mkdir -p "$dest"
  if ! curl -fL --progress-bar "$url" | tee "$fifo" | tar -xzf - -C "$dest" --strip-components=1; then
    wait "$pid" 2>/dev/null || true
    rm -rf "$dest"
    die "download or unpacking of $url failed - out of disk space? Raise the server's disk limit and reinstall"
  fi
  wait "$pid"
  got=$(cat "$TMP/hash.txt")
  if [ -n "$want" ]; then
    [ "$got" = "$want" ] || { rm -rf "$dest"; die "SHA-256 mismatch for $url (got $got, expected $want)"; }
  else
    log "Warning: no SHA-256 published for $url, skipping verification."
  fi
}

mkdir -p "$DIR"
cd "$DIR"
# Stage inside the server folder: the installer container's /tmp is a small tmpfs (about 100 MB by default on Wings).
TMP="$DIR/.horizon-install"
rm -rf "$TMP"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- 1. Horizon itself
log "Looking up release '$TAG' on GitHub..."
JSON=$(curl -fsSL -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG") || die "release '$TAG' not found"
URL=$(printf '%s' "$JSON" | jq -r --arg a "$ASSET" '.assets[] | select(.name==$a) | .browser_download_url')
DIGEST=$(printf '%s' "$JSON" | jq -r --arg a "$ASSET" '.assets[] | select(.name==$a) | .digest // empty' | sed 's/^sha256://')
[ -n "$URL" ] && [ "$URL" != null ] || die "release '$TAG' has no $ASSET"

# Remove the previous program first so a reinstall doesn't need room for two copies.
# (Only ./horizon/ is touched; worlds, server.toml and resources/ stay.)
rm -rf "$DIR/horizon"
require_free 260 "Horizon (about 210 MB unpacked)"
log "Downloading and unpacking $ASSET (about 210 MB unpacked)..."
fetch_tar "$URL" "$DIGEST" "$TMP/x"
[ -x "$TMP/x/horizon-server" ] || die "$ASSET contains no horizon-server"
log "SHA-256 OK."
mv "$TMP/x" "$DIR/horizon"
mkdir -p "$DIR/resources"
printf '%s\n' "$TAG" > "$DIR/horizon/.installed-tag"

# ---------------------------------------------------------------- 2. Game files
prepare_game_files() {
  local H="$DIR/horizon" LOCK="$DIR/horizon/research-lock.json"
  [ -f "$LOCK" ] || die "the release has no research-lock.json, can't tell which Minecraft files it needs"
  [ -x "$H/horizon-prepare" ] || die "the release has no horizon-prepare"
  local MC_VER MANIFEST_SHA1 JAVA_MAJOR
  MC_VER=$(jq -r '.minecraft.version' "$LOCK")
  MANIFEST_SHA1=$(jq -r '.minecraft.manifest_sha1' "$LOCK")
  JAVA_MAJOR=$(jq -r '.minecraft.java_major' "$LOCK")

  require_free 2000 "preparing the game files (Java, Mojang's files and the output, deleted afterwards)"

  # --- Java (Eclipse Temurin JDK) -------------------------------------------------------------
  log "Looking up a Java $JAVA_MAJOR JDK (Eclipse Temurin)..."
  local JDK_JSON JDK_URL JDK_SHA
  JDK_JSON=$(curl -fsSL "https://api.adoptium.net/v3/assets/latest/$JAVA_MAJOR/hotspot?architecture=x64&image_type=jdk&os=linux&vendor=eclipse") \
    || die "couldn't reach api.adoptium.net to download Java $JAVA_MAJOR"
  JDK_URL=$(printf '%s' "$JDK_JSON" | jq -r '.[0].binary.package.link')
  JDK_SHA=$(printf '%s' "$JDK_JSON" | jq -r '.[0].binary.package.checksum // empty')
  [ -n "$JDK_URL" ] && [ "$JDK_URL" != null ] || die "no Java $JAVA_MAJOR JDK found for linux x64"
  log "Downloading Java $JAVA_MAJOR..."
  fetch_tar "$JDK_URL" "$JDK_SHA" "$TMP/jdk"
  [ -x "$TMP/jdk/bin/java" ] || die "the Java download has no bin/java"

  # --- Mojang's files, laid out like the official launcher's .minecraft folder ------------------
  local MC="$TMP/minecraft" VJ
  VJ="$MC/versions/$MC_VER/$MC_VER.json"
  mkdir -p "$MC/versions/$MC_VER" "$MC/assets/indexes"
  log "Downloading the Minecraft $MC_VER version file..."
  curl -fsSL -o "$VJ" "https://piston-meta.mojang.com/v1/packages/$MANIFEST_SHA1/$MC_VER.json" \
    || die "couldn't download the $MC_VER version file from Mojang"
  [ "$(sha1sum "$VJ" | cut -d' ' -f1)" = "$MANIFEST_SHA1" ] || die "the $MC_VER version file doesn't match its SHA-1"

  local IDX_ID IDX
  IDX_ID=$(jq -r '.assetIndex.id' "$VJ")
  IDX="$MC/assets/indexes/$IDX_ID.json"
  curl -fsSL -o "$IDX" "$(jq -r '.assetIndex.url' "$VJ")" || die "couldn't download the asset index"
  [ "$(sha1sum "$IDX" | cut -d' ' -f1)" = "$(jq -r '.assetIndex.sha1' "$VJ")" ] || die "the asset index doesn't match its SHA-1"

  # One list of every file: url, path, sha1. Libraries in Maven layout, assets by hash.
  local LIST="$TMP/files.tsv"
  {
    jq -r --arg mc "$MC" --arg v "$MC_VER" '
      "\(.downloads.client.url)\t\($mc)/versions/\($v)/\($v).jar\t\(.downloads.client.sha1)",
      "\(.downloads.server.url)\t\($mc)/server.jar\t\(.downloads.server.sha1)",
      (.libraries[] | (.downloads.artifact // empty), (.downloads.classifiers // {} | .[])
        | select(.path and .url and .sha1)
        | "\(.url)\t\($mc)/libraries/\(.path)\t\(.sha1)")' "$VJ"
    jq -r --arg mc "$MC" '.objects[] | .hash
      | "https://resources.download.minecraft.net/\(.[0:2])/\(.)\t\($mc)/assets/objects/\(.[0:2])/\(.)\t\(.)"' "$IDX"
  } | sort -u -t "$(printf '\t')" -k2,2 > "$LIST"

  local N; N=$(wc -l < "$LIST")
  log "Downloading $N files from Mojang (client, server, libraries, assets: about 700 MB)..."
  awk -F'\t' '{ printf "url = \"%s\"\noutput = \"%s\"\n", $1, $2 }' "$LIST" > "$TMP/curl.cfg"
  curl -fsS --retry 3 --create-dirs --parallel --parallel-max 16 -K "$TMP/curl.cfg" \
    || die "downloading Mojang's files failed - out of disk space or no connection?"
  log "Checking $N files against Mojang's SHA-1..."
  awk -F'\t' '{ printf "%s  %s\n", $3, $2 }' "$LIST" | sha1sum -c --quiet - \
    || die "some of Mojang's files don't match their SHA-1"

  # --- horizon-prepare ----------------------------------------------------------------------
  local OUT="$TMP/prepared"
  mkdir -p "$OUT"
  log "Preparing the game files with horizon-prepare (usually under a minute; needs about 3 GB of RAM)..."
  HOME="$TMP/home" JAVA_HOME="$TMP/jdk" PATH="$TMP/jdk/bin:$PATH" HORIZON_NO_UPDATE_CHECK=1 \
    "$H/horizon-prepare" --prepare \
      --minecraft-dir "$MC" \
      --server-jar "$MC/server.jar" \
      --java-home "$TMP/jdk" \
      --output "$OUT" \
    || die "horizon-prepare failed (see above). Too little RAM? It needs about 3 GB."

  # The prepared folder is the one holding registries.json (horizon-client/26.3 or the output itself).
  local SRC
  SRC=$(find "$OUT" -name registries.json -printf '%h\n' 2>/dev/null | head -n1)
  [ -n "$SRC" ] || die "horizon-prepare finished, but no prepared folder (with registries.json) was found in its output"
  log "Moving the prepared files into resources/..."
  rm -rf "$DIR/resources"
  mv "$SRC" "$DIR/resources"
  # Import caches horizon-prepare may leave next to the program; the server only reads resources/.
  rm -rf "$H/.local"
  rm -rf "$TMP/minecraft" "$TMP/jdk" "$OUT" "$TMP/home"
  log "Game files prepared."
}

resources_ready() {
  [ -f "$DIR/resources/registries.json" ] && [ -f "$DIR/resources/commands.json" ]
}

case "$PREPARE" in
  off)
    log "HORIZON_PREPARE=off: not preparing the game files. Upload them to resources/ yourself."
    ;;
  auto)
    if resources_ready; then
      log "resources/ already holds prepared game files: keeping them (set 'Prepare game files' to always to redo it)."
    else
      prepare_game_files
    fi
    ;;
  always)
    prepare_game_files
    ;;
esac

# ---------------------------------------------------------------- 3. Start script
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
  echo "[Horizon] Set 'Prepare game files' to auto and reinstall to prepare them automatically,"
  echo "[Horizon] or prepare them yourself with horizon-prepare and upload them to resources/"
  echo "[Horizon] (see https://playhorizon.dev/docs/hosting)."
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

log "Installed: $TAG"
if resources_ready; then
  log "Next: set the EULA variable to true and start the server."
else
  log "Next: upload the prepared $(jq -r '.minecraft.version' "$DIR/horizon/research-lock.json" 2>/dev/null || echo 26.3) game files to resources/,"
  log "set the EULA variable to true and start the server."
fi
