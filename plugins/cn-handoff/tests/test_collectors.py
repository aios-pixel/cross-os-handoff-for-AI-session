import json
import platform
import re
import shutil
import subprocess
import unittest
from pathlib import Path


PLUGIN_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[3]
SKILL_ROOT = PLUGIN_ROOT / "skills" / "handoff"
SCRIPTS = SKILL_ROOT / "scripts"

REQUIRED_TOP_LEVEL = {
    "SchemaVersion",
    "CollectedAt",
    "RequestedPath",
    "WorkspaceRoot",
    "RepositoryName",
    "IsGitRepository",
    "GitAvailable",
    "Branch",
    "Head",
    "Upstream",
    "RemoteCount",
    "GitStatus",
    "WorktreeCount",
    "NestedRepositoryCount",
    "EntryFiles",
    "TopLevelEntryCount",
}
REQUIRED_STATUS = {"IsDirty", "Staged", "Unstaged", "Untracked", "Conflicts"}
CANONICAL_TEXT_FILES = (
    SKILL_ROOT / "SKILL.md",
    SKILL_ROOT / "agents" / "openai.yaml",
    SCRIPTS / "collect-workspace-state.ps1",
    SCRIPTS / "collect-workspace-state.sh",
    PLUGIN_ROOT / ".codex-plugin" / "plugin.json",
)


class CollectorContractTests(unittest.TestCase):
    def assert_contract(self, raw: str) -> None:
        data = json.loads(raw)
        self.assertEqual(data["SchemaVersion"], 2)
        self.assertEqual(set(data), REQUIRED_TOP_LEVEL)
        self.assertEqual(set(data["GitStatus"]), REQUIRED_STATUS)
        self.assertEqual(data["RequestedPath"], "<WORKSPACE_ROOT>")
        self.assertEqual(data["WorkspaceRoot"], "<WORKSPACE_ROOT>")
        self.assertNotRegex(raw, r"/Users/[^/\"\s]+")
        self.assertNotRegex(raw, r"[A-Za-z]:\\Users\\[^\\\"\s]+")
        self.assertNotIn("Hostname", data)
        self.assertNotIn("DeviceName", data)

    def test_posix_collector(self) -> None:
        if platform.system() == "Windows":
            self.skipTest("POSIX collector is not the native Windows path")
        result = subprocess.run(
            [str(SCRIPTS / "collect-workspace-state.sh"), str(REPO_ROOT)],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        self.assert_contract(result.stdout)

    def test_windows_collector_when_powershell_exists(self) -> None:
        shell = shutil.which("pwsh") or shutil.which("powershell")
        if not shell:
            self.skipTest("PowerShell is unavailable on this host")
        result = subprocess.run(
            [shell, "-NoProfile", "-File", str(SCRIPTS / "collect-workspace-state.ps1"), "-Path", str(REPO_ROOT)],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        self.assert_contract(result.stdout)

    def test_windows_collector_declares_redacted_contract(self) -> None:
        script = (SCRIPTS / "collect-workspace-state.ps1").read_text(encoding="utf-8")
        for field in REQUIRED_TOP_LEVEL:
            self.assertIn(field, script)
        for field in REQUIRED_STATUS:
            self.assertIn(field, script)
        self.assertIn('RequestedPath = "<WORKSPACE_ROOT>"', script)
        self.assertIn('WorkspaceRoot = "<WORKSPACE_ROOT>"', script)
        self.assertNotIn("Hostname =", script)
        self.assertNotIn("DeviceName =", script)

    def test_plugin_and_skill_have_no_placeholders(self) -> None:
        manifest = json.loads((PLUGIN_ROOT / ".codex-plugin" / "plugin.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["name"], "cn-handoff")
        self.assertEqual(manifest["version"], "2.0.0")
        skill = (SKILL_ROOT / "SKILL.md").read_text(encoding="utf-8")
        self.assertIn("name: handoff", skill)
        self.assertNotIn("[TO" + "DO:", skill)
        self.assertIsNone(re.search(r"(?i)(api[_-]?key|access[_-]?token)\s*[:=]\s*[A-Za-z0-9_-]{12,}", skill))

    def test_plugin_text_files_use_canonical_lf(self) -> None:
        attributes = (REPO_ROOT / ".gitattributes").read_text(encoding="utf-8")
        self.assertIn("plugins/cn-handoff/** text eol=lf", attributes)
        for path in CANONICAL_TEXT_FILES:
            with self.subTest(path=path.relative_to(REPO_ROOT)):
                self.assertNotIn(b"\r\n", path.read_bytes())


if __name__ == "__main__":
    unittest.main()
