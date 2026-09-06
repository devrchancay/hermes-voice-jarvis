# Task 15 — Polish & Release

## Goal
Get the project ready to publish as open source on GitHub.

## What to do

1. README.md:
   - Hero: screenshot or animated GIF of the orb in action
   - One-line description: "Talk to Hermes Agent with your voice. Native macOS, zero cost STT/TTS."
   - Features as bullets
   - Requirements: macOS 14+, Hermes Agent with the API server enabled
   - Quick Start: 3 steps (clone, open in Xcode, build & run)
   - Configuration: how to set the URL and API key
   - How it works: architecture diagram (ASCII or an image)
   - Contributing: basic guidelines
   - License: MIT
   - Credits: Hermes Agent by Nous Research

2. LICENSE — MIT, copyright Ramón Chancay / Desarol

3. App icon:
   - Design a simple icon: blue orb on a black background
   - Generate every macOS size (16-1024pt)
   - Or use a placeholder and improve it later

4. Code review:
   - Remove every TODO and FIXME
   - Verify there are no hardcoded secrets
   - Verify there are no `print()` calls — everything via os.Logger
   - Verify basic accessibility (VoiceOver labels on buttons)
   - Check for memory leaks with Instruments

5. Automated build:
   - `.github/workflows/build.yml`
   - macOS runner, Xcode 15+
   - Build + test on every push/PR
   - No deploy/release automation needed for the MVP

6. Git housekeeping:
   - `.gitignore` for Xcode (xcuserdata, build, etc.)
   - Delete unnecessary files

7. First release:
   - Tag v0.1.0
   - Release notes on GitHub
   - Attach the compressed .app (or build instructions)

## Acceptance criteria
- [ ] Complete README with clear instructions
- [ ] MIT LICENSE present
- [ ] App icon exists (at least a placeholder)
- [ ] No secrets, prints, or TODOs in the code
- [ ] The CI build passes on GitHub Actions
- [ ] .gitignore configured
- [ ] The repo is clonable and buildable by an outsider
- [ ] Builds without warnings
