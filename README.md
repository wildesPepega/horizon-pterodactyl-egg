# Horizon Pterodactyl Egg

A [Pterodactyl](https://pterodactyl.io) egg for [Horizon](https://playhorizon.dev): a Minecraft Java Edition 26.3 server written in Rust. Horizon runs as one native program, `horizon-server`, and needs no Java.

Based on the official hosting guide at <https://playhorizon.dev/docs/hosting> and the upstream repository [horizon-rust/horizon](https://github.com/horizon-rust/horizon).

## Install

1. Download [`egg-horizon.json`](egg-horizon.json).
2. In the panel, go to **Admin → Nests → Import Egg** and import the file.
3. Create a server with the egg. Install it on an **x86-64 Linux** node. Horizon publishes its server build only for this platform.

**Disk space:** Give the server at least **1 GB** of disk. The install alone needs about 300 MB: Horizon takes about 200 MB unpacked, plus the download. The game files and the world come on top of that.

## Before the first start

Horizon needs Minecraft 26.3 game files prepared from your own copy of the game. The egg doesn't download anything from Mojang.

1. On your own computer, prepare the files with `horizon-prepare` (this step needs Java 25):
   ```sh
   horizon-prepare --prepare --server-jar /path/to/server.jar
   ```
   See the [hosting guide](https://playhorizon.dev/docs/hosting) for details.
2. Upload the prepared files into the server's `resources/` folder, for example with SFTP.
3. On the **Startup** tab, set **Accept the Minecraft EULA** to `true`.
4. Start the server.

If `resources/` is empty or the EULA hasn't been accepted, the start stops with a message that says what to do.

## Variables

| Variable | Env | Default | When it's read |
|---|---|---|---|
| Accept the Minecraft EULA | `HORIZON_EULA` | `false` | first start |
| Horizon release | `HORIZON_VERSION` | `nightly` | install / reinstall |
| World name | `HORIZON_WORLD` | `world` | first start |
| World seed | `HORIZON_SEED` | *(random)* | first start |
| Whitelist | `HORIZON_WHITELIST` | `true` | first start |
| Whitelisted players | `HORIZON_PLAYERS` | *(empty)* | first start |
| Operator | `HORIZON_OP` | *(empty)* | first start |
| Online mode | `HORIZON_ONLINE` | `true` | first start |
| Disable update check | `HORIZON_NO_UPDATE_CHECK` | *(empty)* | every start |

The first start runs `horizon-server init`, which writes `server.toml` from these variables. After that, change settings in `server.toml` (changes apply after a restart) or with console commands such as `whitelist add NAME` and `op NAME`. The game port always follows the panel's allocation and is set on every start.

## How it works

- **Install:** The script downloads `horizon-server-linux-x86_64.tar.gz` from the chosen GitHub release and checks it against the SHA-256 that GitHub publishes. It unpacks the program into `horizon/`, creates `resources/` and writes `horizon-start.sh`. A reinstall replaces only `horizon/`. Worlds, `server.toml`, `resources/` and backups stay.
- **Start:** `horizon-start.sh` runs `init` on the first start. On every start it sets `port` in `server.toml` to `SERVER_PORT`, then runs `horizon-server run` in the foreground.
- **Ready detection:** The panel marks the server as running when it sees vanilla's `Done (…s)! For help, type "help"` line.
- **Stop:** The panel sends the console command `stop`. It saves the world, then shuts down.

## Troubleshooting

- **`No space left on device` during install** and then **`cannot open ./horizon-start.sh`**: the server's disk limit is too small for the install. Raise it to 1 GB or more and reinstall.

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
