# Phase 0 Research: One-command Install + Single-binary Refactor

**Feature**: 003-tms-install-bootstrap
**Date**: 2026-04-22

This document resolves the remaining technical unknowns from `plan.md`'s Technical Context. Each section follows Decision / Rationale / Alternatives. No `NEEDS CLARIFICATION` markers remain after this phase.

---

## 1. OS detection

**Decision**: Use `uname -s` once at the start of `cmd_install`, normalize the result with a case statement to one of three buckets: `Darwin` → "macos", `Linux` → "linux", anything else → "other". The detected bucket drives dependency-hint formatting (§3) and gates the Claude-notification advertisement (§4).

**Rationale**: `uname -s` is POSIX, available on every shell environment we'd plausibly support, and produces stable strings. A three-bucket split matches the spec's explicit handling: macOS gets Homebrew hints, Linux gets per-pkg-manager hints, "other" gets generic hints (clarification 2026-04-22). We deliberately do NOT detect macOS architecture (Intel vs Apple Silicon) — Homebrew handles its own prefix internally and the install hints we print (`brew install <pkg>`) are identical on both.

**Alternatives considered**:

- `$OSTYPE` (bash-specific) — works on bash but is non-POSIX. Since `bin/tms` already uses `#!/usr/bin/env bash`, this would be safe, but `uname` is more portable and aligns with the existing project style of using stable POSIX commands.
- Per-distro detection on Linux (parsing `/etc/os-release`) — overkill. Pkg-manager presence (§2) is the only thing we actually need; whether the host calls itself "Ubuntu" vs "Linux Mint" doesn't change the install command.

---

## 2. Linux package-manager detection

**Decision**: Probe for installed package managers via `command -v` in the priority order **apt → dnf → pacman → zypper → apk**, first match wins. If none match, drop to the "generic" hint format. Per FR-005 / clarification 2026-04-22 (low-impact item, locked in by spec).

Specific install-command templates:

| Detected | Install template | Notes |
|----------|------------------|-------|
| `apt-get` (or `apt`) | `sudo apt install <pkg>` | Modern apt is preferred; `apt-get` works too. |
| `dnf` | `sudo dnf install <pkg>` | Fedora / RHEL 8+. |
| `pacman` | `sudo pacman -S <pkg>` | Arch / Manjaro. `-S` is install. |
| `zypper` | `sudo zypper install <pkg>` | openSUSE. |
| `apk` | `sudo apk add <pkg>` | Alpine. |
| (none) | `Install <pkg> via your distro's package manager.` | Never guess wrong. |

**Rationale**: `command -v` is POSIX and faster than spawning the package manager itself with `--version`. Priority order reflects rough population share among likely tms users (apt > dnf > others). The "first match wins" rule is simple and predictable; users on a hybrid setup (apt + dnf) will get the apt hint, which is consistent with the apt-being-more-common assumption from the spec's Assumptions section.

**Alternatives considered**:

- Auto-detect based on `/etc/os-release` `ID` field — finer-grained but redundant: pkg-manager presence is what actually matters for the hint command.
- Probe pkg managers in a different order (e.g., dnf first because Fedora is a more common dev-laptop choice in some communities) — population-share-arguments are not strong enough to override the spec's locked-in order.
- Detect `flatpak` / `snap` / `nix` — out of scope; tms runtime deps (`tmux`, `yq`, `fzf`, `jq`) are all conventionally installed as system packages.

---

## 3. Per-package install commands across platforms

**Decision**: Hardcode a small per-package, per-(os, pkg-manager) lookup table in `lib/install.sh`. Most packages have the same name across distros; the only non-uniform case is **yq**, which is handled with a special pip-based hint (§3a).

| Package | macOS (Homebrew) | apt | dnf | pacman | zypper | apk | generic / other |
|---------|------------------|-----|-----|--------|--------|-----|-----------------|
| `tmux` | `brew install tmux` | `sudo apt install tmux` | `sudo dnf install tmux` | `sudo pacman -S tmux` | `sudo zypper install tmux` | `sudo apk add tmux` | `Install tmux via your package manager.` |
| `yq` (Python — see §3a) | `pip3 install yq` | `pip3 install yq` | `pip3 install yq` | `pip3 install yq` | `pip3 install yq` | `pip3 install yq` | `pip3 install yq` |
| `fzf` | `brew install fzf` | `sudo apt install fzf` | `sudo dnf install fzf` | `sudo pacman -S fzf` | `sudo zypper install fzf` | `sudo apk add fzf` | `Install fzf via your package manager.` |
| `alerter` (macOS only) | `brew install alerter` | (not advertised on Linux per FR-006) |  |  |  |  | (not advertised on non-macOS) |
| `jq` | `brew install jq` | `sudo apt install jq` | `sudo dnf install jq` | `sudo pacman -S jq` | `sudo zypper install jq` | `sudo apk add jq` | `Install jq via your package manager.` |

### 3a. The yq special case

**Decision**: For `yq`, regardless of OS or detected pkg-manager, print `pip3 install yq` as the install hint, with a one-line preamble noting "Note: tms requires Python yq (kislyuk), not the Go-based mikefarah yq commonly shipped by package managers."

**Rationale**: `yq` is the only package whose canonical name conflicts across ecosystems. On macOS, `brew install yq` installs mikefarah's Go yq, not the Python one tms requires (per `CLAUDE.md`: "yq: uses Python-based yq (pip install yq), not mikefarah/yq."). On Fedora, `dnf install yq` installs Go yq too. On Debian/Ubuntu, `apt install yq` does NOT exist as a Python yq package universally — `python3-yq` is shipped only on some releases. Suggesting `pip3 install yq` is consistent across every platform, always installs the right tool, and matches the existing project documentation. The only failure mode is "user doesn't have pip" — which is rare on dev machines and surfaced by pip's own absence error if attempted.

**Alternatives considered**:

- Detect distro and use `python3-yq` where available (Debian/Ubuntu, openSUSE) — adds detection complexity for marginal benefit; user still ends up with the right tool either way.
- Suggest `pipx install yq` instead of `pip3` — pipx is cleaner (per-tool venv) but not universally pre-installed; pip3 is the lowest-common-denominator. Document pipx as an alternative in the README, not in the install hint.
- Tell the user "install yq somehow, then check with `which yq`" — useless; the whole point of dependency hints is to copy-paste a command.

---

## 4. Notification dependency advertisement on non-macOS

**Decision**: On Linux (any distro) and on "other" platforms, `cmd_install` does NOT include `alerter` or `jq` in its dependency-hint output. Instead, it prints exactly one line at the end of the dep-hint block: `Note: Claude Code notification banners are macOS-only in this version. To use them, install on macOS.` Per FR-006 + clarification 2026-04-22.

**Rationale**: `alerter` is a macOS-only binary (depends on `UNUserNotificationCenter`). Listing it as a missing dep on Linux would suggest the user can install it, which is false. `jq` is technically cross-platform, but in the tms surface area it's only used by `tms install-hooks`, which is itself macOS-only because it sets up an alerter pipeline. Bundling them into a single "macOS-only feature" line is more accurate and less noisy than listing each separately with a "doesn't apply to your OS" footnote.

**Alternatives considered**:

- List `alerter`/`jq` as missing on Linux but mark them "(macOS-only)" — visually noisy and confuses the dep-hint format.
- Probe for `alerter` even on Linux and silently skip if absent — works but tells the user nothing about why notifications aren't an option for them. Loud is better than silent here.
- Auto-substitute `notify-send` (libnotify) on Linux — out of scope for v3 (per spec Out-of-Scope: "Linux notification support — separate feature").

---

## 5. PATH-on-prefix detection

**Decision**: After installing the symlink, check whether the resolved prefix appears in the user's `$PATH`. Implementation: split `$PATH` on `:`, realpath-normalize each entry that exists as a directory, compare against the realpath-normalized prefix. If the prefix is not present, print a one-line warning with the exact shell-rc append line:

```text
Note: <prefix> is not on your $PATH.
To use `tms` from any shell, add this line to your shell rc (~/.zshrc, ~/.bashrc, etc.):

    export PATH="<prefix>:$PATH"
```

The warning does NOT block install (FR-009: "Successful install otherwise.").

**Rationale**: A common failure mode for fresh installs is "I ran it but `tms` isn't found" — the user has the symlink but `~/.local/bin/` isn't on PATH (Debian/Ubuntu put it on PATH conditionally; macOS doesn't by default). The warning catches this proactively. Realpath normalization handles the case where the user has `$HOME/.local/bin` in PATH and `--prefix=~/.local/bin` (or vice versa) — string comparison alone would miss it. The script does NOT modify shell rc files (per spec Out-of-Scope: too risky, too many shell-rc combinations).

**Alternatives considered**:

- Modify the user's `.zshrc` / `.bashrc` automatically — rejected (spec Out-of-Scope, dangerous, requires guessing which rc file is authoritative for the user's shell).
- Fail-loud with non-zero exit on PATH miss — too aggressive; many users add to PATH later or use direnv / mise / asdf shims.
- Use `which tms` post-install to verify — works but doesn't tell us *which* prefix is missing from PATH for the warning text. Manual `$PATH` walk gives precise diagnostics.

---

## 6. Symlink semantics — install, update, refuse

**Decision**: At write time, `cmd_install` distinguishes four states at the install-target path `<prefix>/tms`:

| State | Behavior |
|-------|----------|
| Path does not exist | Create the symlink → `<TMS_DIR>/bin/tms`. Print `Installed tms at <path>.` |
| Path exists, is a symlink, target is exactly `<TMS_DIR>/bin/tms` | Idempotent no-op. Print `tms is already installed at <path>.` |
| Path exists, is a symlink, target is some other path ending in `/bin/tms` | The user moved their checkout. Replace the symlink in place. Print `Updated tms path: <old> → <new>` |
| Path exists, is a symlink, target is unrelated (does NOT end in `/bin/tms`) | Refuse. Print `Error: <path> is a symlink to <target> which does not look like a tms checkout. Refusing to overwrite. Use --prefix=<dir> to install elsewhere.` Exit 1. |
| Path exists, is NOT a symlink (regular file, dir, etc.) | Refuse per FR-008. Print `Error: <path> exists and is not a symlink — refusing to overwrite. Move it aside or use --prefix=<dir>.` Exit 1. |

Detection uses `[[ -L "<path>" ]]` (symlink test) and `readlink "<path>"` (target read) — POSIX shell builtins. Target-path "looks like a tms checkout" is the heuristic `<target>` ends with `/bin/tms` AND `<target>` exists AND is executable. Conservative: false negatives (user has a similarly-named tool not in `bin/tms`) prefer to refuse rather than corrupt state.

**Rationale**: Mirrors the established pattern in `cmd_install_hooks` (feature 002, lib/notify.sh:_install_hooks_install) where path-mismatch updates in place but unrelated entries are left alone. The "ends in /bin/tms" heuristic is what `cmd_install_hooks` already uses for its own settings.json migration; reusing it here keeps the codebase coherent.

**Alternatives considered**:

- Always overwrite the symlink (no refuse case) — destroys user-managed symlinks the user may have set up for their own reasons. FR-008 explicitly requires refuse.
- Use `find` to verify the target is a tms checkout (e.g., look for `lib/notify.sh` next to it) — over-engineered for the rarity of the false-positive case.
- `--force` flag to override the refuse — out of scope for v3; if user has a custom symlink they need to move aside, manual `rm` is one step.

---

## 7. settings.json migration: `bin/tms-notify-hook` → `tms notify-hook`

**Decision**: In `cmd_install_hooks` (lib/notify.sh, feature 002), add a migration step that runs **before** the existing entry-locator logic. The migration:

1. Read `~/.claude/settings.json` (treat missing as `{}` — same as current install path).
2. Find any entry under `.hooks.Notification[]` whose `.hooks[].command` ends with `bin/tms-notify-hook` (the old binary path).
3. For each match, rewrite that entry's `.command` to `<TMS_DIR>/bin/tms notify-hook` (note the space — single string, two tokens). Preserve `.timeout`, `.type`, `.matcher`, and any other existing fields.
4. If migrations occurred, print `Migrated tms-notify-hook entry to tms notify-hook.` (FR-014, exactly one line). Continue with the normal install/update/no-op flow against the post-migration JSON.
5. The post-migration JSON is what the rest of `cmd_install_hooks` operates on; the existing path-comparison logic now compares against `<TMS_DIR>/bin/tms notify-hook` instead of `<TMS_DIR>/bin/tms-notify-hook`.

jq query for step 2-3 (executed in a single round-trip):

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

Run with `--arg newcmd "<TMS_DIR>/bin/tms notify-hook"`. The `bin/tms-notify-hook` suffix match is the same boundary `cmd_install_hooks` already uses for its own entry-finder — it correctly handles symlinked or absolute-path variations of the old entry.

**Rationale**: A focused jq migration step that runs once on the in-memory JSON before the install logic touches it. The match condition (`endswith("bin/tms-notify-hook")`) is the existing boundary used for entry detection in feature 002; reusing it ensures we migrate exactly the entries the prior install would have managed, no more, no less. The migration is structurally idempotent: re-running the migration on already-migrated JSON finds no matches and rewrites nothing, so the FR-014 "silent on subsequent runs" requirement falls out for free.

**Alternatives considered**:

- Migration logic in a separate `_install_hooks_migrate` function called as Step 0 of install — cleaner separation, but adds a layer for what is one jq query. Inlining is fine.
- Invoke a separate `tms migrate-hooks` subcommand — more user-visible than necessary; the migration is a one-time thing that should happen invisibly during the user's normal `tms install-hooks` run.
- Detect-and-fail approach (refuse to install over a stale entry, instruct user to manually fix) — terrible UX for what is unambiguously an in-place rewrite.

---

## 8. Subcommand wrapping: `bin/tms-notify-hook` → `tms notify-hook`

**Decision**: Move the entire body of the old `bin/tms-notify-hook` script into a new function `cmd_notify_hook` in `lib/notify.sh`. The function preserves the script's source-stdin-read-and-dispatch logic verbatim (including the trap, the IFS read with timeout, the parse-error / no-cwd / no-project-match / opt-out / empty-message / alerter-missing branches, and the detached subshell that invokes alerter). `bin/tms` gains a `notify-hook)` case arm that calls `cmd_notify_hook` after sourcing the lib modules (already loaded for other subcommands).

**Rationale**: This is a pure mechanical move. Feature 002 FR-007 (non-blocking) and the entire behavior tree from `contracts/tms-notify-hook-stdin.md` continue to hold byte-for-byte. The old script's `set -euo pipefail` and `trap '_hook_error_handler' ERR` translate cleanly into the function (the function body has the same semantics; trap scope is the function via local trap, OR we leave the trap at script-top and rely on dispatch falling through to `cmd_notify_hook`).

Open question for implementation (resolved here): trap scope. The trap is currently set at the top of `bin/tms-notify-hook`; in the refactored shape, `bin/tms` doesn't want a script-wide ERR trap because it would change behavior for `start`/`stop`/`list`/etc. Resolution: define the trap inside `cmd_notify_hook` using `trap '...' ERR` at function entry (bash supports per-function traps via `local -` and `set -E` inheritance), and `set +E ; trap - ERR` on exit. Or simpler: wrap the function body in a subshell `( ... )` and put the trap inside, so the trap dies with the subshell. The subshell approach is cleaner and avoids any possibility of trap leakage; it's also consistent with the detached-subshell pattern already used for the alerter invocation. Decision: subshell wrap inside `cmd_notify_hook`.

**Alternatives considered**:

- Keep `bin/tms-notify-hook` as a one-liner that `exec`s `tms notify-hook` (i.e., a permanent shim) — creates a cyclic dependency (the shim needs `tms` to be on PATH) and re-introduces the two-binary surface area FR-013 explicitly removes.
- Source `bin/tms-notify-hook`'s body into `bin/tms` directly without a `cmd_notify_hook` function — works but obscures the dispatch shape. Function-per-subcommand is the established pattern.

---

## Summary of decisions feeding Phase 1

- **OS bucket**: `Darwin` / `Linux` / `other` via `uname -s`.
- **Linux pkg-manager**: probe order apt → dnf → pacman → zypper → apk; first match wins; "(none)" → generic hint.
- **yq install hint**: `pip3 install yq` everywhere, with a one-line note about the kislyuk-vs-mikefarah distinction.
- **Notification deps on non-macOS**: not advertised; one-line "macOS-only" footer instead.
- **PATH detection**: realpath-normalized walk of `$PATH`; warn-only on miss; never modify shell rc.
- **Symlink semantics**: idempotent on exact match, in-place update on tms-checkout-mismatch, refuse otherwise.
- **settings.json migration**: one jq round-trip in `cmd_install_hooks` rewrites `bin/tms-notify-hook` → `tms notify-hook`; print one line if changes happened.
- **Subcommand wrap**: move script body to `cmd_notify_hook` in `lib/notify.sh`, wrap in a subshell so the ERR trap doesn't leak into the parent `bin/tms` process.

All Technical Context unknowns resolved; no `NEEDS CLARIFICATION` markers remaining.
