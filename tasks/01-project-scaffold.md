# Task 01 — Project Scaffold

## Goal
Create the Xcode project and the base file structure.

## What to do

1. Create a macOS App project with SwiftUI (no Storyboard).
   - Product name: `HermesVoice`
   - Bundle ID: `com.desarol.hermes-voice`
   - Deployment target: macOS 14.0
   - Swift 6

2. Create the folder structure:
   ```
   HermesVoice/
   ├── App/
   ├── Core/
   ├── Views/
   ├── Models/
   └── Resources/
   ```

3. Configure entitlements:
   - `com.apple.security.device.audio-input` = true
   - `com.apple.security.network.client` = true
   - App Sandbox = true

4. Configure Info.plist:
   - `NSSpeechRecognitionUsageDescription` = "HermesVoice uses speech recognition to transcribe your voice into text for the AI assistant."
   - `NSMicrophoneUsageDescription` = "HermesVoice needs microphone access to hear your voice."

5. Create placeholder files (empty, with a stub type):
   - `App/HermesVoiceApp.swift` — @main entry point
   - `App/ContentView.swift` — placeholder showing the text "HermesVoice"
   - `Models/AppState.swift` — empty @Observable class
   - `Models/Message.swift` — empty struct

6. Create `HermesColors.swift` in Resources/ with the palette:
   ```swift
   enum HermesColors {
       static let background = Color.black
       static let primary = Color(hex: "00A8FF")      // electric blue
       static let secondary = Color(hex: "00F5FF")     // cyan
       static let accent = Color.white.opacity(0.15)   // lines/grid
       static let text = Color.white
       static let error = Color(hex: "FF6B35")         // orange
   }
   ```

7. Verify that it builds without errors.

## Acceptance criteria
- [ ] Project opens in Xcode without errors
- [ ] Builds for macOS 14+
- [ ] Folder structure exists
- [ ] Entitlements configured
- [ ] Info.plist has the permission descriptions
- [ ] HermesColors defined with the palette from the spec
- [ ] App launches and shows "HermesVoice" in a window
