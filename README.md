# Horizon Pterodactyl Egg

A [Pterodactyl](https://pterodactyl.io) egg for [Horizon](https://playhorizon.dev): a Minecraft Java Edition 26.3 server written in Rust. Horizon runs as one native program, `horizon-server`, and needs no Java at runtime.

Based on the official hosting guide at <https://playhorizon.dev/docs/hosting> and the upstream repository [horizon-rust/horizon](https://github.com/horizon-rust/horizon).

## Install

1. Download [`egg-horizon.json`](egg-horizon.json).
2. In the panel, go to **Admin → Nests → Import Egg** and import the file.
3. Create a server with the egg. Install it on an **x86-64 Linux** node. Horizon publishes its server build only for this platform.

**Resources:** Give the server at least **4 GB of disk** and **4 GB of RAM**. While the install prepares the game files, it needs about 2 GB of free disk and about 3 GB of RAM. Afterwards it deletes the downloads, and Horizon plus the game files take a few hundred MB.

## Game files

Horizon reads Minecraft 26.3's data, prepared with `horizon-prepare`. The egg does this for you during the install (**Prepare game files** = `auto`, the default):

1. It downloads a Java 25 JDK ([Eclipse Temurin](https://adoptium.net)).
2. It downloads the 26.3 client, server, libraries and assets from Mojang's official servers, the same files the official launcher downloads. Every file is checked against the SHA-1 that Mojang publishes, and the version file is pinned by Horizon's `research-lock.json`.
3. It runs `horizon-prepare --prepare` and moves the result into `resources/`.
4. It deletes Java and the downloaded Mojang files again.

On a reinstall with `auto`, prepared game files that are already in `resources/` are kept. Set the variable to `always` to prepare them again, for example after a Horizon update that asks for it. Set it to `off` to prepare the files yourself as the [hosting guide](https://playhorizon.dev/docs/hosting) describes, then upload them to `resources/`.

You need your own Minecraft Java Edition account to play, and by running the server you accept the [Minecraft EULA](https://aka.ms/MinecraftEULA).

## Before the first start

1. On the **Startup** tab, set **Accept the Minecraft EULA** to `true`.
2. Start the server.

If `resources/` is empty or the EULA hasn't been accepted, the start stops with a message that says what to do.

## Variables

| Variable | Env | Default | When it's read |
|---|---|---|---|
| Accept the Minecraft EULA | `HORIZON_EULA` | `false` | first start |
| Horizon release | `HORIZON_VERSION` | `nightly` | install / reinstall |
| Prepare game files | `HORIZON_PREPARE` | `auto` | install / reinstall |
| World name | `HORIZON_WORLD` | `world` | first start |
| World seed | `HORIZON_SEED` | *(random)* | first start |
| Whitelist | `HORIZON_WHITELIST` | `true` | first start |
| Whitelisted players | `HORIZON_PLAYERS` | *(empty)* | first start |
| Operator | `HORIZON_OP` | *(empty)* | first start |
| Online mode | `HORIZON_ONLINE` | `true` | first start |
| Disable update check | `HORIZON_NO_UPDATE_CHECK` | *(empty)* | every start |

The first start runs `horizon-server init`, which writes `server.toml` from these variables. After that, change settings in `server.toml` (changes apply after a restart) or with console commands such as `whitelist add NAME` and `op NAME`. The game port always follows the panel's allocation and is set on every start.

## How it works

- **Install:** The script downloads `horizon-server-linux-x86_64.tar.gz` from the chosen GitHub release and checks it against the SHA-256 that GitHub publishes. It unpacks the program into `horizon/`, prepares the game files into `resources/` (see [Game files](#game-files)) and writes `horizon-start.sh`. A reinstall replaces `horizon/`. Worlds, `server.toml` and backups stay, and so does `resources/` unless the game files are prepared again.
- **Start:** `horizon-start.sh` runs `init` on the first start. On every start it sets `port` in `server.toml` to `SERVER_PORT`, then runs `horizon-server run` in the foreground.
- **Ready detection:** The panel marks the server as running when it sees vanilla's `Done (…s)! For help, type "help"` line.
- **Stop:** The panel sends the console command `stop`. It saves the world, then shuts down.

## Troubleshooting

- **`No space left on device` during install** and then **`cannot open ./horizon-start.sh`**: the server's disk limit is too small for the install. Raise it to 4 GB or more and reinstall.
- **`horizon-prepare failed`:** usually too little RAM during install. Give the server 4 GB or more and reinstall.
- **The install log doesn't show any `[Horizon]` lines:** the panel is still running an older install script. Import the current `egg-horizon.json` over the existing egg, then reinstall.

## Updating

To update Horizon, set **Horizon release** to a newer tag, or leave it on `nightly`, and click **Reinstall** in the panel. Your data stays.

## Development

The egg JSON is generated from [`scripts/install.sh`](scripts/install.sh). After you edit the script, rebuild the JSON:

```sh
python3 tools/build-egg.py
```

To dry-run the installer locally:

```sh
HORIZON_INSTALL_DIR=/tmp/horizon-test bash scripts/install.sh
```

## Disclaimer

This is an unofficial community egg. It isn't affiliated with Mojang, Microsoft or the Horizon project. Minecraft is a trademark of Mojang Studios.

## License

[MIT](LICENSE). Horizon itself is MIT-licensed; see its own repository.
