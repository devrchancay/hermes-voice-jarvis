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
   - Voice picker (Picker listing the available voices)
   - Activation mode (Picker: Push-to-Talk / Continuous)
   - A "Save" button

3. Jarvis visual style:
   - Dark background (not macOS' default white sheet)
   - Fields with a subtle blue border
   - Text in SF Mono / monospace
   - Use the HermesColors palette

4. Behavior:
   - Shown as a modal sheet on first launch (if no URL is saved)
   - Opens from the ⚙️ button on the main screen
   - On save, it tries to connect automatically
   - If the connection fails, show the error but still allow saving

5. Validation:
   - The URL must start with http:// or https://
   - The API key cannot be empty
   - Show errors inline, not as alerts

## Acceptance criteria
- [ ] The URL and API key fields work
- [ ] "Test Connection" runs the check and shows the result
- [ ] Opens automatically when there is no saved configuration
- [ ] Dark styling consistent with the Jarvis theme
- [ ] Data persists (URL in UserDefaults, key in the Keychain)
- [ ] The voice picker lists the available Spanish voices
- [ ] Working Preview
- [ ] Builds without warnings
