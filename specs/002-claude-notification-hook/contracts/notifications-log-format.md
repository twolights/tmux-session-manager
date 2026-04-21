# Contract: notifications.log file format

**Surface**: `${TMS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tmux-session-manager}/notifications.log`
**Callers**: `lib/notify.sh:notify_log_failure` (write), `lib/notify.sh:click_callback` via `tee` (write), human user via `less` / `tail` (read).

## File properties

- **Encoding**: UTF-8, no BOM.
- **Line terminator**: `\n` (LF).
- **Append-only**: writers MUST open with `>>`, never truncate.
- **Mode**: 0644 (world-readable; this is user-scoped state, not secrets).
- **Directory**: created with `mkdir -p` on first write, mode 0755.
- **Rotation**: none in v1 (see plan.md Scale/Scope).

## Line format

One event per line. Fields tab-separated (`\t`, literal 0x09). Fields MUST NOT contain embedded tabs — writers replace any inbound `\t` with a single space before composing the line. Example:

```text
2026-04-21T17:52:03+08:00	alerter-failed	my-webapp	permission_prompt	abc-123	Claude needs your permission to run: git push
```

### Fields (in order)

| # | Name | Type | Missing sentinel |
|---|------|------|------------------|
| 1 | ISO-8601 timestamp with timezone offset (`date -u '+%Y-%m-%dT%H:%M:%S%z'`) | string | never missing |
| 2 | Category | string (one of the set below) | never missing |
| 3 | Project name | string | `-` |
| 4 | `notification_type` from payload | string | `-` |
| 5 | `session_id` from payload | string | `-` |
| 6 | Message summary (≤ 200 chars, `…` suffix if truncated; newlines → space) | string | `-` |

### Defined categories

See data-model.md §Notification Failure Log Entry for full list with triggers. Reproduced here for reader convenience:

- `alerter-missing`
- `alerter-failed` (covers unexpected alerter results / non-zero exits; silent permission denial is caught at install time, not runtime — see `contracts/tms-install-hooks-cli.md` §Post-install probe)
- `no-cwd`
- `no-project-match`
- `parse-error`
- `empty-message`
- `switch-failed` (written by the click callback inside the detached subshell via `notify_log_failure`)
- `hook-error` (script-wide ERR trap; rare)

### Extensibility

New categories MAY be added in later versions; readers MUST tolerate unknown categories by passing them through. Column count and order MUST NOT change; new fields would be appended at column 7+ in a future version.

## Reader contract

Humans are the primary readers. The `tms` CLI does NOT provide a subcommand for reading the log in v1 — `tail -f <path>` is the intended workflow. A future `tms doctor` or `tms log` subcommand MAY parse this format; the tab-separated layout is chosen so `awk -F'\t'` and `cut` work directly.

## Writer constraints

- Writers MUST acquire a POSIX advisory lock via `flock -x` (shell builtin when available; otherwise skip the lock and accept that concurrent writes might interleave — the append-only mode makes this safe up to a line-boundary on Linux/macOS local filesystems when writes are smaller than `PIPE_BUF`).
- On Darwin, `flock(1)` is not shipped by default; `lib/notify.sh` uses a `write-then-rename` pattern for single-line appends instead: compose the line into a variable, then `printf '%s\n' "$line" >> "$logfile"` in one `printf` call (bash guarantees a single write syscall for output this small).

## Manual test mapping

Covered by quickstart.md scenarios QS-7 (no-project-match entry), QS-10 (parse-error entry), QS-12 (alerter-missing entry).
