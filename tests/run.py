"""Run lifecycle regressions in Tern's bundled Luau VM, without playing audio.

Requires a running Tern window. Links a uniquely named temporary test plugin,
then unlinks it; Tern reloads plugins as part of those operations. The real
Bell settings and source files are never changed by this runner.
"""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
import uuid


def tern(*args):
    return subprocess.run(["tern", *args], check=True, capture_output=True, text=True, timeout=20)


def main():
    repo = pathlib.Path(__file__).resolve().parents[1]
    plugin_id = "bell-check-" + uuid.uuid4().hex[:12]
    data_dir = None
    linked = False
    with tempfile.TemporaryDirectory(prefix="bell-lifecycle-") as root:
        root = pathlib.Path(root)
        plugin = root / "plugin"
        plugin.mkdir()
        result_path = root / "result.json"
        (plugin / "plugin.toml").write_text(
            f'schema = 1\nid = "{plugin_id}"\nname = "Bell lifecycle tests"\n'
            'version = "0.0.0"\nwindow = "window.luau"\n'
        )
        # Only wrap the real entry to inject the test host; do not rewrite its logic.
        (plugin / "subject.luau").write_text(
            "return function(tern, require)\n" + (repo / "window.luau").read_text() + "\nend\n"
        )
        shutil.copyfile(repo / "tests/lifecycle.luau", plugin / "lifecycle.luau")
        (plugin / "window.luau").write_text(
            'local ok, result = pcall(require("./lifecycle"), require("./subject"))\n'
            f'tern.fs.write({json.dumps(str(result_path))}, '
            'tern.json.encode({ok = ok, result = result, data = tern.plugin.data}))\n'
        )
        try:
            tern("plugin", "link", str(plugin))
            linked = True
            deadline = time.monotonic() + 15
            while not result_path.exists():
                if time.monotonic() >= deadline:
                    raise RuntimeError("Test window VM produced no results. Check Tern's running window and plugin errors.")
                time.sleep(0.05)
            payload = json.loads(result_path.read_text())
            data_dir = pathlib.Path(payload["data"])
            if not payload["ok"]:
                raise RuntimeError("Test setup failed: " + str(payload["result"]))
            results = payload["result"]
            if not isinstance(results, list) or not results:
                raise RuntimeError("No behavioral cases executed")
            for result in results:
                print(("PASS" if result["passed"] else "FAIL") + ": " + result["name"])
                if not result["passed"]:
                    print("  " + result["error"])
            failed = sum(not result["passed"] for result in results)
            print(f"{len(results) - failed}/{len(results)} passed")
            return 1 if failed else 0
        finally:
            if linked:
                tern("plugin", "unlink", plugin_id)
            if data_dir is not None and data_dir.name == plugin_id and data_dir.is_dir():
                # Remove only the empty directory created for this unique test plugin.
                try:
                    data_dir.rmdir()
                except OSError:
                    pass


if __name__ == "__main__":
    sys.exit(main())
