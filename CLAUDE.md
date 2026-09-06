# CLAUDE.md — Instructions for Claude Code

## Project
HermesVoice: native macOS app (SwiftUI) for talking by voice to Hermes Agent.
Visual style: J.A.R.V.I.S. from the Marvel MCU.

## How to work

1. Read `SPEC.md` in full before starting any task.
2. Tasks live in `tasks/`, numbered. Execute them in order.
3. Every task has acceptance criteria — do not call it done until all of them are met.
4. Zero external dependencies. Apple frameworks only.
5. Swift 6, SwiftUI, macOS 14+ (Sonoma).
6. Use `@Observable` (not `ObservableObject`).
7. Use structured concurrency (async/await, no Combine except where SwiftUI requires it).
8. Naming: English, descriptive, no obscure abbreviations.
9. Every new file must start with a one-line header comment describing it.

## Code conventions

- Indentation: 4 spaces
- Maximum 100 characters per line (preference, not a hard limit)
- Organize long files with `// MARK: -`
- Errors: define enums conforming to `LocalizedError`
- Logs: use `os.Logger` (never `print`)
- Colors: define them in a `HermesColors` enum with the values from the spec

## Structure
Respect the structure defined in SPEC.md. Do not create folders or files outside it
without justification.

## Testing
- Write unit tests for Core/ (HermesClient, states)
- Every View must have a working Preview
- Automated UI tests are not required for the MVP

## Git
- One commit per completed task
- Format: `feat(task-XX): short description`
- Branch: `main` (no feature branches for the MVP)
