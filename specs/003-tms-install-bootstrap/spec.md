# Feature Specification: One-command Install + Single-binary Refactor

**Feature Branch**: `003-tms-install-bootstrap`
**Created**: 2026-04-22
**Status**: Draft
**Input**: User description: "the installation method is a bit troublesome. link this link that. give me some advices" → "spec both, also, detect OS (Linux or macOS) and give dependency hints accordingly"

## Clarifications

### Session 2026-04-22

- Q: Migration timing for the `tms-notify-hook` → `tms notify-hook` refactor — drop immediately, ship a deprecation shim, or chain a fix-up into `tms install` itself? → A: Drop `bin/tms-notify-hook` immediately. Rely on FR-014's `tms install-hooks` migration as the only safety net (single-user tool; a shim would add permanent maintenance for a nonexistent installed-user base).
- Q: Default install prefix for `tms install`? → A: `~/.local/bin/` — matches the project's existing user-scope convention (config dir `~/.config/tmux-session-manager/`, log dir `~/.local/state/tmux-session-manager/`). No sudo; XDG-aligned.
- Q: Should `tms install` automatically chain into `tms install-hooks` on macOS? → A: No. Keep them explicit. `tms install` only prints the "optionally run `tms install-hooks` for Claude notifications (macOS)" line in its next-step block. Rationale: `install-hooks` modifies user-global state (`~/.claude/settings.json`) and runs an interactive probe banner; auto-chaining violates least-surprise.
- Q: Behavior on non-macOS, non-Linux platforms (BSD / illumos / etc.)? → A: Partial install. Do the symlink + config bootstrap, print dep hints in generic form ("Install <pkg> via your package manager"), do not advertise notifications. Exit 0. Rationale: symlink + config bootstrap are POSIX-portable; refusing entirely would punish users who already got tmux/yq/fzf working manually.
- Q: Multi-prefix idempotency — what happens if the user runs `tms install --prefix=A` and later `tms install --prefix=B`? → A: Each prefix is independent. The second install adds a new symlink at B; the existing one at A is untouched. `tms install --uninstall --prefix=X` removes only the symlink at X. No state file is introduced. Users who want exactly one symlink must `--uninstall` the prior prefix first.

All 5 clarification questions for this session answered. Remaining low-impact item (Linux package-manager priority order — apt → dnf → pacman → zypper → apk per FR-005) is already documented and not asked here.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Single-command first-time install (Priority: P1) 🎯 MVP

A developer has just `git clone`d the repo onto a fresh machine. They want to start using `tms` without reading the README in full or hunting for which symlinks go where. They run `./bin/tms install` and the tool puts itself in their `$PATH`, prepares the user config from the example, and tells them what to do next — including which packages they still need to install via their system package manager and the exact command to run.

**Why this priority**: This is the entire point of the feature — collapse the multi-step install dance into one command. Without it, the rest of the feature is decoration. Delivers standalone value for any user, on any supported OS, regardless of whether they ever enable Claude notifications.

**Independent Test**: On a fresh checkout, run `./bin/tms install` from the repo root. Verify (a) `tms` is now on `$PATH` (newly resolvable from a fresh shell), (b) `~/.config/tmux-session-manager/projects.yml` exists and is a usable copy of `projects.example.yml`, (c) the command's output lists exactly the missing OS packages with the correct install command for the host OS, and (d) the printed next-step guidance ends with a single actionable instruction (`edit projects.yml then run …`).

**Acceptance Scenarios**:

1. **Given** a fresh clone on macOS with no existing `~/.local/bin/tms` symlink and missing one or more required deps, **When** the user runs `./bin/tms install`, **Then** a symlink is created at `~/.local/bin/tms` pointing at the repo's `bin/tms`, `~/.config/tmux-session-manager/projects.yml` is created from the example, and the output ends with a clearly-formatted "Missing dependencies — install with:" block whose hints use `brew install <pkg>`.
2. **Given** a fresh clone on Linux with apt available and missing `tmux`, **When** the user runs `./bin/tms install`, **Then** the printed dependency hint reads `sudo apt install tmux` (or the distro-correct package name), not `brew install tmux`.
3. **Given** the symlink and the user-config file already exist from a prior install, **When** the user runs `./bin/tms install` again, **Then** the command prints a friendly "tms is already installed at <path>; projects.yml is already present" message, makes no destructive changes, and exits 0.
4. **Given** the user has moved the repo to a new location (so the existing symlink points at a stale path), **When** they run `./bin/tms install` from the new location, **Then** the symlink is updated in place with a "Updated tms path: <old> → <new>" message; existing `projects.yml` is left untouched.

---

### User Story 2 - Single-binary footprint (Priority: P1)

The user only ever needs to symlink one binary (`tms`) into their `$PATH`. The Claude Code notification hook is reachable as `tms notify-hook` (a subcommand) rather than a separate `tms-notify-hook` binary. As a side effect, `tms install-hooks` writes a settings.json entry that calls `tms notify-hook` (using the resolved absolute `tms` path), so registration cannot accidentally point at a missing or stale binary.

**Why this priority**: This eliminates the entire class of bug encountered during feature 002 bring-up where the user's settings.json pointed at a `tms-notify-hook` symlink that never got created — the click pipeline silently dropped events. With one binary and one symlink, that bug shape goes away. Also halves the work `tms install` has to do.

**Independent Test**: After `tms install`, run `tms install-hooks` and inspect `~/.claude/settings.json`. The registered command should be `<absolute-path-to>/tms notify-hook`, not `<absolute-path-to>/tms-notify-hook`. Trigger a Claude Code Notification event and verify the hook fires end-to-end (banner appears, click switches sessions). The repo no longer contains a `bin/tms-notify-hook` file.

**Acceptance Scenarios**:

1. **Given** the refactor is in place, **When** the user lists `bin/`, **Then** there is exactly one executable script (`bin/tms`) for the user-facing CLI.
2. **Given** an existing `~/.claude/settings.json` registered against the old `bin/tms-notify-hook` path from feature 002, **When** the user runs `tms install-hooks` after pulling this feature, **Then** the entry is updated in place to call `<tms-path> notify-hook` and a one-line "Migrated tms-notify-hook entry to tms notify-hook." status is printed; the user does not need any other manual fix.
3. **Given** the new `tms notify-hook` subcommand is the registered hook, **When** Claude Code fires a `Notification` event, **Then** the behavior matches feature 002 exactly — banner appears, click foregrounds terminal and switches session, all error branches (parse-error, no-cwd, no-project-match, opt-out, etc.) log identically.

---

### User Story 3 - OS-aware dependency hints (Priority: P2)

When `tms install` detects missing dependencies, it prints install commands the user can copy-paste verbatim for their host OS. macOS users get `brew install` lines. Linux users get the right command for their detected package manager (apt / dnf / pacman / zypper / apk). Users on unrecognized package managers or non-Linux/macOS hosts get a generic instruction that names the package without committing to a wrong command.

**Why this priority**: Dependency hints make the install output self-explanatory. Without OS detection, a Linux user would read `brew install` lines and be momentarily confused. P2 (not P1) because the install step still completes correctly without accurate hints — only the printed text is wrong; the user can still figure it out.

**Independent Test**: Spoof `uname -s` and the available package managers via PATH manipulation (or test on real Linux + macOS hosts). For each (OS, package-manager) combination listed in the matrix below, run `tms install` against a setup with all deps deliberately missing, and verify the printed install line matches the expected per-platform format.

**Acceptance Scenarios**:

1. **Given** the host is macOS (`uname -s` is `Darwin`), **When** dependency hints are printed, **Then** every hint uses `brew install <pkg>`.
2. **Given** the host is Linux with apt-get available, **When** dependency hints are printed, **Then** every hint uses `sudo apt install <pkg>` with the correct distro-package name (e.g., `python3-yq` or `yq` depending on what apt actually ships — to be pinned in the plan).
3. **Given** the host is Linux with no recognized package manager (apt/dnf/pacman/zypper/apk all absent from PATH), **When** dependency hints are printed, **Then** the output uses a generic form: `Install <pkg> via your distro's package manager.` — never a wrong-distro command.
4. **Given** the host is on macOS but Homebrew is not installed, **When** the dependency hints are printed, **Then** the output still uses `brew install <pkg>` with a one-line preamble pointing at https://brew.sh — installing Homebrew itself is out of scope for `tms install` (per non-goals).
5. **Given** the host is Linux, **When** alerter and jq dependency hints would have been printed for the notification feature, **Then** they are NOT printed (alerter is macOS-only); a single line states "Notification banners are macOS-only in this version" instead.

---

### Edge Cases

- The user's `$HOME` is unset or unwritable: `tms install` MUST refuse with a clear error rather than silently doing nothing or writing into the current directory.
- The chosen install prefix (default `~/.local/bin/`) does not exist: `tms install` creates it with `mkdir -p` (mode 0755). If `mkdir -p` fails (e.g., permission denied on a custom `--prefix`), the command MUST exit non-zero with a clear "could not create install prefix at <path>" message.
- The chosen install prefix is not on the user's `$PATH`: `tms install` succeeds (the symlink is still useful) but prints a one-line warning telling the user to add the prefix to their shell rc with the exact line to append. Detection compares `$PATH` entries to the resolved prefix; both paths are realpath-normalized to handle `~` vs `/home/<user>` mismatches.
- A non-symlink file already exists at the install target (e.g., the user previously copied `bin/tms` rather than symlinking): `tms install` MUST NOT silently overwrite it. Print a clear "<path> exists and is not a symlink — refusing to overwrite. Move it aside or use --prefix=<other>" message and exit non-zero.
- The user's `~/.claude/settings.json` registers `bin/tms-notify-hook` from a prior install of feature 002: when `tms install-hooks` next runs, the entry MUST be transparently updated to the new `<tms-path> notify-hook` form (the migration in US2 AS-2). No data is lost; the old entry is not duplicated.
- A user has manually edited their `bin/tms-notify-hook` (e.g., to add custom logging): the file is removed by this refactor. The release notes / migration documentation MUST flag this; the migration message in `tms install-hooks` MUST also mention it. (We accept that in a single-user tool, custom hook edits are rare and worth the simpler installation in exchange.)
- The host is FreeBSD / OpenBSD / NetBSD / illumos: `tms install` completes the symlink + config bootstrap, prints dependency hints in generic form, and does NOT block. The notification feature remains macOS-only and is not advertised in the dependency-hint section on these platforms.
- `tms install --uninstall` is run on a system where the user installed manually (no symlink at the default prefix; their `tms` is a copy): the command MUST report "no tms install found at <prefix>" and exit 0 without searching every PATH entry. Use of `--prefix=<dir>` allows uninstalling from non-default locations.
- The repo is a worktree (git worktree, not the primary checkout): the symlink resolves through the worktree's bin/ directory. `tms install --uninstall` from the same worktree removes it cleanly. From a different worktree, the symlink target check correctly identifies "this symlink points elsewhere; refusing to remove".

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `tms install` MUST symlink the repo's `bin/tms` into a target install prefix (default `~/.local/bin/`). The prefix MUST be overridable via `--prefix=<dir>`. If the prefix does not exist, `tms install` MUST create it (`mkdir -p`, mode 0755).
- **FR-002**: `tms install` MUST create the user config directory (default `~/.config/tmux-session-manager/`, honoring `$TMS_CONFIG_DIR` for parity with existing tms code) and copy `config/projects.example.yml` to `projects.yml` if and only if no `projects.yml` already exists. The command MUST NEVER overwrite an existing `projects.yml`.
- **FR-003**: `tms install` MUST detect the host OS via `uname -s` and route dependency-hint printing accordingly: `Darwin` → Homebrew hints, `Linux` → distro-package-manager hints (per FR-005), other → generic hints.
- **FR-004**: For each runtime dependency, `tms install` MUST check presence on `$PATH` (`command -v`) and report each missing dep with a copy-pasteable install command for the host's package manager. The dependency list MUST distinguish required (`tmux`, `yq`, `fzf`) from optional/macOS-only (`alerter`, `jq` — only relevant when notifications are enabled).
- **FR-005**: On Linux, `tms install` MUST detect the available package manager by probing `command -v` in the priority order apt → dnf → pacman → zypper → apk; the first one found determines the install-hint format. If none is found, the output MUST use a generic "install <pkg> via your distro's package manager" form rather than guessing wrong.
- **FR-006**: On Linux, `tms install` MUST NOT print install hints for `alerter` or `jq` (the notification-only deps). It MUST print exactly one line stating that notification banners are macOS-only in this version.
- **FR-007**: `tms install` MUST be idempotent **per-prefix**. Running it twice against the same `--prefix` with no intervening changes MUST be a no-op with a friendly status message; running it after the repo has moved MUST update the symlink target in place and announce the change. Different prefixes are treated independently — a second install with `--prefix=<B>` MUST NOT touch a prior symlink at `--prefix=<A>` (clarified 2026-04-22). No cross-prefix state is tracked.
- **FR-008**: `tms install` MUST NOT silently overwrite a non-symlink file at the install target. If the target exists and is not a symlink (or is a symlink pointing elsewhere outside this repo), the command MUST print a clear refusal and exit non-zero.
- **FR-009**: `tms install` MUST detect when the install prefix is not on the user's `$PATH` and print a one-line warning with the exact shell-rc line to append. Successful install otherwise.
- **FR-010**: `tms install --uninstall` MUST remove the tms symlink at the chosen prefix and print what was removed. It MUST NOT touch `~/.config/tmux-session-manager/` (user data is preserved).
- **FR-011**: `tms install --dry-run` MUST print every action `tms install` would take without performing any of them, then exit 0.
- **FR-012**: The Claude Code notification hook entry point MUST be reachable as `tms notify-hook` — a subcommand on the main `bin/tms` binary — rather than as a separate `bin/tms-notify-hook` script. The behavior of `tms notify-hook` MUST be byte-for-byte identical to the prior `bin/tms-notify-hook` (same stdin contract, same exit-code guarantees per feature 002 FR-007, same log entries).
- **FR-013**: `bin/tms-notify-hook` MUST be removed from the repo in the same commit as the `tms notify-hook` subcommand is introduced. No deprecation shim is shipped; FR-014's migration in `tms install-hooks` is the only safety net for prior-installed users (single-user tool; a shim would add permanent maintenance for a nonexistent installed-user base — clarified 2026-04-22). After the refactor, `bin/` contains exactly one user-facing script (`bin/tms`).
- **FR-014**: `tms install-hooks` MUST detect existing `~/.claude/settings.json` entries that reference the old `bin/tms-notify-hook` path and transparently update them to call `<absolute-path-to>/tms notify-hook` instead. The migration MUST be idempotent and MUST print a one-line "Migrated tms-notify-hook entry to tms notify-hook" message when a migration occurs (silent on subsequent runs).
- **FR-015**: All existing functional behavior of the Claude notification hook (feature 002 FR-001 through FR-011) MUST continue to hold after the refactor. Manual quickstart scenarios QS-2, QS-3, QS-4, QS-6, QS-7 from feature 002 MUST pass without modification.

### Key Entities *(include if feature involves data)*

- **Install Plan**: The set of actions `tms install` would take on a given host: which symlinks to create or update, whether to copy `projects.example.yml`, which dependency hints to print. Computed lazily, materialized as the dry-run output and as the actual install steps.
- **Dependency Hint**: A pair of `(package-name, install-command-template)` derived from the detected OS + package manager. Rendered into the user-facing output verbatim so the user can copy-paste.
- **Install Target**: The absolute path of the symlink the install creates (default `~/.local/bin/tms`). Detection of pre-existing files at this path (other-symlink, regular-file, missing) drives the FR-007 / FR-008 branches.
- **Notify-Hook Subcommand**: The `tms notify-hook` invocation. Its stdin/stdout/exit-code contract is unchanged from the old `bin/tms-notify-hook`; this entity exists as a labeled boundary so the migration in FR-014 is testable without depending on internal implementation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user who has just cloned the repo can be running `tms list` (against the example projects) within 60 seconds of starting `tms install` — assuming dependencies are already installed. (Dependency installation itself is gated by Homebrew/apt/etc. and is not measured here.)
- **SC-002**: Zero install steps require the user to manually type a path, edit a settings.json, or know which file to symlink. Validated by: running through README's "Installation" section as a fresh user and confirming all steps are either single-line commands or "edit your projects.yml" (the one place user judgment is irreducible).
- **SC-003**: After this feature ships, the average count of distinct binaries the user must symlink to use the notification hook drops from 2 (`tms` + `tms-notify-hook`) to 1 (`tms` only). Validated by listing `bin/` contents and checking `~/.claude/settings.json`'s registered command path.
- **SC-004**: Dependency-hint accuracy is 100% across a matrix of (OS × package-manager) combinations: macOS+Homebrew, Linux+apt, Linux+dnf, Linux+pacman, Linux+zypper, Linux+apk, Linux+none, "other-OS". Validated by the test recipe in QS-3 (acceptance scenario for US3).
- **SC-005**: The migration in FR-014 is invisible: a user who installed feature 002 and then pulls feature 003 + runs `tms install-hooks` once sees a single one-line migration message and the next Claude notification fires correctly. Zero manual editing of settings.json required.

## Assumptions

- The target user has shell access and a writable `$HOME`. We do NOT support sandboxed install scenarios (e.g., systems where `~/.local/bin/` cannot be written) — those users use `--prefix=<dir>` to point at a writable location.
- The user is comfortable adding `~/.local/bin/` to their `$PATH` if it is not already there. `tms install` warns them with the exact line to append; it does NOT modify the user's shell rc files (too risky, too many shell-rc combinations to support).
- Homebrew is the canonical macOS package manager. Users on MacPorts, pkgsrc, or building from source manage their own deps; the `brew install` hint is "the obvious thing" for the macOS audience, and being slightly wrong for the long tail is acceptable.
- The Linux package-manager priority order (apt → dnf → pacman → zypper → apk) reflects rough population share among likely users. We accept that a user with both apt and dnf available (e.g., a custom Debian + RPM hybrid) gets the apt hint; this is a non-goal to disambiguate further.
- The notification feature stays macOS-only in v3. Adding `notify-send` / libnotify support for Linux is a separate feature and is explicitly out of scope here. `tms install` on Linux just doesn't advertise the notification path.
- Existing feature 002 users will run `tms install-hooks` after pulling this feature (whether prompted or out of habit). The migration message on first post-pull run is the canonical communication channel; we do NOT additionally post-process old settings.json entries from `tms install` itself, since that path is not the natural place for it.
- The project's existing convention of "shell-only, no compiled artifacts, no Makefiles" continues. `tms install` is bash, not a Makefile target or a Python script.

## Out of Scope (explicitly)

- Installing Homebrew, apt-get, or any underlying system package manager.
- Writing or modifying the user's shell rc files (`.bashrc`, `.zshrc`, `.profile`, `fish/config.fish`, etc.). `tms install` warns; it does not patch.
- Publishing a Homebrew formula, a Homebrew tap, an apt repository, or any package-manager distribution channel.
- A `curl <url> | sh` style one-line installer hosted on a URL.
- `make install` / `make uninstall` Makefile targets. `tms install` is the canonical mechanism.
- Linux notification support (notify-send, libnotify, etc.).
- Migrating `~/bin/`, `/usr/local/bin/`, or other custom historical install paths automatically — `tms install --prefix=<dir>` lets the user opt in, but the default is `~/.local/bin/` and we do not search alternative prefixes for stale symlinks.
- A graphical installer or interactive TUI walking the user through prefix selection; the CLI flags are the interface.
- Cross-platform parity for the notification hook itself — that's a v4 conversation, not this feature.
