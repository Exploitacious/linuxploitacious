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
                # No installed tool or harness can escape this fixture.
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

    def test_no_rtk_rewrite_hook(self):
        # The rtk PreToolUse(Bash) rewrite was retired 2026-11-04: it handed the
        # agent compressed or truncated output instead of what the command printed
        # (truncated file reads, a false "no tests" from pytest, `grep -h` read as
        # no matches, git refused in isolated worktree lanes) for a small token
        # saving. Bringing a rewrite hook back is a new decision, not a fix.
        self.assertFalse([c for c in HOOKS if "rtk" in c])
        self.assertFalse((ROOT / "claude/.claude/rtk-hook.sh").exists())

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
        # wip-refresh-nudge: the Planner WIP board is dormant (Alex, 2026-11-07), so its
        # per-prompt refresh nudge is gone with it.
        for retired in ("WORKFORCE", "ac-reorient", "remote-session-register", "wip-refresh-nudge"):
            self.assertNotIn(retired, text)
        # Compare against the surviving hook contract, not a second read of
        # the same JSON. Losing another hook must fail this retirement check.
        expected = {
            "startup|clear": ["session-briefing.sh", "post-compact-resume.sh",
                              "handoff-check.sh", "vault-inbox-check.sh",
                              "memory-index.sh", "memory-digest.sh",
                              "foreman-context.sh", "lane-rules.sh",
                              "session-work-init.sh", "seatpool-notice.sh"],
            "resume|compact": ["post-compact-resume.sh", "handoff-check.sh",
                               "session-briefing.sh", "memory-digest.sh",
                               "foreman-context.sh", "lane-rules.sh",
                               "session-work-init.sh", "seatpool-notice.sh"],
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

    def test_claude_memory_features_stay_off(self):
        # Alex 2026-10-21: "please ensure that all Anthropic Claude Code /
        # Claude Cloud memories are always turned off." autoMemoryEnabled is
        # the only local switch that stops the prompt block, the MEMORY.md
        # load, auto-dream and the server-flagged post-turn extractor together
        # (autoDreamEnabled alone leaves the extractor). A defined falsy
        # CLAUDE_CODE_DISABLE_AUTO_MEMORY ("0", "false") forces the engine ON
        # over the setting, so the key must never appear in env.
        # CLAUDE_CODE_DISABLE_ORG_MEMORY gates only the cloud org-memory store,
        # never the organization instructions (2026-10-22 memory study).
        self.assertIs(SETTINGS["autoMemoryEnabled"], False)
        self.assertIs(SETTINGS["autoDreamEnabled"], False)
        self.assertNotIn("CLAUDE_CODE_DISABLE_AUTO_MEMORY", SETTINGS["env"])
        self.assertEqual(SETTINGS["env"]["CLAUDE_CODE_DISABLE_ORG_MEMORY"], "1")
        # With the engine off the harness digest is the only memory load, so
        # it must fire on every SessionStart source, compaction included.
        groups = {g["matcher"]: [h["command"] for h in g["hooks"]]
                  for g in SETTINGS["hooks"]["SessionStart"]}
        for matcher in ("startup|clear", "resume|compact"):
            self.assertTrue(any("/.claude-config/hooks/memory-digest.sh" in c
                                for c in groups[matcher]), matcher)

    def test_claude_ai_cloud_connectors_stay_off(self):
        # Alex 2026-11-04: "we're never going to use Anthropic Claude 'Cloud'
        # connectors". Every MCP server reaches Claude Code locally through
        # MetaMCP (COWORK .claude-config/mcp-servers.tsv). A claude.ai
        # connector adds a second login path and a second, staler tool
        # inventory beside the local one (the 2026-09-04 ruling). In Claude
        # Code 2.1.318 the setting stops the connector list from being fetched
        # or connected at all; the env var ENABLE_CLAUDEAI_MCP_SERVERS is only
        # a second way to disable, so it stays out of env and this one switch
        # owns the behaviour.
        self.assertIs(SETTINGS["disableClaudeAiConnectors"], True)
        self.assertNotIn("ENABLE_CLAUDEAI_MCP_SERVERS", SETTINGS["env"])

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

    def test_disk_alert_hook_is_registered_and_never_blocks(self):
        # COWORK's disk alert (Alex, 2026-10-28): a Stop hook that tells the session when the
        # shared disk passes 85% and 95%. It must be one Stop entry with a short timeout, and a
        # host without the hook must still exit 0 (the "|| true").
        hooks = [hook for group in SETTINGS["hooks"]["Stop"] for hook in group["hooks"]
                 if "/disk-alert.sh" in hook["command"]]
        self.assertEqual(len(hooks), 1)
        self.assertTrue(hooks[0]["command"].endswith("|| true"))
        self.assertLessEqual(hooks[0].get("timeout", 600), 10)
        result = subprocess.run(["/bin/bash", "-c", hooks[0]["command"]],
                                env={"HOME": str(self.home), "PATH": "/usr/bin:/bin"},
                                input="{}", capture_output=True, text=True)
        self.assertEqual((result.returncode, result.stdout), (0, ""))

    # The hooks the harness lanes added on 2026-11-07, and where each one must be
    # registered: (event, matcher) pairs. Each script lives in the harness, not here, and
    # prints nothing when it has nothing to say. askuser-cancel.sh is also on
    # PostToolUseFailure: a declined question may reach Claude Code as a failed tool call
    # rather than a completed one, and the script reads whichever event arrives.
    LANE_HOOKS = {
        "lane-rules.sh": {("SubagentStart", ".*"), ("SessionStart", "startup|clear"),
                          ("SessionStart", "resume|compact")},
        "foreman-context.sh": {("SessionStart", "startup|clear"), ("SessionStart", "resume|compact")},
        "report-lint.sh": {("Stop", ".*")},
        "askuser-cancel.sh": {("PostToolUse", "AskUserQuestion"), ("PostToolUseFailure", "AskUserQuestion")},
        "memory-hint.sh": {("UserPromptSubmit", ".*")},
    }

    def registrations(self, script):
        return [(event, group["matcher"], hook) for event, groups in SETTINGS["hooks"].items()
                for group in groups for hook in group["hooks"]
                if f"/.claude-config/hooks/{script}" in hook["command"]]

    def test_lane_hooks_are_registered_where_the_harness_expects_them(self):
        for script, expected in self.LANE_HOOKS.items():
            with self.subTest(script=script):
                found = self.registrations(script)
                self.assertEqual({(event, matcher) for event, matcher, _ in found}, expected)
                # One entry per (event, matcher): a duplicate would run the hook twice.
                self.assertEqual(len(found), len(expected))

    def test_lane_hooks_use_the_guarded_pattern_and_fail_open(self):
        prefix = 'H="$HOME/COWORK"; [ -d "$H" ] || H="$HOME/OPS"; test -x "$H/.claude-config/hooks/'
        for script in self.LANE_HOOKS:
            for event, _, hook in self.registrations(script):
                with self.subTest(script=script, event=event):
                    command = hook["command"]
                    self.assertTrue(command.startswith(prefix + script), command)
                    self.assertTrue(command.endswith("2>/dev/null || true"), command)
                    # Every one gets a short timeout: a slow or hung hook must not hold a
                    # session (prompt-time hooks are held to the same 5 s as skill-hint).
                    self.assertLessEqual(hook.get("timeout", 600), 10, command)
                    self.assertNotIn("onFailure", hook)
                    # Stop and the prompt hooks speak through stdout JSON: the guard's
                    # `|| true` turns any exit code, a blocking exit 2 included, into 0.
                    for harness in ("COWORK", "OPS"):
                        target = self.home / harness / ".claude-config/hooks" / script
                        self.executable(target, "cat; exit 2")
                        result = self.shell(command)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(result.stdout, "{}")  # the hook's stdin reached the script
                        shutil.rmtree(self.home / harness)
                    result = self.shell(command, PATH=str(self.home))
                    self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))

    def test_prompt_time_lane_hooks_have_the_skill_hint_timeout(self):
        skill_hint = next(h for _, _, h in self.registrations("skill-hint.sh"))
        for _, _, hook in self.registrations("memory-hint.sh"):
            self.assertLessEqual(hook["timeout"], skill_hint["timeout"])

    def test_skill_hint_context_watch_and_guards_keep_their_registrations(self):
        # The lane hooks were added beside these, not instead of them.
        self.assertEqual({(e, m) for e, m, _ in self.registrations("skill-hint.sh")},
                         {("UserPromptSubmit", ".*")})
        self.assertEqual({(e, m) for e, m, _ in self.registrations("context-watch.sh")},
                         {("PostToolUse", ".*"), ("Stop", ".*"), ("UserPromptSubmit", ".*")})
        for guard in ("secrets-guard.sh", "git-guard.sh", "review-gate-guard.sh"):
            self.assertTrue(any(e == "PreToolUse" for e, _, _ in self.registrations(guard)), guard)

    def test_poppler_is_installed_on_every_package_family(self):
        # Claude Code's Read tool renders a PDF through pdftoppm, and agents call
        # pdftotext: poppler is a base package, not something each box adds by hand.
        text = (ROOT / "shellSetup.sh").read_text()
        for name, package in (("DEBIAN_PKGS", "poppler-utils"), ("ARCH_PKGS", "poppler"),
                              ("FEDORA_PKGS", "poppler-utils")):
            with self.subTest(family=name):
                line = re.search(rf"local {name}=\((.*)\)", text)[1].split()
                self.assertIn(package, line)
        omarchy = (ROOT / "omarchy/omarchySetup.sh").read_text()
        self.assertIn("poppler", re.search(r"^PKGS=\((.*)\)$", omarchy, re.M)[1].split())

    # ----- pyenv: the global list keeps the Python that holds the pip tools -----

    def pyenv_binary(self):
        found = shutil.which("pyenv") or str(Path.home() / ".pyenv/bin/pyenv")
        return found if os.access(found, os.X_OK) else None

    def pyenv_root(self, versions):
        """A throwaway PYENV_ROOT with fake installed versions: {version: [commands]}."""
        root = Path(self.temp.name) / "pyenv"
        for version, commands in versions.items():
            bin_dir = root / "versions" / version / "bin"
            bin_dir.mkdir(parents=True)
            for command in commands:
                self.executable(bin_dir / command, "exit 0")
        return root

    def pyenv_env(self, root):
        link_dir = Path(self.temp.name) / "pyenv-path"
        link_dir.mkdir(exist_ok=True)
        if not (link_dir / "pyenv").exists():
            (link_dir / "pyenv").symlink_to(self.pyenv_binary())
        return {"PYENV_ROOT": str(root), "PATH": f"{link_dir}:/usr/bin:/bin"}

    def pyenv_global(self, env):
        return subprocess.run(["pyenv", "global"], env=self.env | env, capture_output=True,
                              text=True).stdout.split()

    @unittest.skipUnless(shutil.which("pyenv") or (Path.home() / ".pyenv/bin/pyenv").exists(),
                         "pyenv is not installed")
    def test_pyenv_set_global_keeps_the_previous_default_after_the_latest(self):
        function = "  pyenv_set_global() {" + section(
            "shellSetup.sh", "  pyenv_set_global() {", "  install_python_env() {")
        root = self.pyenv_root({"3.14.5": ["python"], "3.14.7": ["python", "ruff"], "3.13.9": ["python"]})
        env = self.pyenv_env(root)
        run = lambda version: self.shell(function + f'\npyenv_set_global {version}\n', **env)
        subprocess.run(["pyenv", "global", "3.14.5"], env=self.env | env, check=True)
        # The defect: ruff lives in 3.14.7 and the global list names only 3.14.5.
        self.assertNotEqual(subprocess.run(["pyenv", "which", "ruff"], env=self.env | env,
                                           capture_output=True).returncode, 0)
        result = run("3.14.7")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.pyenv_global(env), ["3.14.7", "3.14.5"])
        self.assertEqual(subprocess.run(["pyenv", "which", "ruff"], env=self.env | env,
                                        capture_output=True).returncode, 0)
        # Idempotent, and the list never grows past three entries.
        run("3.14.7")
        self.assertEqual(self.pyenv_global(env), ["3.14.7", "3.14.5"])
        run("3.13.9")
        self.assertEqual(self.pyenv_global(env), ["3.13.9", "3.14.7", "3.14.5"])
        (root / "version").write_text("3.14.7\n3.14.5\n3.13.9\n")
        run("3.14.7")
        self.assertEqual(self.pyenv_global(env), ["3.14.7", "3.14.5", "3.13.9"])
        # A version that is no longer installed is dropped, not passed to pyenv global.
        (root / "version").write_text("3.14.5\n2.7.18\n")
        result = run("3.14.7")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.pyenv_global(env), ["3.14.7", "3.14.5"])
        # A box on `system` Python moves to the new pyenv default; `system` is not carried.
        (root / "version").write_text("system\n")
        run("3.14.7")
        self.assertEqual(self.pyenv_global(env), ["3.14.7"])

    def test_python_step_sets_the_global_through_the_helper_and_installs_uv(self):
        step = section("shellSetup.sh", "  install_python_env() {", "  # --- AI CLI TOOLS")
        self.assertIn('pyenv_set_global "$LATEST_PY"', step)
        self.assertNotIn('pyenv global "$LATEST_PY"', step)
        # uv comes from the vendor installer without editing rc files, and success is
        # judged by the binary: the pipeline's own status is sh's.
        self.assertIn("UV_NO_MODIFY_PATH=1", step)
        self.assertIn('[ -x "$HOME/.local/bin/uv" ]', step)

    # ----- migrations for boxes provisioned before these changes -----

    def migration(self, name_part):
        """The one migration script whose header comment starts with `# Migration: <name_part>`."""
        found = [p for p in sorted((ROOT / "migrations").glob("*.sh"))
                 if p.read_text().splitlines()[1].startswith("# Migration: " + name_part)]
        self.assertEqual(len(found), 1, name_part)
        return found[0]

    def stub_bin(self, **commands):
        """A PATH directory holding only the coreutils a migration needs plus the given stubs."""
        bin_dir = Path(self.temp.name) / "stub-bin"
        shutil.rmtree(bin_dir, ignore_errors=True)
        bin_dir.mkdir()
        for tool in ("id", "sh", "env", "cat", "mkdir", "mv", "install", "cmp", "readlink", "dirname",
                     "date", "touch", "chmod", "grep", "sort", "tr", "ln", "bash"):
            real = shutil.which(tool, path="/usr/bin:/bin")
            if real:
                (bin_dir / tool).symlink_to(real)
        for name, body in commands.items():
            self.executable(bin_dir / name, body)
        return bin_dir

    def run_migration(self, script, bin_dir, tty=False):
        return subprocess.run(["/bin/bash", str(script)], env=self.env | {"PATH": str(bin_dir)},
                              input="", text=True, capture_output=True, timeout=30)

    FAKE_PACKAGE_MANAGER = (  # an install (apt-get/dnf install, pacman -S) drops the poppler commands
        'echo "$0 $*" >> "$HOME/calls"\n'
        'case "$*" in *install*|*-S*) for c in pdftotext pdftoppm; do '
        'printf "#!/bin/sh\\nexit 0\\n" > "$(dirname "$0")/$c"; chmod +x "$(dirname "$0")/$c"; done;; esac'
    )
    FAKE_UV_INSTALLER = (  # curl prints an installer script that puts uv in ~/.local/bin
        "echo \"curl $*\" >> \"$HOME/calls\"\n"
        "echo 'mkdir -p \"$HOME/.local/bin\"; echo \"UV_NO_MODIFY_PATH=$UV_NO_MODIFY_PATH\" >> \"$HOME/calls\"; "
        "printf \"#!/bin/sh\\nexit 0\\n\" > \"$HOME/.local/bin/uv\"; chmod +x \"$HOME/.local/bin/uv\"'"
    )

    def test_poppler_uv_migration_installs_both_and_is_idempotent(self):
        script = self.migration("poppler and uv")
        bin_dir = self.stub_bin(sudo='echo "sudo $*" >> "$HOME/calls"\n[ "$1" = -n ] && exit 0\nexec "$@"',
                                **{"apt-get": self.FAKE_PACKAGE_MANAGER, "curl": self.FAKE_UV_INSTALLER})
        result = self.run_migration(script, bin_dir)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = (self.home / "calls").read_text()
        self.assertIn("apt-get install -y poppler-utils", calls)
        self.assertIn("astral.sh/uv/install.sh", calls)
        self.assertIn("UV_NO_MODIFY_PATH=1", calls)  # the installer must not edit the rc files
        self.assertTrue((self.home / ".local/bin/uv").exists())
        self.assertIn("poppler installed", result.stdout)
        # Second run: everything is present, nothing is called again.
        (self.home / "calls").unlink()
        again = self.run_migration(script, bin_dir)
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertFalse((self.home / "calls").exists())

    def test_poppler_uv_migration_supports_pacman_and_dnf(self):
        script = self.migration("poppler and uv")
        for manager, expected in (("pacman", "pacman -S --noconfirm --needed poppler"),
                                  ("dnf", "dnf install -y poppler-utils")):
            with self.subTest(manager=manager):
                (self.home / "calls").unlink(missing_ok=True)
                shutil.rmtree(self.home / ".local", ignore_errors=True)
                bin_dir = self.stub_bin(sudo='[ "$1" = -n ] && exit 0\nexec "$@"',
                                        **{manager: self.FAKE_PACKAGE_MANAGER, "curl": self.FAKE_UV_INSTALLER})
                result = self.run_migration(script, bin_dir)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(expected, (self.home / "calls").read_text())

    def test_poppler_uv_migration_fails_closed_but_still_tries_uv(self):
        script = self.migration("poppler and uv")
        # No sudo password available and no terminal: fail instead of waiting on a prompt.
        bin_dir = self.stub_bin(sudo='exit 1', **{"apt-get": self.FAKE_PACKAGE_MANAGER,
                                                  "curl": self.FAKE_UV_INSTALLER})
        result = self.run_migration(script, bin_dir)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no terminal to ask on", result.stderr)
        self.assertNotIn("apt-get", (self.home / "calls").read_text())
        self.assertTrue((self.home / ".local/bin/uv").exists())  # uv was attempted anyway
        # No package manager at all.
        shutil.rmtree(self.home / ".local")
        bin_dir = self.stub_bin(sudo='[ "$1" = -n ] && exit 0\nexec "$@"', curl=self.FAKE_UV_INSTALLER)
        result = self.run_migration(script, bin_dir)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no supported package manager", result.stderr)
        # A package manager that "succeeds" without leaving the commands behind.
        bin_dir = self.stub_bin(sudo='[ "$1" = -n ] && exit 0\nexec "$@"',
                                **{"apt-get": "exit 0", "curl": self.FAKE_UV_INSTALLER})
        result = self.run_migration(script, bin_dir)
        self.assertEqual(result.returncode, 1)
        self.assertIn("still not on PATH", result.stderr)

    def test_poppler_uv_migration_does_not_trust_a_failed_uv_download(self):
        script = self.migration("poppler and uv")
        bin_dir = self.stub_bin(sudo='[ "$1" = -n ] && exit 0\nexec "$@"',
                                **{"apt-get": self.FAKE_PACKAGE_MANAGER, "curl": "exit 22"})
        result = self.run_migration(script, bin_dir)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("did not leave ~/.local/bin/uv", result.stderr)

    @unittest.skipUnless(shutil.which("pyenv") or (Path.home() / ".pyenv/bin/pyenv").exists(),
                         "pyenv is not installed")
    def test_pyenv_tools_migration_appends_the_version_that_holds_a_dangling_tool(self):
        script = self.migration("keep the pyenv shims")
        root = self.pyenv_root({"3.14.5": ["python"], "3.14.7": ["python", "ruff", "black"],
                                "3.13.9": ["python", "pytest"]})
        env = self.pyenv_env(root)
        subprocess.run(["pyenv", "global", "3.14.5"], env=self.env | env, check=True)
        subprocess.run(["pyenv", "rehash"], env=self.env | env, check=True)

        def run():
            return subprocess.run(["/bin/bash", str(script)], env=self.env | env, input="", text=True,
                                  capture_output=True, timeout=60)
        result = run()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # The default stays first; the versions that hold ruff/black and pytest follow it.
        self.assertEqual(self.pyenv_global(env), ["3.14.5", "3.14.7", "3.13.9"])
        for tool in ("ruff", "black", "pytest"):
            self.assertEqual(subprocess.run(["pyenv", "which", tool], env=self.env | env,
                                            capture_output=True).returncode, 0, tool)
        # Idempotent.
        self.assertIn("pyenv global: 3.14.5 3.14.7 3.13.9", run().stdout)
        self.assertEqual(self.pyenv_global(env), ["3.14.5", "3.14.7", "3.13.9"])
        # `system` stays the first entry when that is what the box uses (whether a tool such
        # as pytest also exists on the host PATH does not matter here, only ruff's version).
        (root / "version").write_text("system\n")
        run()
        resolved = self.pyenv_global(env)
        self.assertEqual(resolved[0], "system")
        self.assertIn("3.14.7", resolved)

    @unittest.skipUnless(shutil.which("pyenv") or (Path.home() / ".pyenv/bin/pyenv").exists(),
                         "pyenv is not installed")
    def test_pyenv_tools_migration_keeps_a_stale_list_and_skips_env_names(self):
        script = self.migration("keep the pyenv shims")
        # 3dtool is a pyenv-virtualenv style name that starts with a digit: not a version.
        root = self.pyenv_root({"3.14.5": ["python"], "3.14.7": ["python", "ruff"],
                                "3dtool": ["python", "black"]})
        env = self.pyenv_env(root)
        run = lambda: subprocess.run(["/bin/bash", str(script)], env=self.env | env, input="",
                                     text=True, capture_output=True, timeout=60)
        # A global list naming an uninstalled version: never dropped, never blocks the run.
        (root / "version").write_text("3.14.5\n3.9.99\n")
        result = run()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("3.9.99, which is not installed", result.stderr)
        self.assertEqual((root / "version").read_text(), "3.14.5\n3.9.99\n")
        # With a clean list, ruff's version is appended and the env name never is.
        (root / "version").write_text("3.14.5\n")
        subprocess.run(["pyenv", "rehash"], env=self.env | env, check=True)
        result = run()
        self.assertNotIn("3dtool", self.pyenv_global(env))
        self.assertEqual(self.pyenv_global(env), ["3.14.5", "3.14.7"])

    def test_poppler_migration_runs_after_the_unprivileged_ones(self):
        # lpx-migrate stops at the first failure, and the poppler step fails on a headless box
        # with no passwordless sudo: it must not hold back the pyenv and drop-in migrations.
        poppler = int(self.migration("poppler and uv").stem)
        for other in ("keep the pyenv shims", "OOMPolicy=continue"):
            with self.subTest(other=other):
                self.assertGreater(poppler, int(self.migration(other).stem))

    def test_pyenv_tools_migration_does_nothing_without_pyenv(self):
        script = self.migration("keep the pyenv shims")
        bin_dir = self.stub_bin()
        result = self.run_migration(script, bin_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("nothing to do", result.stdout)

    def scope_drop_in(self):
        return ROOT / "systemd/.config/systemd/user/t3code-claude-.scope.d/oom-continue.conf"

    def test_t3_scope_drop_in_sets_oom_policy_continue(self):
        # A prefix drop-in: systemd merges it into every t3code-claude-<id>.scope. The
        # default for a scope is OOMPolicy=stop, which fails the whole thread when the
        # kernel kills one child. Proved end to end on a live box 2026-11-07: a scope
        # started with -p OOMPolicy=stop, a 1 GiB allocation under MemoryMax=512M, scope
        # still active with this file present and failed with oom-kill without it.
        lines = [line for line in self.scope_drop_in().read_text().splitlines()
                 if line.strip() and not line.startswith("#")]
        self.assertEqual(lines, ["[Scope]", "OOMPolicy=continue"])
        self.assertEqual(self.scope_drop_in().parent.name, "t3code-claude-.scope.d")

    @unittest.skipUnless(shutil.which("stow"), "GNU Stow is not installed")
    def test_t3_scope_drop_in_stows_into_the_user_unit_directory(self):
        # deploy_stow pre-creates the parent directories (ensure_target_dirs), so only the
        # files are linked, and herdr@.service keeps working beside the drop-in.
        unit_dir = self.home / ".config/systemd/user"
        (unit_dir / "t3code-claude-.scope.d").mkdir(parents=True)
        subprocess.run(["stow", "-d", str(ROOT), "-t", str(self.home), "systemd"], check=True)
        link = unit_dir / "t3code-claude-.scope.d/oom-continue.conf"
        self.assertEqual(link.resolve(), self.scope_drop_in())
        self.assertEqual((unit_dir / "herdr@.service").resolve().name, "herdr@.service")

    def test_t3_scope_migration_installs_the_drop_in_once_and_keeps_stow_links(self):
        script = self.migration("OOMPolicy=continue")
        reload_log = self.home / "systemctl.log"
        bin_dir = self.stub_bin(systemctl=f'echo "$*" >> "{reload_log}"')
        dest = self.home / ".config/systemd/user/t3code-claude-.scope.d/oom-continue.conf"
        result = self.run_migration(script, bin_dir)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(dest.read_text(), self.scope_drop_in().read_text())
        self.assertFalse(dest.is_symlink())  # a copy: stow owns only the links it made
        self.assertEqual(reload_log.read_text().strip(), "--user daemon-reload")
        self.assertIn("installed", result.stdout)
        self.assertIn("already in place", self.run_migration(script, bin_dir).stdout)
        # A different file (the hand-made one) is kept under a backup name, then replaced.
        dest.write_text("[Scope]\nOOMPolicy=stop\n")
        result = self.run_migration(script, bin_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(dest.read_text(), self.scope_drop_in().read_text())
        backups = list(dest.parent.glob("oom-continue.conf.backup_*"))
        self.assertEqual([b.read_text() for b in backups], ["[Scope]\nOOMPolicy=stop\n"])
        # A stow link to the repo file is left alone.
        dest.unlink()
        dest.symlink_to(self.scope_drop_in())
        result = self.run_migration(script, bin_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(dest.is_symlink())
        self.assertIn("already linked", result.stdout)

    def test_t3_scope_migration_survives_a_box_with_no_user_manager(self):
        script = self.migration("OOMPolicy=continue")
        bin_dir = self.stub_bin(systemctl="exit 1")
        result = self.run_migration(script, bin_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("daemon-reload did not run", result.stdout)
        # And with no systemctl at all.
        result = self.run_migration(script, self.stub_bin())
        self.assertEqual(result.returncode, 0, result.stderr)

    # ----- msg-read: the sanctioned .msg reader -----

    MSG_READ = ROOT / "scripts/.local/bin/msg-read"
    STUB_EXTRACT_MSG = '''
class Attachment:
    def __init__(self, name, data):
        self.name, self.data = name, data
    def getFilename(self):
        return self.name
    def save(self, customPath=None, customFilename=None):
        with open(customPath + "/" + customFilename, "w") as handle:
            handle.write("embedded message")

class Message:
    sender = "Sender Name <sender@example.test>"
    to = "Recipient <to@example.test>"
    cc = ""
    date = "2026-01-02 03:04:05"
    subject = "Quarterly report"
    body = ""
    htmlBody = (b"<html><head><style>p{color:red}</style></head><body><p>Hello <b>there</b></p>"
                b"<script>var x = 1;</script><div>second line</div></body></html>")
    attachments = [Attachment("../escape.txt", b"one"), Attachment("report.pdf", b"%PDF-1"),
                   Attachment("report.pdf", b"%PDF-2"), Attachment("", b"zz"),
                   Attachment("inner.eml", object())]
    def close(self):
        pass

def openMsg(path):
    if path.endswith("broken.msg"):
        raise ValueError("not an OLE file")
    return Message()
'''

    def msg_read(self, *args, with_uv=True, stub=None):
        stubs = Path(self.temp.name) / "msg-stub"
        shutil.rmtree(stubs, ignore_errors=True)
        stubs.mkdir()
        (stubs / "extract_msg.py").write_text(stub or self.STUB_EXTRACT_MSG)
        bin_dir = Path(self.temp.name) / "msg-bin"
        shutil.rmtree(bin_dir, ignore_errors=True)
        bin_dir.mkdir()
        if with_uv:  # runs the helper the way `uv run ... python - args` would, with the stub module
            self.executable(bin_dir / "uv",
                            'echo "$*" > "$HOME/uv-args"\nwhile [ "$1" != python ]; do shift; done\nshift\n'
                            'exec python3 "$@"')
        return subprocess.run(["bash", str(self.MSG_READ), *map(str, args)], text=True, capture_output=True,
                              timeout=30, env=self.env | {"PATH": f"{bin_dir}:/usr/bin:/bin",
                                                          "PYTHONPATH": str(stubs)})

    def test_msg_read_prints_headers_attachments_and_a_text_body(self):
        result = self.msg_read("mail.msg")
        self.assertEqual(result.returncode, 0, result.stderr)
        out = result.stdout
        self.assertIn("From: Sender Name <sender@example.test>", out)
        self.assertIn("Subject: Quarterly report", out)
        self.assertNotIn("Cc:", out)  # an empty header is not printed
        self.assertIn("Attachments (5):", out)
        self.assertIn("1. ../escape.txt (3 bytes)", out)
        self.assertIn("5. inner.eml (embedded message)", out)
        body = out.split("--- body ---", 1)[1]
        self.assertIn("Hello there", body)  # HTML turned into text when there is no plain body
        self.assertIn("second line", body)
        self.assertNotIn("var x", body)
        self.assertNotIn("color:red", body)
        # extract-msg is requested through uv with a floor and a ceiling, outside any project.
        uv_args = (self.home / "uv-args").read_text()
        for part in ("run", "--no-project", "--with", "extract-msg>=0.55,<1", "python"):
            self.assertIn(part, uv_args)

    def test_msg_read_saves_attachments_without_escaping_or_overwriting(self):
        out = self.home / "saved"
        result = self.msg_read("-o", out, "mail.msg")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(p.name for p in out.iterdir()),
                         ["attachment-4", "escape.txt", "inner.eml.msg", "report-2.pdf", "report.pdf"])
        self.assertFalse((self.home / "escape.txt").exists())  # `../escape.txt` stayed inside -o
        self.assertEqual((out / "report.pdf").read_bytes(), b"%PDF-1")
        self.assertEqual((out / "report-2.pdf").read_bytes(), b"%PDF-2")
        self.assertEqual((out / "inner.eml.msg").read_text(), "embedded message")
        self.assertIn(f"-> {out}/report-2.pdf", result.stdout)
        # Run again: the existing files are not overwritten, they get new suffixes.
        self.msg_read("-o", out, "mail.msg")
        self.assertEqual((out / "report.pdf").read_bytes(), b"%PDF-1")
        self.assertTrue((out / "report-3.pdf").exists())

    def test_msg_read_reports_each_bad_file_and_keeps_going(self):
        result = self.msg_read("broken.msg", "notes.txt", "mail.msg")
        self.assertEqual(result.returncode, 1)
        self.assertIn("broken.msg: ValueError: not an OLE file", result.stderr)
        self.assertIn("notes.txt: not a .msg file", result.stderr)
        self.assertIn("=== mail.msg ===", result.stdout)  # a banner when there is more than one file
        self.assertIn("Subject: Quarterly report", result.stdout)

    def test_msg_read_usage_and_missing_uv(self):
        self.assertEqual(self.msg_read().returncode, 2)
        self.assertEqual(self.msg_read("-x", "mail.msg").returncode, 2)
        self.assertEqual(self.msg_read("-o").returncode, 2)
        if shutil.which("uv", path="/usr/bin:/bin"):
            self.skipTest("uv is installed system-wide")
        result = self.msg_read("mail.msg", with_uv=False)
        self.assertEqual(result.returncode, 127)
        self.assertIn("astral.sh/uv/install.sh", result.stderr)

    # ----- zsh -c behaves like bash for the two habits that fail as zsh errors -----

    ZSHENV = ROOT / "zsh/.zshenv"

    def zsh(self, *args, home=None):
        return subprocess.run(["zsh", *args], capture_output=True, text=True, timeout=10,
                              env={"HOME": str(home or self.home), "PATH": "/usr/bin:/bin",
                                   "LC_ALL": "C.UTF-8"})

    @unittest.skipUnless(shutil.which("zsh"), "zsh is not installed")
    def test_zshenv_makes_zsh_dash_c_tolerate_bash_globs_and_equals_words(self):
        # Agent tools run `zsh -lc '<command>'` on a box whose login shell is zsh, and
        # Codex cannot be pointed at another shell (checked on Codex 0.167). `ls *.log`
        # with no match was "zsh: no matches found" and `echo =x` an expansion error.
        shutil.copy(self.ZSHENV, self.home / ".zshenv")
        for flags in ("-c", "-lc"):
            with self.subTest(flags=flags):
                result = self.zsh(flags, "echo *.nomatch-here; echo =nosuchword; echo status=$?")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "*.nomatch-here\n=nosuchword\nstatus=0\n")
                self.assertEqual(result.stderr, "")
        # The PATH entry the file existed for is still added.
        result = self.zsh("-c", "echo $PATH")
        self.assertIn(f"{self.home}/.local/bin", result.stdout)

    @unittest.skipUnless(shutil.which("zsh"), "zsh is not installed")
    def test_zshenv_leaves_scripts_and_interactive_shells_on_zsh_defaults(self):
        shutil.copy(self.ZSHENV, self.home / ".zshenv")
        script = self.home / "task.zsh"
        script.write_text("echo *.nomatch-here\n")
        result = self.zsh(str(script))
        self.assertNotEqual(result.returncode, 0)  # zsh still stops on an unmatched glob in a script
        self.assertIn("no matches found", result.stderr)
        # An interactive shell has no -c command string either.
        result = subprocess.run(["zsh", "-i"], input="echo *.nomatch-here\nexit\n", capture_output=True,
                                text=True, timeout=10, env={"HOME": str(self.home), "PATH": "/usr/bin:/bin"})
        self.assertIn("no matches found", result.stderr)

    def test_readme_lists_every_migration_and_only_real_ones(self):
        readme = (ROOT / "README.md").read_text()
        listed = set(re.findall(r"`(\d{10}\.sh)`", readme))
        shipped = {path.name for path in (ROOT / "migrations").glob("*.sh")}
        self.assertEqual(listed, shipped)

    def test_python_bytecode_is_not_written(self):
        # Alex, 2026-10-28: lanes left 13.7 GB of __pycache__ across the project checkouts on
        # t3cowork. Every Claude session and its Bash commands inherit this env.
        self.assertEqual(SETTINGS["env"]["PYTHONDONTWRITEBYTECODE"], "1")

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
        # broken helper or context readout would otherwise block every
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
        # of the operating model would be a second copy of the core. The one
        # SubagentStart hook is the short lane-rules block (lane-rules.sh): the
        # shell rules a lane needs and a brief does not carry, not the core.
        text = (ROOT / "claude/.claude/settings.json").read_text()
        self.assertNotIn("umbrella-operating-model", text)
        commands = [h["command"] for g in SETTINGS["hooks"]["SubagentStart"] for h in g["hooks"]]
        self.assertEqual(len(commands), 1, commands)
        self.assertIn("/.claude-config/hooks/lane-rules.sh", commands[0])

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

    def plant_stale_links(self):
        config = self.home / ".claude"
        config.mkdir(exist_ok=True)
        ours = config / "rtk-hook.sh"
        ours.symlink_to(ROOT / "claude/.claude/rtk-hook.sh")
        foreign = config / "foreign.sh"
        foreign.symlink_to(self.home / "elsewhere/missing.sh")
        return config, ours, foreign

    def assert_stale_links_pruned(self, config, ours, foreign):
        # Only a dangling link into claude/.claude goes; a dangling link that
        # points anywhere else is someone else's and stays.
        self.assertFalse(os.path.lexists(ours))
        self.assertTrue(os.path.lexists(foreign))
        for name in ("settings.json", "CLAUDE.md", "statusline.sh"):
            self.assertEqual((config / name).resolve(), ROOT / "claude/.claude" / name)

    def test_linux_claude_config_prunes_its_own_dangling_links(self):
        config, ours, foreign = self.plant_stale_links()
        function = "deploy_claude_config() {" + section(
            "shellSetup.sh", "deploy_claude_config() {", "  # --- CLAUDE CODE PLUGINS")
        result = self.shell(MESSAGES + function + "\ndeploy_claude_config\n", REPO_DIR=str(ROOT))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Removed stale link", result.stdout)
        self.assert_stale_links_pruned(config, ours, foreign)

    def test_omarchy_stage1_prunes_its_own_dangling_links(self):
        config, ours, foreign = self.plant_stale_links()
        result = self.stage1_files()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_stale_links_pruned(config, ours, foreign)

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
