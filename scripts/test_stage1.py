#!/usr/bin/env python3
"""Offline Stage-1 checks. Run with: python3 scripts/test_stage1.py."""
import json
import os
from pathlib import Path
import pty
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SETTINGS = json.loads((ROOT / "claude/.claude/settings.json").read_text())
HOOKS = [hook["command"] for groups in SETTINGS["hooks"].values()
         for group in groups for hook in group["hooks"]]
MESSAGES = """
msg_info() { echo "INFO: $*"; }
msg_success() { echo "SUCCESS: $*"; }
msg_warn() { echo "WARN: $*"; }
msg_header() { :; }
"""


def section(path, start, end):
    return (ROOT / path).read_text().split(start, 1)[1].split(end, 1)[0]


class Stage1Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="stage1-test-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / "home with spaces"
        self.home.mkdir()
        self.env = {"HOME": str(self.home), "PATH": "/usr/bin:/bin",
                    "LC_ALL": "C.UTF-8"}

    def shell(self, code, **env):
        return subprocess.run(["/bin/bash", "--noprofile", "--norc", "-c", code],
                              env=self.env | env, input="{}", text=True,
                              capture_output=True, timeout=10)

    def executable(self, path, body):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)

    def test_hook_shell_syntax_and_absent_dependencies(self):
        for command in HOOKS:
            with self.subTest(command=command):
                syntax = subprocess.run(["bash", "-n", "-c", command],
                                        capture_output=True, text=True)
                self.assertEqual(syntax.returncode, 0, syntax.stderr)
                # No installed rtk or harness can escape this fixture.
                result = self.shell(command, PATH=str(self.home))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")

    def test_harness_paths_and_guard_exit_codes(self):
        for harness in ("COWORK", "OPS"):
            for command in HOOKS:
                match = re.search(r"\$H(/[^\s\";]+)", command)
                if not match:
                    continue
                with self.subTest(harness=harness, command=command):
                    target = self.home / harness / match[1].lstrip("/")
                    guard = "-guard.sh" in str(target)
                    self.executable(target, "echo invoked; exit " + ("2" if guard else "0"))
                    result = self.shell(command)
                    self.assertEqual(result.stdout.strip(), "invoked", result.stderr)
                    self.assertEqual(result.returncode, 2 if guard else 0)
            shutil.rmtree(self.home / harness)

    def test_herdr_uses_active_profile(self):
        command = next(c for c in HOOKS if "herdr-agent-state.sh" in c)
        active = self.home / ".claude-personal"
        self.executable(self.home / ".claude/hooks/herdr-agent-state.sh", "echo wrong-profile")
        self.executable(active / "hooks/herdr-agent-state.sh", 'echo "personal:$1"')
        result = self.shell(command, CLAUDE_CONFIG_DIR=str(active))
        self.assertEqual(result.stdout.strip(), "personal:session", result.stderr)
        self.assertEqual(result.returncode, 0)
        result = self.shell(command)
        self.assertEqual(result.stdout.strip(), "wrong-profile")

    def test_rtk_path_and_fallback(self):
        command = next(c for c in HOOKS if "rtk hook claude" in c)
        bindir = self.home / "bin"
        bindir.mkdir()
        self.executable(self.home / ".local/bin/rtk", 'echo "fallback:$*"')
        result = self.shell(command, PATH=str(bindir))
        self.assertEqual(result.stdout.strip(), "fallback:hook claude")
        self.executable(bindir / "rtk", 'echo "path:$*"')
        result = self.shell(command, PATH=str(bindir))
        self.assertEqual(result.stdout.strip(), "path:hook claude")

    def retirement(self, stub):
        function = "  retire_claude_plugins() {" + section(
            "shellSetup.sh", "  retire_claude_plugins() {", "  # --- AI HARNESS:")
        return self.shell(MESSAGES + stub + function + "\nretire_claude_plugins\n")

    def test_plugin_retirement_reports_failures_without_deleting_files(self):
        marketplace = self.home / ".claude/plugins/marketplaces/caveman"
        marketplace.mkdir(parents=True)
        sentinel = marketplace / "keep"
        sentinel.write_text("CLI failed; preserve state")
        result = self.retirement('claude() { echo "permission denied" >&2; return 1; }\n')
        self.assertIn("WARN:", result.stdout)
        self.assertIn("permission denied", result.stdout)
        self.assertNotIn("SUCCESS:", result.stdout)
        self.assertTrue(sentinel.exists())

    def test_plugin_retirement_success(self):
        result = self.retirement('claude() { return 0; }\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("caveman", result.stdout)
        self.assertIn("ponytail", result.stdout)
        self.assertNotIn("WARN:", result.stdout)

    def test_t3_install_failure_does_not_refresh_package_database(self):
        body = section("omarchy/omarchySetup.sh", "# T3 Code desktop client:",
                       "# 10. Summary")
        # The first line of the section is a continued comment.
        body = "# T3 Code desktop client:" + body
        result = self.shell(MESSAGES + """
pacman() { return 1; }
install_from_repo_or_aur() { return 1; }
sudo() { printf '%s\n' "$*" >> "$HOME/sudo-calls"; return 0; }
""" + body)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertIn("WARN:", result.stdout)
        self.assertFalse((self.home / "sudo-calls").exists())

    def stage1_files(self, prefix=""):
        body = "CLAUDE_SRC=" + section("omarchy/omarchySetup.sh", "CLAUDE_SRC=",
                                       "# Enable tailscaled")
        return self.shell("set -euo pipefail\n" + MESSAGES + prefix + body,
                          LPX_DIR=str(ROOT))

    def test_omarchy_stage1_backup_and_idempotence(self):
        config = self.home / ".claude"
        config.mkdir()
        (config / "settings.json").write_text("old config")
        for _ in range(2):
            result = self.stage1_files()
            self.assertEqual(result.returncode, 0, result.stderr)
        backups = list(config.glob("settings.json.backup_*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "old config")
        for name in ("settings.json", "CLAUDE.md", "statusline.sh"):
            self.assertEqual((config / name).resolve(), ROOT / "claude/.claude" / name)

    def test_omarchy_stage1_stops_on_failed_link(self):
        result = self.stage1_files('ln() { case "$*" in *settings.json*) return 1;; '
                                  '*) command ln "$@";; esac; }\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / ".claude/CLAUDE.md").exists())

    def test_session_pickers_skip_non_tty_and_noninteractive_shells(self):
        for shell, path in (("bash", "bash/.bashrc"), ("zsh", "zsh/.zshrc")):
            text = (ROOT / path).read_text()
            start = next(line for line in text.splitlines()
                         if line.startswith("if [[") and "SSH_CONNECTION" in line)
            code = 'tmux() { :; }; herdr() { :; };\n' + start
            code += '\necho PICKER_RAN\nfi\necho completed\n'
            for flags in (["-c"], ["-i", "-c"]):
                with self.subTest(shell=shell, flags=flags):
                    result = subprocess.run([shell, "-f", *flags, code],
                                            input="", capture_output=True, text=True,
                                            env=self.env | {"SSH_CONNECTION": "test"}, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), "completed")
            master, slave = pty.openpty()
            try:
                for interactive in (False, True):
                    flags = ["-i", "-c"] if interactive else ["-c"]
                    result = subprocess.run([shell, "-f", *flags, code], stdin=slave,
                                            capture_output=True, text=True,
                                            env=self.env | {"SSH_CONNECTION": "test"}, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual("PICKER_RAN" in result.stdout, interactive)
            finally:
                os.close(master)
                os.close(slave)

    def test_statusline_profiles(self):
        for personal in (False, True):
            config = self.home / (".claude-personal" if personal else ".claude")
            config.mkdir()
            (config / "settings.json").write_text(json.dumps(SETTINGS))
            result = subprocess.run(
                ["bash", str(ROOT / "claude/.claude/statusline.sh")],
                env=self.env | {"CLAUDE_CONFIG_DIR": str(config)}, text=True,
                input=json.dumps({"model": {"display_name": "Fable 5.1"}}),
                capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            self.assertIn("PERSONAL" if personal else "WORK", result.stdout)
            self.assertIn("[Umbrella]", result.stdout)

    @unittest.skipUnless(shutil.which("pwsh"), "PowerShell is not installed")
    def test_windows_retirement_exit_codes(self):
        body = section("winSetup.ps1", "# This block used to INSTALL caveman;", "# ═")
        body = "if (Get-Command claude" + body.split("if (Get-Command claude", 1)[1]
        for status in (0, 1):
            code = """
function Write-Header { param($Message) }
function Write-Success { param($Message) Write-Output "SUCCESS: $Message" }
function Write-Warn { param($Message) Write-Output "WARN: $Message" }
function claude { $global:LASTEXITCODE = STATUS; 'CLI result' }
""".replace("STATUS", str(status)) + body
            result = subprocess.run(["pwsh", "-NoProfile", "-Command", code],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("WARN:" if status else "SUCCESS:", result.stdout)
            if status:
                self.assertNotIn("SUCCESS:", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
