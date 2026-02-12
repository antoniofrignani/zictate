# Zictate

<p align="center">
  <img src="docs/images/logo.png" alt="Zictate logo" width="160" />
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2026.2%2B-111827?style=flat-square">
  <img alt="Language" src="https://img.shields.io/badge/language-Swift%205-F97316?style=flat-square">
  <img alt="UI" src="https://img.shields.io/badge/UI-SwiftUI-0EA5E9?style=flat-square">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-16A34A?style=flat-square">
</p>

Local, menu-bar dictation app for macOS.

Zictate records microphone audio, transcribes locally with `whisper.cpp`, and inserts text where your cursor is.

## Highlights

- 100% local speech-to-text with downloadable Whisper models.
- Global start/stop triggers:
  - Keyboard shortcut
  - Double-tap modifier key
- Live bottom overlay with waveform and stop control.
- Secure transcript history:
  - System-auth unlock (Touch ID / password)
  - Pagination + bulk actions
  - Auto-lock timeout
- Cursor insertion modes:
  - Direct key events
  - Pasteboard + Cmd+V
- Bring-your-own-model support:
  - Validate model URL before download
  - Show size, progress, speed, ETA
  - Import local model files

## Requirements

- Apple Silicon Mac (recommended)
- macOS 26.2+
- Xcode 26.2+
- Homebrew
- `whisper.cpp` CLI

## Quick Start

1. Clone and open:

```bash
git clone <your-repo-url>
cd Zictate
open Zictate.xcodeproj
```

2. Install and verify `whisper.cpp`:

```bash
brew install whisper-cpp
which whisper-cli
whisper-cli --help
```

Expected Apple Silicon path:

```bash
/opt/homebrew/bin/whisper-cli
```

3. Run the app from Xcode (`Zictate` scheme on `My Mac`).

4. First launch setup in **Settings**:
- Grant Microphone and Accessibility permissions.
- Install/import a model and click **Use**.
- Set **CLI Path** to `/opt/homebrew/bin/whisper-cli` (or keep auto-discovery if it works).
- Configure trigger + language in **Dictation**.

## Unsigned GitHub Build (No Notarization)

This repository includes a GitHub Actions workflow that builds an unsigned macOS `.app` and publishes:

- `Zictate-macOS-unsigned.zip`
- `Zictate-macOS-unsigned.sha256`

Workflow file:

- `.github/workflows/build-macos-unsigned.yml`

How to publish a downloadable build:

1. Push a tag like `v0.1.0` (or run the workflow manually from Actions).
2. Download the produced ZIP from the workflow artifact or GitHub Release assets.

Important:

- Because the app is not notarized, macOS Gatekeeper will warn users.
- Users can still run it by right-clicking the app and selecting **Open**, then confirming.
- If needed, users can remove quarantine from Terminal:

```bash
xattr -dr com.apple.quarantine /path/to/Zictate.app
```

## BYOM Example (Italian)

Model page URL:

`https://huggingface.co/bofenghuang/whisper-large-v3-distil-it-v0.2/blob/main/ggml-model.bin`

1. Open **Settings -> Models**.
2. Paste URL in **Bring Your Own Model**.
3. Optional name: `ggml-model-it.bin`.
4. Click **Validate & Add**.
5. Download from **Validated Remote Models**.
6. Click **Use**.
7. In **Dictation**, select language `Auto` or `Italian`.

Notes:

- Repo root URLs like `https://huggingface.co/<org>/<repo>` are rejected.
- `.../blob/...` URLs are automatically normalized to direct `.../resolve/...` URLs.

## Usage

1. Start dictation from shortcut, double-tap trigger, or menu bar.
2. Speak.
3. Stop dictation (same trigger or overlay stop button).
4. Transcript is saved to history and optionally auto-inserted at cursor.

## Troubleshooting

### `whisper.cpp CLI executable was not found`

```bash
brew install whisper-cpp
ls -l /opt/homebrew/bin/whisper-cli
```

Then set **Settings -> CLI Path** to `/opt/homebrew/bin/whisper-cli`.

### CLI path says "not executable"

- Use absolute path: `/opt/homebrew/bin/whisper-cli`
- Clean if needed:

```bash
xcodebuild -project Zictate.xcodeproj -scheme Zictate clean
```

### No text inserted at cursor

- Confirm Accessibility permission is granted.
- Ensure target input field is focused when dictation stops.

### Model download/install failed

- Retry in **Models**.
- Check network connectivity.
- Ensure app can write to Application Support storage.

## Development

- Language: Swift
- UI: SwiftUI
- Persistence: SwiftData
- Test targets:
  - `ZictateTests`
  - `ZictateUITests`

Optional CLI build:

```bash
xcodebuild \
  -project Zictate.xcodeproj \
  -scheme Zictate \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build
```

## License

MIT. See `LICENSE`.
