"""Play an owned child, cancelling when the request changes or disappears."""
import pathlib
import subprocess
import sys
import time

request, token, sound, volume = sys.argv[1:]
request = pathlib.Path(request)

def current():
    try:
        return request.read_text() == token
    except FileNotFoundError:
        return False

if current():
    child = subprocess.Popen(['/usr/bin/afplay', '-v', volume, sound])
    try:
        deadline = time.monotonic() + 10
        while child.poll() is None and current() and time.monotonic() < deadline:
            time.sleep(0.025)
        if child.poll() is not None and child.returncode != 0:
            raise SystemExit(child.returncode)
    finally:
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=1)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
