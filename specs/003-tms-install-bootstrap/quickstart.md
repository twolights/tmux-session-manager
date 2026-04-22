# Quickstart: One-command Install + Single-binary Refactor

**Feature**: 003-tms-install-bootstrap
**Date**: 2026-04-22

This document is both the user-facing install guide post-feature-003 AND the manual verification recipe. Each scenario maps to an acceptance criterion in `spec.md` and each branch of the contracts in `contracts/`.

---

## Verification scenarios

### QS-1: Fresh install (success path)

**Covers**: US1 AS-1; FR-001, FR-002, FR-003, FR-004 (macOS variant); contracts/tms-install-cli.md install path.

```bash
# In a fresh clone with no prior install:
rm -f ~/.local/bin/tms ~/.local/bin/tms-notify-hook 2>/dev/null   # clean slate for the test
./bin/tms install
```

**Expect** on macOS:
1. Output begins with `Installed tms at /Users/<you>/.local/bin/tms.`
2. If `~/.config/tmux-session-manager/projects.yml` was absent, line `Created /Users/<you>/.config/tmux-session-manager/projects.yml from example.`
3. Dependency-hint block lists each missing required dep (`tmux`, `yq`, `fzf`) with `brew install <pkg>` (or `pip3 install yq` for yq specifically) lines, and each missing optional dep (`alerter`, `jq`) with `brew install <pkg>` lines if missing.
4. PATH-warning line if `~/.local/bin` is not on `$PATH`.
5. Final `Next steps:` block with two numbered items: edit projects.yml, optionally run `tms install-hooks`.
6. Exit code 0.

```bash
# Verify the symlink:
ls -la ~/.local/bin/tms          # → symlink to <repo>/bin/tms
~/.local/bin/tms list             # → runs tms (assuming the prefix is on $PATH or you use the full path)
```

---

### QS-2: Config bootstrap is non-destructive

**Covers**: FR-002; spec edge case "Never overwrite an existing projects.yml".

1. After QS-1, edit `~/.config/tmux-session-manager/projects.yml` to add a custom entry. Save.
2. Run `./bin/tms install` again.
3. Open `~/.config/tmux-session-manager/projects.yml`.

**Expect**: your custom edits are preserved verbatim. Output line reads `Config already present at <path>.` (not `Created … from example.`).

---

### QS-3: Idempotent re-install (same prefix)

**Covers**: US1 AS-3; FR-007 (per-prefix idempotency); contracts/tms-install-cli.md install path branch `same-symlink`.

```bash
./bin/tms install   # second invocation, no changes since QS-1
```

**Expect**:
- `tms is already installed at /Users/<you>/.local/bin/tms.`
- `Config already present at /Users/<you>/.config/tmux-session-manager/projects.yml.`
- Same dep-hint and PATH sections as before (or absent if everything is now installed).
- Exit 0. No mutations to the symlink, the config, or any other file.

Verify: `ls -la ~/.local/bin/tms` mtime is unchanged from QS-1 (best-effort signal).

---

### QS-4: Re-install after moving the repo (path update)

**Covers**: US1 AS-4; FR-007 mismatch branch; contracts/tms-install-cli.md `tms-mismatch-symlink`.

1. Move the repo: `mv /path/to/tmux-session-manager /new/path/tmux-session-manager`.
2. From the new location: `./bin/tms install`.

**Expect**:
- `Updated tms path: /old/path/.../bin/tms → /new/path/.../bin/tms`
- Subsequent `~/.local/bin/tms list` works against the new location.
- Exit 0.

---

### QS-5: Uninstall preserves config

**Covers**: FR-010; contracts/tms-install-cli.md uninstall path; spec edge case "user data is preserved".

```bash
./bin/tms install --uninstall
```

**Expect**:
- `Removed tms symlink at /Users/<you>/.local/bin/tms.`
- One-line note: `Note: Claude Code hook registration (if any) is unchanged. Run \`tms install-hooks --uninstall\` to remove it.`
- `~/.config/tmux-session-manager/projects.yml` and the directory itself are NOT touched.
- Exit 0.

Verify: `ls -la ~/.local/bin/tms` returns "no such file"; `cat ~/.config/tmux-session-manager/projects.yml` still present.

---

### QS-6: Dry-run

**Covers**: FR-011; contracts/tms-install-cli.md dry-run path.

```bash
./bin/tms install --dry-run                              # preview install
./bin/tms install --dry-run --uninstall                  # preview uninstall
```

**Expect**: every action line is prefixed with `[dry-run] would …`. No files are created, modified, or deleted (verify by checking mtimes / file existence before and after). Exit 0.

---

### QS-7: Refuse on unrelated symlink

**Covers**: FR-008 (spirit); contracts/tms-install-cli.md `unrelated-symlink` branch; spec edge case "non-symlink file at install target".

```bash
ln -s /usr/bin/cat ~/.local/bin/tms     # plant a misleading symlink
./bin/tms install ; echo "exit=$?"
```

**Expect**: `Error: ~/.local/bin/tms is a symlink to /usr/bin/cat which does not look like a tms checkout. Refusing to overwrite. Use --prefix=<dir> to install elsewhere.` Exit 1. The misleading symlink is NOT touched.

Cleanup: `rm ~/.local/bin/tms` then re-run QS-1 if you want to continue.

---

### QS-8: Refuse on non-symlink target

**Covers**: FR-008 directly.

```bash
echo '#!/bin/sh
echo i am not the real tms' > ~/.local/bin/tms
chmod +x ~/.local/bin/tms
./bin/tms install ; echo "exit=$?"
```

**Expect**: `Error: ~/.local/bin/tms exists and is not a symlink — refusing to overwrite. Move it aside or use --prefix=<dir>.` Exit 1. The user's regular file is left intact.

Cleanup: `rm ~/.local/bin/tms`.

---

### QS-9: PATH warning when prefix not on PATH

**Covers**: FR-009.

```bash
./bin/tms install --prefix=$HOME/.tms-test-prefix
```

**Expect** (assuming `$HOME/.tms-test-prefix` is not on PATH): a warning block at the bottom of the output:

```text
Note: /Users/<you>/.tms-test-prefix is not on your $PATH.
To use `tms` from any shell, add this line to your shell rc (~/.zshrc, ~/.bashrc, etc.):

    export PATH="/Users/<you>/.tms-test-prefix:$PATH"
```

The install itself still completed (symlink exists at the custom prefix). Exit 0.

Cleanup: `./bin/tms install --uninstall --prefix=$HOME/.tms-test-prefix`.

---

### QS-10: macOS dependency hints

**Covers**: US3 AS-1; FR-003 (Darwin branch); FR-004; research.md §3.

On macOS, with at least one required dep deliberately missing (e.g., uninstall fzf temporarily, or use `PATH="/usr/bin:/bin"` to shadow it):

```bash
PATH="/usr/bin:/bin" ./bin/tms install
```

**Expect** the dependency-hint block contains `brew install fzf` (and similar `brew install …` lines for any other missing dep). For yq specifically: `pip3 install yq    # (Python yq, not mikefarah/yq — see README)`.

---

### QS-11: Linux apt dependency hints

**Covers**: US3 AS-2; FR-005; research.md §2.

On a Linux host with `apt` available (or simulate by mocking `command -v` via PATH):

```bash
./bin/tms install
```

**Expect** missing-dep lines use `sudo apt install <pkg>`, NOT `brew install <pkg>`. The yq line still uses `pip3 install yq`.

Repeat the test on dnf, pacman, zypper, apk hosts (or in containerized environments) to verify per-pkg-manager rendering. Each host should produce the install command matching its native pkg manager per the table in research.md §3.

---

### QS-12: Notifications not advertised on Linux

**Covers**: US3 AS-5; FR-006 + clarification 2026-04-22.

On Linux:

```bash
./bin/tms install
```

**Expect**:
1. Dependency-hint block does NOT include `alerter` or `jq` lines (they're macOS-only).
2. Block ends with the one-line footer: `Note: Claude Code notification banners are macOS-only in this version.`
3. Next-step block does NOT include the `Run \`tms install-hooks\`` line (that suggestion is macOS-only per the contract).

---

### QS-13: Multi-prefix independence

**Covers**: FR-007 + clarification 2026-04-22.

```bash
./bin/tms install --prefix=$HOME/.local/bin            # → install at A
./bin/tms install --prefix=$HOME/.tms-second-prefix    # → install at B
ls -la $HOME/.local/bin/tms $HOME/.tms-second-prefix/tms
```

**Expect**: both symlinks exist, both pointing at the same `<repo>/bin/tms`. Neither install touched the other prefix.

```bash
./bin/tms install --uninstall --prefix=$HOME/.tms-second-prefix
ls -la $HOME/.local/bin/tms $HOME/.tms-second-prefix/tms
```

**Expect**: `~/.local/bin/tms` is still present; `~/.tms-second-prefix/tms` is gone. Each prefix is managed independently.

---

### QS-14: settings.json migration after upgrading from feature 002

**Covers**: US2 AS-2; FR-014; SC-005; contracts/tms-install-hooks-cli-update.md migration path.

**Setup**: Confirm your `~/.claude/settings.json` has an entry from feature 002 pointing at the old binary path. If not (because it was already migrated by an earlier run of `tms install-hooks` post-feature-003), restore one for the test:

```bash
jq '.hooks.Notification[0].hooks[0].command = "/path/to/tms/bin/tms-notify-hook"' \
    ~/.claude/settings.json > ~/.claude/settings.json.tmp && \
    mv ~/.claude/settings.json.tmp ~/.claude/settings.json
```

Then run:

```bash
tms install-hooks
```

**Expect**:
1. Output starts with `Migrated tms-notify-hook entry to tms notify-hook.` (one line).
2. Then the normal install-hooks output (probe banner attempt, post-install diagnostic block).
3. Inspect the settings.json:
   ```bash
   jq '.hooks.Notification[0].hooks[0].command' ~/.claude/settings.json
   ```
   Should print `"<absolute-path>/bin/tms notify-hook"` (NOT `…/bin/tms-notify-hook`).
4. Trigger a Claude Code Notification event (e.g., a permission-required command). Banner appears as before; click switches sessions correctly. Behavior matches feature 002 QS-2 / QS-3 byte-for-byte.

Re-run `tms install-hooks` and verify NO migration line is printed (idempotent — the entry is already migrated).

---

### QS-15: `bin/tms-notify-hook` is gone

**Covers**: FR-013.

```bash
ls bin/
```

**Expect**: only `bin/tms` exists (and `bin/tms-switch` if it's still in place per feature 001 — that's a separate tool, unaffected by this feature). NO `bin/tms-notify-hook` file.

```bash
which tms-notify-hook 2>&1 || echo "not on PATH (expected)"
```

**Expect**: `not on PATH (expected)` — the binary no longer exists in this repo or anywhere `tms install` has put files.

If you previously symlinked `bin/tms-notify-hook` into `~/.local/bin/` or elsewhere, that symlink is now dangling. Clean it up manually: `rm ~/.local/bin/tms-notify-hook`. (Per spec: not auto-cleaned by `tms install` because `tms install` doesn't track legacy paths; the user does this once.)

---

### QS-16: `tms notify-hook` direct invocation

**Covers**: US2 AS-3; FR-012; spec edge case "byte-for-byte same as feature 002".

```bash
echo '{"hook_event_name":"Notification","cwd":"'$(pwd)'","message":"direct subcommand test","notification_type":"idle_prompt"}' | tms notify-hook
echo "exit=$?"
```

**Expect**: exit 0; banner fires (assuming alerter is installed and macOS notification permissions granted); behavior identical to feature 002's `bin/tms-notify-hook` invocation. Verifies the subcommand wrap preserves the stdin contract.

---

## Acceptance traceability matrix

| Spec element | Quickstart scenario |
|--------------|---------------------|
| US1 AS-1 | QS-1 |
| US1 AS-2 (`tms` resolvable post-install) | QS-1 step "verify symlink" |
| US1 AS-3 (idempotent re-install) | QS-3 |
| US1 AS-4 (repo move) | QS-4 |
| US2 AS-1 (single binary in bin/) | QS-15 |
| US2 AS-2 (settings.json migration) | QS-14 |
| US2 AS-3 (`tms notify-hook` byte-for-byte same) | QS-16 + feature 002 QS-2 / QS-3 re-run |
| US3 AS-1 (Homebrew hints on macOS) | QS-10 |
| US3 AS-2 (apt hints on Linux) | QS-11 |
| US3 AS-3 (generic on no-pkg-mgr) | QS-11 (run with PATH stripped of pkg managers) |
| US3 AS-4 (Homebrew not installed) | QS-10 (with brew not on PATH) |
| US3 AS-5 (no notification deps on Linux) | QS-12 |
| FR-001 | QS-1, QS-9 |
| FR-002 | QS-2 |
| FR-003 | QS-10, QS-11 |
| FR-004 | QS-10, QS-11 |
| FR-005 | QS-11 |
| FR-006 | QS-12 |
| FR-007 | QS-3, QS-4, QS-13 |
| FR-008 | QS-7, QS-8 |
| FR-009 | QS-9 |
| FR-010 | QS-5 |
| FR-011 | QS-6 |
| FR-012 | QS-16 |
| FR-013 | QS-15 |
| FR-014 | QS-14 |
| FR-015 (feature 002 behavior preserved) | feature 002 QS-2, QS-3, QS-4, QS-6, QS-7 re-run |
| SC-001 (60-second install) | Observational during QS-1 |
| SC-002 (zero manual paths) | QS-1 + QS-14 (everything is a single command or "edit projects.yml") |
| SC-003 (binary count drops 2 → 1) | QS-15 |
| SC-004 (dep-hint matrix accuracy) | QS-10, QS-11 (full matrix) |
| SC-005 (migration is invisible) | QS-14 |

All spec requirements and acceptance scenarios have at least one corresponding manual verification step.
