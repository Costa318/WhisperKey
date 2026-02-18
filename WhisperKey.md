# WhisperKey – Lightweight Local Transcription Tool for macOS

## Project Overview

A minimal macOS menu bar app that transcribes speech locally using whisper.cpp. The app should use virtually zero resources when idle and only load the Whisper model during active transcription.

**Core problem:** Existing tools like Superwhisper consume 1GB+ RAM even when idle. This tool should use <20MB when not transcribing.

**Target user:** Developer who wants a global hotkey to transcribe speech (German and English) and paste the result.

**UX principle:** The app should feel like a polished macOS tool. Open it, follow the wizard, done. No Terminal, no manual configuration, no file pickers for normal usage.

## Tech Stack

- **Language:** Swift + SwiftUI
- **UI:** macOS Menu Bar app (NSStatusItem)
- **Transcription engine:** whisper.cpp (https://github.com/ggerganov/whisper.cpp) – called as a CLI subprocess
- **Model:** `ggml-medium.bin` (~1.5GB) – good balance between accuracy and speed for DE/EN
- **Audio capture:** AVFoundation (AVAudioEngine)
- **Hotkey:** HotKey package (https://github.com/soffes/HotKey) or Carbon global hotkey APIs
- **Min macOS version:** 14.0 (Sonoma)
- **Sandboxing:** Disabled (required for running external subprocess and accessing `~/.whisperkey/`)

## Architecture

```
┌─────────────────────────────────────────────┐
│  Menu Bar Icon (idle: ~10-15MB RAM)         │
│  - Status indicator (idle / recording /     │
│    transcribing)                            │
│  - Settings, Quit                           │
└──────────────┬──────────────────────────────┘
               │ Global Hotkey (default: ⌥+Space)
               ▼
┌─────────────────────────────────────────────┐
│  Recording Phase                            │
│  - AVAudioEngine captures microphone input  │
│  - Save as WAV (16kHz, mono, 16-bit)        │
│  - Visual feedback: menu bar icon changes   │
│  - Press hotkey again to stop               │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│  Transcription Phase                        │
│  - Call whisper.cpp CLI as a subprocess      │
│  - Parse stdout for transcribed text        │
│  - Model loaded only during this phase      │
│  - RAM spike ~500MB, then fully released    │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│  Output Phase                               │
│  - Copy transcription to clipboard          │
│  - Auto-paste into active app (if enabled)  │
│  - Temporary audio file deleted             │
└─────────────────────────────────────────────┘
```

## Key Design Decisions

### Why CLI subprocess instead of linked library?
- Model memory is fully released when subprocess exits (zero idle RAM from model)
- whisper.cpp binary is easily updatable independently
- Simpler to build and maintain
- Trade-off: ~1-2s startup per transcription (acceptable)

### Why `medium` model?
- `tiny`/`base`: Too many errors in German
- `medium`: Excellent DE/EN quality, ~1.5GB disk, transcription takes ~3-5s for 30s audio on M-series
- `large-v3`: Marginal improvement, 2x slower, 3GB disk
- User can swap models via Settings (advanced)

## Standard Paths

The app uses a fixed default directory. No configuration needed for normal usage:

```
~/.whisperkey/
├── bin/
│   └── whisper-cli          # Compiled whisper.cpp binary
└── models/
    └── ggml-medium.bin      # Default model
```

On every launch, the app checks these paths automatically. If both exist → app is ready.

---

## First Launch Flow

The entire setup happens inside the app. The user never needs to open Terminal.

### App Launch Logic

```
App starts
  → Check ~/.whisperkey/bin/whisper-cli exists AND ~/.whisperkey/models/ggml-medium.bin exists
    → YES: Check permissions → Show menu bar icon (normal operation)
    → NO:  Show First Launch Wizard
```

### First Launch Wizard (SwiftUI Window)

The wizard is a single window with a step indicator at the top. The user clicks "Next" to progress. Back button available on every step.

#### Step 1: Welcome
- App icon + "Welcome to WhisperKey"
- "WhisperKey transcribes your speech locally on your Mac. Nothing is sent to the cloud."
- "To get started, WhisperKey needs to download and set up a speech recognition engine. This is a one-time process."
- Single button: **"Get Started"**

#### Step 2: Prerequisites Check
The app automatically checks for Xcode Command Line Tools (needed to compile whisper.cpp):

```swift
// Check by running: xcode-select -p
// If exit code 0 → installed
// If exit code 2 → not installed
```

**If installed:** Show green checkmark "✓ Build tools found", auto-advance to Step 3 after 1 second.

**If not installed:** Show explanation:
- "WhisperKey needs Apple's build tools to set up the speech engine."
- Button: **"Install Build Tools"**
- This triggers `xcode-select --install` which shows Apple's native installation dialog
- App polls `xcode-select -p` every 3 seconds to detect completion
- Once detected → auto-advance to Step 3

#### Step 3: Install whisper.cpp & Model
This is the main installation step. Everything runs as a background `Process()` within the app.

**UI layout:**
- Progress bar (determinate where possible, indeterminate during compilation)
- Status text showing current step
- Scrollable log view (collapsed by default, expandable via "Show Details" toggle)
- **"Cancel"** button to abort

**Installation steps executed in-app (not as external shell script):**

```
Step 1/4: "Creating directories..."
  → mkdir -p ~/.whisperkey/bin ~/.whisperkey/models

Step 2/4: "Downloading whisper.cpp source code..."
  → git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git /tmp/whisperkey-build/whisper.cpp
  → Progress: indeterminate (git doesn't reliably report progress)

Step 3/4: "Compiling whisper.cpp (this may take 1-2 minutes)..."
  → cd /tmp/whisperkey-build/whisper.cpp
  → cmake -B build -DWHISPER_METAL=ON
  → cmake --build build --config Release -j$(sysctl -n hw.ncpu)
  → cp build/bin/whisper-cli ~/.whisperkey/bin/whisper-cli
  → chmod +x ~/.whisperkey/bin/whisper-cli
  → Progress: indeterminate, but show elapsed time

Step 4/4: "Downloading speech model (~1.5 GB)..."
  → Download ggml-medium.bin from Hugging Face:
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin
  → Save to ~/.whisperkey/models/ggml-medium.bin
  → Use URLSession for download with progress tracking
  → Progress: determinate (show MB downloaded / total, percentage, estimated time)

Cleanup:
  → rm -rf /tmp/whisperkey-build
```

**Important implementation notes:**
- The model download (Step 4) should use `URLSessionDownloadTask` so the app can show real download progress (bytes received / total bytes)
- All steps run as Swift `Process()` calls or native URLSession, NOT as an external .sh script
- If any step fails, show the error message clearly with a "Retry" button and a "Show Details" button that reveals the log output
- If compilation fails, the most common cause is missing Xcode CLT – detect this and guide the user back to Step 2
- Before starting, check available disk space (`FileManager.attributesOfFileSystem`). If <3GB free, warn: "WhisperKey needs ~2GB of free disk space for installation."

**On success:**
- Show checkmark animation: "✓ Installation complete!"
- Auto-advance to Step 4 after 2 seconds

#### Step 4: Permissions
Guide the user through macOS permissions. Show both as a checklist on a single screen:

**Microphone (required):**
- Button: **"Grant Access"**
- Triggers `AVAudioApplication.requestRecordPermission` → native macOS dialog appears
- Note: Requires `com.apple.security.device.audio-input` entitlement (Hardened Runtime) and the app must be in `.regular` activation policy (not `.accessory`) for the dialog to appear
- After user responds, update status:
  - ✓ "Microphone access granted" (green)
  - ✗ "Access denied" (red) — microphone status is polled every 2s to detect changes
- If denied: show note "WhisperKey cannot work without microphone access."

**Accessibility (optional, for auto-paste):**
- Explanation: "Allow WhisperKey to automatically paste transcriptions into your active app. Without this, text is copied to your clipboard instead."
- Button: **"Enable Auto-Paste"** → opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` with prompt to add WhisperKey
- The app polls `AXIsProcessTrusted()` every 2 seconds to detect when user grants permission
- When granted → show ✓
- **"Skip"** link below: "I'll just use clipboard" → marks auto-paste as disabled in Preferences

#### Step 5: Ready
- "You're all set! WhisperKey is now in your menu bar."
- Show the menu bar icon location with a pointer/arrow illustration
- "Press **⌥ Space** to start recording. Press again to stop and transcribe."
- Checkbox: **"Launch WhisperKey at login"** (checked by default)
- Button: **"Start Using WhisperKey"** → closes wizard, activates menu bar icon

---

## Normal Operation (Post-Setup)

### Menu Bar Icon & Menu

The menu bar icon is the primary interface. It uses SF Symbols and changes based on state:

- **Idle:** `waveform` icon (default color)
- **Recording:** `waveform` icon (red tint) or `record.circle` with red fill
- **Transcribing:** `waveform` icon with activity spinner overlay

**Menu (click on icon):**
```
Recording...              ← only visible during recording
Press ⌥Space to record    ← only visible when idle
──────────────
Settings...
Launch at Login  ✓        ← toggle
──────────────
Quit WhisperKey
```

Keep the menu minimal. No permission status, no technical details. If something is broken, the app shows a notification or alert – not a permanent status in the menu.

### Recording & Transcription Flow

1. User presses hotkey (default ⌥+Space)
2. Menu bar icon changes to recording state
3. Optional: subtle system sound on start (configurable, off by default)
4. User speaks
5. User presses hotkey again to stop
6. Menu bar icon changes to transcribing state
7. whisper.cpp subprocess runs with the recorded audio
8. On completion:
   - Text is copied to clipboard (always)
   - If auto-paste enabled + Accessibility granted: simulate Cmd+V to paste into active app
   - If auto-paste disabled or no Accessibility: show brief macOS notification with transcription preview and "Copied to clipboard" message
9. Menu bar icon returns to idle state
10. Temp audio file deleted

### Settings Window

Simple SwiftUI window, opened via menu bar → "Settings..."

**General tab:**
- Hotkey: Display current hotkey + "Change" button with key recorder
- Language: Dropdown – Auto (recommended) / German / English
- Auto-paste: Toggle (shows note if Accessibility not granted: "Requires Accessibility permission. [Grant]")
- Launch at Login: Toggle
- Sound feedback on recording start/stop: Toggle (default: off)

**Advanced tab** (for power users, not needed for normal use):
- whisper.cpp binary path (with file picker + "Reset to default" button)
- Model file path (with file picker + "Reset to default" button)
- Thread count for transcription (default: 4)
- Max recording duration (default: 5 minutes)

---

## Subsequent Launches & Error Recovery

On every launch:

1. Check `~/.whisperkey/bin/whisper-cli` exists
2. Check `~/.whisperkey/models/ggml-medium.bin` exists (or custom path from Preferences)
3. If either missing → show alert with two buttons:
   - **"Run Setup Again"** → opens First Launch Wizard at Step 3
   - **"Locate Files"** → opens Settings window on Advanced tab
4. Check microphone permission → if revoked since last use, show one-time alert:
   - "Microphone access was revoked. WhisperKey needs microphone access to work. [Open Settings] [Dismiss]"
5. Check Accessibility → if not granted, silently disable auto-paste (no alert, no nag)
6. Register global hotkey
7. Show menu bar icon

---

## Detailed Implementation Plan

### Phase 1: Project Setup
1. Create new Xcode project: macOS App, SwiftUI lifecycle
2. Configure as menu bar only app (set `LSUIElement = true` in Info.plist)
3. Disable App Sandbox in entitlements (needed for subprocess + `~/.whisperkey/` access)
4. Add `com.apple.security.device.audio-input` entitlement (required by Hardened Runtime for mic access)
5. Add `NSMicrophoneUsageDescription` in Info.plist: "WhisperKey needs microphone access to record your speech for transcription."
5. Set up GitHub repo with .gitignore for Xcode/Swift
6. Add to .gitignore: `*.bin`, `.whisperkey/`

### Phase 2: First Launch Wizard
1. Implement `SetupManager` – handles prerequisite checks, installation steps, path validation
2. Implement `ModelDownloader` – URLSessionDownloadTask with progress delegate
3. Implement `PermissionManager` – microphone request, Accessibility check, polling
4. Implement `FirstLaunchView` – SwiftUI wizard with step indicator and all 5 steps
5. Implement compilation via `Process()` with stdout/stderr capture for the log view
6. Test: fresh install experience end-to-end

### Phase 3: Menu Bar UI
1. Create `NSStatusItem` with SF Symbol icon
2. Implement three visual states (idle, recording, transcribing)
3. Build menu with minimal items
4. Implement Settings window with General and Advanced tabs
5. Implement Launch at Login via `SMAppService.mainApp` (macOS 13+)

### Phase 4: Audio Recording
1. Use `AVAudioEngine` with input node
2. Configure: 16kHz sample rate, mono, 16-bit PCM
3. On hotkey press → start recording, write to temp WAV file in `NSTemporaryDirectory()`
4. On hotkey press again → stop recording
5. Max recording duration: 5 minutes (safety limit, configurable in Advanced settings)
6. Handle edge case: empty/very short recording (<0.5s) → show notification "Recording too short", don't transcribe

### Phase 5: Whisper Integration
1. Run whisper-cli as `Process()` subprocess:
   ```
   ~/.whisperkey/bin/whisper-cli \
     --model ~/.whisperkey/models/ggml-medium.bin \
     --file /tmp/recording.wav \
     --language auto \
     --output-txt \
     --no-timestamps \
     --threads 4
   ```
2. Use paths from Preferences (defaults to `~/.whisperkey/` paths)
3. Capture stdout, parse transcription text (strip whitespace, remove empty lines)
4. Handle errors gracefully:
   - Binary not found → alert with "Run Setup Again" option
   - Model not found → same
   - Process crashes → notification "Transcription failed. Try again."
   - Empty result → notification "Could not detect speech."
5. Delete temp audio file after transcription
6. Log transcription time to console for debugging

### Phase 6: Output & Paste
1. Copy transcribed text to `NSPasteboard.general`
2. If auto-paste enabled AND `AXIsProcessTrusted()`:
   - Simulate Cmd+V via `CGEvent` to paste into the previously active app
   - Brief delay (~100ms) before simulating paste to ensure app focus is restored
3. If auto-paste disabled or no Accessibility:
   - Show macOS notification: "[First 80 chars of text...] – Copied to clipboard"
   - Use `UNUserNotificationCenter` for notifications
4. Always copy to clipboard regardless of auto-paste setting

### Phase 7: Global Hotkey
1. Add HotKey SPM package (https://github.com/soffes/HotKey)
2. Default: Option + Space (stored in Preferences, configurable in Settings)
3. Toggle behavior: first press starts recording, second press stops and transcribes
4. Handle conflict: if hotkey is already in use by another app, show alert with option to change

---

## File Structure

```
WhisperKey/
├── WhisperKey.xcodeproj
├── WhisperKey/
│   ├── App/
│   │   ├── WhisperKeyApp.swift          # App entry point, decides wizard vs menu bar
│   │   └── AppState.swift               # Observable state (idle/recording/transcribing/setup)
│   ├── Setup/
│   │   ├── SetupManager.swift           # Prerequisite checks, installation logic, Process() calls
│   │   ├── ModelDownloader.swift         # URLSession download with progress tracking
│   │   ├── PermissionManager.swift       # Microphone & Accessibility checks/requests
│   │   └── FirstLaunchView.swift         # Setup wizard UI (all 5 steps)
│   ├── MenuBar/
│   │   ├── StatusBarController.swift     # NSStatusItem, icon states, menu
│   │   └── SettingsView.swift            # Settings window (General + Advanced tabs)
│   ├── Core/
│   │   ├── AudioRecorder.swift           # AVAudioEngine recording logic
│   │   ├── WhisperTranscriber.swift      # Subprocess management for whisper-cli
│   │   ├── OutputManager.swift           # Clipboard + paste simulation
│   │   ├── HotkeyManager.swift          # Keyboard trigger registration (HotKey SPM)
│   │   └── MouseTriggerManager.swift    # Mouse button trigger (CGEvent tap, double-click detection)
│   ├── Utilities/
│   │   └── Preferences.swift            # UserDefaults wrapper for all settings
│   ├── Assets.xcassets
│   ├── Info.plist
│   └── WhisperKey.entitlements
├── README.md
├── CLAUDE.md                             # This file
└── .gitignore
```

Note: No `scripts/` directory. All setup logic lives in `SetupManager.swift` and `ModelDownloader.swift` and runs within the app process.

---

## Edge Cases & Error Handling

### Setup & Dependencies
- **No Xcode CLT:** Wizard Step 2 detects this and triggers `xcode-select --install`
- **Compilation fails:** Show error log, suggest "Make sure Xcode Command Line Tools are installed", offer Retry
- **Download fails (network error):** Show "Download failed. Check your internet connection." + Retry button. Partially downloaded file should be cleaned up.
- **Download interrupted (app closed):** On next launch, detect incomplete model file (check file size against expected ~1.5GB), delete partial file, restart download
- **Disk space insufficient:** Before downloading model, check available disk space (`FileManager.attributesOfFileSystem`). If <3GB free, warn: "WhisperKey needs ~2GB of free disk space for installation."
- **whisper.cpp binary missing after setup (user deleted it):** On launch, show alert with "Run Setup Again" option
- **Model file missing after setup:** Same as above

### Permissions
- **Microphone denied:** Show alert with deep-link to System Settings. App cannot function without this – disable hotkey.
- **Microphone revoked after initial grant:** On launch, show one-time alert. Don't nag on every transcription attempt.
- **Accessibility not granted:** Silently disable auto-paste. Show note in Settings. Never nag.
- **Accessibility revoked:** Silently disable auto-paste on next attempt.

### Recording & Transcription
- **Empty/too-short recording (<0.5s):** Notification "Recording too short", don't transcribe
- **Very long recording (>max duration):** Auto-stop with notification "Maximum recording time reached"
- **Transcription returns empty result:** Notification "Could not detect speech. Try again."
- **whisper.cpp process crashes/hangs:** Timeout after 60 seconds, kill process, show error notification, clean up temp file
- **Multiple rapid hotkey presses:** Debounce – ignore presses during transcription phase
- **Hotkey pressed while already recording:** Treat as "stop recording" (expected behavior)

---

## Performance Targets

- **Idle RAM:** <20MB
- **During transcription:** <600MB (temporarily, fully released after subprocess exits)
- **Transcription speed:** <5s for 30s of audio on Apple Silicon
- **Hotkey response:** <100ms from keypress to recording start
- **App launch to menu bar:** <1s (when setup is complete)

---

## Future Enhancements (Not for MVP)

- [ ] Transcription history (last 20 transcriptions, viewable from menu)
- [ ] Customizable output format (e.g., add punctuation cleanup, capitalization)
- [ ] Multiple model support (quick-switch between tiny for speed, medium for accuracy)
- [ ] Audio level meter during recording (visual feedback in menu bar)
- [ ] Automatic silence detection to auto-stop recording
- [ ] Sparkle framework for auto-updates
- [ ] Pre-compiled whisper-cli binary download (skip compilation step, no Xcode CLT needed)

### Implemented Improvements (not in original MVP scope)
- [x] Auto-download cmake if not installed on system (downloads temporary copy from GitHub releases)
- [x] DMG installer with Applications shortcut
- [x] GitHub Releases distribution
- [x] Unified trigger system: two configurable trigger slots (primary + alternative), each supports keyboard hotkey or mouse button (with double-click detection)