#!/usr/bin/env python3
"""Exercise CI path selection with real commits in an isolated repository."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="changed-apps-") as directory:
    root = Path(directory)
    def git(*args):
        return subprocess.check_output(["git", *args], cwd=root, text=True).strip()
    git("init", "-q")
    git("config", "user.name", "Calum")
    git("config", "user.email", "6991398+0x63616c@users.noreply.github.com")
    (root / "scripts").mkdir()
    for script in ["changed-apps.sh", "app-config.rb"]:
        shutil.copy2(ROOT / "scripts" / script, root / "scripts" / script)
    for app in ["tendr", "blockr"]:
        path = root / "apps" / app
        path.mkdir(parents=True)
        (path / "app.yml").write_text(f"testflight: {str(app == 'tendr').lower()}\n")
        (path / "code.swift").write_text(f"// {app}\n")
    git("add", ".")
    git("commit", "-qm", "Fixture")
    def selected(base, *options):
        return json.loads(subprocess.check_output(["bash", "scripts/changed-apps.sh", base, *options], cwd=root, text=True))
    assert selected("") == ["blockr", "tendr"]
    assert selected("0" * 40, "--only", "testflight") == ["tendr"]
    assert selected("HEAD") == []
    def change(path, content):
        base = git("rev-parse", "HEAD")
        dest = root / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)
        git("add", ".")
        git("commit", "-qm", "Fixture change")
        return base
    base = change("apps/tendr/docs/guide.md", "Docs\n")
    assert selected(base) == ["tendr"]
    assert selected(base, "--build") == []
    base = change("apps/blockr/code.swift", "// New\n")
    assert selected(base) == ["blockr"]
    assert selected(base, "--only", "testflight") == []
    base = change("packages/RDesign/shared.swift", "// Shared\n")
    assert selected(base, "--build") == ["blockr", "tendr"]
    base = change("site/tendr/privacy/index.html", "Privacy\n")
    assert selected(base) == []
    base = change("templates/new-app/Example.swift", "// Template\n")
    assert selected(base) == []
    base = git("rev-parse", "HEAD")
    git("mv", "apps/tendr/code.swift", "apps/blockr/moved.swift")
    git("commit", "-qm", "Cross-app move")
    assert sorted(selected(base)) == ["blockr", "tendr"]
print("Path filter checks passed (initial push, no changes, docs, app, shared, site, template, cross-app rename).")
