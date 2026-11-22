---
name: swift-app-dev
description: Develop and maintain a native Swift or SwiftUI app (macOS, iOS or a Swift package) end to end. Covers coding new features, fixing bugs, refactoring, reviewing code and proposing new feature ideas, always starting from the project's own AGENTS.md and README. Use this skill whenever the user works on a Swift app or package, mentions SwiftUI, AppKit, SwiftPM, AGENTS.md, or says things like "add a setting", "fix this crash", "what should we add next", "refactor this view", "swift build fails", even if they do not name the skill.
---

# Swift app development

Work on a native Swift app the way its maintainers would. The project's own documents define what "right" looks like; this skill defines the workflow around them.

## Step 0: Ground yourself in the project

1. Read `AGENTS.md` (or `AGENTS-*.md`) first. It is the authority on toolchain, layout, commands and conventions, and it wins over anything in this skill.
2. Read the README for the intended behaviour, feature list and architecture.
3. Check `Package.swift` or the project file for the real platform, tools version and dependencies. If documents disagree with each other or with the manifest, tell the user instead of silently choosing.
4. List the source tree and read the files you will touch plus their direct neighbours. Never edit a file you have not read.
5. Note what the toolchain can and cannot do (for example no Xcode means no XCTest, no `xcodebuild`) and stay within it.

## Workflows

### Adding a feature
1. Restate the behaviour in a sentence or two, including edge cases (empty state, persistence across launches, error paths). Ask the user only when a decision materially changes the design.
2. Find the existing code closest to the feature and decide where it fits. Tell the user briefly which files will change and whether a new file is really needed.
3. Implement bottom-up: model and logic, then services, then UI. Keep logic free of UI and platform frameworks where possible so it can be tested.
4. Reuse the project's existing mechanisms for persistence, preferences, navigation and styling rather than inventing new ones.
5. Add or extend tests for new logic using whatever the project provides, and register new files wherever the build or test scripts list them.
6. Update the docs (README features, layout trees, shortcuts) when behaviour or structure changes.
7. Verify (see below).

### Fixing a bug
1. Find the root cause by reading the code path end to end, including async, cancellation and threading, before editing.
2. Fix it where it originates, not by patching the symptom in the view.
3. If the bug is in testable logic, add a check that fails before the fix and passes after.
4. Keep the diff minimal; mention unrelated problems instead of fixing them in the same change.
5. Report what was wrong, what changed, and what could not be verified.

### Proposing features
- Ground ideas in the app's purpose and its documented limitations.
- Give 3 to 5 ideas, each with: a one-line pitch, the user benefit, which existing parts it would extend, rough size (small/medium/large) and risks (new dependency, permissions, distribution, network).
- Rank them by value over complexity and say which you would do first. Do not implement until the user chooses.

### Refactoring and reviewing
- Look for duplicated data, near-identical views, files with mixed responsibilities, dead code and stale comments.
- Refactor in behaviour-preserving steps and run the checks between steps.
- Report review findings grouped as bugs, simplifications, structure and style, most important first.

## Guidelines worth keeping in mind

These are tendencies that keep a codebase healthy, not rigid rules. Defer to the project's conventions when they differ.

- **Simplicity:** prefer the smallest change and standard platform APIs; avoid speculative abstractions and new dependencies unless the user agrees.
- **Structure:** put code where the existing layout says it belongs, one clear responsibility per file, and keep layout docs in sync when files move.
- **Build on what exists:** extend existing types and flows before creating parallel ones, and keep a single source of truth for each piece of data.
- **Comments:** let names carry the meaning; comment only to explain why, and never leave commented-out or redundant comments.
- **Names:** intent-revealing, no abbreviations, magic numbers turned into named constants.

## Verification

Run the commands the project defines (build, formatter or linter, test or smoke scripts) and fix what they report. If something cannot be run, say so plainly rather than claiming success. Before finishing, re-read your diff for stray debug code, unused code and imports, and outdated docs.

## Final report

Keep it short: what changed per file, why it fits the existing structure, what was verified, and what the user should check by hand (sound, network, window behaviour and anything the checks cannot exercise). Mention doc inconsistencies or follow-up ideas in one line each without acting on them.
