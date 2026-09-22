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
msg_error() { echo "ERROR: $*"; }
msg_header() { :; }
"""
STAGE2_GATE = "    # Stage 2 is gated on the harness's own deployer"


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

    def stage2(self, harness):
        # The gate through the end of setup_harness; the section carries the
        # function's closing brace, which closes the wrapper opened here.
        body = STAGE2_GATE + section("shellSetup.sh", STAGE2_GATE,
                                     "  # --- MENU & EXECUTION ---")
        return self.shell(MESSAGES + 'stage2() {\n  local HARNESS_DIR="$1"\n'
                          + body + '\nstage2 "$HARNESS"\n', HARNESS=str(harness))

    def deployer(self, harness, status):
        self.executable(harness / ".claude-config/deploy.sh",
                        'touch "$HOME/deploy-ran"; exit ' + str(status))

    def test_stage2_gate_runs_deploy_script_without_workforce(self):
        # The harness retired WORKFORCE/; Stage 2 must still run on a new box.
        harness = self.home / "COWORK"
        self.deployer(harness, 0)
        self.assertFalse((harness / "WORKFORCE").exists())
        zshrc = self.home / ".zshrc"
        zshrc.write_text("# keep\n# --- COWORK Multi-Agent Coordination ---\n"
                         'export PATH="$HOME/COWORK/AGENTS/bin:$PATH"\n')
        result = self.stage2(harness)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / "deploy-ran").exists())
        self.assertIn("SUCCESS: Harness deployed at " + str(harness), result.stdout)
        self.assertNotIn("WARN:", result.stdout)
        # The kept legacy cleanup still strips the old harness PATH block.
        self.assertEqual(zshrc.read_text(), "# keep\n")

    def test_stage2_gate_skips_with_warning_without_deploy_script(self):
        # A leftover WORKFORCE/ must not stand in for the deployer.
        harness = self.home / "COWORK"
        (harness / "WORKFORCE").mkdir(parents=True)
        result = self.stage2(harness)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("WARN: No Stage 2 deployer at " + str(harness)
                      + "/.claude-config/deploy.sh", result.stdout)
        self.assertIn("Skipping Stage 2.", result.stdout)
        self.assertNotIn("SUCCESS:", result.stdout)
        self.assertFalse((self.home / "deploy-ran").exists())

    def test_stage2_gate_runs_deploy_script_with_workforce(self):
        harness = self.home / "COWORK"
        self.deployer(harness, 0)
        (harness / "WORKFORCE").mkdir()
        result = self.stage2(harness)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / "deploy-ran").exists())
        self.assertIn("SUCCESS: Harness deployed at " + str(harness), result.stdout)

    def test_stage2_gate_reports_failed_deploy_without_claiming_success(self):
        harness = self.home / "OPS"
        self.deployer(harness, 3)
        result = self.stage2(harness)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / "deploy-ran").exists())
        self.assertIn("ERROR: Harness deploy.sh failed.", result.stdout)
        self.assertNotIn("SUCCESS:", result.stdout)

    def test_windows_stage2_gate_keys_on_deploy_script(self):
        # Static: pwsh is absent on most Linux boxes, and the gate must hold
        # on every one of them before a Windows box ever runs it.
        text = (ROOT / "winSetup.ps1").read_text()
        body = section("winSetup.ps1", STAGE2_GATE, "# ═")
        assign = "$deployScript = Join-Path $CoworkDir '.claude-config\\deploy.ps1'"
        gate = "if ($canProceed -and (Test-Path -LiteralPath $deployScript -PathType Leaf)) {"
        self.assertIn(gate, body)
        self.assertLess(body.index(assign), body.index(gate))
        self.assertIn('Write-Warn "No Stage 2 deployer at $deployScript', body)
        self.assertNotIn("WORKFORCE", text)

    def test_windows_summary_only_claims_successful_harness_deploy(self):
        body = section("winSetup.ps1", "#  DONE", "Write-Host '  Keybinds")
        self.assertIn("'SSHKEY','HARNESS')", body)
        self.assertNotIn("'COWORK'", body)
        self.assertIn("if (($Selected -contains 'HARNESS') -and $deployOk) {", body)
        self.assertIn('Write-Host "    AI harness deployed at $CoworkDir"', body)

    def test_settings_has_no_retired_fleet_hooks(self):
        text = (ROOT / "claude/.claude/settings.json").read_text()
        for retired in ("WORKFORCE", "ac-reorient"):
            self.assertNotIn(retired, text)
        # Compare against the surviving hook contract, not a second read of
        # the same JSON. Losing another hook must fail this retirement check.
        expected = {
            "startup|clear": ["session-briefing.sh", "post-compact-resume.sh",
                              "handoff-check.sh", "vault-inbox-check.sh",
                              "memory-index.sh", "remote-session-register.sh",
                              "session-work-init.sh"],
            "resume|compact": ["post-compact-resume.sh", "handoff-check.sh",
                               "session-briefing.sh", "remote-session-register.sh",
                               "session-work-init.sh"],
            "*": ["herdr-agent-state.sh"],
        }
        groups = SETTINGS["hooks"]["SessionStart"]
        self.assertEqual([group["matcher"] for group in groups], list(expected))
        for group in groups:
            names = [re.search(r"/([\w-]+\.sh)", hook["command"]).group(1)
                     for hook in group["hooks"]]
            self.assertEqual(names, expected[group["matcher"]])
        # Every harness hook lives in the harness's hooks dir, which survives
        # layout changes the way the retired fleet dir did not.
        targets = [m[1] for c in HOOKS for m in [re.search(r"\$H(/[^\s\";]+)", c)] if m]
        self.assertTrue(targets)
        for target in targets:
            self.assertTrue(target.startswith("/.claude-config/hooks/"), target)

    def test_rc_files_do_not_source_claude_wrapper(self):
        # The wrapper is root-only now; COWORK's deploy.sh wires /root's rcs.
        for path in ("bash/.bashrc", "zsh/.zshrc", "omarchy/bashrc-overlay.sh",
                     "omarchy/omarchySetup.sh"):
            with self.subTest(path=path):
                self.assertNotIn("claude-wrapper.sh", (ROOT / path).read_text())

    def test_omarchy_managed_block_drops_old_wrapper_line(self):
        start = 'msg_header "7. Wire ~/.bashrc managed block"'
        body = start + section("omarchy/omarchySetup.sh", start,
                               "# 7b. Stage-1 Claude files")
        overlay = '[ -r "$HOME/.config/lpx/bashrc-overlay.sh" ] && . "$HOME/.config/lpx/bashrc-overlay.sh"\n'
        local = '[ -r "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"\n'
        bashrc = self.home / ".bashrc"
        # A box provisioned before the wrapper went root-only.
        bashrc.write_text(
            "# omarchy default\n# >>> lpx-omarchy (managed) >>>\n" + overlay
            + "# --- COWORK Claude wrapper (root/master safety) ---\n"
            '[ -r "$HOME/COWORK/WORKFORCE/bin/claude-wrapper.sh" ] && '
            '. "$HOME/COWORK/WORKFORCE/bin/claude-wrapper.sh"\n'
            + local + "# <<< lpx-omarchy (managed) <<<\n")
        expected = ("# omarchy default\n\n# >>> lpx-omarchy (managed) >>>\n" + overlay
                    + local + "# <<< lpx-omarchy (managed) <<<\n")
        for _ in range(2):
            result = self.shell("set -euo pipefail\n" + MESSAGES + body)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(bashrc.read_text(), expected)

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
