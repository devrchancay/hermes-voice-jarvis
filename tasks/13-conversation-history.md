# Task 13 — Conversation History

## Goal
A side panel or modal showing the current conversation history,
styled consistently with the HUD.

## What to do

1. Create `Views/ConversationHistoryView.swift`

2. Layout:
   - A side panel sliding in from the left, or
   - A semi-transparent overlay on top of the HUD
   - Background: black at opacity 0.9
   - Width: 40% of the window (or 300pt minimum)

3. Content:
   - List of messages (user + assistant) in chronological order
   - User messages: right-aligned, subtle blue background
   - Hermes messages: left-aligned, no background
   - Timestamp below each message (HH:mm)
   - Font: SF Mono, 13pt

4. Actions:
   - Toggle: a button in the HUD or a gesture (swipe from the left edge)
   - Clear: a button to clear the history (with confirmation)
   - Copy: clicking a message copies its text

5. Scrolling:
   - Auto-scroll to the latest message when a new one arrives
   - The user can scroll up freely

6. Integration:
   - Reads from `appState.messages`
   - Updates in real time as tokens arrive

## Acceptance criteria
- [ ] The history shows every message from the session
- [ ] Visual distinction between user and assistant
- [ ] Updates in real time during streaming
- [ ] Can be opened/closed without interrupting the conversation
- [ ] The clear button works, with confirmation
- [ ] Styling consistent with the Jarvis theme
- [ ] Builds without warnings
