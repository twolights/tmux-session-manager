# Quickstart: Claude Code Notification Hook with Click-to-Switch

**Feature**: 002-claude-notification-hook
**Date**: 2026-04-21

This document is both the user-facing install guide and the manual verification recipe. Because the repo has no automated test harness, each numbered scenario below maps to an acceptance criterion in `spec.md` and each branch of the contracts in `contracts/`.

---

## Prerequisites (one-time per machine)

```bash
brew install alerter jq
# tmux, yq, fzf already required by tms
```

> **macOS 26+ note**: `alerter` was chosen as the notifier (over `terminal-notifier`) because `terminal-notifier`'s click callbacks no longer dispatch on macOS 26 — see [research.md §7](research.md). Banner delivery + click-to-switch both work with `alerter`.

Then, from the repo root on branch `002-claude-notification-hook`:

```bash
tms install-hooks
```

This writes one entry to `~/.claude/settings.json` under `hooks.Notification`. Re-running `tms install-hooks` is idempotent.

`tms install-hooks` runs a probe banner at the end of install that triggers macOS's permission prompt for **Terminal** (alerter delivers under Terminal's bundle for macOS 26+ compatibility — see research.md §6). Click **Allow**. If you dismiss the prompt or miss the banner, the install output includes explicit instructions to open **System Settings → Notifications → Terminal** and enable it there. See QS-13 for the full probe verification recipe.

To remove: `tms install-hooks --uninstall`.

---

## Verification scenarios

Each scenario lists the spec coverage it satisfies. Run them in order the first time; individual scenarios are idempotent thereafter.

### QS-1: Install hook (success path)

**Covers**: contracts/tms-install-hooks-cli.md install path; FR-008.

```bash
tms install-hooks
```

**Expect**: `Installed tms-notify-hook at <absolute path>.` and a note about the macOS permission prompt. Then:

```bash
jq '.hooks.Notification' ~/.claude/settings.json
```

**Expect**: one array entry with `matcher: ""` and an inner `hooks[].command` ending in `bin/tms-notify-hook`.

---

### QS-2: Happy path — notification fires with project name (User Story 1, P1)

**Covers**: spec US1 acceptance scenarios 1 & 2; FR-001, FR-002, FR-003.

1. Add a dummy project to `~/.config/tmux-session-manager/projects.yml` pointing at any real directory, e.g.:

   ```yaml
   projects:
     - name: qs-demo
       dir: ~/Projects/ykchen/tmux-session-manager
   ```

2. Start the session and focus something else (a different app):

   ```bash
   tms start qs-demo
   # switch to Safari or another app
   ```

3. Trigger the Claude Code `Notification` hook in the qs-demo session. The easiest way is to run a command that requires approval, e.g. ask Claude Code to run a command not on your allow-list.

**Expect**: a macOS notification banner appears with title `qs-demo` and body = Claude Code's `message` verbatim (possibly truncated by Notification Center for display, not by us). No click yet — just verify the banner.

---

### QS-3: Click-to-switch lands on workspace window (User Story 2, P1)

**Covers**: spec US2 acceptance scenario 1; FR-004, FR-005.

1. With the banner from QS-2 still visible, click the banner body.

**Expect** in this order within ~2 seconds:

1. Your terminal application comes to the foreground.
2. The active tmux session is `qs-demo`.
3. The active window is `workspace` (check `tmux display-message -p '#W'` — should print `workspace`).

This verifies SC-002 (< 2 s click-to-switch) and FR-004's landing-on-workspace-window requirement.

**Known limitation — multiple terminal windows**: if you have two or more windows of the same terminal emulator open, `open -b <bundle>` foregrounds the application but macOS chooses whichever window was most recently active as the frontmost OS window. The tmux client in any other window **does** get retargeted to `qs-demo`, but it may be hidden behind the frontmost window. Cycle windows (⌘\` on macOS) to find it. Single-window users will never see this. This is an accepted tradeoff — see data-model.md §Click Action Payload for the rationale (per-emulator AppleScript would be the alternative).

---

### QS-4: Click when target session has been stopped

**Covers**: spec US2 acceptance scenario 2; FR-006; Edge Case 4.

1. Trigger a notification as in QS-2. Before clicking, in another terminal run `tms stop qs-demo`.
2. Click the banner.

**Expect**:
1. The terminal foregrounds (via `open -b <bundle>`).
2. `tms switch qs-demo` exits non-zero with the exact stderr line `Error: session 'qs-demo' is not running. Run 'tms start qs-demo' to restart it.` — verify by `tail -f ~/.local/state/tmux-session-manager/notifications.log` before clicking; that message is captured by the click-callback's `tee -a`.
3. A **follow-up macOS notification** appears within ~1 second, titled `Claude Code — qs-demo` with body `Session not running. Run 'tms start qs-demo' to restart it.` — this is the user-visible "loud error" signal per FR-006.
4. No session is created; `tmux list-sessions` does NOT show `qs-demo`.
5. The user is NOT silently dumped on an unrelated session.

---

### QS-5: Multi-project disambiguation (User Story 1 acceptance scenario 2, SC-004)

**Covers**: spec US1 AS-2; FR-002; SC-004 no-cross-talk.

1. Register two projects, `qs-demo-a` and `qs-demo-b`. `tms start` both.
2. Trigger a `Notification` event in each in rapid succession.
3. Verify both banners appear with distinct titles (`qs-demo-a`, `qs-demo-b`).
4. Click the `qs-demo-b` banner specifically.

**Expect**: you land on `qs-demo-b`'s workspace window, not `qs-demo-a`. Then click `qs-demo-a`'s banner: you land on `qs-demo-a`. Neither click switches to the wrong project.

---

### QS-6: Per-project opt-out + visual-bell coexistence (FR-011, FR-009)

**Covers**: spec Clarification Q3; FR-011; FR-009.

1. Edit `~/.config/tmux-session-manager/projects.yml`:

   ```yaml
   - name: qs-demo
     dir: ~/Projects/ykchen/tmux-session-manager
     notifications:
       enabled: false
   ```

2. Trigger a `Notification` event in qs-demo.

**Expect (opt-out behavior)**: no macOS banner appears. `tail -f ~/.local/state/tmux-session-manager/notifications.log` shows NO new entry (opt-out is silent, not a failure).

**Expect (visual-bell coexistence — FR-009)**: the tmux visual bell continues to fire for Claude Code prompts. Verify positively:

```bash
tmux show-options -t qs-demo | grep -E '^(visual-bell|monitor-bell)'
```

Output MUST be exactly:

```
monitor-bell on
visual-bell on
```

Both options must survive `tms install-hooks` and every notification firing. If either is off or missing, the feature has silently regressed on FR-009 — fail the scenario.

Restore `enabled: true` (or delete the `notifications` block) and re-verify QS-2 fires the macOS banner again. Re-run the two `tmux show-options` queries to confirm bell options remain `on` after the opt-out is disabled.

---

### QS-7: Graceful outside tms context (User Story 3, P3)

**Covers**: spec US3; FR-010; data-model.md `no-project-match` category.

1. Run `claude` from `~/scratch` (a directory NOT in `projects.yml`).
2. Trigger a `Notification` event.

**Expect**: either
(a) a banner appears with a title that does NOT advertise a clickable session switch (e.g., title = `Claude Code` without tms project name, and no `-execute` payload), OR
(b) no banner at all.

Then:

```bash
tail -1 ~/.local/state/tmux-session-manager/notifications.log
```

**Expect**: one `no-project-match` entry with the unmatched `cwd`.

---

### QS-8: Uninstall

**Covers**: contracts/tms-install-hooks-cli.md uninstall path.

```bash
tms install-hooks --uninstall
```

**Expect**: `Removed tms-notify-hook.` and:

```bash
jq '.hooks.Notification // "absent"' ~/.claude/settings.json
```

returns `"absent"` (or the key exists but does not contain any tms entry). No other keys in `settings.json` are touched — verify this by diffing against a backup you took before QS-1.

---

### QS-9: Idempotent re-install

**Covers**: contracts/tms-install-hooks-cli.md idempotent path.

```bash
tms install-hooks
tms install-hooks   # second invocation
```

**Expect** on the second invocation: `tms-notify-hook is already installed at <path>.`; no duplicate entry appears in `settings.json`.

---

### QS-10: Malformed payload

**Covers**: contracts/tms-notify-hook-stdin.md `parse-error` branch; FR-007.

Directly invoke the hook with garbage:

```bash
echo 'not json' | bin/tms-notify-hook
echo "exit=$?"
```

**Expect**: `exit=0` (FR-007: never blocks Claude Code). `tail -1 ~/.local/state/tmux-session-manager/notifications.log` shows a `parse-error` entry.

---

### QS-11: Missing cwd field

**Covers**: contracts/tms-notify-hook-stdin.md `no-cwd` branch; FR-010.

```bash
echo '{"hook_event_name":"Notification","message":"hello"}' | bin/tms-notify-hook
```

**Expect**: either a plain notification with no click-to-switch appears, or no notification; in either case a `no-cwd` entry is appended to the log. Exit 0.

---

### QS-12: alerter missing

**Covers**: contracts/tms-notify-hook-stdin.md `alerter-missing` branch; FR-007.

Temporarily shadow `alerter` out of `$PATH` and invoke the hook with a valid payload:

```bash
PATH="/usr/bin:/bin" echo '{
  "hook_event_name":"Notification",
  "cwd":"'$(pwd)'",
  "message":"test"
}' | bin/tms-notify-hook
```

**Expect**: exit 0; `alerter-missing` log entry. Claude Code would continue unblocked.

---

### QS-13: Install-time permission probe (Edge Case)

**Covers**: spec Edge Cases (permission denial); contracts/tms-install-hooks-cli.md §Post-install probe.

This scenario verifies that the feature catches the "permissions never granted" setup proactively at install time rather than attempting runtime detection.

1. Ensure **Terminal** has no existing Notification Center permission entry (first-time-ever state). If you've used Terminal-based notifications before, open System Settings → Notifications, find `Terminal`, and delete or disable its entry; then `killall NotificationCenter`.
2. Run `tms install-hooks`.

**Expect**:
1. The install writes the settings.json entry as in QS-1.
2. macOS prompts you to allow notifications for **Terminal** (alerter delivers under Terminal's bundle for macOS 26+ compatibility — see research.md §6). Click Allow.
3. A probe banner titled `tms` with body `Notification hook installed. You should see this banner.` appears.
4. The install output includes the full diagnostic block per contracts/tms-install-hooks-cli.md §Post-install probe, pointing at System Settings → Notifications → Terminal and the absolute path of `notifications.log`.

Then deliberately deny the permission (System Settings → Notifications → Terminal → Allow Notifications off) and run `tms install-hooks` again (it's idempotent and re-runs the probe):

**Expect**: same install output as above, but no banner appears. The printed diagnostic tells the user exactly where to look to fix it. `notifications.log` does NOT receive a `permission-denied` entry — by design, runtime detection was removed in favor of this install-time check.

---

## Acceptance traceability matrix

| Spec element | Quickstart scenario |
|--------------|---------------------|
| US1 AS-1 | QS-2 |
| US1 AS-2 | QS-5 |
| US1 AS-3 (coexists with visual bell) | QS-6 (bell still fires when opted out) |
| US2 AS-1 | QS-3 |
| US2 AS-2 | QS-4 |
| US2 AS-3 (dismissal leaves no residual state) | Verified as part of QS-2 (subsequent `tms list` unaffected) |
| US3 AS-1, AS-2 | QS-7 |
| FR-001 | QS-2 |
| FR-002 | QS-5 |
| FR-003 | QS-2 |
| FR-004 | QS-3 |
| FR-005 | QS-3 (via `tms switch`) |
| FR-006 | QS-4 |
| FR-007 | QS-10, QS-11, QS-12 |
| FR-008 | QS-1, README |
| FR-009 | QS-6 (explicit `tmux show-options` assertion for `visual-bell` and `monitor-bell`) |
| FR-010 | QS-7, QS-11 |
| FR-011 | QS-6 |
| SC-001 (3 s identify) | Observational during QS-2 |
| SC-002 (2 s click-to-switch) | Observational during QS-3 |
| SC-004 (no cross-talk, project-count-independent) | QS-5 as-is |
| SC-005 (< 100 ms hook overhead) | Measured separately: `time` around a synthetic invocation of `bin/tms-notify-hook` with a valid payload |

All spec requirements and acceptance scenarios have at least one corresponding manual verification step.
