"""Resolve and play automatic notifications outside Tern's UI thread."""
import json
import math
import pathlib
import subprocess
import sys

BUILTINS = {
    "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
    "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
}
EXTENSIONS = {"wav", "aiff", "mp3", "m4a", "caf"}


def load_settings(data):
    try:
        stored = json.loads((data / "kv.json").read_text())
    except FileNotFoundError:
        stored = {}
    if not isinstance(stored, dict):
        raise ValueError("Bell settings store must be an object")
    cfg = stored.get("settings")
    if isinstance(cfg, list):
        cfg = {}
    elif not isinstance(cfg, dict):
        cfg = {key: stored.get(key) for key in ("enabled", "sound", "volume")}
    volume = cfg.get("volume", 50)
    if type(volume) not in (int, float) or not math.isfinite(volume):
        volume = 50
    return {
        "enabled": cfg.get("enabled") is not False,
        "volume": max(0, min(100, volume)),
        "sound": cfg.get("sound") if isinstance(cfg.get("sound"), str) and cfg["sound"] else "Glass",
        "failureSound": cfg.get("failureSound") if isinstance(cfg.get("failureSound"), str) and cfg["failureSound"] else "Basso",
    }


def sound_path(data, name):
    path = pathlib.Path("/System/Library/Sounds") / (name + ".aiff") if name in BUILTINS else None
    custom = data / "sounds" / "custom"
    if custom.exists():
        for file in sorted(custom.iterdir()):
            if file.stem == name and file.suffix[1:].lower() in EXTENSIONS:
                path = file
    if path is None or not path.exists():
        raise ValueError("Sound unavailable: " + name + ". Restore the file or choose another sound in Bell: Settings.")
    return path


def notify(data, failed):
    try:
        cfg = load_settings(data)
    except (OSError, ValueError) as error:
        print("Bell settings unavailable: " + str(error), file=sys.stderr)
        return 2
    if not cfg["enabled"] or cfg["volume"] == 0:
        return 0
    name = cfg["failureSound"] if failed else cfg["sound"]
    try:
        sound = sound_path(data, name)
        result = subprocess.run(
            ["/usr/bin/afplay", "-v", str(cfg["volume"] / 100), str(sound)],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            print("Could not play " + name + ": " + (result.stderr.strip() or "exit " + str(result.returncode)), file=sys.stderr)
            return 1
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(notify(pathlib.Path(sys.argv[1]), sys.argv[2] == "failed"))
