#!/usr/bin/env python3
"""Portable tests for capability probing, fallback and the full capture script handshake."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("duo_simulator", ROOT / "scripts/duo-simulator.py")
duo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(duo)

MOCK_TOOL = r'''#!/usr/bin/env python3
import base64, json, os, pathlib, sys, time
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
mode = os.environ["MOCK_DUO_MODE"]
if name == "ruby":
    print({"project_path":"apps/tendr/Still.xcodeproj", "scheme":"Still", "duo_screenshot_test":"StillUITests/DuoScreenshotTests", "name":"Tendr"}[args[-1]])
elif name == "xcrun":
    args = args[1:]
    if args[:2] == ["list", "devicetypes"]:
        print(json.dumps({"devicetypes": [] if mode == "missing" else [{"name":"iPhone Duo", "identifier":"mock.duo"}]}))
    elif args[:2] == ["list", "runtimes"]:
        print(json.dumps({"runtimes":[{"platform":"iOS", "isAvailable":True,"version":"27.1","identifier":"mock.ios27"}]}))
    elif args[0] == "create":
        pathlib.Path(os.environ["MOCK_CREATED_DEVICE"]).write_text(args[2])
        print("mock-udid")
    elif args[0] == "help":
        if mode in ("fold", "rejected") and args[-1] == "fold":
            print("fold <device> <state>: folded or unfolded")
        elif mode == "displays" and args[-1] == "io":
            print("screenshot --display=<id>")
        else:
            print("No fold or named display support")
    elif args[0] == "fold" and mode == "rejected":
        sys.exit(1)
    elif args[0] == "io" and args[2] == "enumerate":
        print("Display 0: Inner\nDisplay 1: Outer" if mode == "displays" else "Display 0: Main")
    elif args[0] == "io" and args[2] == "screenshot":
        pathlib.Path(args[-1]).write_bytes(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
elif name == "xcodebuild" and args[0] == "test-without-building":
    folder = pathlib.Path(os.environ["TEST_RUNNER_DUO_CONTROL_DIR"])
    def request(action, value):
        identifier = str(time.time_ns())
        temporary = folder / "test-request.tmp"
        temporary.write_text(json.dumps({"id":identifier,"action":action,"name":value}))
        temporary.replace(folder / "request.json")
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            response = folder / "response.json"
            if response.exists():
                result = json.loads(response.read_text())
                if result["id"] == identifier:
                    assert result["ok"], result
                    return
            time.sleep(0.02)
        sys.exit("Mock UI test timed out")
    poses = ["inner", "outer"] if os.environ["TEST_RUNNER_DUO_CAN_FOLD"] == "1" else ["default"]
    for pose in poses:
        if pose != "default": request("pose", pose)
        for screen in ["home","treatment","progress","journal","settings","log-dose","landscape-home","landscape-progress","landscape-log-dose"]:
            request("capture", screen)
'''


class DuoCapabilitiesTests(unittest.TestCase):
    def test_only_explicit_inner_and_outer_names_are_used(self):
        self.assertEqual(duo.named_displays("Display 0: Main\nDisplay 1: External"), {})
        self.assertEqual(duo.named_displays("Display 0: Inner"), {})
        self.assertEqual(duo.named_displays("Display 2: Inner\nDisplay 4: Outer"), {"inner":"2", "outer":"4"})
        self.assertEqual(duo.named_displays(json.dumps({"displays":[{"id":3,"name":"Inner display"},{"id":7,"name":"Outer display"}]})), {"inner":"3", "outer":"7"})

    def test_no_undocumented_fold_command_is_attempted(self):
        self.assertEqual(duo.fold_candidates("test", {}), [])
        self.assertEqual(duo.fold_candidates("test", {"ui":"appearance light dark"}), [])
        commands = duo.fold_candidates("test", {"ui":"fold <state>: folded unfolded"})
        self.assertEqual(commands, [{"outer":["ui","test","fold","folded"],"inner":["ui","test","fold","unfolded"]}])

    def capture(self, mode, override=None):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            scripts = root / "scripts"
            scripts.mkdir()
            for name in ["capture-duo-screenshots.sh", "duo-simulator.py", "boot-simulator.sh"]:
                shutil.copy2(ROOT / "scripts" / name, scripts / name)
            commands = root / "bin"
            commands.mkdir()
            tool = commands / "mock-tool"
            tool.write_text(MOCK_TOOL)
            tool.chmod(0o755)
            for name in ["ruby", "xcrun", "xcodebuild"]:
                (commands / name).symlink_to(tool)
            env = dict(os.environ, PATH=f"{commands}:{os.environ['PATH']}", MOCK_DUO_MODE=mode,
                       MOCK_CREATED_DEVICE=str(root / "created-device"))
            env.pop("R_SIM_DEVICE_TYPE", None)
            env.pop("R_SIM_RUNTIME", None)
            if override:
                env["R_SIM_DEVICE_TYPE"] = override
            output = root / "output with spaces"
            result = subprocess.run(["bash", str(scripts / "capture-duo-screenshots.sh"), "tendr", str(output)],
                                    text=True, capture_output=True, env=env, timeout=55)
            if mode == "missing" and override is None:
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("No iPhone Duo simulator device type found", result.stderr)
                return
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            plan = json.loads((output / "plan.json").read_text())
            expected_mode = mode if mode in ("fold", "displays") else "default"
            self.assertEqual(plan["mode"], expected_mode)
            poses = ["inner", "outer"] if expected_mode in ("fold", "displays") else ["default"]
            self.assertEqual(len(list(output.glob("*.png"))), len(poses) * 2 * 9)
            for pose in poses:
                for appearance in ["light", "dark"]:
                    self.assertTrue((output / f"{pose}-{appearance}-home.png").is_file())
            self.assertEqual((root / "created-device").read_text(), override or "mock.duo")
            if expected_mode == "default":
                self.assertIn("default only", (output / "capture-notes.txt").read_text())

    def test_fold_capture(self): self.capture("fold")
    def test_named_displays_capture(self): self.capture("displays")
    def test_default_capture(self): self.capture("default")
    def test_rejected_fold_falls_back(self): self.capture("rejected")
    def test_missing_device_fails_clearly(self): self.capture("missing")
    def test_explicit_device_override(self): self.capture("missing", override="custom.duo")


if __name__ == "__main__":
    unittest.main()
