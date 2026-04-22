# Specification Quality Checklist: Click-to-Exact-Tab Notification Switch

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-04-22
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs) — *AppleScript is mentioned as the specific mechanism; this is intentional and unavoidable because it's the only way to achieve the FR-001 behavior on macOS, and it's a user-visible permission surface. Documented as a constraint rather than a suggestion.*
- [x] Focused on user value and business needs — *"click lands on the exact tab" is the primary user value; multi-window productivity is the business case.*
- [x] Written for non-technical stakeholders — *terminology uses "window", "tab", "session" which are familiar concepts. AppleScript is named in FRs but not in user stories.*
- [x] All mandatory sections completed — *User Scenarios, Requirements, Success Criteria all filled.*

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain — *verified; none in spec.*
- [x] Requirements are testable and unambiguous — *each FR specifies concrete conditions (MUST / MUST NOT); acceptance scenarios use given/when/then.*
- [x] Success criteria are measurable — *SC-001 through SC-005 include specific numbers (95%, 2s, 20 clicks, zero regression).*
- [x] Success criteria are technology-agnostic — *SC-001/002/003 use observable user-side latencies; AppleScript implementation detail not baked into SCs.*
- [x] All acceptance scenarios are defined — *each user story has 2-3 given/when/then scenarios.*
- [x] Edge cases are identified — *7 edge cases listed covering multi-client, fullscreen, closed window, multi-bundle, permission denial, Stage Manager.*
- [x] Scope is clearly bounded — *Out of Scope section enumerates Spaces, Stage Manager, spawning, non-AppleScript terminals, SSH, non-tmux tabs.*
- [x] Dependencies and assumptions identified — *Assumptions section enumerates terminal support, TTY format, permission grants, local-only.*

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria — *FRs map to acceptance scenarios; FR-001 → US1 AS-1, FR-004 → US2 AS-1, FR-008 → US3 AS-1, etc.*
- [x] User scenarios cover primary flows — *US1 (primary), US2 (fallback), US3 (degraded) cover the decision tree.*
- [x] Feature meets measurable outcomes defined in Success Criteria — *SC coverage maps back through FRs.*
- [x] No implementation details leak into specification — *AppleScript is mentioned as constraint (how the platform makes this achievable) not as implementation prescription.*

## Notes

- AppleScript is an unavoidable platform-specific constraint, not a free implementation choice. Named in FRs (FR-002, FR-003, FR-005) because alternative mechanisms (D-Bus, window managers, window title matching) either don't exist on macOS or are explicitly rejected (FR-002 rules out title matching).
- The "first client wins" policy in FR-009 was chosen as a reasonable default over a user-clarification question. The edge case is rare (user has same session attached in 2 tabs) and deterministic + manual-cycle-to-other is a workable UX.
- No [NEEDS CLARIFICATION] markers required — every ambiguous area had a clear best-default (first-client-wins, no-space-switching, fall-back-to-existing-attach).
