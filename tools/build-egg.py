#!/usr/bin/env python3
"""Builds egg-horizon.json from scripts/install.sh. Run from the repo root: python3 tools/build-egg.py"""
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def var(name, desc, env, default, rules):
    return {"name": name, "description": desc, "env_variable": env, "default_value": default,
            "user_viewable": True, "user_editable": True, "rules": rules, "field_type": "text"}


egg = {
    "_comment": "DO NOT EDIT: FILE GENERATED AUTOMATICALLY BY PTERODACTYL PANEL - PTERODACTYL.IO",
    "meta": {"version": "PTDL_v2",
             "update_url": "https://raw.githubusercontent.com/wildesPepega/horizon-pterodactyl-egg/main/egg-horizon.json"},
    "exported_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    "name": "Horizon",
    "author": "wildesPepega@users.noreply.github.com",
    "description": "Horizon - a Minecraft Java Edition 26.3 server written in Rust (horizon-server): one native "
                   "program, no Java at runtime. The install prepares the game files automatically from "
                   "Mojang's official downloads (https://playhorizon.dev/docs/hosting).",
    "features": [],
    "docker_images": {"Debian": "ghcr.io/ptero-eggs/yolks:debian"},
    "file_denylist": [],
    "startup": "sh ./horizon-start.sh",
    "config": {
        "files": "{}",
        "startup": json.dumps({"done": ")! For help, type "}, indent=4),
        "logs": "{}",
        "stop": "stop",
    },
    "scripts": {"installation": {
        "script": (ROOT / "scripts" / "install.sh").read_text(),
        "container": "ghcr.io/ptero-eggs/installers:debian",
        "entrypoint": "bash",
    }},
    "variables": [
        var("Accept the Minecraft EULA",
            "true accepts the Minecraft EULA (https://aka.ms/MinecraftEULA). The server won't start until it is true.",
            "HORIZON_EULA", "false", "required|string|in:true,false"),
        var("Horizon release",
            "GitHub release tag: nightly or an exact tag such as v1.2.3. Read on install/reinstall only.",
            "HORIZON_VERSION", "nightly", "required|string|max:64"),
        var("Prepare game files",
            "auto prepares the Minecraft game files during install when resources/ has none: it downloads "
            "the pinned client, server, libraries and assets from Mojang plus a Java JDK (Eclipse Temurin), "
            "runs horizon-prepare and deletes the downloads again (needs about 2 GB of free disk and 3 GB of "
            "RAM during install). always redoes it on every reinstall. off: upload them to resources/ yourself.",
            "HORIZON_PREPARE", "auto", "required|string|in:auto,always,off"),
        var("World name", "The world's folder name. First start only.",
            "HORIZON_WORLD", "world", "nullable|string|max:64"),
        var("World seed", "The world seed; empty picks a random one. First start only.",
            "HORIZON_SEED", "", "nullable|string|max:64"),
        var("Whitelist",
            "true turns the whitelist on. First start only (later: whitelist on/off in the console).",
            "HORIZON_WHITELIST", "true", "required|string|in:true,false"),
        var("Whitelisted players", "Player names, comma-separated. First start only.",
            "HORIZON_PLAYERS", "", "nullable|string|max:512"),
        var("Operator", "A player name to make operator. First start only.",
            "HORIZON_OP", "", "nullable|string|max:32"),
        var("Online mode",
            "true checks accounts with Mojang. false lets anyone join under any name - only use it with "
            "the whitelist or on a private network. First start only.",
            "HORIZON_ONLINE", "true", "required|string|in:true,false"),
        var("Disable update check",
            "1 turns off Horizon's update check; empty leaves it on. To update, change the release "
            "variable and reinstall.",
            "HORIZON_NO_UPDATE_CHECK", "", "nullable|string|in:1"),
    ],
}

out = ROOT / "egg-horizon.json"
out.write_text(json.dumps(egg, indent=4, ensure_ascii=False) + "\n")
print(f"wrote {out.relative_to(ROOT)}")
