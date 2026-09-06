# HermesVoice — Spec

## Overview

Native macOS app (SwiftUI) in the style of MCU's J.A.R.V.I.S. for talking by voice to
any Hermes Agent instance (or any OpenAI-compatible backend).
Open source, zero external dependencies, zero STT/TTS cost.

Repo: `github.com/devrchancay/hermes-voice-jarvis`
License: MIT


## Design principles

1. **Native first** — Swift 6, SwiftUI, macOS 14+. No Electron, no web views.
2. **Zero dependencies** — Apple frameworks only. No SPM, no CocoaPods, nothing.
3. **Zero voice cost** — STT and TTS 100% on-device (SFSpeechRecognizer + AVSpeechSynthesizer).
4. **Connects to any Hermes** — all it needs is the API server URL + API key.
5. **Any language** — one setting drives recognition, synthesis, and the language
   the model answers in. Nothing is hardcoded to a single locale.
6. **Jarvis look** — dark interface, translucent HUD, animated central orb, waveforms.
7. **Spec-driven** — every task is self-contained, verifiable, and built with Claude Code.


## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    HermesVoice (macOS)                   │
│                                                         │
│  ┌──────────┐    ┌──────────────┐    ┌───────────────┐  │
│  │Microphone│───▶│SFSpeech      │───▶│ HermesClient  │  │
│  │          │    │Recognizer    │    │ (HTTP + SSE)  │  │
│  │          │    │(on-device)   │    │               │──────▶ Hermes API Server
│  └──────────┘    └──────────────┘    │               │◀────── /v1/chat/completions
│                                      └───────┬───────┘  │     (SSE streaming)
│  ┌──────────┐    ┌──────────────┐            │          │
│  │ Speaker  │◀───│AVSpeech      │◀───────────┘          │
│  │          │    │Synthesizer   │                        │
│  │          │    │(on-device)   │                        │
│  └──────────┘    └──────────────┘                        │
│                                                         │
│  ┌─────────────────────────────────────────────────────┐│
│  │              SwiftUI Views (Jarvis HUD)             ││
│  │  OrbView · WaveformView · TranscriptOverlay · HUD  ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```


## Hermes API (what we consume)

### Main endpoint
```
POST /v1/chat/completions
Authorization: Bearer <API_SERVER_KEY>
Content-Type: application/json

{
  "model": "hermes-agent",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "user's transcribed text"}
  ],
  "stream": true
}
```

### Streaming (SSE)
Every chunk arrives as:
```
data: {"id":"chatcmpl-xxx","choices":[{"delta":{"content":"token"},"finish_reason":null}]}
```
End:
```
data: [DONE]
```

### Multi-turn
Option A: keep the `messages` array on the client (stateless).
Option B: use `previous_response_id` on /v1/responses (stateful in Hermes).

For the MVP we use Option A (simpler, works with any backend).

### Other useful endpoints
- `GET /v1/models` — discover the available model
- `GET /health` — check that the server is alive
- `GET /v1/capabilities` — discover supported features


## Tech stack

| Layer       | Technology                    | Cost |
|-------------|-------------------------------|------|
| STT         | SFSpeechRecognizer (on-device)| $0   |
| TTS         | AVSpeechSynthesizer           | $0   |
| LLM         | Hermes API Server (remote)    | ~cents/conversation |
| UI          | SwiftUI + Metal (shaders)     | $0   |
| Audio       | AVFoundation                  | $0   |
| Networking  | URLSession (native SSE)       | $0   |


## Project structure

```
hermes-voice-jarvis/
├── README.md
├── LICENSE                          (MIT)
├── SPEC.md                          (this file)
├── CLAUDE.md                        (instructions for Claude Code)
├── tasks/                           (spec-driven tasks)
│   ├── 01-project-scaffold.md
│   ├── 02-hermes-client.md
│   ├── 03-speech-recognizer.md
│   ├── 04-speech-synthesizer.md
│   ├── 05-app-state.md
│   ├── 06-connection-settings.md
│   ├── 07-jarvis-hud-basic.md
│   ├── 08-voice-loop.md
│   ├── 09-orb-animation.md
│   ├── 10-waveform-visualizer.md
│   ├── 11-transcript-overlay.md
│   ├── 12-interruptions.md
│   ├── 13-conversation-history.md
│   ├── 14-continuous-listening.md
│   ├── 15-polish-and-release.md
│   └── ...
├── HermesVoice/
│   ├── HermesVoice.xcodeproj/
│   ├── HermesVoice/
│   │   ├── App/
│   │   │   ├── HermesVoiceApp.swift
│   │   │   └── ContentView.swift
│   │   ├── Core/
│   │   │   ├── HermesClient.swift
│   │   │   ├── SpeechRecognizer.swift
│   │   │   ├── SpeechSynthesizer.swift
│   │   │   └── AudioEngine.swift
│   │   ├── Views/
│   │   │   ├── JarvisHUD.swift
│   │   │   ├── OrbView.swift
│   │   │   ├── WaveformView.swift
│   │   │   ├── TranscriptOverlay.swift
│   │   │   └── ConnectionSheet.swift
│   │   ├── Models/
│   │   │   ├── AppState.swift
│   │   │   ├── Message.swift
│   │   │   └── SpeechLanguage.swift
│   │   ├── Resources/
│   │   │   └── Assets.xcassets/
│   │   └── HermesVoice.entitlements
│   └── HermesVoiceTests/
└── .github/
    └── workflows/
        └── build.yml
```


## Required entitlements

```xml
<key>com.apple.security.device.audio-input</key>    <!-- microphone -->
<true/>
<key>com.apple.security.network.client</key>         <!-- HTTP connection -->
<true/>
<key>NSSpeechRecognitionUsageDescription</key>       <!-- on-device STT -->
```


## UI — Jarvis style

### Color palette
- Background: pure black (#000000)
- Primary: electric blue (#00A8FF)
- Secondary: cyan (#00F5FF)
- Accent: low-opacity white for grids/lines
- Text: white (#FFFFFF) in a monospace font (SF Mono or Menlo)
- Alerts/errors: orange (#FF6B35)

### Orb visual states
1. **Idle** — small orb, slow and subtle pulse, dim blue
2. **Listening** — orb expands, microphone audio waves, bright blue
3. **Thinking** — orb spins/pulses fast, orbiting particles, cyan
4. **Speaking** — orb emits outward waves, TTS waveform, blue+cyan
5. **Error** — orb contracts, orange flicker

### Layout
```
┌──────────────────────────────────────────┐
│                                          │
│           [user transcript]              │
│                                          │
│                                          │
│              ┌──────────┐                │
│              │          │                │
│              │   ORB    │                │
│              │          │                │
│              └──────────┘                │
│                                          │
│           [Hermes response]              │
│                                          │
│  ┌────┐                        ┌──────┐ │
│  │ ⚙️ │                        │ 🎤   │ │
│  └────┘                        └──────┘ │
└──────────────────────────────────────────┘
```
- Bottom-left corner: settings button (opens ConnectionSheet)
- Bottom-right corner: microphone button (push-to-talk / toggle)
- Center: animated orb
- Above the orb: the user's latest transcript (fade in/out)
- Below the orb: Hermes' response appearing token by token


## Interaction flow

1. User opens the app → connection screen if no URL is saved (language defaults
   to the system locale)
2. App checks `GET /health` on the server → orb goes to Idle
3. User presses the microphone button (or a global hotkey) → orb goes to Listening
4. SFSpeechRecognizer transcribes in real time → text appears above the orb
5. User releases the button → the text is sent to Hermes over SSE
6. Orb goes to Thinking → tokens start arriving
7. First token arrives → orb goes to Speaking, AVSpeechSynthesizer starts
8. Tokens accumulate below the orb in real time
9. TTS finishes → orb returns to Idle
10. (Phase 3) Continuous detection: if the user speaks during Speaking, it interrupts


## Language

A single `SpeechLanguage` setting drives three things at once:

| Consumer            | How it uses the setting                        |
|---------------------|------------------------------------------------|
| SFSpeechRecognizer  | built with that `Locale`                        |
| AVSpeechSynthesizer | voices filtered by that language code           |
| System prompt       | `Always reply in <English name of the language>.` |

The available list is the intersection of what the device can transcribe
(`SFSpeechRecognizer.supportedLocales()`) and what it can speak (installed
`AVSpeechSynthesisVoice`s) — a language you can hear but not speak would break
the loop. The default follows the system locale, falling back to `en-US`.

The system prompt template stays in English: it is an instruction to the model,
not user-facing copy. The reply language is injected as a directive, so
supporting a new language costs nothing beyond the OS having the voice.

Switching language mid-session is supported and preserves the conversation
history. See task 08 for the catalog and the switching rules.


## Persistence

- `UserDefaults` for:
  - Hermes server URL
  - API key (in the Keychain via SecItemAdd)
  - Selected language (BCP-47 id, e.g. "es-ES")
  - Preferred voice per language (`[language id: AVSpeechSynthesisVoice id]`)
  - Custom system prompt (optional; nil uses the default template)
  - Activation mode (push-to-talk vs continuous)
- `@AppStorage` for simple UI preferences
- Conversation history: array of `Message` in memory (not persisted across sessions in the MVP)


## Testing

Every task defines its own acceptance criteria. Minimum tests:
- `HermesClientTests` — SSE parsing, request building
- `SpeechRecognizerTests` — state handling, permissions
- `AppStateTests` — orb state transitions
- `SpeechLanguageTests` — catalog filtering, default resolution, prompt directive
- Working UI previews for every view


## Phases

### Phase 1 — Working MVP (tasks 01-08)
Hermes connection, STT, TTS, basic UI, full voice loop.

### Phase 2 — Jarvis visuals (tasks 09-11)
Animated orb, waveforms, HUD-style overlays.

### Phase 3 — Polish (tasks 12-15)
Interruptions, history, continuous listening, release.
