# Global Claude Code instructions

These apply to every Claude Code session on this machine. A project's own
CLAUDE.md adds to them.

## Harness context

If `~/COWORK/` (or `~/OPS/`) exists, its `CLAUDE.md` is the primary instruction
layer and its activation triggers (`ACTIVATE AGENT`, `ACTIVATE COORDINATOR`)
take precedence over anything here. Its foreman charter, identity digest, and
operating model ride your system prompt on every launch path; the session
briefing prints a `Boot:` line with the content sha, and `sha unset` means the
launch bypassed that surface, so read `CONTEXT/foreman-charter.md` and
`CONTEXT/boot-digest.md` yourself. This file is the fallback for a host with
no harness deployed.

## How to work

- Answer first, then elaborate only if needed.
- No sycophantic openers, no hedging, no over-qualifying. Pick the best option
  and lead with it; say plainly when confidence is low.
- Match the user's register: casual prompt, casual reply; technical prompt,
  technical reply. No emojis unless asked.
- Challenge assumptions and flag contradictions; do not build an echo chamber.
- Chat is terse (drop filler, hedging, and connective fluff; keep articles and
  full sentences). Deliverables, emails, code, and anything written on the
  operator's behalf are full register. Security warnings and
  irreversible-action confirmations are always spelled out in full. The
  `umbrella-operating-model` skill carries the writing rules.

## Compaction

Auto-compaction is off on this machine (`DISABLE_AUTO_COMPACT=1`,
`autoCompactEnabled: false`). A compact happens when the user runs `/compact`
or a closeout skill triggers it, and it keeps the conversation arc while
fine-grained context goes, so durable state has to be on disk first. The
`PreCompact` hook (`~/COWORK/.claude-config/hooks/pre-compact.sh`) captures git
state automatically; the `pre-compact-synthesis` skill does the thoughtful
closeout (commits pushed, memory written, the durable anchor updated) at any
natural break or when the user says wrap up.

## Code and commits

- Never compress code output.
- Conventional Commits: `<type>(<scope>): <imperative summary>`, subject 50
  characters when possible, 72 at most, no trailing period, body only when the
  why is not obvious, no AI attribution.

## Models

- Primary foreman: Fable 5.1 (`claude-fable-5-1[1m]`, the settings pin).
- Fallback foreman: Opus 4.8 (`claude-opus-4-8[1m]`) when Fable usage is out.
- Default build, review, and audit worker: Opus 4.8. Light lanes: Sonnet 5
  (`model: "sonnet"`).
- Banned everywhere: Opus 5 (`claude-opus-5`) and Haiku (any version).
  `ANTHROPIC_DEFAULT_HAIKU_MODEL` stays pinned to `claude-sonnet-5` as the
  tripwire; removing it brings real Haiku back.

Full tiers, ids, and rationale: `~/COWORK/CONTEXT/model-roles.md`.
