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


# OPS's model checks as data. Every OPS install runs verify-ops.sh (public repo
# Exploitacious/OPS, .claude-config/bin/verify-ops.sh) against this
# settings.json, so a model change here that those checks reject fails every
# fresh OPS install; that happened once already (OPS drift audit 2026-10-18,
# findings C3 and C4). Copied from verify-ops.sh at OPS 659bf41: check 14
# (check_model_policy, OPS_FOREMAN_PIN), check 15 (check_opus5_ban) and check
# 15b (check_retired_model_pins and _check_haiku_pin, HAIKU_OK). verify-ops.sh
# has no effort check, so an effort change reaches OPS only through the
# ops-port pass. When OPS changes these checks, the ops-port skill (COWORK
# SKILLS/ops-port) updates this block in the same pass;
# test_ops_model_rules_match_the_real_verify_ops compares the two whenever
# OPS_DIR names an OPS checkout.
OPS_FOREMAN_PIN = "claude-opus-5-5[1m]"
OPS_HAIKU_OK = "claude-haiku-5-5"
OPS_RETIRED = ("claude-sonnet-5", "claude-opus-4-8")
# An id ends at its last digit: claude-sonnet-5 is a prefix of claude-sonnet-5-5.
OPS_ID_END = r"(\[|[^A-Za-z0-9-]|$)"
OPS_OPUS5 = re.compile(r"claude-opus-5" + OPS_ID_END, re.M)
OPS_TOKEN = re.compile(r"[a-z0-9][a-z0-9._:@/-]*(\[[^\]]*\])?", re.I)
OPS_HAIKU_TOKEN = re.compile(r"claude[-_][a-z0-9._@:-]*haiku|haiku[-_][0-9]", re.I)
OPS_HAIKU_ALIAS = re.compile(r"haiku(\[1m\])?", re.I)


def ops_settings_text(settings):
    """verify-ops _ops_settings_text: every object key and string value, one per
    line (jq -r '.. | if type == "object" then keys[] elif type == "string" then . else empty end')."""
    out = []

    def walk(value):
        if isinstance(value, dict):
            out.extend(sorted(value))
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)
        elif isinstance(value, str):
            out.append(value)

    walk(settings)
    return "\n".join(out)


def ops_string_values(settings):
    if isinstance(settings, dict):
        return [s for v in settings.values() for s in ops_string_values(v)]
    if isinstance(settings, list):
        return [s for v in settings for s in ops_string_values(v)]
    return [settings] if isinstance(settings, str) else []


def ops_model_verdicts(settings):
    """The four verdict lines verify-ops.sh prints for one settings file, in
    order: check 14, check 15, check 15b's pin scan, check 15b's Haiku pin."""
    model = settings.get("model") if isinstance(settings, dict) else None
    model = model if isinstance(model, str) else ""
    text = ops_settings_text(settings)
    # Check 14 only WARNs: an Operator may pin another tier on purpose.
    policy = "ok" if model in ("", OPS_FOREMAN_PIN) else "warn"
    opus5 = "fail" if OPS_OPUS5.search(text) else "ok"
    hits = [i for i in OPS_RETIRED if re.search(re.escape(i) + OPS_ID_END, text, re.M)]
    for line in text.splitlines():
        for match in OPS_TOKEN.finditer(line):
            token = re.sub(r"[._@:-]+$", "", match.group(0))
            if (OPS_HAIKU_TOKEN.search(match.group(0)) and not re.fullmatch(r"[a-z_]+", token, re.I)
                    and token != OPS_HAIKU_OK):
                hits.append(token)
    hits += [s for s in ops_string_values(settings) if OPS_HAIKU_ALIAS.fullmatch(s)]
    retired = "fail" if hits else "ok"
    env = settings.get("env") if isinstance(settings, dict) else None
    pin = env.get("ANTHROPIC_DEFAULT_HAIKU_MODEL") if isinstance(env, dict) else None
    pin = "" if pin in (None, False) else pin if isinstance(pin, str) else json.dumps(pin)
    haiku_pin = "ok" if pin == OPS_HAIKU_OK else "fail"
    return [policy, opus5, retired, haiku_pin]


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

    # rtk-hook.sh: the PreToolUse(Bash) wrapper. Claude Code's own worktree-isolation
    # guard refuses `rtk git ...` from an isolated lane (cwd <repo>/.claude/worktrees/<name>),
    # so the wrapper must leave that lane's commands untouched and rewrite everywhere
    # else. Each case runs the real script against a stub rtk that records its call and
    # echoes the stdin it was handed, so "rewritten" and "payload passed unchanged" are
    # both observable.
    RTK_STUB = 'echo "rtk-called:$*"; cat'

    def rtk_payload(self, cwd, command="git status"):
        return json.dumps({"session_id": "s", "cwd": cwd, "hook_event_name": "PreToolUse",
                           "tool_name": "Bash", "tool_input": {"command": command}})

    def run_rtk_wrapper(self, payload, jq=True):
        bindir = self.home / ("bin-jq" if jq else "bin-nojq")
        bindir.mkdir(exist_ok=True)
        self.executable(bindir / "rtk", self.RTK_STUB)
        for tool in ("bash", "cat", "sed", "head") + (("jq",) if jq else ()):
            link = bindir / tool
            if not link.exists():
                link.symlink_to(shutil.which(tool))
        return subprocess.run(["/bin/bash", str(ROOT / "claude/.claude/rtk-hook.sh")],
                              env=self.env | {"PATH": str(bindir)}, input=payload,
                              text=True, capture_output=True, timeout=10)

    def test_rtk_wrapper_rewrites_outside_isolated_worktrees(self):
        for jq in (True, False):
            for cwd in ("/home/u/COWORK", "/home/u/COWORK/.claude", "/home/u/repo/.claude/worktreesX",
                        "/home/u/.claude/worktrees-old/repo", "/home/u/repo/worktrees/.claude"):
                with self.subTest(jq=jq, cwd=cwd):
                    payload = self.rtk_payload(cwd)
                    result = self.run_rtk_wrapper(payload, jq)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertTrue(result.stdout.startswith("rtk-called:hook claude\n"), result.stdout)
                    # rtk gets the payload exactly as Claude Code sent it.
                    self.assertEqual(result.stdout.split("\n", 1)[1], payload)

    def test_rtk_wrapper_skips_isolated_worktrees(self):
        for jq in (True, False):
            for cwd in ("/home/u/COWORK/.claude/worktrees/lane", "/home/u/COWORK/.claude/worktrees/lane/sub/dir",
                        "C:\\Users\\u\\COWORK\\.claude\\worktrees\\lane"):
                with self.subTest(jq=jq, cwd=cwd):
                    result = self.run_rtk_wrapper(self.rtk_payload(cwd), jq)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    # No output at all: Claude Code reads that as "no rewrite".
                    self.assertEqual((result.stdout, result.stderr), ("", ""))

    def test_rtk_wrapper_judges_cwd_not_the_command_text(self):
        # A command that merely names a worktree path, run from an ordinary cwd,
        # is still rewritten; an isolated cwd stays untouched whatever the command is.
        for jq in (True, False):
            with self.subTest(jq=jq):
                named = self.run_rtk_wrapper(self.rtk_payload("/home/u/repo", "git -C /a/.claude/worktrees/b status"), jq)
                self.assertTrue(named.stdout.startswith("rtk-called:hook claude"), named.stdout)
                quoted = self.run_rtk_wrapper(self.rtk_payload("/home/u/repo", 'echo "cwd":"/x/.claude/worktrees/y"'), jq)
                self.assertTrue(quoted.stdout.startswith("rtk-called:hook claude"), quoted.stdout)
                isolated = self.run_rtk_wrapper(self.rtk_payload("/home/u/repo/.claude/worktrees/b", "ls"), jq)
                self.assertEqual(isolated.stdout, "")

    def test_rtk_wrapper_fails_toward_the_old_behavior(self):
        # An unreadable payload or a missing cwd is not a worktree: rtk runs as before.
        for payload in ("not json", "{}", '{"cwd": null}', ""):
            for jq in (True, False):
                with self.subTest(payload=payload, jq=jq):
                    result = self.run_rtk_wrapper(payload, jq)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertTrue(result.stdout.startswith("rtk-called:hook claude"), result.stdout)
        # With no rtk anywhere it exits 0 and says nothing.
        bare = self.home / "bare"
        bare.mkdir()
        for tool in ("bash", "cat", "sed", "head"):
            (bare / tool).symlink_to(shutil.which(tool))
        result = subprocess.run(["/bin/bash", str(ROOT / "claude/.claude/rtk-hook.sh")],
                                env=self.env | {"PATH": str(bare)}, input=self.rtk_payload("/home/u/repo"),
                                text=True, capture_output=True, timeout=10)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))

    def test_rtk_settings_hook_goes_through_the_wrapper_when_installed(self):
        command = next(c for c in HOOKS if "rtk hook claude" in c)
        self.assertIn("rtk-hook.sh", command)
        bindir = self.home / "bin"
        bindir.mkdir()
        self.executable(bindir / "rtk", self.RTK_STUB)
        for tool in ("bash", "cat", "sed", "head", "jq"):
            (bindir / tool).symlink_to(shutil.which(tool))
        script = self.home / ".claude/rtk-hook.sh"
        script.parent.mkdir(parents=True)
        script.symlink_to(ROOT / "claude/.claude/rtk-hook.sh")
        run = lambda cwd: subprocess.run(
            ["/bin/bash", "--noprofile", "--norc", "-c", command], env=self.env | {"PATH": str(bindir)},
            input=self.rtk_payload(cwd), text=True, capture_output=True, timeout=10)
        self.assertTrue(run("/home/u/repo").stdout.startswith("rtk-called:hook claude"))
        self.assertEqual(run("/home/u/repo/.claude/worktrees/lane").stdout, "")
        # Without the installed script the hook is the old direct call, worktree or not.
        script.unlink()
        self.assertTrue(run("/home/u/repo/.claude/worktrees/lane").stdout.startswith("rtk-called:hook claude"))

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
        for retired in ("WORKFORCE", "ac-reorient", "remote-session-register"):
            self.assertNotIn(retired, text)
        # Compare against the surviving hook contract, not a second read of
        # the same JSON. Losing another hook must fail this retirement check.
        expected = {
            "startup|clear": ["session-briefing.sh", "post-compact-resume.sh",
                              "handoff-check.sh", "vault-inbox-check.sh",
                              "memory-index.sh", "session-work-init.sh",
                              "seatpool-notice.sh"],
            "resume|compact": ["post-compact-resume.sh", "handoff-check.sh",
                               "session-briefing.sh", "session-work-init.sh",
                               "seatpool-notice.sh"],
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

    def test_seatpool_notice_hook_is_registered_and_never_blocks(self):
        # COWORK's seat pool notice (claude-fleet SETUP SP-4/SP-7): SessionStart (both
        # matchers, asserted above), every prompt and Stop. The script stays silent with no
        # notice and in PERSONAL; a host without it must still exit 0 (the "|| true"), so a
        # missing hook never turns into a blocking exit 2.
        def notice_hooks(event):
            return [hook for group in SETTINGS["hooks"][event] for hook in group["hooks"]
                    if "/seatpool-notice.sh" in hook["command"]]
        for event in ("UserPromptSubmit", "Stop"):
            hooks = notice_hooks(event)
            self.assertEqual(len(hooks), 1, event)
            self.assertTrue(hooks[0]["command"].endswith("|| true"), event)
        for hook in notice_hooks("SessionStart"):
            self.assertTrue(hook["command"].endswith("|| true"))
        result = subprocess.run(["/bin/bash", "-c", notice_hooks("Stop")[0]["command"]],
                                env={"HOME": str(self.home), "PATH": "/usr/bin:/bin"},
                                input="{}", capture_output=True, text=True)
        self.assertEqual((result.returncode, result.stdout), (0, ""))

    def test_claude_md_is_a_public_core_pointer(self):
        # ~/.claude/CLAUDE.md is symlinked from this public repo on every host.
        # It carries one @import of the harness core plus generic defaults;
        # the rules themselves live in the private harness, never here, and
        # the retired injection chain (charter, digest, boot shim) must not
        # come back as prose that claims to ride the system prompt.
        text = (ROOT / "claude/.claude/CLAUDE.md").read_text()
        lines = text.splitlines()
        # A bare import line, not inside backticks or a fence, so Claude Code
        # expands it (docs: code spans and fenced blocks are skipped).
        self.assertIn("@~/COWORK/CONTEXT/core.md", lines)
        self.assertNotIn("```", text)
        self.assertIn("~/OPS/CONTEXT/core.md", text)
        self.assertIn("If the imported file is unavailable", text)
        self.assertIn("not an automatic import", text)
        self.assertLess(len(text.encode()), 2048)
        for retired in ("foreman-charter", "boot-digest", "boot-surface",
                        "operating-doctrine", "working-preferences", "Boot:",
                        "system prompt", "umbrella-operating-model",
                        "Umbrella"):
            self.assertNotIn(retired, text)

    def test_settings_model_pin_and_env_pins(self):
        # Opus 5.5 is the default foreman (ruling 2026-09-22). The haiku alias
        # points at Haiku 5.5, the only Haiku allowed (ruling 2026-10-14); the
        # key never comes out, because Claude Code older than 2.1.293 and the
        # third-party clouds resolve the bare alias to Haiku 4.5.
        self.assertEqual(SETTINGS["model"], "claude-opus-5-5[1m]")
        env = SETTINGS["env"]
        self.assertEqual(env["ANTHROPIC_DEFAULT_OPUS_MODEL"], "claude-opus-5-5[1m]")
        self.assertEqual(env["ANTHROPIC_DEFAULT_SONNET_MODEL"], "claude-sonnet-5-5[1m]")
        self.assertEqual(env["ANTHROPIC_DEFAULT_HAIKU_MODEL"], "claude-haiku-5-5")

    def test_settings_pass_the_ops_model_checks(self):
        # OK on all four, the WARN-only check 14 included: a pin OPS does not
        # name as its foreman means OPS's doctrine is behind, and an ops-port
        # pass is due before this ships.
        self.assertEqual(ops_model_verdicts(SETTINGS), ["ok", "ok", "ok", "ok"])

    # Settings drifts and the verdicts verify-ops.sh gives them, by hand, so
    # the rules above are checked against expectations, not against themselves.
    OPS_MODEL_DRIFTS = {
        "foreman pin retired Opus 4.8": (lambda s: s.update(model="claude-opus-4-8[1m]"),
                                         ["warn", "ok", "fail", "ok"]),
        "foreman pin Opus 5": (lambda s: s.update(model="claude-opus-5[1m]"), ["warn", "fail", "ok", "ok"]),
        "Opus alias on Opus 5": (lambda s: s["env"].update(ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-5"),
                                 ["ok", "fail", "ok", "ok"]),
        "lane pin retired Sonnet 5": (lambda s: s["env"].update(CLAUDE_CODE_SUBAGENT_MODEL="claude-sonnet-5[1m]"),
                                      ["ok", "ok", "fail", "ok"]),
        "Sonnet alias retired": (lambda s: s["env"].update(ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-5"),
                                 ["ok", "ok", "fail", "ok"]),
        "Haiku pin removed": (lambda s: s["env"].pop("ANTHROPIC_DEFAULT_HAIKU_MODEL"), ["ok", "ok", "ok", "fail"]),
        "Haiku pin with a context suffix": (
            lambda s: s["env"].update(ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-haiku-5-5[1m]"),
            ["ok", "ok", "fail", "fail"]),
        "Haiku 4.5 pinned": (lambda s: s["env"].update(ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-haiku-4-5"),
                             ["ok", "ok", "fail", "fail"]),
        "bare haiku alias as the lane model": (lambda s: s["env"].update(CLAUDE_CODE_SUBAGENT_MODEL="haiku"),
                                               ["ok", "ok", "fail", "ok"]),
        "a foreman OPS does not know yet": (lambda s: s.update(model="claude-opus-6[1m]"),
                                            ["warn", "ok", "ok", "ok"]),
        "no top-level pin": (lambda s: s.pop("model"), ["ok", "ok", "ok", "ok"]),
    }

    def drifted(self, mutate):
        settings = json.loads(json.dumps(SETTINGS))
        mutate(settings)
        return settings

    def test_ops_model_rules_reject_each_drift(self):
        for name, (mutate, expected) in self.OPS_MODEL_DRIFTS.items():
            with self.subTest(name):
                self.assertEqual(ops_model_verdicts(self.drifted(mutate)), expected)

    @unittest.skipUnless(os.environ.get("OPS_DIR"),
                         "set OPS_DIR to an OPS checkout to compare these rules with its verify-ops.sh")
    def test_ops_model_rules_match_the_real_verify_ops(self):
        # Runs OPS's own checks 14, 15 and 15b on the shipped settings and on
        # every drift above, in a throwaway HOME with no OPS tree, so only the
        # settings file is judged. Any difference means the rules above are
        # stale: update them from verify-ops.sh.
        gate = Path(os.environ["OPS_DIR"]) / ".claude-config/bin/verify-ops.sh"
        self.assertTrue(gate.is_file(), f"OPS_DIR has no {gate}")
        self.assertTrue(shutil.which("jq", path=self.env["PATH"]), "jq is required to run verify-ops.sh")
        config = self.home / ".claude"
        config.mkdir()
        cases = {"shipped settings": (lambda s: None, ["ok", "ok", "ok", "ok"])} | self.OPS_MODEL_DRIFTS
        for name, (mutate, _) in cases.items():
            with self.subTest(name):
                settings = self.drifted(mutate)
                (config / "settings.json").write_text(json.dumps(settings, indent=2))
                result = subprocess.run(
                    ["/bin/bash", "--noprofile", "--norc", "-c",
                     'source "$1" || exit 90; check_model_policy; check_opus5_ban; check_retired_model_pins',
                     "ops-model-parity", str(gate)],
                    env=self.env, text=True, capture_output=True, timeout=30)
                verdicts = [line.split(":", 1)[0].lower() for line in result.stdout.splitlines()
                            if line.startswith(("OK:", "WARN:", "FAIL:"))]
                self.assertEqual(verdicts, ops_model_verdicts(settings), result.stdout + result.stderr)

    def assert_compaction_policy(self, settings):
        # Auto-compaction is on harness-wide and Haiku 5.5 compacts inside a
        # 100K window (ruling 2026-10-14): Haiku 5.5 bills every rate at 5x
        # once a request's prompt passes 100K tokens. Opus and Sonnet keep
        # their 1M default (compaction near 967K, a backstop under manual
        # compaction at natural breaks). Claude Code 2.1.299 reads two
        # process-wide switches, the env DISABLE_AUTO_COMPACT (DISABLE_COMPACT
        # stops every compaction) and autoCompactEnabled; either one closed
        # turns the per-model window into a no-op. CLAUDE_CODE_AUTO_COMPACT_WINDOW
        # outranks every per-model window, and a top-level autoCompactWindow or
        # another model's entry would move Opus or Sonnet off their 1M window.
        # The value is pinned exactly because Claude Code drops a bad per-model
        # value silently (its 2.1.299 schema catches it) and `claude doctor`
        # does not flag one, while it does flag a non-boolean autoCompactEnabled.
        # DISABLE_AUTO_COMPACT is "0", not absent: a removed key leaves an old
        # "1" in force (a running session keeps it through a settings reload,
        # a `claude` started from it inherits it, and winSetup's merge keeps a
        # key the base no longer has), while "0" overrides all three (scratch
        # runs, 2.1.299). CLAUDE_AUTOCOMPACT_PCT_OVERRIDE lowers every model's
        # threshold to that percent of its window (2.1.300), which could compact
        # a foreman under the 600K point COWORK's pre-compact.sh relies on.
        # idleCompaction is false: Claude Code's idle compaction (server-gated,
        # off today) can compact an idle main thread from 100K, well before the
        # ruled 967K backstop and under that 600K point; false turns it off,
        # true does not force it on (2.1.300 schema).
        env = settings.get("env", {})
        self.assertEqual(env.get("DISABLE_AUTO_COMPACT"), "0")
        for key in ("DISABLE_COMPACT", "CLAUDE_CODE_AUTO_COMPACT_WINDOW", "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE"):
            self.assertNotIn(key, env)
        self.assertIs(settings.get("autoCompactEnabled"), True)
        self.assertIs(settings.get("idleCompaction"), False)
        self.assertNotIn("autoCompactWindow", settings)
        windows = {model: entry["autoCompactWindow"]
                   for model, entry in settings.get("modelSettings", {}).items()
                   if "autoCompactWindow" in entry}
        self.assertEqual(windows, {"claude-haiku-5-5": 100000})
        self.assertIs(type(windows["claude-haiku-5-5"]), int)

    def test_auto_compaction_on_with_a_100k_haiku_window(self):
        self.assert_compaction_policy(SETTINGS)

    def test_auto_compaction_policy_rejects_each_drift(self):
        # Every drift that would leave Haiku 5.5 running past 100K, or move the
        # Opus and Sonnet window, must fail the policy check above.
        def drop(key):
            return lambda s: s.pop(key)
        mutations = {
            "env DISABLE_AUTO_COMPACT back": lambda s: s["env"].update(DISABLE_AUTO_COMPACT="1"),
            "env DISABLE_AUTO_COMPACT removed": lambda s: s["env"].pop("DISABLE_AUTO_COMPACT"),
            "env DISABLE_COMPACT": lambda s: s["env"].update(DISABLE_COMPACT="true"),
            "env window override": lambda s: s["env"].update(CLAUDE_CODE_AUTO_COMPACT_WINDOW="100000"),
            "env threshold percent override": lambda s: s["env"].update(CLAUDE_AUTOCOMPACT_PCT_OVERRIDE="50"),
            "autoCompactEnabled false": lambda s: s.update(autoCompactEnabled=False),
            "autoCompactEnabled as a string": lambda s: s.update(autoCompactEnabled="true"),
            "autoCompactEnabled removed": drop("autoCompactEnabled"),
            "idleCompaction true": lambda s: s.update(idleCompaction=True),
            "idleCompaction removed": drop("idleCompaction"),
            "modelSettings removed": drop("modelSettings"),
            "Haiku window raised": lambda s: s["modelSettings"]["claude-haiku-5-5"].update(autoCompactWindow=200000),
            "Haiku window as a string": lambda s: s["modelSettings"]["claude-haiku-5-5"].update(autoCompactWindow="100000"),
            "Haiku window as a float": lambda s: s["modelSettings"]["claude-haiku-5-5"].update(autoCompactWindow=100000.0),
            "Haiku key misspelled": lambda s: s.update(modelSettings={"claude-haiku-5.5": {"autoCompactWindow": 100000}}),
            "top-level window": lambda s: s.update(autoCompactWindow=1000000),
            "Sonnet window added": lambda s: s["modelSettings"].update({"claude-sonnet-5-5": {"autoCompactWindow": 500000}}),
        }
        for name, mutate in mutations.items():
            with self.subTest(name):
                settings = json.loads(json.dumps(SETTINGS))
                mutate(settings)
                with self.assertRaises(AssertionError):
                    self.assert_compaction_policy(settings)

    def test_guards_fail_closed_and_helpers_fail_open(self):
        # The three PreToolUse guards block the call when they crash, time
        # out or exit with anything but 0 or 2 (onFailure, Claude Code
        # 2.1.295; ruling 2026-10-14). Every other hook must fail open: a
        # broken rtk rewriter or context readout would otherwise block every
        # Bash call or prompt. A misspelled onFailure value makes Claude Code
        # drop the whole settings file, so the value is pinned exactly.
        guards = ('secrets-guard.sh" pre', 'git-guard.sh"', 'review-gate-guard.sh"')
        seen = []
        for event, groups in SETTINGS["hooks"].items():
            for group in groups:
                for hook in group["hooks"]:
                    command = hook.get("command", "").rstrip()
                    is_guard = event == "PreToolUse" and command.endswith(guards)
                    if is_guard:
                        seen.append(command)
                        self.assertEqual(hook.get("onFailure"), "block", command)
                        self.assertEqual(hook.get("timeout"), 30, command)
                    else:
                        self.assertNotIn("onFailure", hook, f"{event}: {command}")
        self.assertEqual(len(seen), 3, seen)

    def test_settings_has_no_subagent_operating_model_hook(self):
        # Subagents load ~/.claude/CLAUDE.md and its core import themselves
        # (Explore and Plan skip it by design), so a SubagentStart injection
        # of the operating model would be a second copy of the core.
        text = (ROOT / "claude/.claude/settings.json").read_text()
        self.assertNotIn("SubagentStart", SETTINGS["hooks"])
        self.assertNotIn("umbrella-operating-model", text)

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
        for name in ("settings.json", "CLAUDE.md", "statusline.sh", "rtk-hook.sh"):
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

    def test_statusline_autocompact_badge(self):
        # Auto-compaction on is the normal state since 2026-10-14, so "AC:on"
        # is the quiet green and "AC:off" the yellow warning. Off is either
        # switch closed: autoCompactEnabled false, or a truthy
        # DISABLE_AUTO_COMPACT or DISABLE_COMPACT in the env the statusline
        # inherits from the session (Claude Code lowercases and trims, then
        # takes 1, true, yes or on).
        green, yellow = "\033[38;5;78m", "\033[38;5;220m"
        config = self.home / ".claude"
        config.mkdir()
        cases = (
            ("Stage-1 settings", {}, {}, "on"),
            ("autoCompactEnabled absent", {"drop": True}, {}, "on"),
            ("autoCompactEnabled false", {"autoCompactEnabled": False}, {}, "off"),
            ("env DISABLE_AUTO_COMPACT 0", {}, {"DISABLE_AUTO_COMPACT": "0"}, "on"),
            ("env DISABLE_AUTO_COMPACT 1", {}, {"DISABLE_AUTO_COMPACT": "1"}, "off"),
            ("env DISABLE_AUTO_COMPACT ' Yes '", {}, {"DISABLE_AUTO_COMPACT": " Yes "}, "off"),
            ("env DISABLE_COMPACT true", {}, {"DISABLE_COMPACT": "true"}, "off"),
            ("env DISABLE_COMPACT 2", {}, {"DISABLE_COMPACT": "2"}, "on"),
        )
        for name, change, env, state in cases:
            with self.subTest(name):
                settings = json.loads(json.dumps(SETTINGS))
                if change.pop("drop", False):
                    settings.pop("autoCompactEnabled")
                settings.update(change)
                (config / "settings.json").write_text(json.dumps(settings))
                base = {k: v for k, v in self.env.items() if k not in ("DISABLE_AUTO_COMPACT", "DISABLE_COMPACT")}
                result = subprocess.run(
                    ["bash", str(ROOT / "claude/.claude/statusline.sh")],
                    env=base | {"CLAUDE_CONFIG_DIR": str(config)} | env, text=True,
                    input=json.dumps({"model": {"display_name": "Opus 5.5"}}),
                    capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                color = green if state == "on" else yellow
                self.assertIn("AC:\033[0m%s%s\033[0m" % (color, state), result.stdout)

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
