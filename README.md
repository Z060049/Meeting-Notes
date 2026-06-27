# AutoScribe

AutoScribe is a native macOS menu-bar app for recording microphone and system audio, sending the capture through an API-first transcription/summarization flow, and exporting Markdown notes.

## Current MVP Build

- Native Swift/SwiftUI menu-bar utility
- Manual start/stop from the menu bar
- Double-tap Command global shortcut
- First-run consent checklist
- Microphone capture via AVFoundation
- System audio capture via Core Audio Tap with temporary ScreenCaptureKit fallback
- OpenAI transcription and summarization provider
- Markdown export to `~/Documents/AutoScribe/`
- Settings for OpenAI key, output folder, inactivity timeout, summary depth, and consent reminder

## Run

For permission testing, use the dev app bundle:

```sh
./scripts/build-dev-app.sh
open .build/AutoScribe.app
```

Then confirm the relevant macOS permissions:

- `Privacy & Security > Accessibility` for the double-Command shortcut.
- `Privacy & Security > Screen & System Audio Recording > System Audio Recording Only` for Core Audio system capture.
- `Privacy & Security > Screen & System Audio Recording` only if the temporary ScreenCaptureKit fallback is used.

If `AutoScribe` is not listed, click the `+` button and choose:

```text
AutoScribe/.build/AutoScribe.app
```

You can also run the raw Swift package executable, but macOS permissions may appear under the launching app instead of AutoScribe:

```sh
swift run AutoScribe
```

## Test

```sh
swift test
```

## MVP Validation

Use the manual validation checklist for Track 1 testing:

- Checklist: `docs/MVP_VALIDATION_CHECKLIST.md`
- Test run template: `docs/MVP_TEST_RUN_TEMPLATE.md`

Recommended validation flow:

1. Build and launch the dev app bundle:

   ```sh
   ./scripts/build-dev-app.sh
   open .build/AutoScribe.app
   ```

2. Open AutoScribe from the menu bar and confirm settings, output folder, and permissions.
3. Run scenarios from `docs/MVP_VALIDATION_CHECKLIST.md`.
4. In the Debug section, use **Copy Validation Report** after each scenario or test run.
5. Paste the report and generated Markdown paths into `docs/MVP_TEST_RUN_TEMPLATE.md`.

The smallest smoke pass is:

- Mic-only short recording.
- System-audio-only browser playback recording.
- Combined mic + browser playback recording.

For a production distributable, sign and notarize the app bundle.
