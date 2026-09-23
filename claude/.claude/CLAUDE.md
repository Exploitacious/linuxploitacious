# Global Claude Code instructions

@~/COWORK/CONTEXT/core.md

The import above is the harness core: one file, loaded into every session and
every subagent that reads this file. If `~/COWORK/` is absent on this host,
read `~/OPS/CONTEXT/core.md` instead (the public template keeps the same
file). With no harness at all, these defaults apply:

- Answer first, then elaborate only if needed. No sycophantic openers, no
  hedging; say plainly when confidence is low.
- Match the user's register: casual prompt, casual reply; technical prompt,
  technical reply. No emojis unless asked.
- Never compress code output.
- Conventional Commits: `<type>(<scope>): <imperative summary>`, subject 72
  characters at most, no trailing period, no AI attribution.
