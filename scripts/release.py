#!/usr/bin/env python3
"""Local, fail-closed internal TestFlight release. Never submits to the App Store."""
import argparse
import base64
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
APP_ID = "6818884320"
BUNDLE = "com.calum.shots"
GROUP_ID = "a72d0ddb-1a61-41d5-b660-b99e7cd45391"
TESTER_ID = "bd9581ba-7a5d-42aa-983a-032b7c27e059"
PREFIX = "APP_STORE_CONNECT_API__"
API = "https://api.appstoreconnect.apple.com"


def tool_environment():
    # The wrapper decrypts more than ASC credentials. Tests/build phases must not
    # inherit its vault; only ordinary local toolchain settings cross this boundary.
    allowed = {"PATH", "HOME", "USER", "LOGNAME", "SHELL", "LANG", "LC_ALL", "TMPDIR",
               "DEVELOPER_DIR", "SDKROOT", "MACOSX_DEPLOYMENT_TARGET", "TERM", "CI"}
    return {name: value for name, value in os.environ.items() if name in allowed}


def run(args, capture=False, timeout=None):
    result = subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True,
                            text=True, stdout=subprocess.PIPE if capture else None,
                            timeout=timeout, env=tool_environment())
    return result.stdout.strip() if capture else None


def credentials():
    names = [PREFIX + name for name in ("KEY_ID", "ISSUER_ID", "P8_CONTENT")]
    if all(os.environ.get(name) for name in names):
        return
    wrapper = Path(os.environ.get("SHOTS_SECRETS_WRAPPER",
                                 str(ROOT.parent / "world-wide-webb/scripts/secrets.sh"))).expanduser()
    if not wrapper.is_file():
        raise RuntimeError("Set APP_STORE_CONNECT_API__KEY_ID / ISSUER_ID / P8_CONTENT, or SHOTS_SECRETS_WRAPPER.")
    if os.environ.get("SHOTS_RELEASE_WRAPPED"):
        raise RuntimeError("Secrets wrapper did not provide all three App Store Connect variables.")
    env = os.environ.copy()
    env["SHOTS_RELEASE_WRAPPED"] = "1"
    # Existing wrapper executes its argument as a shell command; quote it once.
    command = shlex.join([sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]])
    result = subprocess.run([str(wrapper), command], cwd=ROOT, env=env)
    raise SystemExit(result.returncode)


def private_key():
    pem = os.environ[PREFIX + "P8_CONTENT"].replace("\\n", "\n").encode()
    return pem if pem.lstrip().startswith(b"-----BEGIN") else base64.b64decode(pem, validate=True)


def token():
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec, utils
    key = serialization.load_pem_private_key(private_key(), password=None)
    now = int(time.time())
    parts = [{"alg": "ES256", "kid": os.environ[PREFIX + "KEY_ID"], "typ": "JWT"},
             {"iss": os.environ[PREFIX + "ISSUER_ID"], "iat": now - 10,
              "exp": now + 600, "aud": "appstoreconnect-v1"}]
    b64 = lambda value: base64.urlsafe_b64encode(value).rstrip(b"=")
    unsigned = b".".join(b64(json.dumps(part).encode()) for part in parts)
    r, s = utils.decode_dss_signature(key.sign(unsigned, ec.ECDSA(hashes.SHA256())))
    return (unsigned + b"." + b64(r.to_bytes(32, "big") + s.to_bytes(32, "big"))).decode()


def api(path):
    if not path.startswith("/v1/"):
        raise RuntimeError("Refusing an unexpected App Store Connect API path.")
    request = urllib.request.Request(API + path, headers={"Authorization": "Bearer " + token()})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"App Store Connect returned HTTP {error.code}; no upload retry was attempted.") from None


def all_data(path, request=api):
    result = []
    visited = set()
    while path:
        if path in visited:
            raise RuntimeError("App Store Connect returned a pagination loop.")
        visited.add(path)
        page = request(path)
        result.extend(page["data"])
        next_url = page.get("links", {}).get("next")
        if next_url:
            url = urllib.parse.urlsplit(next_url)
            if url.scheme != "https" or url.netloc != "api.appstoreconnect.apple.com":
                raise RuntimeError("Refusing an unexpected API pagination host.")
            path = url.path + ("?" + url.query if url.query else "")
        else:
            path = None
    return result


def builds():
    return all_data(f"/v1/builds?filter[app]={APP_ID}&limit=200")


def next_build(local, remote, preserved):
    values = [int(local)]
    for value in [item["attributes"]["version"] for item in remote] + list(preserved):
        # Our release scheme uses positive integer CFBundleVersion values.
        if not str(value).isdigit():
            raise RuntimeError("Non-integer historical build number; choose a migration explicitly.")
        values.append(int(value))
    return str(max(values) + 1)


def ensure_newer(number, remote):
    maximum = int(next_build("0", remote, [])) - 1
    if maximum >= int(number):
        raise RuntimeError("Apple has an equal or newer build; release stopped before upload.")


def pending_uploads():
    pending = []
    for report in (ROOT / "release").glob("testflight-*-build*/release.json"):
        evidence = json.loads(report.read_text())
        if evidence.get("uploadAttempted") and not evidence.get("uploadResolved"):
            pending.append(evidence["build"])
    return pending


def record_status(number, result):
    resolved = result["ready"] or result["processing"] in ("FAILED", "INVALID")
    for report in (ROOT / "release").glob("testflight-*-build*/release.json"):
        evidence = json.loads(report.read_text())
        if evidence.get("build") == number:
            evidence["testflight"] = result
            evidence["uploadResolved"] = resolved
            report.write_text(json.dumps(evidence, indent=2) + "\n")


def settings():
    project = json.loads(run(["plutil", "-convert", "json", "-o", "-",
                              ROOT / "Shots.xcodeproj/project.pbxproj"], capture=True))
    configs = [obj["buildSettings"] for obj in project["objects"].values()
               if obj.get("isa") == "XCBuildConfiguration"
               and obj.get("buildSettings", {}).get("PRODUCT_BUNDLE_IDENTIFIER") == BUNDLE]
    versions = {(obj["MARKETING_VERSION"], obj["CURRENT_PROJECT_VERSION"]) for obj in configs}
    if len(versions) != 1:
        raise RuntimeError("Production Debug/Release versions disagree or bundle is missing.")
    return next(iter(versions))


def simulator():
    override = os.environ.get("SHOTS_SIMULATOR_UDID")
    devices = json.loads(run(["xcrun", "simctl", "list", "devices", "available", "--json"], capture=True))
    matches = [device for runtime, group in devices["devices"].items()
               if ".iOS-" in runtime and int(runtime.split(".iOS-")[1].split("-")[0]) >= 26
               for device in group if device.get("isAvailable")
               and (device["udid"] == override if override else device["name"].startswith("Shots"))]
    if not matches:
        raise RuntimeError("Create a dedicated iOS 26+ simulator named Shots, or set SHOTS_SIMULATOR_UDID.")
    device = next((item for item in matches if item["state"] == "Booted"), matches[0])
    if device["state"] != "Booted":
        run(["xcrun", "simctl", "boot", device["udid"]])
    run(["xcrun", "simctl", "bootstatus", device["udid"], "-b"])
    return device["udid"]


def verify(output):
    for binary in ("swift", "xcodebuild", "xcrun", "xcodegen", "python3"):
        if not shutil.which(binary):
            raise RuntimeError(f"Missing required local tool: {binary}")
    run(["swift", "test"])
    run([sys.executable, "-m", "unittest", "discover", "-s", "scripts/tests", "-v"])
    run(["bash", "scripts/run-ui-tests.sh", simulator(), output / "ui"])
    run(["xcodebuild", "-quiet", "-project", "Shots.xcodeproj", "-scheme", "Shots",
         "-configuration", "Release", "-destination", "generic/platform=iOS",
         "-derivedDataPath", output / "unsigned", "CODE_SIGNING_ALLOWED=NO", "build"])


def audit_ipa(ipa, version, build):
    with zipfile.ZipFile(ipa) as archive:
        info = plistlib.loads(archive.read("Payload/Shots.app/Info.plist"))
        if (info.get("CFBundleIdentifier"), info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")) != (BUNDLE, version, build):
            raise RuntimeError("Exported IPA bundle/version/build differs from the release request.")
        if info.get("ITSAppUsesNonExemptEncryption") is not False:
            raise RuntimeError("Unexpected encryption declaration.")
        if info.get("MinimumOSVersion") != "26.0" or info.get("DTPlatformName") != "iphoneos":
            raise RuntimeError("Unexpected minimum iOS version or non-device IPA.")
        if "processing" not in info.get("UIBackgroundModes", []) or "com.calum.shots.scan.current" not in info.get("BGTaskSchedulerPermittedIdentifiers", []):
            raise RuntimeError("Background continuation registration missing from IPA.")
        executable = archive.read("Payload/Shots.app/" + info["CFBundleExecutable"])
        if any(marker in executable for marker in (b"CaptureSamples", b"--large-library", b"--test-scan",
                                                   b"--test-refresh-scan", b"--header-transitions", b"HeaderProbeCollectionView")):
            raise RuntimeError("Synthetic fixture detected in production IPA.")
    return hashlib.sha256(ipa.read_bytes()).hexdigest()


def upload(ipa, key_directory):
    key_id = os.environ[PREFIX + "KEY_ID"]
    if not key_id.isalnum():
        raise RuntimeError("Invalid App Store Connect key identifier.")
    with tempfile.TemporaryDirectory(prefix="upload-key-", dir=key_directory) as directory:
        path = Path(directory) / f"AuthKey_{key_id}.p8"
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as file:
            file.write(private_key())
        env = tool_environment()
        env["API_PRIVATE_KEYS_DIR"] = directory
        try:
            subprocess.run(["xcrun", "altool", "--upload-package", str(ipa),
                            "--api-key", key_id, "--api-issuer", os.environ[PREFIX + "ISSUER_ID"],
                            "--wait", "--output-format", "json"], env=env, cwd=ROOT,
                           check=True, timeout=1800)
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
            raise RuntimeError("Upload result uncertain or failed. Do not retry blindly; run just release-status BUILD.") from None


def status(number, request=api):
    matches = [item for item in all_data(f"/v1/builds?filter[app]={APP_ID}&limit=200", request)
               if item["attributes"]["version"] == number]
    if not matches:
        return {"build": number, "processing": "NOT_VISIBLE", "ready": False}
    if len(matches) != 1:
        raise RuntimeError("Build number is ambiguous across marketing versions; inspect App Store Connect.")
    build = matches[0]
    result = {"build": number, "buildID": build["id"],
              "processing": build["attributes"]["processingState"], "ready": False}
    if result["processing"] != "VALID":
        return result
    detail = request(f"/v1/builds/{build['id']}/buildBetaDetail")["data"]["attributes"]
    group = request(f"/v1/betaGroups/{GROUP_ID}")["data"]["attributes"]
    assigned = all_data(f"/v1/betaGroups/{GROUP_ID}/builds?limit=200", request)
    testers = all_data(f"/v1/betaGroups/{GROUP_ID}/betaTesters?limit=200", request)
    result.update(internalState=detail.get("internalBuildState"), group=group.get("name"),
                  autoNotifyEnabled=detail.get("autoNotifyEnabled"),
                  groupHasBuild=any(item["id"] == build["id"] for item in assigned),
                  testerPresent=any(item["id"] == TESTER_ID for item in testers))
    result["ready"] = (result["internalState"] == "IN_BETA_TESTING" and group.get("isInternalGroup") is True
                       and result["groupHasBuild"] and result["testerPresent"])
    return result


def wait_ready(number, timeout=1200):
    deadline = time.monotonic() + timeout
    while True:
        result = status(number)
        print(json.dumps(result), flush=True)
        if result["ready"]:
            return result
        if result["processing"] in ("FAILED", "INVALID"):
            raise RuntimeError("Apple rejected processing; inspect App Store Connect before another release.")
        if time.monotonic() >= deadline:
            raise RuntimeError(f"Uploaded build {number} is not ready yet. Run just release-status {number}; do not re-upload.")
        time.sleep(20)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--verify", action="store_true", help="Validate only; no credentials, signing, or upload.")
    mode.add_argument("--status", metavar="BUILD", help="Read-back only; never uploads.")
    args = parser.parse_args()
    if not args.verify:
        credentials()
    if args.status:
        result = status(args.status)
        record_status(args.status, result)
        print(json.dumps(result, indent=2))
        return 0 if result["ready"] else 1
    state = ROOT / ".release"
    state.mkdir(exist_ok=True)
    with (state / "lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another local verification/release is running.") from None
        if not args.verify:
            if run(["git", "status", "--porcelain"], capture=True):
                raise RuntimeError("Commit all changes before release; the archive must identify a clean Git revision.")
            revision = run(["git", "rev-parse", "HEAD"], capture=True)
            pending = pending_uploads()
            if pending:
                raise RuntimeError(f"Previous upload unresolved (build {', '.join(pending)}). Run just release-status BUILD before publishing again.")
            apps = all_data(f"/v1/apps?filter[bundleId]={BUNDLE}")
            if len(apps) != 1 or apps[0]["id"] != APP_ID:
                raise RuntimeError("Approved App Store Connect listing does not match.")
            version, local = settings()
            preserved = [path.name.rsplit("-build", 1)[1] for path in (ROOT / "release").glob("testflight-*-build*")]
            number = next_build(local, builds(), preserved)
            output = ROOT / "release" / f"testflight-{datetime.date.today():%Y%m%d}-build{number}"
            output.mkdir()  # Exclusive: never overwrite a preserved artifact.
        else:
            output = Path(tempfile.mkdtemp(prefix="verify-", dir=state))
        print(f"Validation evidence: {output}", flush=True)
        verify(output)
        if args.verify:
            print("Local core/tool/native tests and unsigned Release build passed. Nothing uploaded.")
            return 0
        if run(["git", "status", "--porcelain"], capture=True) or run(["git", "rev-parse", "HEAD"], capture=True) != revision:
            raise RuntimeError("Git source changed during validation; release stopped.")
        ensure_newer(number, builds())
        archive = output / "Shots.xcarchive"
        run(["xcodebuild", "-quiet", "-project", "Shots.xcodeproj", "-scheme", "Shots",
             "-configuration", "Release", "-destination", "generic/platform=iOS",
             "-derivedDataPath", output / "signed", "-archivePath", archive,
             f"CURRENT_PROJECT_VERSION={number}", "archive"])
        run(["codesign", "--verify", "--deep", "--strict", archive / "Products/Applications/Shots.app"])
        run(["xcodebuild", "-quiet", "-exportArchive", "-archivePath", archive,
             "-exportOptionsPlist", "release/ExportOptions.plist", "-exportPath", output / "export"])
        ipa = output / "export/Shots.ipa"
        digest = audit_ipa(ipa, version, number)
        # Verify the exported (potentially re-signed) app as well as the archive.
        with tempfile.TemporaryDirectory(prefix="ipa-audit-", dir=state) as directory:
            run(["ditto", "-x", "-k", ipa, directory])
            run(["codesign", "--verify", "--deep", "--strict", Path(directory) / "Payload/Shots.app"])
        if run(["git", "status", "--porcelain"], capture=True) or run(["git", "rev-parse", "HEAD"], capture=True) != revision:
            raise RuntimeError("Git source changed during signing; upload stopped.")
        ensure_newer(number, builds())
        evidence = {"version": version, "build": number, "gitRevision": revision, "sha256": digest,
                    "ipa": str(ipa.relative_to(ROOT)), "uploadAttempted": True, "uploadResolved": False}
        report = output / "release.json"
        report.write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"Uploading Shots {version} ({number}); SHA256 {digest}", flush=True)
        upload(ipa, state)
        evidence["testflight"] = wait_ready(number)
        evidence["uploadResolved"] = True
        report.write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"Shots {version} ({number}) is available to Calum in TestFlight. Evidence: {report}")
        return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, subprocess.CalledProcessError, ValueError) as error:
        # Never dump environment values or cryptographic inputs on failures.
        print(f"Release stopped: {error}", file=sys.stderr)
        raise SystemExit(1)
