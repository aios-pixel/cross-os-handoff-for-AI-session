from __future__ import annotations

import json
import os
import platform
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


PLUGIN_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[3]
WORKSPACE_ROOT = REPO_ROOT if (REPO_ROOT / ".git").exists() else PLUGIN_ROOT
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
    "UpstreamHead",
    "Ahead",
    "Behind",
    "RemoteCount",
    "GitStatus",
    "WorktreeCount",
    "NestedRepositoryCount",
    "EntryFiles",
    "TopLevelEntryCount",
}
REQUIRED_STATUS = {"Available", "IsDirty", "Staged", "Unstaged", "Untracked", "Conflicts"}
CANONICAL_TEXT_FILES = (
    SKILL_ROOT / "SKILL.md",
    SKILL_ROOT / "agents" / "openai.yaml",
    SCRIPTS / "collect-workspace-state.ps1",
    SCRIPTS / "collect-workspace-state.sh",
    PLUGIN_ROOT / ".codex-plugin" / "plugin.json",
)


class CollectorContractTests(unittest.TestCase):
    def run_git(self, working_path: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", "-C", str(working_path), *arguments],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )

    def native_collector_command(self, workspace: Path) -> list[str]:
        if platform.system() == "Windows":
            shell = shutil.which("pwsh") or shutil.which("powershell")
            if not shell:
                self.skipTest("PowerShell is unavailable on this Windows host")
            return [shell, "-NoProfile", "-File", str(SCRIPTS / "collect-workspace-state.ps1"), "-Path", str(workspace)]
        return [str(SCRIPTS / "collect-workspace-state.sh"), str(workspace)]

    def run_native_collector(
        self,
        workspace: Path,
        *,
        check: bool = True,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            self.native_collector_command(workspace),
            check=check,
            capture_output=True,
            text=True,
            encoding="utf-8",
            env=env,
        )

    def assert_contract(self, raw: str) -> None:
        data = json.loads(raw)
        self.assertEqual(data["SchemaVersion"], 3)
        self.assertEqual(set(data), REQUIRED_TOP_LEVEL)
        self.assertEqual(set(data["GitStatus"]), REQUIRED_STATUS)
        self.assertEqual(data["RequestedPath"], "<WORKSPACE_ROOT>")
        self.assertEqual(data["WorkspaceRoot"], "<WORKSPACE_ROOT>")
        self.assertNotRegex(raw, r"/Users/[^/\"\s]+")
        self.assertNotRegex(raw, r"[A-Za-z]:\\Users\\[^\\\"\s]+")
        self.assertNotIn("Hostname", data)
        self.assertNotIn("DeviceName", data)
        if data["IsGitRepository"]:
            self.assertTrue(data["GitStatus"]["Available"])
            self.assertIsInstance(data["GitStatus"]["IsDirty"], bool)
            for field in ("Staged", "Unstaged", "Untracked", "Conflicts"):
                self.assertIsInstance(data["GitStatus"][field], int)
            if data["Upstream"] is None:
                self.assertIsNone(data["UpstreamHead"])
                self.assertIsNone(data["Ahead"])
                self.assertIsNone(data["Behind"])
            else:
                self.assertIsInstance(data["UpstreamHead"], str)
                self.assertIsInstance(data["Ahead"], int)
                self.assertIsInstance(data["Behind"], int)
        else:
            self.assertFalse(data["GitStatus"]["Available"])
            for field in ("IsDirty", "Staged", "Unstaged", "Untracked", "Conflicts"):
                self.assertIsNone(data["GitStatus"][field])

    def test_posix_collector(self) -> None:
        if platform.system() == "Windows":
            self.skipTest("POSIX collector is not the native Windows path")
        result = subprocess.run(
            [str(SCRIPTS / "collect-workspace-state.sh"), str(WORKSPACE_ROOT)],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        self.assert_contract(result.stdout)

    def test_native_collector_marks_non_git_status_unavailable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            result = self.run_native_collector(Path(temporary_directory))
            data = json.loads(result.stdout)
            self.assert_contract(result.stdout)
            self.assertFalse(data["IsGitRepository"])
            self.assertFalse(data["GitStatus"]["Available"])
            self.assertIsNone(data["Head"])
            self.assertIsNone(data["Ahead"])
            self.assertIsNone(data["Behind"])

    def test_native_collector_reports_clean_counts_as_zero(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = Path(temporary_directory)
            self.run_git(repository, "init", "-q")
            self.run_git(repository, "config", "user.name", "Collector Test")
            self.run_git(repository, "config", "user.email", "collector.invalid")
            (repository / "tracked.txt").write_text("base\n", encoding="utf-8")
            self.run_git(repository, "add", "tracked.txt")
            self.run_git(repository, "commit", "-q", "-m", "base")

            result = self.run_native_collector(repository)
            data = json.loads(result.stdout)
            self.assert_contract(result.stdout)
            self.assertFalse(data["GitStatus"]["IsDirty"])
            for field in ("Staged", "Unstaged", "Untracked", "Conflicts"):
                self.assertEqual(data["GitStatus"][field], 0)

    def test_native_collector_reports_dirty_counts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = Path(temporary_directory)
            self.run_git(repository, "init", "-q")
            self.run_git(repository, "config", "user.name", "Collector Test")
            self.run_git(repository, "config", "user.email", "collector.invalid")
            (repository / "tracked.txt").write_text("base\n", encoding="utf-8")
            self.run_git(repository, "add", "tracked.txt")
            self.run_git(repository, "commit", "-q", "-m", "base")

            (repository / "tracked.txt").write_text("changed\n", encoding="utf-8")
            (repository / "staged.txt").write_text("staged\n", encoding="utf-8")
            self.run_git(repository, "add", "staged.txt")
            (repository / "untracked.txt").write_text("untracked\n", encoding="utf-8")

            result = self.run_native_collector(repository)
            data = json.loads(result.stdout)
            self.assert_contract(result.stdout)
            self.assertTrue(data["GitStatus"]["IsDirty"])
            self.assertEqual(data["GitStatus"]["Staged"], 1)
            self.assertEqual(data["GitStatus"]["Unstaged"], 1)
            self.assertEqual(data["GitStatus"]["Untracked"], 1)
            self.assertEqual(data["GitStatus"]["Conflicts"], 0)

    def test_native_collector_rejects_missing_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            missing_workspace = Path(temporary_directory) / "missing"
            result = self.run_native_collector(missing_workspace, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertIn("collector_error=workspace_unavailable", result.stderr)

    def test_native_collector_fails_closed_when_git_is_unavailable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            repository = root / "repository"
            repository.mkdir()
            self.run_git(repository, "init", "-q")
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()

            if platform.system() == "Windows":
                environment = os.environ.copy()
                environment["PATH"] = str(fake_bin)
            else:
                for command_name in ("bash", "dirname"):
                    command_path = shutil.which(command_name)
                    self.assertIsNotNone(command_path)
                    (fake_bin / command_name).symlink_to(command_path)
                environment = os.environ.copy()
                environment["PATH"] = str(fake_bin)

            result = self.run_native_collector(repository, check=False, env=environment)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertIn("collector_error=git_unavailable", result.stderr)

    def test_native_collector_ignores_hidden_untracked_host_config(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = Path(temporary_directory)
            self.run_git(repository, "init", "-q")
            self.run_git(repository, "config", "user.name", "Collector Test")
            self.run_git(repository, "config", "user.email", "collector.invalid")
            (repository / "tracked.txt").write_text("base\n", encoding="utf-8")
            self.run_git(repository, "add", "tracked.txt")
            self.run_git(repository, "commit", "-q", "-m", "base")
            self.run_git(repository, "config", "status.showUntrackedFiles", "no")
            (repository / "untracked.txt").write_text("untracked\n", encoding="utf-8")

            result = self.run_native_collector(repository)
            data = json.loads(result.stdout)
            self.assertTrue(data["GitStatus"]["IsDirty"])
            self.assertEqual(data["GitStatus"]["Untracked"], 1)

    def test_collectors_disable_git_optional_locks(self) -> None:
        bash_script = (SCRIPTS / "collect-workspace-state.sh").read_text(encoding="utf-8")
        powershell_script = (SCRIPTS / "collect-workspace-state.ps1").read_text(encoding="utf-8")
        self.assertIn("export GIT_OPTIONAL_LOCKS=0", bash_script)
        self.assertIn('$env:GIT_OPTIONAL_LOCKS = "0"', powershell_script)

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            repository = root / "repository"
            repository.mkdir()
            self.run_git(repository, "init", "-q")
            self.run_git(repository, "config", "user.name", "Collector Test")
            self.run_git(repository, "config", "user.email", "collector.invalid")
            (repository / "tracked.txt").write_text("base\n", encoding="utf-8")
            self.run_git(repository, "add", "tracked.txt")
            self.run_git(repository, "commit", "-q", "-m", "base")
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            real_git = shutil.which("git")
            self.assertIsNotNone(real_git)

            if platform.system() == "Windows":
                wrapper = fake_bin / "git.cmd"
                wrapper.write_text(
                    f'@echo off\r\nif not "%GIT_OPTIONAL_LOCKS%"=="0" exit /b 43\r\n"{real_git}" %*\r\n',
                    encoding="utf-8",
                )
            else:
                wrapper = fake_bin / "git"
                wrapper.write_text(
                    f'#!/bin/sh\n[ "$GIT_OPTIONAL_LOCKS" = "0" ] || exit 43\nexec "{real_git}" "$@"\n',
                    encoding="utf-8",
                )
                wrapper.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = str(fake_bin) + os.pathsep + environment.get("PATH", "")
            result = self.run_native_collector(repository, env=environment)
            self.assert_contract(result.stdout)

    def test_native_collector_counts_recursive_git_directories_and_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = Path(temporary_directory)
            self.run_git(repository, "init", "-q")
            self.run_git(repository, "config", "user.name", "Collector Test")
            self.run_git(repository, "config", "user.email", "collector.invalid")
            (repository / "root.txt").write_text("root\n", encoding="utf-8")
            self.run_git(repository, "add", "root.txt")
            self.run_git(repository, "commit", "-q", "-m", "root")
            deep_repository = repository / "a" / "b" / "nested"
            deep_repository.mkdir(parents=True)
            self.run_git(deep_repository, "init", "-q")
            git_file_parent = repository / "linked" / "worktree"
            git_file_parent.mkdir(parents=True)
            (git_file_parent / ".git").write_text("gitdir: ../../metadata\n", encoding="utf-8")

            result = self.run_native_collector(repository)
            data = json.loads(result.stdout)
            self.assert_contract(result.stdout)
            self.assertEqual(data["NestedRepositoryCount"], 2)

    def test_native_collector_reports_behind_and_diverged_state(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            remote = root / "remote.git"
            source = root / "source"
            destination = root / "destination"
            subprocess.run(["git", "init", "--bare", "-q", str(remote)], check=True)
            self.run_git(remote, "symbolic-ref", "HEAD", "refs/heads/main")
            subprocess.run(["git", "clone", "-q", str(remote), str(source)], check=True, capture_output=True)
            self.run_git(source, "config", "user.name", "Collector Test")
            self.run_git(source, "config", "user.email", "collector.invalid")
            (source / "base.txt").write_text("base\n", encoding="utf-8")
            self.run_git(source, "add", "base.txt")
            self.run_git(source, "commit", "-q", "-m", "base")
            self.run_git(source, "push", "-q", "-u", "origin", "main")
            subprocess.run(["git", "clone", "-q", str(remote), str(destination)], check=True, capture_output=True)
            self.run_git(destination, "config", "user.name", "Collector Test")
            self.run_git(destination, "config", "user.email", "collector.invalid")

            (source / "remote.txt").write_text("remote\n", encoding="utf-8")
            self.run_git(source, "add", "remote.txt")
            self.run_git(source, "commit", "-q", "-m", "remote")
            self.run_git(source, "push", "-q")
            self.run_git(destination, "fetch", "-q", "origin")

            behind_result = self.run_native_collector(destination)
            behind_data = json.loads(behind_result.stdout)
            self.assert_contract(behind_result.stdout)
            self.assertEqual(behind_data["Ahead"], 0)
            self.assertEqual(behind_data["Behind"], 1)
            self.assertNotEqual(behind_data["Head"], behind_data["UpstreamHead"])

            (destination / "local.txt").write_text("local\n", encoding="utf-8")
            self.run_git(destination, "add", "local.txt")
            self.run_git(destination, "commit", "-q", "-m", "local")
            diverged_result = self.run_native_collector(destination)
            diverged_data = json.loads(diverged_result.stdout)
            self.assert_contract(diverged_result.stdout)
            self.assertEqual(diverged_data["Ahead"], 1)
            self.assertEqual(diverged_data["Behind"], 1)

    def test_native_collector_fails_closed_when_git_status_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            repository = root / "repository"
            repository.mkdir()
            self.run_git(repository, "init", "-q")
            self.run_git(repository, "config", "user.name", "Collector Test")
            self.run_git(repository, "config", "user.email", "collector.invalid")
            (repository / "root.txt").write_text("root\n", encoding="utf-8")
            self.run_git(repository, "add", "root.txt")
            self.run_git(repository, "commit", "-q", "-m", "root")
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            real_git = shutil.which("git")
            self.assertIsNotNone(real_git)

            if platform.system() == "Windows":
                wrapper = fake_bin / "git.cmd"
                wrapper.write_text(
                    f'@echo off\r\nif /I "%~3"=="status" exit /b 42\r\n"{real_git}" %*\r\n',
                    encoding="utf-8",
                )
            else:
                wrapper = fake_bin / "git"
                wrapper.write_text(
                    f'#!/bin/sh\nif [ "$3" = "status" ]; then exit 42; fi\nexec "{real_git}" "$@"\n',
                    encoding="utf-8",
                )
                wrapper.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = str(fake_bin) + os.pathsep + environment.get("PATH", "")
            result = self.run_native_collector(repository, check=False, env=environment)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertIn("collector_error=git_status_unavailable", result.stderr)

    def test_native_collector_fails_closed_when_git_root_discovery_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            repository = root / "repository"
            repository.mkdir()
            self.run_git(repository, "init", "-q")
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            real_git = shutil.which("git")
            self.assertIsNotNone(real_git)

            if platform.system() == "Windows":
                wrapper = fake_bin / "git.cmd"
                wrapper.write_text(
                    f'@echo off\r\nif /I "%~3"=="rev-parse" if /I "%~4"=="--show-toplevel" exit /b 42\r\n"{real_git}" %*\r\n',
                    encoding="utf-8",
                )
            else:
                wrapper = fake_bin / "git"
                wrapper.write_text(
                    f'#!/bin/sh\nif [ "$3" = "rev-parse" ] && [ "$4" = "--show-toplevel" ]; then exit 42; fi\nexec "{real_git}" "$@"\n',
                    encoding="utf-8",
                )
                wrapper.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = str(fake_bin) + os.pathsep + environment.get("PATH", "")
            result = self.run_native_collector(repository, check=False, env=environment)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertIn("collector_error=git_root_unavailable", result.stderr)

    def test_windows_collector_restores_process_state(self) -> None:
        shell = shutil.which("pwsh") or shutil.which("powershell")
        if not shell:
            self.skipTest("PowerShell is unavailable on this host")
        with tempfile.TemporaryDirectory() as temporary_directory:
            harness = Path(temporary_directory) / "invoke-collector.ps1"
            harness.write_text(
                '$originalConsoleOutputEncoding = [Console]::OutputEncoding\n'
                '$callerConsoleOutputEncoding = [System.Text.Encoding]::ASCII\n'
                '[Console]::OutputEncoding = $callerConsoleOutputEncoding\n'
                'try {\n'
                '    $env:GIT_OPTIONAL_LOCKS = "caller-value"\n'
                '    $collectorOutput = @(& $args[0] -Path $args[1])\n'
                '    if ($env:GIT_OPTIONAL_LOCKS -ne "caller-value") { exit 44 }\n'
                '    if ([Console]::OutputEncoding.CodePage -ne $callerConsoleOutputEncoding.CodePage) { exit 45 }\n'
                '    $collectorOutput\n'
                '}\n'
                'finally {\n'
                '    [Console]::OutputEncoding = $originalConsoleOutputEncoding\n'
                '}\n',
                encoding="utf-8",
            )
            result = subprocess.run(
                [shell, "-NoProfile", "-File", str(harness), str(SCRIPTS / "collect-workspace-state.ps1"), str(WORKSPACE_ROOT)],
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
        self.assertIn("SchemaVersion = 3", script)
        self.assertIn("UpstreamHead = $upstreamHead", script)
        self.assertIn("Ahead = $ahead", script)
        self.assertIn("Behind = $behind", script)
        self.assertIn("Available = $gitStatusAvailable", script)
        self.assertIn('Stop-Collector -Code "git_status_unavailable"', script)
        self.assertIn('Stop-Collector -Code "git_root_unavailable"', script)
        self.assertIn('Stop-Collector -Code "git_unavailable"', script)
        self.assertIn('Stop-Collector -Code "workspace_unavailable"', script)
        self.assertIn('"--untracked-files=all"', script)
        self.assertIn('$env:GIT_OPTIONAL_LOCKS = "0"', script)
        self.assertIn('$previousOptionalLocks = $env:GIT_OPTIONAL_LOCKS', script)
        self.assertIn('$env:GIT_OPTIONAL_LOCKS = $previousOptionalLocks', script)
        self.assertIn('Remove-Item Env:GIT_OPTIONAL_LOCKS', script)
        self.assertIn('$previousConsoleOutputEncoding = [Console]::OutputEncoding', script)
        self.assertIn('[Console]::OutputEncoding = $previousConsoleOutputEncoding', script)
        self.assertIn("Test-GitMarkerInAncestry", script)
        self.assertIn('$_.Substring(0, 2) -eq "??"', script)
        self.assertNotIn('-like "??*"', script)
        self.assertNotIn('-notlike "??*"', script)
        self.assertNotIn("Hostname =", script)
        self.assertNotIn("DeviceName =", script)

    def test_plugin_and_skill_have_no_placeholders(self) -> None:
        manifest = json.loads((PLUGIN_ROOT / ".codex-plugin" / "plugin.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["name"], "cn-handoff")
        self.assertEqual(manifest["version"], "2.1.7")
        skill = (SKILL_ROOT / "SKILL.md").read_text(encoding="utf-8")
        self.assertIn("name: handoff", skill)
        self.assertNotIn("[TO" + "DO:", skill)
        self.assertIsNone(re.search(r"(?i)(api[_-]?key|access[_-]?token)\s*[:=]\s*[A-Za-z0-9_-]{12,}", skill))

    def test_skill_declares_deterministic_resume_boundaries(self) -> None:
        skill = (SKILL_ROOT / "SKILL.md").read_text(encoding="utf-8")
        self.assertIn("git log -1 --format=%H -- SESSION.md", skill)
        self.assertIn("git log -1 --format=%H -- HANDOFF_交班.md", skill)
        self.assertIn("`Ahead = 0`, `Behind = 0`, and `Head = UpstreamHead`", skill)
        self.assertIn("GitStatus.Available", skill)

    def test_posix_collector_avoids_tempfile_backed_here_strings(self) -> None:
        script = (SCRIPTS / "collect-workspace-state.sh").read_text(encoding="utf-8")
        self.assertNotIn("<<<", script)

    def test_plugin_text_files_use_canonical_lf(self) -> None:
        attributes_path = REPO_ROOT / ".gitattributes"
        if attributes_path.is_file():
            attributes = attributes_path.read_text(encoding="utf-8")
            self.assertIn("plugins/cn-handoff/** text eol=lf", attributes)
        for path in CANONICAL_TEXT_FILES:
            with self.subTest(path=path.relative_to(REPO_ROOT)):
                self.assertNotIn(b"\r\n", path.read_bytes())


if __name__ == "__main__":
    unittest.main()
