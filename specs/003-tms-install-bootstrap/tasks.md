---

description: "Task list for feature 003-tms-install-bootstrap"
---

# Tasks: One-command Install + Single-binary Refactor

**Input**: Design documents from `/specs/003-tms-install-bootstrap/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Not generated. The repo has no automated test harness (established by feature 001, carried through feature 002). `quickstart.md` is the manual verification recipe; task T025 runs the full QS-1..QS-16 suite as the acceptance gate for the feature.

**Organization**: Tasks grouped by user story so each story is independently completable and testable as an MVP increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Paths are absolute

## Path Conventions

Single-repo bash CLI layout (see plan.md §Project Structure). All paths rooted at `/Users/ykchen/Projects/ykchen/tmux-session-manager/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the skeleton for the new library module so subsequent tasks can edit it without path-not-found errors. No business logic.

- [X] T001 [P] Create skeleton `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh` with `#!/usr/bin/env bash` shebang and a one-line header comment (`# install.sh — tms install/uninstall + OS-aware dependency hints`). File is sourced by `bin/tms`; no executable bit needed.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core primitives every user story depends on: flag parsing, OS detection, prefix resolution. All live in `lib/install.sh` so tasks are sequential within this phase.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 Implement `_install_parse_flags` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh` per contracts/tms-install-cli.md §Signature: parse `--prefix=<dir>` (default `~/.local/bin/`), `--uninstall`, `--dry-run`. Unknown flags → `die` with the usage line from the contract. Set global vars `_INSTALL_PREFIX`, `_INSTALL_UNINSTALL`, `_INSTALL_DRY_RUN` for the rest of the module to consume.
- [X] T003 Implement `_install_detect_os` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh` per research.md §1: `uname -s` → normalize to one of `macos` / `linux` / `other`. Print to stdout. Depends on T002 (same file).
- [X] T004 Implement `_install_resolve_prefix` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh`: take the user-supplied `--prefix` value (or default), run it through `expand_path` (existing helper in `lib/utils.sh`), then realpath-normalize to an absolute path. Create the directory with `mkdir -p -m 0755` if absent; `die` on `mkdir` failure per contract error-handling table. Depends on T003 (same file).

**Checkpoint**: Foundation ready — US1, US2, US3 can proceed.

---

## Phase 3: User Story 1 — Single-command first-time install (Priority: P1) 🎯 MVP

**Goal**: On a fresh checkout, `./bin/tms install` symlinks `tms` to the chosen prefix, bootstraps `~/.config/tmux-session-manager/projects.yml` from the example if absent, prints dep hints for the **macOS** bucket, checks PATH membership, and prints the next-step block. Also provides `--uninstall` and `--dry-run`.

**Independent Test**: On a fresh clone on macOS, run `./bin/tms install`; verify QS-1 (happy path), QS-2 (non-destructive config), QS-3 (idempotent re-run), QS-4 (repo move), QS-5 (uninstall preserves config), QS-6 (dry-run), QS-7 and QS-8 (refuse branches), QS-9 (PATH warning), QS-10 (macOS dep hints), QS-13 (multi-prefix independence).

### Implementation for User Story 1

- [X] T005 [P] [US1] Implement `_install_classify_target` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh` per data-model.md §Install Target: given the resolved `target_link` path, return one of `absent` / `same-symlink` / `tms-mismatch-symlink` / `unrelated-symlink` / `non-symlink`. Uses `[[ -L ]]` and `readlink`; the "ends in /bin/tms" heuristic per research.md §6. Print the classification to stdout. Depends on T004 (same file).
- [X] T006 [US1] Implement `_install_symlink` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh` per contracts/tms-install-cli.md §Install: branches on `_install_classify_target` output: absent → `ln -s`; same-symlink → no-op message; tms-mismatch-symlink → `rm && ln -s` with "Updated" message; unrelated-symlink or non-symlink → `die` with the exact error text from the contract. Depends on T005.
- [X] T007 [P] [US1] Implement `_install_bootstrap_config` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh` per FR-002: compute `<config_dir>` via `${TMS_CONFIG_DIR:-$HOME/.config/tmux-session-manager}` (matching `lib/utils.sh:config_dir`); `mkdir -p -m 0755` the dir; if `<config_dir>/projects.yml` does NOT exist, `cp "$TMS_DIR/config/projects.example.yml" "<config_dir>/projects.yml"` and print `Created <path> from example.`; else print `Config already present at <path>.`. NEVER overwrite. Depends on T004 (same file).
- [X] T008 [P] [US1] Implement `_install_check_deps` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh` per data-model.md §Dependency Hint: probe `command -v` for required deps (`tmux`, `yq`, `fzf`) and push missing ones to `_MISSING_REQUIRED`. On macOS (`_OS_BUCKET == macos`) additionally probe optional deps (`alerter`, `jq`) and push to `_MISSING_OPTIONAL`. Do NOT print anything — `_install_print_hints` is a separate task. Depends on T003 (reads `_OS_BUCKET`).
- [X] T009 [US1] Implement the **macOS branch** of `_install_print_hints` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh` per research.md §3: when `_OS_BUCKET == macos`, emit `brew install <pkg>` for each missing required dep EXCEPT `yq` which emits `pip3 install yq    # (Python yq, not mikefarah/yq — see README)`; then `brew install <pkg>` for each missing optional dep. Header text: `Missing dependencies — install with:` (required) and `Optional dependencies for Claude notifications — install with:` (optional). Leave Linux and "other" branches as stubs (empty case arms, TODO comments pointing at US3 tasks). Depends on T008.
- [X] T010 [P] [US1] Implement `_install_check_path` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh` per research.md §5 and FR-009: split `$PATH` on `:`, realpath-normalize each directory entry that exists, compare to the realpath-normalized `_INSTALL_PREFIX`; if no match, print the PATH warning block (exact text from research.md §5) with `export PATH="<prefix>:$PATH"`. Does NOT exit non-zero. Depends on T004 (reads `_INSTALL_PREFIX`).
- [X] T011 [P] [US1] Implement `_install_print_next_steps` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh` per contracts/tms-install-cli.md §Install step 8: print the two-line "Next steps:" block. The `(macOS only) Run \`tms install-hooks\`…` second line is emitted ONLY when `_OS_BUCKET == macos` (so Linux/other users don't see the macOS-only suggestion). Depends on T003 (reads `_OS_BUCKET`).
- [X] T012 [US1] Implement `cmd_install` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh` as the top-level orchestrator: call `_install_parse_flags`, `_install_detect_os`, `_install_resolve_prefix`, then branch on `_INSTALL_UNINSTALL` (→ `_install_uninstall_symlink`). On install: if `_INSTALL_DRY_RUN`, every subsequent action prints `[dry-run] would …` prefix and writes nothing; otherwise run the full sequence: `_install_symlink` → `_install_bootstrap_config` → `_install_check_deps` → `_install_print_hints` → `_install_check_path` → `_install_print_next_steps`. Exit 0 on success. Depends on T002, T003, T004, T006, T007, T008, T009, T010, T011.
- [X] T013 [US1] Implement `cmd_uninstall` (and helper `_install_uninstall_symlink`) in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh` per data-model.md §Install Target uninstall classification: branches on `_install_classify_target` — absent → friendly "No tms install found"; same-symlink / tms-mismatch-symlink → `rm` + message; unrelated-symlink / non-symlink → `die` with refusal. After removal, print the one-line note about `tms install-hooks --uninstall` per contracts/tms-install-cli.md §Uninstall. Does NOT touch `~/.config/tmux-session-manager/`. Depends on T005 (same file, shared classifier).
- [X] T014 [US1] Add `install` subcommand dispatch in `/Users/ykchen/Projects/ykchen/tmux-session-manager/bin/tms`: source `lib/install.sh` near the other `source` lines; add `install)` case arm that calls `cmd_install "$@"`. Update the `usage()` heredoc: add `tms install [--prefix=<dir>] [--uninstall] [--dry-run]   Bootstrap tms: symlink bin/tms, copy example config, print dep hints`. Depends on T012 and T013.

**Checkpoint**: User Story 1 (MVP on macOS) is functional and testable. QS-1, QS-2, QS-3, QS-4, QS-5, QS-6, QS-7, QS-8, QS-9, QS-10, QS-13 pass on macOS. Linux runs of `tms install` will print empty dep-hint blocks (stubs from T009) — that's filled in by US3.

---

## Phase 4: User Story 2 — Single-binary footprint (Priority: P1)

**Goal**: `bin/tms-notify-hook` is folded into a `tms notify-hook` subcommand. `tms install-hooks` transparently migrates pre-existing `~/.claude/settings.json` entries from the old path to the new one. After this phase, `bin/` contains exactly one user-facing script.

**Independent Test**: QS-14 (migration on first post-pull install-hooks run), QS-15 (`bin/tms-notify-hook` is gone), QS-16 (`tms notify-hook` direct invocation byte-for-byte matches feature 002's behavior). Feature 002 QS-2 / QS-3 / QS-4 / QS-6 / QS-7 all pass unchanged.

### Implementation for User Story 2

- [X] T015 [US2] Move the body of `/Users/ykchen/Projects/ykchen/tmux-session-manager/bin/tms-notify-hook` into a new function `cmd_notify_hook` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh` per research.md §8. Wrap the function body in a subshell `( ... )` so the `set -euo pipefail` and `trap '_hook_error_handler' ERR` don't leak into the parent `bin/tms` process. Preserve verbatim: stdin read with timeout, parse-error / no-cwd / no-project-match / opt-out / empty-message / alerter-missing branches, detached alerter subshell, structured `switch-failed` log on click-callback failure. `TMS_DIR` is already resolved by `bin/tms`; no need to recompute inside the function. `_hook_error_handler` → move to a static helper inside `cmd_notify_hook`'s subshell.
- [X] T016 [US2] Delete `/Users/ykchen/Projects/ykchen/tmux-session-manager/bin/tms-notify-hook` per FR-013 (single-binary footprint). Use `git rm`. No shim is left behind (clarification 2026-04-22). Depends on T015 (so functionality survives the delete).
- [X] T017 [US2] Add `notify-hook` subcommand dispatch in `/Users/ykchen/Projects/ykchen/tmux-session-manager/bin/tms`: add `notify-hook)` case arm that calls `cmd_notify_hook "$@"`. Do NOT add this subcommand to the `usage()` heredoc — it's an internal-only entry point called by Claude Code, not a user-typed command (surface it in a one-line "Internal subcommands:" footer in usage() if desired). Depends on T015.
- [X] T018 [US2] Implement the settings.json migration step in `cmd_install_hooks` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh` per contracts/tms-install-hooks-cli-update.md §Change 1 and research.md §7: run a single jq query that rewrites any `.hooks.Notification[].hooks[].command` ending with `bin/tms-notify-hook` to `<TMS_DIR>/bin/tms notify-hook`. If the resulting JSON differs from the input, print exactly `Migrated tms-notify-hook entry to tms notify-hook.` (one line). The rest of `cmd_install_hooks` then operates on the migrated JSON. Run this step unconditionally at the start of the function (before flag-branching) so it also runs under `--uninstall` and `--dry-run`.
- [X] T019 [US2] Update `cmd_install_hooks` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh` per contracts/tms-install-hooks-cli-update.md §Change 2 and §Change 3: change the entry-locator suffix match from `bin/tms-notify-hook` to `bin/tms notify-hook` (note the space). Change the entry-writer to set `.command = "<TMS_DIR>/bin/tms notify-hook"`. Update the post-install probe's diagnostic text that references the path to say `<TMS_DIR>/bin/tms notify-hook` instead of the old form. Depends on T018 (same function).

**Checkpoint**: User Story 2 complete. QS-14, QS-15, QS-16 pass. All feature 002 behavior preserved byte-for-byte (verified by re-running feature 002 QS-2, QS-3).

---

## Phase 5: User Story 3 — OS-aware dependency hints (Priority: P2)

**Goal**: `tms install` detects Linux vs macOS vs other and prints the correct per-pkg-manager install hint. On Linux, probes apt/dnf/pacman/zypper/apk in priority order; generic "install via your package manager" fallback when none match. On non-macOS, omits `alerter`/`jq` hints entirely and prints a "macOS-only" footer.

**Independent Test**: QS-11 (apt hints on Linux), QS-12 (notifications not advertised on Linux), and the full US3 acceptance-scenario matrix (macOS+brew / Linux+apt / Linux+dnf / Linux+pacman / Linux+zypper / Linux+apk / Linux+none / other-OS) per SC-004.

### Implementation for User Story 3

- [X] T020 [P] [US3] Implement `_install_detect_pkg_manager` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh` per research.md §2: probe `command -v` in the order apt → dnf → pacman → zypper → apk; first match wins; return the detected name (or empty string). Print to stdout. Callable only when `_OS_BUCKET == linux`; elsewhere short-circuits to empty. Depends on T003 (reads `_OS_BUCKET`).
- [X] T021 [US3] Implement the **Linux branch** of `_install_print_hints` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh`: when `_OS_BUCKET == linux`, look up `_install_detect_pkg_manager` and emit the per-pkg-manager install command per the table in research.md §3 (e.g., `sudo apt install <pkg>`, `sudo pacman -S <pkg>`). `yq` always uses `pip3 install yq    # (Python yq, not mikefarah/yq — see README)`. If pkg-manager is empty (none detected), emit the generic `Install <pkg> via your distro's package manager.` form. Depends on T009 (replaces the stub added there) and T020.
- [X] T022 [US3] Implement the **"other" branch** of `_install_print_hints` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh`: when `_OS_BUCKET == other`, emit `Install <pkg> via your package manager.` for each missing required dep. Generic form; no per-OS specialization. Depends on T021 (same function; avoid merge conflicts).
- [X] T023 [US3] Add the non-macOS footer line in `_install_print_hints` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/install.sh` per FR-006 and clarification 2026-04-22: when `_OS_BUCKET != macos` AND the required-deps block was printed (or was empty but the header was considered), append one final line: `Note: Claude Code notification banners are macOS-only in this version.`. Depends on T022 (same function).

**Checkpoint**: User Story 3 complete. QS-11 and QS-12 pass. Full (OS × pkg-manager) matrix from SC-004 verified.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, end-to-end acceptance, perf sanity.

- [X] T024 [P] Update `/Users/ykchen/Projects/ykchen/tmux-session-manager/README.md` per FR-008: replace the manual "Installation" section (steps 1-4: clone, symlink, mkdir config, edit projects.yml) with a single `./bin/tms install` line plus a "what it does" bullet list. Document `--prefix=<dir>`, `--uninstall`, `--dry-run`. In the "Enabling Claude Code notifications" section, update any `bin/tms-notify-hook` references to `tms notify-hook`. Add a one-paragraph "Migrating from feature 002" note explaining that `tms install-hooks` now auto-migrates settings.json entries.
- [ ] T025 Run the full quickstart.md verification suite (QS-1 through QS-16) from a clean state on `feat/tms-install-bootstrap`. Any genuine failure re-opens the corresponding phase before this task can be marked done. Depends on T015–T023 (all code complete).
- [X] T026 Measure `tms install` wall-clock time on a populated system: `time ./bin/tms install` (idempotent re-run path, so no actual writes happen beyond re-probing). Record p95 over 10 runs. If p95 > 1000ms, investigate `command -v` redundancy or `realpath` bottleneck. Depends on T025 (feature should be working end-to-end first).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies. T001 only.
- **Foundational (Phase 2)**: Depends on Setup. T002 → T003 → T004 are sequential in `lib/install.sh`.
- **User Stories (Phase 3, 4, 5)**: All depend on Foundational complete. US1 and US2 are both P1; US3 is P2 and naturally sequenced after US1 (extends its hint logic).
- **Polish (Phase 6)**: Depends on all user stories complete.

### User Story Dependencies

- **US1 (P1, MVP)**: Depends only on Foundational. Independently testable on macOS (QS-1..QS-10 except QS-11/QS-12, plus QS-13).
- **US2 (P1)**: Depends on Foundational. Shares `lib/notify.sh` with existing feature 002 code. Does NOT depend on US1 (could run first if desired; placed second here because US1 is the larger piece).
- **US3 (P2)**: Depends on US1 having implemented `_install_print_hints` stubs (T009). Fills in the Linux and "other" branches.

### Within Each User Story

- **US1**: T005 is the pivot (classifier feeds T006 and T013). T007/T008/T010/T011 are parallel-capable once T003/T004 land. T012 and T013 depend on everything before them. T014 queues after T012+T013.
- **US2**: T015 → T016 (delete) → T017 (dispatch). T018 runs in parallel with T015-T017 since it's a different function in the same file (but queue behind for commit cleanliness). T019 depends on T018.
- **US3**: T020 → T021 → T022 → T023 sequential in the same file.

### Parallel Opportunities

- **Setup**: T001 alone.
- **Foundational**: T002 → T003 → T004 sequential (same file, symbol dependencies).
- **US1**: T005, T007, T010 can run in parallel after Foundational completes (different functions in same file; manageable with merge ordering). T008 parallel with T007/T010. T006 blocks on T005. T012 blocks on everything. T013 blocks on T005. T014 blocks on T012+T013.
- **US2**: mostly sequential within the same `lib/notify.sh` and `bin/tms` files.
- **US3**: strictly sequential.
- **Polish**: T024 parallel with anything. T025 and T026 at the end.

---

## Parallel Example: User Story 1

```bash
# After Foundational checkpoint, launch in parallel:
Task: "Implement _install_classify_target in lib/install.sh (T005)"
Task: "Implement _install_bootstrap_config in lib/install.sh (T007)"
Task: "Implement _install_check_deps in lib/install.sh (T008)"
Task: "Implement _install_check_path in lib/install.sh (T010)"
Task: "Implement _install_print_next_steps in lib/install.sh (T011)"

# Then sequentially:
Task: "Implement _install_symlink using T005's classifier (T006)"
Task: "Implement macOS branch of _install_print_hints (T009)"
Task: "Wire up cmd_install orchestrator (T012)"
Task: "Implement cmd_uninstall (T013)"

# Finally:
Task: "Add install subcommand dispatch in bin/tms (T014)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: Setup — one skeleton file.
2. Phase 2: Foundational — flag parser + OS detection + prefix resolution.
3. Phase 3: User Story 1 — the full `tms install` happy path on macOS.
4. **STOP and VALIDATE**: Run QS-1 through QS-10 (macOS) plus QS-13. Ship as "install works on macOS; single-binary and Linux hints come next."

### Incremental Delivery

1. Setup + Foundational → primitives ready.
2. Add US1 → `tms install` works on macOS (MVP).
3. Add US2 → single-binary footprint; `tms install-hooks` migrates cleanly.
4. Add US3 → `tms install` also produces correct hints on Linux and other platforms.
5. Polish → README update, full QS run, perf sanity.

### Parallel Team Strategy (single-developer notes)

- This feature is small enough for one developer; parallelism in the task graph is mostly about pipelining file-independent edits within a single session rather than splitting across developers.
- Natural commit boundaries: end of Phase 2, end of Phase 3 (MVP tag), end of Phase 4, end of Phase 5, end of Phase 6.

---

## Notes

- No automated test tasks. Per plan.md Testing line, this project has no harness and adding one is out of scope for feature 003. `quickstart.md` is the gate.
- `[P]` markers respect both file-independence and logical ordering — if task B needs a symbol defined by task A, B is not [P] even if they edit different files.
- File paths are absolute so each task is executable without ambient context.
- The script-based `.specify/scripts/bash/*` helpers (e.g., `check-prerequisites.sh`) do not support slash-prefixed branch names; this feature's manual tasks.md mirrors the template format directly.
- FR-015 (feature 002 behavior preserved byte-for-byte) is primarily enforced by T015's "preserve verbatim" mandate and validated by re-running feature 002's QS-2 / QS-3 / QS-4 as part of T025.
