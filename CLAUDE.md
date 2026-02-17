# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Summary

WhisperKey is a macOS menu bar app that transcribes speech locally using whisper.cpp as a CLI subprocess. The full specification is in `WhisperKey.md`. Key constraint: <20MB idle RAM — the whisper model is only loaded during active transcription via a short-lived subprocess.

## Tech Stack

- Swift + SwiftUI, macOS 14.0+ (Sonoma)
- Menu bar app (`LSUIElement = true`, no dock icon)
- App Sandbox **disabled** (required for subprocess execution and `~/.whisperkey/` access)
- whisper.cpp called as CLI subprocess (not linked as library) — this is intentional for memory isolation
- HotKey SPM package (https://github.com/soffes/HotKey) for global hotkey
- AVAudioEngine for audio capture (16kHz, mono, 16-bit WAV)

## Build & Run

This is an Xcode project (SwiftUI lifecycle, macOS App template).

```bash
# Build from command line
xcodebuild -project WhisperKey.xcodeproj -scheme WhisperKey -configuration Debug build

# Build release
xcodebuild -project WhisperKey.xcodeproj -scheme WhisperKey -configuration Release build
```

Open `WhisperKey.xcodeproj` in Xcode for standard build/run/debug workflow.

## Architecture

**App state machine:** idle → recording → transcribing → idle (managed by `AppState`)

**Key flow:** Global hotkey (⌥Space) toggles recording. On stop, audio is saved as temp WAV, whisper-cli subprocess runs, result goes to clipboard (and optionally auto-pasted via CGEvent Cmd+V).

**Module layout:**
- `App/` — Entry point (`WhisperKeyApp`) and observable `AppState`
- `Setup/` — First-launch wizard: `SetupManager` (Process() calls for git clone, cmake, compile), `ModelDownloader` (URLSessionDownloadTask with progress), `PermissionManager`, `FirstLaunchView`
- `MenuBar/` — `StatusBarController` (NSStatusItem with 3 visual states), `SettingsView`
- `Core/` — `AudioRecorder` (AVAudioEngine), `WhisperTranscriber` (subprocess management), `OutputManager` (clipboard + paste simulation), `HotkeyManager`
- `Utilities/` — `Preferences` (UserDefaults wrapper)

## Standard Paths

```
~/.whisperkey/
├── bin/whisper-cli          # Compiled whisper.cpp binary
└── models/ggml-medium.bin   # ~1.5GB model file
```

The app checks both paths on launch. If missing → show setup wizard.

## Key Design Constraints

- **No external scripts** — all setup (git clone, cmake, compile, download) runs as Swift `Process()` or URLSession within the app
- **cmake auto-download** — if cmake is not on the system, `SetupManager.ensureCmake()` downloads a temporary copy from GitHub releases to `/tmp/whisperkey-build/`
- **Subprocess-based transcription** — whisper-cli is invoked per-transcription so model memory is fully released when done
- **Microphone is required**, Accessibility is optional (only for auto-paste via CGEvent)
- **No sandboxing** — entitlements must have `com.apple.security.app-sandbox` set to NO
- **Hardened Runtime** is enabled (Xcode default) — entitlements must include `com.apple.security.device.audio-input` or mic access silently fails
- Info.plist must include `NSMicrophoneUsageDescription`
- **LSUIElement + TCC dialogs** — during first-launch setup, the app switches to `NSApp.setActivationPolicy(.regular)` so macOS shows permission dialogs; switches back to `.accessory` after setup completes
- Microphone permission uses `AVAudioApplication.requestRecordPermission` (not the older `AVCaptureDevice` API)

## whisper-cli Invocation

```bash
~/.whisperkey/bin/whisper-cli \
  --model ~/.whisperkey/models/ggml-medium.bin \
  --file /tmp/recording.wav \
  --language auto \
  --output-txt \
  --no-timestamps \
  --threads 4
```

Timeout: 60 seconds. Kill process and clean up temp file on timeout.
