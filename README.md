# WhisperKey

Lightweight local speech-to-text for macOS. Press a hotkey, speak, and your words are transcribed and pasted — all running locally on your Mac. No cloud, no subscription, no data leaves your machine.

WhisperKey sits in your menu bar and uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) under the hood. When you're not transcribing, it uses virtually no resources (~15MB RAM). The speech model only loads during transcription and is fully released afterward.

## Features

- **Global hotkey** (default: ⌥Space) — press to record, press again to transcribe
- **Fully local** — everything runs on-device, nothing is sent to the cloud
- **Minimal footprint** — <20MB RAM when idle, model memory released after each transcription
- **Auto-paste** — transcribed text is automatically pasted into your active app (optional)
- **Multi-language** — supports German, English, and auto-detection via the `ggml-medium` model
- **First-launch wizard** — guided setup that downloads and compiles whisper.cpp for you
- **Apple Silicon optimized** — Metal GPU acceleration for fast transcription

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac
- ~2GB free disk space (for whisper.cpp binary + medium model)
- Xcode Command Line Tools (the setup wizard will help you install these)

## Installation

### From GitHub Releases

1. Download the latest `WhisperKey-x.x.x.dmg` from [Releases](https://github.com/Costa318/WhisperKey/releases)
2. Open the DMG and drag WhisperKey to your Applications folder
3. Launch WhisperKey — the setup wizard will guide you through the rest

> **Note:** Since the app is not notarized, macOS will warn you on first launch. Right-click the app and select "Open" to bypass Gatekeeper, or go to System Settings > Privacy & Security and click "Open Anyway".

### From Source

```bash
git clone https://github.com/Costa318/WhisperKey.git
cd WhisperKey
xcodebuild -scheme WhisperKey -configuration Release
```

The built app will be in `build/Release/WhisperKey.app`.

## Setup

On first launch, WhisperKey opens a setup wizard that:

1. Checks for Xcode Command Line Tools (installs them if needed)
2. Clones and compiles whisper.cpp with Metal acceleration
3. Downloads the `ggml-medium.bin` speech model (~1.5GB)
4. Requests microphone permission
5. Optionally enables auto-paste (requires Accessibility permission)

Everything is installed to `~/.whisperkey/`:

```
~/.whisperkey/
├── bin/
│   └── whisper-cli      # Compiled whisper.cpp binary
└── models/
    └── ggml-medium.bin  # Speech recognition model
```

## Usage

1. Press **⌥Space** (or your configured hotkey) to start recording
2. Speak
3. Press the hotkey again to stop recording and transcribe
4. The transcribed text is copied to your clipboard and optionally auto-pasted

The menu bar icon shows the current state:
- **Idle:** waveform icon
- **Recording:** red waveform icon
- **Transcribing:** waveform with spinner

## Settings

Click the menu bar icon and select **Settings** to configure:

- **Hotkey** — click the hotkey field and press a new key combination
- **Language** — Auto (recommended), German, or English
- **Auto-paste** — automatically paste transcriptions into the active app
- **Launch at Login** — start WhisperKey when you log in
- **Sound feedback** — play a sound when recording starts/stops

Advanced settings include custom paths for the whisper-cli binary and model, thread count, and max recording duration.

## Permissions

WhisperKey needs two macOS permissions:

| Permission | Required | Purpose |
|---|---|---|
| **Microphone** | Yes | Record your speech for transcription |
| **Accessibility** | Optional | Auto-paste transcriptions into the active app |

If you skip Accessibility, transcriptions are still copied to your clipboard — you just paste manually with ⌘V.

## How It Works

WhisperKey runs whisper.cpp as a subprocess rather than linking it as a library. This means the ~500MB of model memory is fully released after each transcription — the app returns to its tiny ~15MB idle footprint. The trade-off is a ~1-2 second startup per transcription, which is barely noticeable in practice.

Audio is captured at 16kHz mono via AVAudioEngine, converted to WAV format, and passed to the whisper-cli binary. The result is parsed from stdout, copied to the clipboard, and optionally pasted via a simulated ⌘V keystroke.

## Troubleshooting

**App doesn't respond to hotkey:**
Make sure no other app is using the same key combination. Try changing the hotkey in Settings.

**Transcription is empty or inaccurate:**
Check that your microphone is working and you're speaking clearly. The medium model works best with clear speech in English or German.

**Auto-paste doesn't work:**
Open System Settings > Privacy & Security > Accessibility and make sure WhisperKey is listed and enabled. If you recently updated the app, you may need to remove and re-add it.

**Setup wizard fails at compilation:**
Ensure Xcode Command Line Tools are installed: `xcode-select --install`

## License

MIT

## Acknowledgments

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) by Georgi Gerganov — the engine behind the transcription
- [HotKey](https://github.com/soffes/HotKey) by Sam Soffes — global hotkey support
