# Contract: `tms install` subcommand

**Surface**: `bin/tms` subcommand dispatch → `lib/install.sh:cmd_install`
**Callers**: User (one-time setup per machine, plus rare re-runs after moving the checkout or changing prefix).

## Signature

```text
tms install [--prefix=<dir>] [--uninstall] [--dry-run]
```

- `--prefix=<dir>`: install symlink prefix. Default `~/.local/bin/`. Tilde is expanded via the existing `expand_path` helper.
- `--uninstall`: remove the tms symlink at `<prefix>` (preserves `projects.yml` — user data).
- `--dry-run`: print every action without performing any of them; exit 0.
- `--uninstall` + `--dry-run` are independently combinable; running both prints the planned uninstall actions without executing.
- No flags → install.

## Preconditions

- `$HOME` is set and writable. If not, exit 1 with `Error: $HOME is not set or not writable.`
- The repo's `bin/tms` (the source of the symlink target) MUST exist and be executable. (It does, because the user is running it.)
- For install: parent dir of `<prefix>` must be writable, or already exist and be writable.

No package-manager preconditions. `tms install` is a shell-only operation; it does NOT depend on `brew`, `apt`, etc. being present (it only prints hints to commands that may be missing).

## Behavior

### Install (no flags or `--prefix=<dir>` only)

1. Resolve `TMS_DIR` to an absolute path (same mechanism as `bin/tms:6`).
2. Resolve `<prefix>` to an absolute path. Create it if absent (`mkdir -p`, mode 0755). If creation fails, exit 1 with `Error: could not create install prefix at <path>.`
3. Compute the install plan (data-model.md §Install Plan): classify the existing target at `<prefix>/tms`, classify config presence, detect OS bucket and pkg-manager, probe for missing deps, check PATH membership.
4. Symlink action (data-model.md §Install Target):
   - `absent` → `ln -s "$TMS_DIR/bin/tms" "<prefix>/tms"`. Print `Installed tms at <path>.`
   - `same-symlink` → idempotent no-op. Print `tms is already installed at <path>.`
   - `tms-mismatch-symlink` → `rm` + `ln -s` (atomic-enough for single-user). Print `Updated tms path: <old> → <new>`.
   - `unrelated-symlink` or `non-symlink` → refuse per FR-008. Exit 1.
5. Config-bootstrap action:
   - `<config_dir>` does not exist → create with `mkdir -p`, mode 0755.
   - `<config_dir>/projects.yml` does not exist → `cp <TMS_DIR>/config/projects.example.yml <config_dir>/projects.yml`. Print `Created <config_dir>/projects.yml from example.`
   - `<config_dir>/projects.yml` already exists → no-op. Print `Config already present at <config_dir>/projects.yml.`
   - **Never overwrite an existing projects.yml** (FR-002).
6. Dependency hint block (data-model.md §Dependency Hint):
   - For each missing required dep (`tmux`, `yq`, `fzf`), emit one install-command line per the table in research.md §3.
   - For each missing optional dep on macOS only (`alerter`, `jq`), emit one install-command line.
   - On non-macOS, emit the one-line "Note: Claude Code notification banners are macOS-only" footer instead of the optional-deps section.
   - If all deps present, skip the section entirely.
7. PATH-on-prefix check (research.md §5): if `<prefix>` is not on `$PATH`, print the warning with the exact `export PATH=...` line.
8. Next-step block (US1 acceptance scenario, FR-001 + clarification 2026-04-22): print exactly:
   ```text
   Next steps:
       1. Edit <config_dir>/projects.yml to add your projects.
       2. (macOS only) Run `tms install-hooks` to enable Claude Code notifications.
   ```
   The "macOS only" parenthetical line is present only if `os_bucket == macos` (so Linux users don't see a misleading suggestion).

### Uninstall (`--uninstall`)

1. Resolve `TMS_DIR` and `<prefix>` as in install.
2. Classify the target (data-model.md §Install Target uninstall classification).
3. Execute the action per the classification table; print the corresponding message.
4. Do NOT touch `<config_dir>` or `projects.yml` (per FR-010 — user data preserved).
5. Do NOT modify `~/.claude/settings.json` (the Claude Code hook registration is managed by `tms install-hooks --uninstall`, which is a separate command). Print a one-line note: `Note: Claude Code hook registration (if any) is unchanged. Run \`tms install-hooks --uninstall\` to remove it.`

### Dry-run (`--dry-run`)

Same plan computation as install (or uninstall, if combined with `--uninstall`), but print every action prefixed with `[dry-run] would …` and write nothing. Exit 0. The dependency-hint and PATH warning sections are still printed (they don't write anything anyway, so dry-run shows the user what they'd see).

## Error handling

| Condition | Behavior |
|-----------|----------|
| `$HOME` unset or unwritable | Exit 1 with `Error: $HOME is not set or not writable.` |
| `--prefix=<dir>` is not creatable | Exit 1 with `Error: could not create install prefix at <path>.` |
| Install target is `unrelated-symlink` | Exit 1 with `Error: <path> is a symlink to <target> which does not look like a tms checkout. Refusing to overwrite. Use --prefix=<dir> to install elsewhere.` |
| Install target is `non-symlink` | Exit 1 with `Error: <path> exists and is not a symlink — refusing to overwrite. Move it aside or use --prefix=<dir>.` |
| Symlink creation fails (filesystem error) | Exit 1, propagate the OS error message. |
| `cp` of `projects.example.yml` fails | Exit 1, propagate the OS error message. |
| Unknown flag | Exit 1 with `Error: unknown flag '<flag>'. Usage: tms install [--prefix=<dir>] [--uninstall] [--dry-run]`. |

## Per-prefix idempotency (FR-007 + clarification 2026-04-22)

Running `tms install --prefix=A` then `tms install --prefix=B` leaves both symlinks. The second invocation does not search PATH or any state file for prior installs at other prefixes. To remove the first, the user must explicitly run `tms install --uninstall --prefix=A`. No metadata file tracks prior prefixes.

## Non-goals (carried over from spec.md)

- Does NOT install Homebrew, apt-get, or any system-level package manager — only print hints.
- Does NOT modify shell rc files (`.bashrc`, `.zshrc`, `.profile`, `fish/config.fish`). Prints PATH warnings instead.
- Does NOT publish a Homebrew formula or maintain an apt repo.
- Does NOT chain into `tms install-hooks` automatically (clarification 2026-04-22 — Q3 Option A).
- Does NOT touch `projects.yml` if it exists (FR-002 — never overwrite user data).

## Manual test mapping

Covered by quickstart.md scenarios QS-1 (install), QS-2 (config-bootstrap), QS-3 (idempotent re-install), QS-4 (re-install after repo move), QS-5 (uninstall), QS-6 (dry-run), QS-7 (refuse on unrelated symlink), QS-8 (refuse on non-symlink), QS-9 (PATH warning), QS-10 (OS-aware dep hints — macOS), QS-11 (OS-aware dep hints — Linux apt), QS-12 (notifications-not-advertised on Linux), QS-13 (multi-prefix independence).
