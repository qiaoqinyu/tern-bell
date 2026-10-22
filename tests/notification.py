"""Behavioral checks for automatic notification settings, selection and failures."""
import contextlib
import importlib.util
import io
import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("bell_notify", pathlib.Path(__file__).resolve().parents[1] / "notify.py")
notify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notify)


class NotificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bell-notify-test-")
        self.addCleanup(self.temp.cleanup)
        self.data = pathlib.Path(self.temp.name)
        custom = self.data / "sounds" / "custom"
        custom.mkdir(parents=True)
        self.complete = custom / "complete.wav"
        self.failure = custom / "failure.wav"
        self.complete.touch()
        self.failure.touch()
        self.settings({"enabled": True, "sound": "complete", "failureSound": "failure", "volume": 70})

    def settings(self, value):
        (self.data / "kv.json").write_text(json.dumps({"settings": value}))

    def run_notification(self, failed=False, result=None):
        with patch.object(notify.subprocess, "run", return_value=result or subprocess.CompletedProcess([], 0, "", "")) as player:
            with contextlib.redirect_stderr(io.StringIO()) as error:
                status = notify.notify(self.data, failed)
            return status, player.call_args_list, error.getvalue()

    def test_completion_and_failure_use_independent_selections(self):
        status, calls, _ = self.run_notification()
        self.assertEqual(status, 0)
        self.assertEqual(calls[0].args[0][-1], str(self.complete))
        self.assertEqual(calls[0].args[0][2], "0.7")
        status, calls, _ = self.run_notification(True)
        self.assertEqual(status, 0)
        self.assertEqual(calls[0].args[0][-1], str(self.failure))

    def test_disabled_and_zero_volume_never_start_player(self):
        for cfg in ({"enabled": False, "sound": "missing"}, {"volume": 0, "sound": "missing"}):
            with self.subTest(cfg=cfg):
                self.settings(cfg)
                status, calls, _ = self.run_notification()
                self.assertEqual((status, calls), (0, []))

    def test_invalid_settings_are_retryable_and_do_not_play(self):
        (self.data / "kv.json").write_text("{")
        status, calls, _ = self.run_notification()
        self.assertEqual((status, calls), (2, []))

    def test_missing_sound_is_not_retryable_and_does_not_play(self):
        self.complete.unlink()
        status, calls, _ = self.run_notification()
        self.assertEqual((status, calls), (1, []))

    def test_decode_failure_is_not_retried(self):
        status, calls, _ = self.run_notification(result=subprocess.CompletedProcess([], 1, "", "bad audio"))
        self.assertEqual(status, 1)
        self.assertEqual(len(calls), 1)

    def test_legacy_settings_and_live_changes_are_respected(self):
        (self.data / "kv.json").write_text(json.dumps({"sound": "complete", "volume": 30}))
        status, calls, _ = self.run_notification()
        self.assertEqual(status, 0)
        self.assertEqual(calls[0].args[0][2], "0.3")
        self.settings({"sound": "failure", "volume": 120})
        status, calls, _ = self.run_notification()
        self.assertEqual(status, 0)
        self.assertEqual(calls[0].args[0][-1], str(self.failure))
        self.assertEqual(calls[0].args[0][2], "1.0")

    def test_custom_file_can_override_builtin_without_path_traversal(self):
        custom = self.complete.parent / "Glass.wav"
        custom.touch()
        self.assertEqual(notify.sound_path(self.data, "Glass"), custom)
        with self.assertRaises(ValueError):
            notify.sound_path(self.data, "../../outside")


if __name__ == "__main__":
    unittest.main()
