"""Exercise the local release protocol without signing, credentials, or network."""
import importlib.util
import contextlib
import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("release", Path(__file__).parents[1] / "release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_build_number_exceeds_local_remote_and_preserved(self):
        self.assertEqual(release.next_build("2", [{"attributes": {"version": "7"}}], ["9"]), "10")
        self.assertEqual(release.next_build("2", [], []), "3")

    def test_noninteger_history_fails_closed(self):
        with self.assertRaises(RuntimeError):
            release.next_build("2", [{"attributes": {"version": "1.2"}}], [])

    def test_pagination_reads_all_builds(self):
        pages = iter([{"data": [1], "links": {"next": release.API + "/v1/builds?cursor=2"}},
                      {"data": [2], "links": {"next": None}}])
        paths = []
        def request(path):
            paths.append(path)
            return next(pages)
        self.assertEqual(release.all_data("/v1/builds", request), [1, 2])
        self.assertEqual(paths, ["/v1/builds", "/v1/builds?cursor=2"])

    def test_pagination_refuses_other_hosts_and_loops(self):
        for next_url in ("https://evil.example/v1/builds", release.API + "/v1/builds"):
            with self.subTest(url=next_url), self.assertRaises(RuntimeError):
                release.all_data("/v1/builds", lambda _: {"data": [], "links": {"next": next_url}})

    def make_ipa(self, folder, build="3", executable=b"production executable"):
        ipa = Path(folder) / "Shotr.ipa"
        info = {"CFBundleIdentifier": release.BUNDLE, "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": build, "CFBundleExecutable": "Shotr",
                "MinimumOSVersion": "26.0", "DTPlatformName": "iphoneos",
                "ITSAppUsesNonExemptEncryption": False, "UIBackgroundModes": ["processing"],
                "BGTaskSchedulerPermittedIdentifiers": ["com.calum.shots.scan.current"]}
        with zipfile.ZipFile(ipa, "w") as archive:
            archive.writestr("Payload/Shotr.app/Info.plist", plistlib.dumps(info))
            archive.writestr("Payload/Shotr.app/Shotr", executable)
        return ipa

    def test_ipa_audit_accepts_only_expected_production_artifact(self):
        with tempfile.TemporaryDirectory() as folder:
            ipa = self.make_ipa(folder)
            self.assertEqual(len(release.audit_ipa(ipa, "1.0", "3")), 64)
            with self.assertRaises(RuntimeError):
                release.audit_ipa(ipa, "1.0", "2")
            ipa = self.make_ipa(folder, executable=b"CaptureSamples")
            with self.assertRaises(RuntimeError):
                release.audit_ipa(ipa, "1.0", "3")

    def fake_status_api(self, internal="IN_BETA_TESTING", assigned=True, tester=True, processing="VALID"):
        def request(path):
            if path.startswith("/v1/builds?"):
                return {"data": [{"id": "build3", "attributes": {"version": "3", "processingState": processing}}]}
            if path.endswith("/buildBetaDetail"):
                return {"data": {"attributes": {"internalBuildState": internal, "autoNotifyEnabled": True}}}
            if path == f"/v1/betaGroups/{release.GROUP_ID}":
                return {"data": {"attributes": {"name": "Calum", "isInternalGroup": True}}}
            if "/betaTesters?" in path:
                return {"data": [{"id": release.TESTER_ID}] if tester else []}
            if "/builds?" in path:
                return {"data": [{"id": "build3"}] if assigned else []}
            self.fail("Unexpected request " + path)
        return request

    def test_readiness_requires_processed_internal_build_group_and_tester(self):
        self.assertTrue(release.status("3", self.fake_status_api())["ready"])
        for arguments in ({"assigned": False}, {"tester": False}, {"internal": "READY_FOR_BETA_TESTING"},
                          {"processing": "PROCESSING"}):
            with self.subTest(arguments=arguments):
                self.assertFalse(release.status("3", self.fake_status_api(**arguments))["ready"])
        self.assertEqual(release.status("4", self.fake_status_api())["processing"], "NOT_VISIBLE")

    def test_upload_key_is_private_and_cleaned_after_success_and_failure(self):
        environment = {release.PREFIX + "KEY_ID": "KEY123", release.PREFIX + "ISSUER_ID": "issuer",
                       release.PREFIX + "P8_CONTENT": "-----BEGIN PRIVATE KEY-----\nfixture\n"}
        for fails in (False, True):
            with self.subTest(fails=fails), tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, environment):
                observed = []
                def uploader(args, **kwargs):
                    directory = Path(kwargs["env"]["API_PRIVATE_KEYS_DIR"])
                    key = directory / "AuthKey_KEY123.p8"
                    observed.append(directory)
                    self.assertEqual(key.stat().st_mode & 0o777, 0o600)
                    self.assertEqual(key.read_bytes(), environment[release.PREFIX + "P8_CONTENT"].encode())
                    self.assertNotIn("fixture", " ".join(args))
                    self.assertNotIn(release.PREFIX + "P8_CONTENT", kwargs["env"])
                    if fails:
                        raise subprocess.CalledProcessError(1, args)
                with patch.object(release.subprocess, "run", side_effect=uploader):
                    if fails:
                        with self.assertRaisesRegex(RuntimeError, "Do not retry blindly"):
                            release.upload(Path(folder) / "Shotr.ipa", folder)
                    else:
                        release.upload(Path(folder) / "Shotr.ipa", folder)
                self.assertEqual(len(observed), 1)
                self.assertFalse(observed[0].exists())

    def test_help_is_executable_without_credentials(self):
        result = subprocess.run(["python3", str(Path(release.__file__)), "--help"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn("--verify", result.stdout)
        self.assertIn("--status", result.stdout)

    def test_verify_dispatch_never_requests_credentials_or_uploads(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(release, "ROOT", Path(folder)), \
                patch.object(release.sys, "argv", ["release.py", "--verify"]), \
                patch.object(release, "verify") as verify, \
                patch.object(release, "credentials") as credentials, \
                patch.object(release, "upload") as upload, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(release.main(), 0)
            verify.assert_called_once()
            credentials.assert_not_called()
            upload.assert_not_called()
            self.assertTrue(verify.call_args.args[0].is_dir())

    def test_dirty_release_stops_before_validation_or_upload(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(release, "ROOT", Path(folder)), \
                patch.object(release.sys, "argv", ["release.py"]), \
                patch.object(release, "credentials"), \
                patch.object(release, "run", return_value=" M Shotr/LibraryStore.swift"), \
                patch.object(release, "verify") as verify, \
                patch.object(release, "upload") as upload:
            with self.assertRaisesRegex(RuntimeError, "Commit all changes"):
                release.main()
            verify.assert_not_called()
            upload.assert_not_called()

    def test_build_children_do_not_receive_secret_vault(self):
        with patch.dict(os.environ, {"UNRELATED_VAULT_SECRET": "private", release.PREFIX + "P8_CONTENT": "private"}), \
                patch.object(release.subprocess, "run", return_value=type("Result", (), {"stdout": "ok"})()) as child:
            self.assertEqual(release.run(["swift", "test"], capture=True), "ok")
            env = child.call_args.kwargs["env"]
            self.assertNotIn("UNRELATED_VAULT_SECRET", env)
            self.assertNotIn(release.PREFIX + "P8_CONTENT", env)
            self.assertIn("PATH", env)

    def test_preupload_check_requires_strictly_newer_number(self):
        release.ensure_newer("3", [{"attributes": {"version": "2"}}])
        for number in ("3", "4"):
            with self.assertRaises(RuntimeError):
                release.ensure_newer("3", [{"attributes": {"version": number}}])

    def orchestration(self, folder, failure=None):
        """Execute main with fake external tools; exported IPA is real serialized output."""
        root = Path(folder)
        (root / "release").mkdir(exist_ok=True)
        commands = []
        status_calls = 0
        builds_calls = 0
        def command(args, capture=False, **kwargs):
            nonlocal status_calls
            args = [str(item) for item in args]
            commands.append(args)
            if args[:3] == ["git", "status", "--porcelain"]:
                status_calls += 1
                if failure == "source_during_validation" and status_calls == 2:
                    return " M Shotr/LibraryStore.swift"
                if failure == "source_during_signing" and status_calls == 3:
                    return " M Shotr/LibraryStore.swift"
                return ""
            if args[:3] == ["git", "rev-parse", "HEAD"]:
                return "abc123"
            if "-exportArchive" in args:
                export = Path(args[args.index("-exportPath") + 1])
                export.mkdir()
                self.make_ipa(export)
            return ""
        def remote_builds():
            nonlocal builds_calls
            builds_calls += 1
            newer = (failure == "newer_during_validation" and builds_calls == 2) or \
                    (failure == "newer_during_signing" and builds_calls == 3)
            return [{"attributes": {"version": "4"}}] if newer else []
        error = RuntimeError(failure) if failure in ("upload_timeout", "processing_timeout") else None
        with contextlib.ExitStack() as stack:
            stack.enter_context(patch.object(release, "ROOT", root))
            stack.enter_context(patch.object(release.sys, "argv", ["release.py"]))
            stack.enter_context(patch.object(release, "credentials"))
            stack.enter_context(patch.object(release, "run", side_effect=command))
            stack.enter_context(patch.object(release, "settings", return_value=("1.0", "2")))
            stack.enter_context(patch.object(release, "all_data", return_value=[{"id": release.APP_ID}]))
            stack.enter_context(patch.object(release, "builds", side_effect=remote_builds))
            verify = stack.enter_context(patch.object(release, "verify", side_effect=RuntimeError("validation failed") if failure == "validation" else None))
            upload = stack.enter_context(patch.object(release, "upload", side_effect=error if failure == "upload_timeout" else None))
            ready = {"ready": True, "processing": "VALID"}
            stack.enter_context(patch.object(release, "wait_ready", side_effect=error if failure == "processing_timeout" else None, return_value=ready))
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            if failure:
                with self.assertRaises(RuntimeError):
                    release.main()
            else:
                self.assertEqual(release.main(), 0)
            return commands, verify.call_count, upload.call_count

    def test_complete_orchestration_writes_ready_receipt(self):
        with tempfile.TemporaryDirectory() as folder:
            commands, verified, uploaded = self.orchestration(folder)
            self.assertEqual((verified, uploaded), (1, 1))
            self.assertTrue(any("archive" in command for command in commands))
            report = next((Path(folder) / "release").glob("*/release.json"))
            receipt = json.loads(report.read_text())
            self.assertTrue(receipt["uploadResolved"])
            self.assertEqual(receipt["gitRevision"], "abc123")
            self.assertEqual(receipt["build"], "3")
            self.assertTrue(receipt["testflight"]["ready"])

    def test_validation_source_changes_and_newer_remote_build_prevent_upload(self):
        for failure in ("validation", "source_during_validation", "source_during_signing",
                        "newer_during_validation", "newer_during_signing"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as folder:
                _, _, uploaded = self.orchestration(folder, failure)
                self.assertEqual(uploaded, 0)

    def test_uncertain_upload_or_processing_blocks_next_release_until_readback(self):
        for failure in ("upload_timeout", "processing_timeout"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as folder:
                _, _, uploaded = self.orchestration(folder, failure)
                self.assertEqual(uploaded, 1)
                with patch.object(release, "ROOT", Path(folder)):
                    self.assertEqual(release.pending_uploads(), ["3"])
                # Second invocation must not upload N+1 automatically.
                _, verified, uploaded = self.orchestration(folder, "unresolved")
                self.assertEqual((verified, uploaded), (0, 0))
                with patch.object(release, "ROOT", Path(folder)):
                    release.record_status("3", {"ready": False, "processing": "NOT_VISIBLE"})
                    self.assertEqual(release.pending_uploads(), ["3"])
                    release.record_status("3", {"ready": True, "processing": "VALID"})
                    self.assertEqual(release.pending_uploads(), [])


if __name__ == "__main__":
    unittest.main()
