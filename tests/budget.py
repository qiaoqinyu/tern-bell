"""Native regression: slow settings I/O must not disable Bell's window hook.

Requires a running Tern window. Optional argument: an unfixed source directory.
Uses the real window entry, filesystem, process API and notification player.
Only a uniquely named temporary plugin and its data are created and removed.
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid


def tern(*args):
    result = subprocess.run(["tern", *args], capture_output=True, text=True, timeout=20)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result.stdout


def wait_for(predicate, description, seconds=10):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.025)
    raise RuntimeError("Timed out: " + description)


def main():
    source = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[1]
    plugin_id = "bell-budget-" + uuid.uuid4().hex[:12]
    data = None
    linked = False
    writer = None
    with tempfile.TemporaryDirectory(prefix="bell-budget-regression-") as root:
        root = pathlib.Path(root)
        plugin = root / "plugin"
        plugin.mkdir()
        ready, entered, result = (root / name for name in ("ready.json", "entered", "result.json"))
        (plugin / "plugin.toml").write_text(
            f'schema = 1\nid = "{plugin_id}"\nname = "Bell budget regression"\n'
            'version = "0.0.0"\nwindow = "window.luau"\n'
        )
        for name in ("window", "audio", "catalog"):
            (plugin / ("subject-" + name + ".luau")).write_text(
                "return function(tern, require)\n" + (source / (name + ".luau")).read_text() + "\nend\n"
            )
        for name in ("play.py", "notify.py"):
            if (source / name).exists():
                shutil.copyfile(source / name, plugin / name)
        script = '''local real = tern
local api = setmetatable({}, { __index = real })
local completions = {}
local function save()
    real.fs.write(RESULT, real.json.encode(completions))
end
api.process = { run = function(argv, opts, callback)
    return real.process.run(argv, opts, function(res, cx)
        callback(res, cx)
        table.insert(completions, { status = res.status, stderr = res.stderr })
        save()
    end)
end }
api.timer = function() end
api.command = function() end
api.on = function(name, callback)
    if name ~= "agent_finished" then return end
    real.command({ id = "trigger", title = "Bell budget regression trigger", run = function(cx)
        real.fs.write(ENTERED, "entered")
        callback({ pane = 7, result = "done" }, cx)
    end })
end
local modules = {}
local function resolve(name)
    if not modules[name] then modules[name] = require("./subject-" .. string.sub(name, 3))(api, resolve) end
    return modules[name]
end
require("./subject-window")(api, resolve)
real.fs.write(READY, real.json.encode({ data = real.plugin.data }))
'''
        for key, value in (("RESULT", result), ("ENTERED", entered), ("READY", ready)):
            script = script.replace(key, json.dumps(str(value)))
        (plugin / "window.luau").write_text(script)
        errors = []
        try:
            tern("plugin", "link", str(plugin))
            linked = True
            wait_for(ready.exists, "probe window startup")
            data = pathlib.Path(json.loads(ready.read_text())["data"])
            settings = data / "kv.json"
            os.mkfifo(settings)
            config = json.dumps({"settings": {"enabled": True, "sound": "Glass", "volume": 1}})

            def release_settings():
                try:
                    wait_for(entered.exists, "callback entry")
                    time.sleep(0.15)
                    with settings.open("w") as stream:
                        stream.write(config)
                    settings.unlink()
                    settings.write_text(config)
                except Exception as error:
                    errors.append(str(error))

            writer = threading.Thread(target=release_settings, daemon=True)
            writer.start()
            action = "plugin." + plugin_id + ".trigger"
            tern("ctl", "plugins", "run", action)
            writer.join(3)
            if writer.is_alive() or errors:
                raise RuntimeError("Settings stall fixture failed: " + str(errors))
            try:
                wait_for(result.exists, "notification after 150 ms settings stall", seconds=4)
            except RuntimeError:
                raise RuntimeError("FAIL: blocked settings I/O prevented playback; window hook may have exceeded 50 ms")
            first = json.loads(result.read_text())
            if len(first) != 1 or first[0]["status"] != 0:
                raise RuntimeError("FAIL: first notification did not play: " + str(first))
            tern("ctl", "plugins", "run", action)
            wait_for(lambda: len(json.loads(result.read_text())) == 2, "second notification")
            records = json.loads(result.read_text())
            if any(record["status"] != 0 for record in records):
                raise RuntimeError("FAIL: later notification did not play: " + str(records))
            print("PASS: 150 ms native settings stall does not disable completion notifications")
            print("PASS: subsequent completion plays without reload")
        finally:
            if linked:
                tern("plugin", "unlink", plugin_id)
            if writer is not None and writer.is_alive() and data is not None:
                # Release only our task-created FIFO's blocked writer after a failed probe.
                try:
                    fd = os.open(data / "kv.json", os.O_RDONLY | os.O_NONBLOCK)
                    os.close(fd)
                except OSError:
                    pass
                writer.join(1)
            if data is not None and data.name == plugin_id:
                shutil.rmtree(data)


if __name__ == "__main__":
    main()
