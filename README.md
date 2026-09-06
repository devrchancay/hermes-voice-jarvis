# HermesVoice

Talk to Hermes Agent with your voice. Native macOS, zero-cost STT/TTS.

A native macOS app (SwiftUI) styled after MCU's J.A.R.V.I.S. that lets you hold a
spoken conversation with any Hermes Agent instance — or any OpenAI-compatible
backend. Speech recognition and speech synthesis run entirely on-device, so the
only thing you pay for is the LLM itself.

> **Status: spec stage.** The specification and the task breakdown are complete;
> the Xcode project has not been scaffolded yet. Start with
> [`tasks/01-project-scaffold.md`](tasks/01-project-scaffold.md).

## Features

- **On-device STT** — SFSpeechRecognizer, no audio ever leaves the machine
- **On-device TTS** — AVSpeechSynthesizer with Siri voices
- **Any language** — one setting drives recognition, synthesis, and the language
  the model replies in; switchable without restarting
- **Streaming responses** — SSE token streaming; the app starts speaking before
  the full answer has arrived
- **Any OpenAI-compatible backend** — Hermes, OpenAI, Ollama, LM Studio
- **Jarvis HUD** — black canvas, animated orb, live waveforms, monospace overlays
- **Zero dependencies** — Apple frameworks only. No SPM, no CocoaPods

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later
- A Hermes Agent instance with the API server enabled (or any OpenAI-compatible endpoint)

## Quick start

```bash
git clone git@github.com:devrchancay/hermes-voice-jarvis.git
cd hermes-voice-jarvis
open HermesVoice/HermesVoice.xcodeproj   # available after task 01
```

Then build & run (⌘R). On first launch the app asks for your server URL and API key.

## Configuration

| Setting        | Where it lives            |
|----------------|---------------------------|
| Server URL     | UserDefaults              |
| API key        | Keychain                  |
| Preferred voice| UserDefaults              |
| Activation mode| UserDefaults              |

Nothing sensitive is ever committed — see [`.gitignore`](.gitignore).

## How it works

```
Microphone → SFSpeechRecognizer (on-device)
           → HermesClient (POST /v1/chat/completions, stream: true)
           → SSE tokens → AVSpeechSynthesizer (on-device) → Speaker
                       └→ SwiftUI Jarvis HUD (orb · waveform · transcript)
```

Full details in [`SPEC.md`](SPEC.md).

## Development

This repo is spec-driven and built with [Claude Code](https://claude.ai/code).

- [`SPEC.md`](SPEC.md) — architecture, API contract, UI design, phases
- [`CLAUDE.md`](CLAUDE.md) — working agreement and code conventions
- [`tasks/`](tasks/) — 15 self-contained tasks, each with acceptance criteria

Tasks run in order. Each one is a single commit: `feat(task-XX): short description`.

| Phase | Tasks | Scope                                             |
|-------|-------|---------------------------------------------------|
| 1     | 01–08 | Working MVP: connection, STT, TTS, basic UI, voice loop |
| 2     | 09–11 | Jarvis visuals: animated orb, waveforms, HUD overlays |
| 3     | 12–15 | Polish: interruptions, history, continuous listening, release |

## Contributing

Issues and pull requests are welcome. Please keep the zero-dependency rule and
follow the conventions in [`CLAUDE.md`](CLAUDE.md).

## License

MIT — see [`LICENSE`](LICENSE).

## Credits

Hermes Agent by Nous Research.
