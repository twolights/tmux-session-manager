# Phase 1 Data Model: One-command Install + Single-binary Refactor

**Feature**: 003-tms-install-bootstrap
**Date**: 2026-04-22

This document maps the spec's Key Entities onto concrete data shapes (in-memory bash variables, on-disk artifacts, JSON migration shapes). Contracts in `contracts/` reference these shapes; do not duplicate structure there.

---

## Entity: Install Plan

The set of actions `tms install` would take on a given host. Computed lazily during `cmd_install`; materialized as the dry-run output and as the actual install steps. Lives only for the duration of one `tms install` invocation.

### Fields (in-memory bash vars)

| Field | Type | Source | Purpose |
|-------|------|--------|---------|
| `tms_dir` | string (abs path) | `cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd` (same as `bin/tms:6`) | Source of the symlink target (`<tms_dir>/bin/tms`) |
| `prefix` | string (abs path) | `--prefix=<dir>` flag, default `~/.local/bin/`; expanded via `expand_path` (utils.sh) | Where the symlink lives |
| `target_link` | string (abs path) | `<prefix>/tms` | The symlink itself |
| `target_state` | enum | `_install_classify_target` (one of: `absent`, `same-symlink`, `tms-mismatch-symlink`, `unrelated-symlink`, `non-symlink`) | Drives the install/update/refuse branch |
| `os_bucket` | enum | `uname -s` → `macos` / `linux` / `other` | Picks dep-hint formatter |
| `pkg_mgr` | enum (linux only) | `command -v` probe in apt → dnf → pacman → zypper → apk order | Picks per-pkg install command |
| `missing_required_deps` | array of pkg names | Each of `tmux`, `yq`, `fzf` — push if `command -v` fails | Drives required-deps hint block |
| `missing_optional_deps` | array of pkg names | macOS only: each of `alerter`, `jq` — push if missing | Drives optional-deps hint block |
| `prefix_on_path` | bool | Walk `$PATH` entries, realpath-normalize, compare to `prefix` | Drives FR-009 PATH warning |
| `config_dir` | string (abs path) | `${TMS_CONFIG_DIR:-$HOME/.config/tmux-session-manager}` (matches `lib/utils.sh:config_dir`) | Where projects.yml lives |
| `config_target` | string (abs path) | `<config_dir>/projects.yml` | The user-config file we may create |
| `config_state` | enum | `present` (file exists) / `absent` (we will copy `projects.example.yml`) | Drives FR-002 |
| `dry_run` | bool | `--dry-run` flag | If true, every "do" step prints what it would do and short-circuits |
| `do_uninstall` | bool | `--uninstall` flag | If true, switch to uninstall flow (remove symlink only; preserve config) |

### State transitions

`Install Plan` is computed once at the start of `cmd_install` (no mutation after). The materialization phase consumes the plan top-to-bottom:

1. Validate flags (`--prefix` is a writable directory candidate; `--uninstall` and `--dry-run` are independent booleans, both can be combined).
2. Compute `target_state`, `config_state`, `os_bucket`, `pkg_mgr`, `missing_*_deps`, `prefix_on_path`.
3. If `dry_run`: print the planned actions in human-readable form, `exit 0`.
4. If `do_uninstall`: execute `_install_uninstall_symlink` and print result; `exit 0`.
5. Otherwise: execute install actions in this order: symlink, config-bootstrap, dep-hints, PATH warning, next-step block.

---

## Entity: Dependency Hint

A pair of `(package-name, install-command-template)` derived from the detected OS + package manager. Rendered into the user-facing output verbatim so the user can copy-paste.

### Shape (in-memory)

Each missing-dep entry is a tuple `(pkg_name, install_command)` where `install_command` is the full literal shell command. The hint block prints them grouped:

```text
Missing dependencies — install with:

    sudo apt install tmux
    pip3 install yq    # (Python yq, not mikefarah/yq — see README)
    sudo apt install fzf
```

### Construction rules

1. For each missing required dep (`tmux`, `fzf`): look up `(os_bucket, pkg_mgr) → install_command` in the table from research.md §3. The `pkg_name` is always the canonical name (no per-distro renames in v3 — we accept the rare miss like Alpine where `fzf` may have a different name).
2. For `yq`: always emit `pip3 install yq` regardless of platform (research.md §3a). Append the parenthetical Python-yq note exactly once at the end of the line.
3. For each missing optional dep on macOS only (`alerter`, `jq`): look up the macOS template (`brew install <pkg>`).
4. On non-macOS, skip the optional-deps section entirely; print the one-line "Note: Claude Code notification banners are macOS-only" (research.md §4) at the end of the dep-hint block instead.
5. If all required deps are present, skip the "Missing dependencies" header entirely. If only optional deps are missing on macOS, the header changes to `Optional dependencies for Claude notifications — install with:`.

### Rendering invariants

- Each hint line MUST be copy-pasteable as-is (no `<placeholder>` markers in the printed output).
- Indentation is exactly 4 spaces (matches the `tms install-hooks` post-install probe diagnostic block from feature 002 for visual consistency).
- The yq parenthetical note is the ONLY decoration; other lines are bare commands.

---

## Entity: Install Target

The absolute path of the symlink the install creates (default `~/.local/bin/tms`). Detection of pre-existing files at this path drives the FR-007 / FR-008 branches.

### Classification (`_install_classify_target`)

Given `target_link` (e.g., `/Users/ykchen/.local/bin/tms`):

| Condition (in evaluation order) | Returns | Branch |
|--------------------------------|---------|--------|
| `! [[ -e "$target_link" ]]` AND `! [[ -L "$target_link" ]]` | `absent` | Create new symlink |
| `[[ -L "$target_link" ]]` AND `readlink "$target_link" == "$tms_dir/bin/tms"` | `same-symlink` | Idempotent no-op |
| `[[ -L "$target_link" ]]` AND `readlink "$target_link" =~ /bin/tms$` AND target file exists and is executable | `tms-mismatch-symlink` | Update in place (user moved checkout) |
| `[[ -L "$target_link" ]]` (any other target) | `unrelated-symlink` | Refuse (per FR-008 spirit) |
| `[[ -e "$target_link" ]]` AND `! [[ -L "$target_link" ]]` | `non-symlink` | Refuse per FR-008 (file exists and is not a symlink) |

Note: `[[ -e ]]` is false for broken symlinks; we use `[[ -L ]]` first to disambiguate.

### Edge case: broken symlink

A broken symlink (target file doesn't exist, e.g., user deleted the old checkout) classifies as `tms-mismatch-symlink` if the broken target ends with `/bin/tms` — we replace it. Otherwise classifies as `unrelated-symlink` and we refuse. This is conservative; users with weirdly-named broken symlinks at the install prefix can manually `rm` them.

### Uninstall classification

`cmd_uninstall` classifies the same way and acts as follows:

| State | Action |
|-------|--------|
| `absent` | Print `No tms install found at <prefix>.`; exit 0. |
| `same-symlink` | `rm "$target_link"`; print `Removed tms symlink at <path>.` |
| `tms-mismatch-symlink` | `rm "$target_link"`; print `Removed tms symlink at <path> (was pointing at <other-tms-checkout>).` |
| `unrelated-symlink` | Refuse: `Error: <path> is a symlink to <target> which does not look like a tms checkout. Refusing to remove. Remove it manually if needed.` Exit 1. |
| `non-symlink` | Refuse: `Error: <path> exists and is not a symlink — not a tms install. Leaving it alone.` Exit 1. |

---

## Entity: Notify-Hook Subcommand

The `tms notify-hook` invocation. Its stdin/stdout/exit-code contract is unchanged from feature 002's `bin/tms-notify-hook`; this entity exists as a labeled boundary so the migration in FR-014 is testable without depending on internal implementation.

### Stdin contract (unchanged from feature 002)

See `specs/002-claude-notification-hook/contracts/tms-notify-hook-stdin.md` — the JSON payload shape, exit-code guarantees (FR-007: always exit 0), notification body construction, detached-subshell pattern, and error-branch behavior tree all carry over verbatim. The only material change is the shell entry point: instead of `bin/tms-notify-hook` (standalone script), the shell command is `<TMS_DIR>/bin/tms notify-hook` (subcommand on the main binary).

### Settings.json registration shape (unchanged structure, changed command)

| Field | Old (feature 002) | New (this feature) |
|-------|-------------------|---------------------|
| `.matcher` | `""` | `""` (unchanged) |
| `.hooks[].type` | `"command"` | `"command"` (unchanged) |
| `.hooks[].command` | `<TMS_DIR>/bin/tms-notify-hook` | `<TMS_DIR>/bin/tms notify-hook` |
| `.hooks[].timeout` | `10` | `10` (unchanged) |

Claude Code accepts the `.command` field as a single shell-string that may include arguments; `<path> notify-hook` is parsed as `<path>` argv[0] + `notify-hook` argv[1] in the spawned process. Confirmed against the Claude Code Hooks documentation referenced in `specs/002-claude-notification-hook/research.md` §3.

---

## Entity: Migration Record (transient)

A boolean signal in `cmd_install_hooks` indicating whether at least one settings.json entry was rewritten from `bin/tms-notify-hook` to `tms notify-hook`. Drives the one-line `Migrated tms-notify-hook entry to tms notify-hook.` print (FR-014). Not persisted; recomputed per invocation.

### Computation

After the jq migration query (research.md §7) runs, compare the pre-migration `original_json` to the post-migration `migrated_json`:

```bash
if [[ "$original_json" != "$migrated_json" ]]; then
    printf 'Migrated tms-notify-hook entry to tms notify-hook.\n'
fi
```

Idempotent: a second invocation finds no `bin/tms-notify-hook` suffixes in the (already migrated) JSON, the diff is empty, no message is printed.

---

## Relationships summary

```text
flag parsing                            (Entity: Install Plan — collected)
  │
  ▼
_install_classify_target                (Entity: Install Target — classified)
  │
  ├─► absent / same-symlink / tms-mismatch-symlink → write/no-op/update
  └─► unrelated-symlink / non-symlink → refuse + exit 1
  │
  ▼
_install_bootstrap_config               (Entity: config_state ∈ Install Plan)
  │
  ▼
_install_check_deps                     (Entity: Dependency Hint — list built)
  │
  ▼
_install_print_hints                    (Entity: Dependency Hint — rendered)
  │
  ▼
_install_check_path                     (Entity: prefix_on_path ∈ Install Plan)
  │
  ▼
_install_print_next_steps               (final user-facing block)


tms install-hooks                       (existing, modified)
  │
  ├─► jq migration (research.md §7)     (Entity: Migration Record)
  │     "rewrite .command if endswith bin/tms-notify-hook"
  │
  ├─► existing install/update/no-op flow against migrated JSON
  │
  └─► post-install probe banner (unchanged from feature 002)


Claude Code Notification fires
  │
  ▼
<tms-abs-path> notify-hook              (Entity: Notify-Hook Subcommand)
  │
  └─► dispatches into cmd_notify_hook in lib/notify.sh
      (subshell-wrapped to scope the ERR trap; behavior identical to
       feature 002's bin/tms-notify-hook script)
```

All entities are either transient (in-memory for one invocation) or are existing artifacts being read/written. No new persistent state is introduced.
