# migrations/

Run-once migrations for the fleet (omarchy-style). Each box applies every
migration exactly once, then remembers it so re-runs are no-ops. This is how
an already-provisioned box picks up a change that can't be expressed as a
plain config edit — installing a new tool, moving a file, seeding state.

## Naming

`<unix-timestamp>.sh` — e.g. `1755900000.sh`. The timestamp orders them: the
runner applies them oldest-first (lexical sort of the digits). Create one with:

```
lpx add-migration      # or: lpx-add-migration
```

which drops a timestamped, commented template into this directory and prints
its path.

## Contract

Each migration is a shell script the runner executes **once per box** with
`bash`. It must be:

- **Idempotent-safe** — it can be re-run by hand without harm, because a
  migration that fails and is retried, or one that overlaps an earlier change,
  should never corrupt state.
- **Non-interactive** — it may run unattended (from `shellSetup.sh`, cron, or
  a headless provisioning run), so it must not block on a prompt.
- **Honest about failure** — exit non-zero if it did not finish. The runner
  treats a non-zero exit as a failure (see below); a migration that
  half-completes and exits 0 hides a broken box.

## How it runs

`lpx-migrate` (in the `scripts` stow package) walks `migrations/*.sh` in order.
For each one it checks for a marker under
`~/.local/state/lpx/migrations/` — `<filename>` for applied,
`skipped/<filename>` for deliberately skipped. If either exists it moves on.
Otherwise it runs the migration with `bash`:

- success → it writes the applied marker and continues;
- failure on an interactive terminal → it asks `skip and continue? [y/N]`
  (`y` writes a skip marker and continues; `N` stops with exit 1);
- failure with no terminal → it **fails closed** (exit 1) rather than skip
  silently.

`shellSetup.sh` invokes the runner automatically after it syncs with upstream,
unless `LPX_NO_MIGRATE=1` is set (which the `--run` path sets to avoid a
migration that re-invokes `shellSetup.sh` looping back into the runner).
