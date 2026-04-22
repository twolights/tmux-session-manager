# Implementation Plan: One-command Install + Single-binary Refactor

**Branch**: `feat/tms-install-bootstrap` (spec dir: `specs/003-tms-install-bootstrap/`) | **Date**: 2026-04-22 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/003-tms-install-bootstrap/spec.md`

## Summary

Add a `tms install` subcommand that bootstraps installation in one command (symlink `tms` into a chosen prefix, copy `projects.example.yml` to `projects.yml` if absent, print OS-aware dependency-install hints) and refactor the standalone `bin/tms-notify-hook` script into a `tms notify-hook` subcommand so users only ever symlink one binary. `tms install-hooks` gains a one-shot migration step that rewrites any pre-existing `~/.claude/settings.json` entry pointing at the old `bin/tms-notify-hook` path. Implementation is bash-only, additive to the existing `bin/` + `lib/` layout, and introduces no new runtime dependencies beyond what feature 002 already requires.

## Technical Context

**Language/Version**: Bash 4+ (POSIX-compatible where feasible), consistent with existing `lib/*.sh` modules
**Primary Dependencies**: tmux 3.2+, yq (Python-based), fzf, Claude Code CLI, macOS system frameworks; existing optional `alerter` + `jq` (from feature 002, unchanged). No new runtime dependencies.
**Storage**:
  - Install symlink: `~/.local/bin/tms` (default; overridable via `--prefix`). Per-prefix idempotency only (clarification 2026-04-22); no cross-prefix state file.
  - Config: `~/.config/tmux-session-manager/projects.yml` — created from `config/projects.example.yml` if absent (FR-002). NEVER overwritten.
  - Claude Code settings: `~/.claude/settings.json` — modified by the existing `tms install-hooks`, now with an in-place migration step (FR-014).
**Testing**: Manual scenario-based verification via `quickstart.md` (no automated harness — same as feature 002). Each acceptance scenario in spec.md and each behavior branch in contracts/ is mapped to a reproducible manual check.
**Target Platform**: macOS (Darwin), Linux (apt/dnf/pacman/zypper/apk distros), with graceful "partial install" behavior on other POSIX platforms (FR-003 + clarification 2026-04-22).
**Project Type**: Single-repo CLI tool (bash scripts).
**Performance Goals**: `tms install` MUST complete in under 1 second on a populated system (most cost is `command -v` probes and one `cp` for the example config). No per-project iteration; no network I/O.
**Constraints**:
  - MUST NOT modify the user's shell rc files. PATH warnings only (FR-009).
  - MUST NOT install Homebrew, apt, or any package manager itself — only print install hints.
  - MUST NOT overwrite a non-symlink at the install target (FR-008) or an existing `projects.yml` (FR-002).
  - The `notify-hook` subcommand MUST preserve the byte-for-byte stdin contract and FR-007 non-blocking guarantee from feature 002 (FR-012).
**Scale/Scope**: Single-user. Install runs once per machine plus rare re-runs (config moves, dep additions). Migration in FR-014 runs at most once per affected user; subsequent `tms install-hooks` runs are no-ops.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project's `.specify/memory/constitution.md` is an unfilled template (placeholder principles, no ratified version). No concrete gates to evaluate. The plan adheres to the implicit conventions documented in `CLAUDE.md`:

- **Bash-first**: New code is bash, matches existing `lib/*.sh` and `bin/tms` style; reuses `utils.sh` helpers (`die`, `warn`, `require_cmd`, `expand_path`, `config_dir`).
- **No build artifacts / Makefiles / packagers**: per spec Out-of-Scope, this feature explicitly does NOT add a Makefile, Homebrew formula, or curl-pipe installer.
- **No state files**: per clarification 2026-04-22, multi-prefix installs do NOT introduce a tracking state file. Each install operates only on the prefix passed to it.
- **Single-user assumption**: feature 002's "single-user tool" assumption carries forward and justifies the no-deprecation-shim policy for `bin/tms-notify-hook` (FR-013).
- **tmux target syntax**: not relevant to this feature (no tmux selectors used).

**Gate status**: PASS (no violations; nothing to justify in Complexity Tracking).

**Post-Phase 1 re-check**: PASS (filled in after Phase 1 completes — see end of file).

## Project Structure

### Documentation (this feature)

```text
specs/003-tms-install-bootstrap/
├── plan.md              # This file
├── spec.md              # Feature specification (already written; clarifications complete)
├── research.md          # Phase 0 output — OS/pkg-mgr detection, yq install hint, settings.json migration shape
├── data-model.md        # Phase 1 output — Install Plan / Dependency Hint / Install Target / Notify-Hook Subcommand entities
├── quickstart.md        # Phase 1 output — manual verification recipe (QS-1 through QS-N)
├── contracts/           # Phase 1 output
│   ├── tms-install-cli.md          # New: install subcommand contract
│   └── tms-install-hooks-cli.md    # Updated reference (migration behavior)
└── tasks.md             # Phase 2 output (/speckit-tasks; NOT created here)
```

### Source Code (repository root)

```text
bin/
├── tms                      # (modified) add `install` and `notify-hook` subcommand dispatch;
│                            # remove `tms-notify-hook` source-and-execute requirement.
└── tms-notify-hook          # (REMOVED — see FR-013) functionality folded into `tms notify-hook`.

lib/
├── utils.sh                 # (unchanged) — die, warn, require_cmd, expand_path, config_dir
├── config.sh                # (unchanged from this feature; perf branch lite-load is independent)
├── session.sh               # (unchanged)
├── servers.sh               # (unchanged)
├── notify.sh                # (modified)
│                            # 1. Move the prior `bin/tms-notify-hook` script body into a function
│                            #    `cmd_notify_hook` exposed via the `tms notify-hook` subcommand.
│                            # 2. cmd_install_hooks gains an FR-014 migration step that rewrites any
│                            #    settings.json entry whose .command ends with `bin/tms-notify-hook`
│                            #    to the new `<tms-abs-path> notify-hook` form.
│                            # 3. cmd_install_hooks now expects the registered command to be
│                            #    `<TMS_DIR>/bin/tms notify-hook` (two tokens) — adjust the existing
│                            #    write-back jq expression accordingly.
└── install.sh               # (NEW) — cmd_install + helpers
                             #   - cmd_install / cmd_uninstall (parses --prefix, --dry-run, --uninstall)
                             #   - _install_resolve_prefix
                             #   - _install_symlink (idempotent symlink writer; FR-007 / FR-008)
                             #   - _install_bootstrap_config (copy projects.example.yml if absent; FR-002)
                             #   - _install_check_deps (probes presence; calls _install_print_hints)
                             #   - _install_print_hints (per-OS, per-pkg-manager hint formatting)
                             #   - _install_detect_os / _install_detect_pkg_manager
                             #   - _install_check_path (warns if prefix not on $PATH; FR-009)
                             #   - _install_print_next_steps (final user-facing block)

config/
└── projects.example.yml     # (unchanged) — sourced by `_install_bootstrap_config`.

README.md                    # (modified) replace the manual install steps with `./bin/tms install`.
                             #   Document `--prefix`, `--dry-run`, `--uninstall`. Document the new
                             #   `tms notify-hook` form (mostly invisible to users via install-hooks).
CLAUDE.md                    # (auto-updated by .specify/scripts/bash/update-agent-context.sh)
```

**Structure Decision**: Single-project layout, additive. New library module `lib/install.sh` keeps install logic isolated from `notify.sh` (which already owns Claude-hook-related code) so the two concerns don't entangle. The `bin/tms` dispatcher gains exactly two new case arms (`install)` and `notify-hook)`); no other top-level binary is added (and one — `tms-notify-hook` — is removed). This matches the existing flat layout convention and keeps the new surface area minimal.

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified.

Not applicable — Constitution Check passed with no violations. The single new module (`lib/install.sh`) is justified by separation of concerns (install ≠ notify), not novelty.

---

## Post-Phase 1 re-check

Filled after Phase 1 (data-model, contracts, quickstart) completes:

**Status**: PASS.

Phase 1 outputs introduce:
- One new contract document (`contracts/tms-install-cli.md`) and one updated reference to the existing `contracts/tms-install-hooks-cli.md` (for the FR-014 migration step). No new architectural patterns.
- No new languages, no new runtime dependencies, no new state files, no new build steps.
- The migration step in `tms install-hooks` reuses the existing `jq` round-trip pattern from feature 002; it only adds one match-and-rewrite jq expression.

The new `lib/install.sh` module is the only added file; `bin/tms-notify-hook` is removed in net change of zero new top-level binaries. Plan remains within the existing bash + yq + tmux + (now) jq + alerter surface.
