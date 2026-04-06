# Feature Specification: Tmux Session Manager for Claude Code & Neovim

**Feature Branch**: `001-tmux-session-manager`  
**Created**: 2026-04-06  
**Status**: Draft  
**Input**: User description: "Tmux configuration for managing multiple Claude Code/neovim sessions with project-based panes, popup server windows, and quick-switch key bindings"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Start a Project Workspace (Priority: P1)

As a developer, I want to launch a complete workspace for a project with a single command, so that I don't have to manually open and arrange tmux panes for neovim and Claude Code every time I start working.

When I run the launch command for a project, it should create a tmux session with a neovim pane and a Claude Code pane, properly sized and arranged, so I can immediately start coding.

**Why this priority**: This is the core value proposition. Without automated workspace setup, the tool provides no benefit over manual tmux configuration.

**Independent Test**: Can be fully tested by running the launch command for a configured project and verifying that a tmux session opens with neovim and Claude Code panes ready to use.

**Acceptance Scenarios**:

1. **Given** a configured project entry, **When** the user runs the launch command, **Then** a tmux session is created with the correct panes running neovim and Claude Code in the project directory.
2. **Given** a project session that already exists, **When** the user runs the launch command again, **Then** the system attaches to the existing session instead of creating a duplicate.
3. **Given** no project configuration exists for the specified name, **When** the user runs the launch command, **Then** the system displays a clear error message indicating the project was not found.

---

### User Story 2 - Switch Between Projects (Priority: P1)

As a developer working on multiple projects simultaneously, I want to quickly switch between project workspaces using key bindings, so that context-switching between projects is fast and seamless.

**Why this priority**: Multi-project navigation is essential for the multi-session management use case. Without this, the tool is just a session launcher.

**Independent Test**: Can be fully tested by launching two project workspaces, then using the key binding to switch between them and verifying each workspace retains its state.

**Acceptance Scenarios**:

1. **Given** multiple project sessions are running, **When** the user presses the project-switching key binding, **Then** a list of active project sessions is displayed for selection.
2. **Given** the project selection list is displayed, **When** the user selects a project, **Then** the tmux client switches to that project's session immediately.
3. **Given** only one project session is running, **When** the user presses the project-switching key binding, **Then** the system indicates there are no other sessions to switch to.

---

### User Story 3 - Manage Server Processes in Popup Windows (Priority: P2)

As a developer, I want to start and view project-related server processes (dev servers, watchers, databases) in popup windows that don't clutter my main workspace, so I can monitor them when needed without losing screen space.

**Why this priority**: Server management is important but secondary to core workspace setup. Many projects require running servers, but the developer's primary workflow is editing and AI-assisted coding.

**Independent Test**: Can be fully tested by configuring a project with server commands, launching the workspace, and toggling the popup window to verify the server is running and visible on demand.

**Acceptance Scenarios**:

1. **Given** a project is configured with server commands, **When** the project workspace is launched, **Then** the configured servers start running in background popup windows.
2. **Given** servers are running in popup windows, **When** the user presses the popup toggle key binding, **Then** the popup window appears showing the server output.
3. **Given** a popup window is visible, **When** the user presses the popup toggle key binding again or dismisses it, **Then** the popup window hides and the main workspace is restored.
4. **Given** a project has multiple servers configured, **When** the user accesses the popup windows, **Then** each server is accessible in its own identifiable popup.

---

### User Story 4 - Configure Project List (Priority: P2)

As a developer, I want to define a list of my projects with their directories and associated commands, so the system knows how to set up each workspace.

**Why this priority**: Configuration is the foundation for all other stories but is a one-time setup activity rather than a daily workflow action.

**Independent Test**: Can be fully tested by creating a configuration file with project entries and verifying the system reads and validates the entries correctly.

**Acceptance Scenarios**:

1. **Given** the user creates a configuration file with project entries, **When** the system reads the configuration, **Then** each project's name, directory, and commands are correctly parsed.
2. **Given** a configuration entry has a missing required field, **When** the system reads the configuration, **Then** a clear validation error is reported indicating which field is missing.
3. **Given** the user adds a new project to the configuration, **When** they launch that project, **Then** the new project workspace is created according to its configuration.

---

### User Story 5 - View and Navigate Project List (Priority: P3)

As a developer, I want to see an overview of all my configured projects and their current status (running/stopped), so I can quickly understand my workspace state and navigate to any project.

**Why this priority**: This is a convenience feature that improves discoverability but is not essential for daily use once the user memorizes their key bindings.

**Independent Test**: Can be fully tested by configuring multiple projects, starting some of them, and invoking the project list view to verify correct status display and navigation.

**Acceptance Scenarios**:

1. **Given** multiple projects are configured, **When** the user invokes the project list, **Then** all configured projects are shown with their running/stopped status.
2. **Given** the project list is displayed, **When** the user selects a stopped project, **Then** the system launches that project's workspace and switches to it.
3. **Given** the project list is displayed, **When** the user selects a running project, **Then** the system switches to that project's existing session.

---

### Edge Cases

- What happens when the user's terminal is too small for the configured pane layout?
- How does the system handle a project directory that no longer exists on disk?
- If a configured server command fails or crashes, the error output remains visible in the popup window for diagnosis. The user manually restarts; no auto-restart is performed.
- How does the system behave when tmux is not installed or is an unsupported version?
- What happens when the user manually closes a pane within a managed session?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow users to define projects in a configuration file, each with a name, working directory, and optional server commands.
- **FR-002**: System MUST create a tmux session for a project with a fixed two-pane layout: one pane running neovim (suspendable to shell via ctrl-z/fg) and one pane running Claude Code, both in the project's directory.
- **FR-003**: System MUST detect and attach to an existing project session if one is already running, rather than creating duplicates.
- **FR-004**: System MUST provide a key binding to display and switch between active project sessions using tmux's built-in session chooser.
- **FR-005**: System MUST run project server commands in tmux popup windows that can be toggled on and off without disrupting the main workspace.
- **FR-006**: System MUST provide a key binding to toggle popup windows for server processes.
- **FR-007**: System MUST display a project list showing all configured projects and their running status.
- **FR-008**: System MUST allow launching or switching to a project directly from the project list.
- **FR-009**: System MUST validate the configuration file and report clear errors for invalid entries.
- **FR-010**: System MUST support multiple server commands per project, each accessible in its own popup window.

### Key Entities

- **Project**: Represents a development workspace. Has a name, working directory path, pane layout preferences, and a list of associated server commands.
- **Server Command**: A background process associated with a project (e.g., dev server, watcher). Has a display name, the command to run, and an optional working directory override.
- **Session**: A running tmux session for a project. One-to-one relationship with a project. Contains the pane layout and references to popup windows.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer can go from zero to a fully set up workspace (neovim + Claude Code) for a project in under 5 seconds with a single command.
- **SC-002**: Switching between project workspaces takes under 2 seconds, including rendering the project list and completing the switch.
- **SC-003**: Toggling a server popup window appears and disappears in under 1 second with no disruption to the main editing panes.
- **SC-004**: A new project can be added to the configuration in under 1 minute by editing the configuration file.
- **SC-005**: All configured projects and their statuses are visible at a glance from the project list view.

## Clarifications

### Session 2026-04-06

- Q: Can projects define arbitrary pane layouts, or is it always neovim + Claude Code? → A: Fixed two-pane layout only (neovim + Claude Code). Additional processes use popup windows. Neovim must be suspendable to shell (ctrl-z/fg) so users can access a shell prompt in the same pane when needed.
- Q: What happens when a configured server command fails to start or crashes? → A: Show error output in the popup window; user manually restarts. No auto-restart.
- Q: How is the project switching list presented to the user? → A: Use tmux built-in session chooser (choose-tree / choose-session). No external dependencies like fzf.

## Assumptions

- The user has tmux installed (version 3.2 or later, which supports popup windows).
- The user has neovim and Claude Code CLI installed and available in their PATH.
- The user primarily works on macOS or Linux (tmux is the target environment).
- The configuration file will be stored in a well-known location (e.g., `~/.config/tmux-session-manager/` or alongside the tmux configuration).
- Projects are local filesystem directories; remote project support is out of scope.
- The pane layout for each project is a fixed two-pane arrangement (neovim + Claude Code). Neovim is launched in a shell that supports suspend/resume (ctrl-z/fg). Additional processes use popup windows.
- Popup windows use tmux's built-in `display-popup` command.
