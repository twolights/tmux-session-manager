# Contract: `tms install-hooks` subcommand

**Surface**: `bin/tms` subcommand dispatch → `lib/notify.sh:cmd_install_hooks`
**Callers**: User (one-time setup per machine).

## Signature

```text
tms install-hooks [--uninstall] [--dry-run]
```

- `--uninstall`: remove the tms-notify-hook entry from `~/.claude/settings.json`. If no tms entry is present, print a friendly message and exit 0.
- `--dry-run`: print the resulting `settings.json` diff to stdout; make no writes. Exit 0.
- No flags → install.

## Preconditions

- `alerter` is installed (`require_cmd alerter`). If absent, print a one-line install hint (`brew install alerter`) and exit 1.
- `jq` is installed (`require_cmd jq`). Required for safe JSON round-tripping. If absent, same treatment.
- `~/.claude/` exists (Claude Code has been run at least once). If not, print a hint and exit 1.

## Behavior

### Install (no flags)

1. Resolve `TMS_DIR` to an absolute path (same mechanism as `bin/tms:6`).
2. Read `~/.claude/settings.json` (or treat as `{}` if missing).
3. Compute the target entry:
   ```json
   {
     "matcher": "",
     "hooks": [
       { "type": "command", "command": "<TMS_DIR>/bin/tms-notify-hook", "timeout": 10 }
     ]
   }
   ```
4. Inspect `.hooks.Notification` array (creating as needed) and look for any existing entry whose `.hooks[].command` ends with `bin/tms-notify-hook`:
   - Exact match (same absolute path) → idempotent no-op. Print `tms-notify-hook is already installed at <path>.`; exit 0.
   - Path mismatch → replace that entry in place (handles the user moving the checkout). Print `Updated tms-notify-hook path: <old> → <new>`.
   - No existing tms entry → append the new entry to `.hooks.Notification`. Print `Installed tms-notify-hook at <path>.`
5. Write the result back atomically (`jq '...' settings.json > settings.json.tmp && mv settings.json.tmp settings.json`).
6. **Post-install probe** (see §Post-install probe below). This replaces runtime permission-denied detection entirely; the probe is the authoritative check that notifications actually reach the user.

## Post-install probe

After the settings.json write, invoke `alerter --title 'tms' --message 'Notification hook installed. You should see this banner.' --timeout 10` (in a backgrounded subshell so the install command returns even if the user doesn't dismiss the banner) and then print, unconditionally, the following block to stdout:

```text
Installed tms-notify-hook at <path>.

If you saw a macOS banner titled 'tms' just now, notifications are working.
If macOS asked you to allow notifications for 'Terminal' (alerter delivers
under Terminal's bundle for macOS 26+ compatibility — see research.md §6),
click Allow — you're done. If nothing appeared, open:

    System Settings → Notifications → Terminal

and turn notifications on for that entry. Claude Code's Notification hook
will fire banners through the same permission, so this is a one-time setup.

Diagnostic log for any future failures:
    <absolute-path-to>/notifications.log
```

Rationale: `alerter` does not expose a reliable permission-denied exit code on current macOS (banner suppression typically produces exit 0), so runtime detection is unreliable. Catching the most common failure mode (permissions never granted) proactively at install time, plus printing the exact System Settings path in the install output, covers the user-diagnosability gap without any runtime complexity.

The probe is not retried or deduped: it runs exactly once, each time `tms install-hooks` is invoked without `--uninstall` or `--dry-run`. Idempotent re-install (same path already registered) still fires the probe — this lets the user run `tms install-hooks` as a "check my setup" command.

### Uninstall (`--uninstall`)

1. Read `~/.claude/settings.json`. If missing or empty, print `No tms-notify-hook installed.`; exit 0.
2. Filter out entries from `.hooks.Notification[]` where any `.hooks[].command` ends with `bin/tms-notify-hook`.
3. If the filter made no changes, print the same friendly message and exit 0.
4. If `.hooks.Notification` ends up as an empty array, **remove** the `.hooks.Notification` key entirely (do not leave `[]`).
5. Write back atomically as above. Print `Removed tms-notify-hook.`

### Dry run (`--dry-run`)

Apply the same logic but print the diff (`diff -u`) between original and computed result to stdout; do not write.

## Error handling

| Condition | Behavior |
|-----------|----------|
| `settings.json` is not valid JSON | Print `Error: ~/.claude/settings.json is not valid JSON; refusing to modify.`; exit 1. |
| `jq` missing | Exit 1 with install hint. |
| Write fails (disk full, permissions) | Leave `.tmp` in place for user recovery; print `Error: failed to write settings.json; .tmp preserved at <path>.`; exit 1. |
| Unrelated keys in `settings.json` | Preserved byte-for-byte via `jq` round-trip (never overwritten). |

## Non-goals

- Does NOT register any other hooks (Stop, SubagentStop, etc.) — per spec FR-001, only `Notification` is in scope for v1.
- Does NOT manage `alerter` installation; that's the user's responsibility, surfaced via error messages.
- Does NOT migrate project-scoped `.claude/settings.json`; user-global only.

## Manual test mapping

Covered by quickstart.md scenarios QS-1 (install), QS-8 (uninstall), QS-9 (idempotent re-install).
