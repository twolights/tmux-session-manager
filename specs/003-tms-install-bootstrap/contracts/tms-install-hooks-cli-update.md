# Contract Update: `tms install-hooks` migration step

**Surface**: `bin/tms` subcommand dispatch → `lib/notify.sh:cmd_install_hooks` (existing)
**Callers**: User (one-time setup per machine; re-run after pulling feature 003 to migrate the settings.json entry).

This document is a **delta** to `specs/002-claude-notification-hook/contracts/tms-install-hooks-cli.md`. Read that document first; everything documented there continues to hold. The only changes introduced by feature 003 are:

## Change 1: New migration step (Step 0, runs before existing logic)

After the JSON-validity check and before the existing entry-locator logic, `cmd_install_hooks` runs a one-shot migration:

1. Identify any `.hooks.Notification[].hooks[].command` value whose string ends with `bin/tms-notify-hook`.
2. Rewrite each such `.command` to `<TMS_DIR>/bin/tms notify-hook` (note: a single shell-string with one space separating argv[0] from argv[1]).
3. If at least one entry was rewritten, print **exactly one line** to stdout: `Migrated tms-notify-hook entry to tms notify-hook.`
4. The post-migration JSON is what the rest of the install logic operates on. The path-comparison in the existing "is this entry already installed" check now compares against `<TMS_DIR>/bin/tms notify-hook`, NOT `<TMS_DIR>/bin/tms-notify-hook`.

The migration is **idempotent**: a second invocation finds no `bin/tms-notify-hook` suffixes (because the first invocation already migrated them), prints nothing, and continues to the normal install flow. (FR-014 specifies this.)

The migration **runs unconditionally** at the start of every `cmd_install_hooks` invocation (install, dry-run, AND uninstall). This guarantees that a user running `tms install-hooks --uninstall` after pulling feature 003 also migrates the entry first, then uninstalls — so the uninstall correctly identifies and removes the now-migrated entry.

### jq query (reproduced from research.md §7 for self-containment)

```jq
.hooks.Notification = (
  (.hooks.Notification // [])
  | map(
      .hooks |= map(
        if (.command | endswith("bin/tms-notify-hook"))
        then .command = $newcmd
        else .
        end
      )
    )
)
```

Run with `--arg newcmd "<TMS_DIR>/bin/tms notify-hook"`.

## Change 2: Entry-locator endswith match changes

The existing `cmd_install_hooks` finds tms entries by matching `.hooks[].command` ending in `bin/tms-notify-hook`. After this feature, that suffix is replaced by `bin/tms notify-hook` (note the space). Update both the find query and any related path-mismatch detection accordingly. The migration in Change 1 ensures pre-existing entries are rewritten before this match runs.

## Change 3: New entry shape (written by install)

| Field | Old (feature 002) | New (this feature) |
|-------|-------------------|---------------------|
| `.hooks[].command` | `<TMS_DIR>/bin/tms-notify-hook` | `<TMS_DIR>/bin/tms notify-hook` |
| All other fields (`.matcher`, `.hooks[].type`, `.hooks[].timeout`) | unchanged | unchanged |

## Change 4: Probe and post-install diagnostic text

The post-install probe banner (alerter test fire) and its accompanying diagnostic block remain functionally identical. The only edit is the diagnostic text, which now references `<absolute-path-to>/tms notify-hook` instead of the old binary path when describing what got installed.

## Unchanged

Everything else from `specs/002-claude-notification-hook/contracts/tms-install-hooks-cli.md` carries over:

- Preconditions (`require_cmd alerter`, `require_cmd jq`, `~/.claude/` exists).
- Atomic write via `jq '...' > .tmp && mv .tmp settings.json`.
- Idempotency: exact-match install is a no-op; path-mismatch updates in place.
- `--uninstall` filters out tms entries; if `.hooks.Notification` becomes `[]`, the key is deleted.
- `--dry-run` prints a `diff -u` and exits 0 (now diffs against the post-migration JSON, so the diff includes both the migration AND the install change in one view — useful diagnostic).
- Post-install probe behavior (alerter banner + diagnostic block, run once per non-uninstall invocation, not retried or deduped).
- All error-handling rows in the original contract.

## Manual test mapping

Migration scenario covered by quickstart.md QS-14 (post-feature-003 first install-hooks run on a feature-002 settings.json).
