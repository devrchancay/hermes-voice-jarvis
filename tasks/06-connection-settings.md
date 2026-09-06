# Task 06 — Connection Settings View

## Goal
A settings screen where the user enters their Hermes URL and API key.

## What to do

1. Create `Views/ConnectionSheet.swift`

2. Fields:
   - Server URL (TextField, placeholder: "http://localhost:8642")
   - API Key (SecureField)
   - A "Test Connection" button that calls `client.checkHealth()`
   - Status indicator: ✓ connected / ✗ error / ⏳ testing
   - Language picker (Picker over `SpeechLanguageCatalog.available()`)
   - Voice picker (Picker listing the voices for the selected language)
   - Activation mode (Picker: Push-to-Talk / Continuous)
   - A "Save" button

3. Language picker behavior:
   - Label each row with the endonym and the localized name, e.g.
     "español (España) — Spanish (Spain)", so it is readable either way
   - Mark rows without on-device recognition with a small warning glyph and a
     tooltip: recognition for that language will not run on-device
   - Changing the language reloads the voice picker immediately
   - The voice picker shows an inline hint when the language has no installed
     voice: responses will be text-only until a voice is added in
     System Settings › Accessibility › Spoken Content
   - Default selection follows the system locale on first launch

4. Jarvis visual style:
   - Dark background (not macOS' default white sheet)
   - Fields with a subtle blue border
   - Text in SF Mono / monospace
   - Use the HermesColors palette

5. Behavior:
   - Shown as a modal sheet on first launch (if no URL is saved)
   - Opens from the ⚙️ button on the main screen
   - On save, it tries to connect automatically
   - If the connection fails, show the error but still allow saving

6. Validation:
   - The URL must start with http:// or https://
   - The API key cannot be empty
   - Show errors inline, not as alerts

## Acceptance criteria
- [ ] The URL and API key fields work
- [ ] "Test Connection" runs the check and shows the result
- [ ] Opens automatically when there is no saved configuration
- [ ] Dark styling consistent with the Jarvis theme
- [ ] Data persists (URL in UserDefaults, key in the Keychain)
- [ ] The language picker lists only languages the device can hear and speak
- [ ] The voice picker follows the selected language and updates on change
- [ ] Languages without on-device recognition are visibly flagged
- [ ] A language with no installed voice shows the text-only hint
- [ ] Language and per-language voice choices persist
- [ ] Working Preview
- [ ] Builds without warnings
