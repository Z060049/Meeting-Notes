# AutoScribe PRD

## 1) Product overview

AutoScribe is a macOS background app that captures both sides of a conversation (microphone + system audio), transcribes it, and outputs clean notes as Markdown.

It is designed for real-world meeting workflows where built-in recording is unavailable or restricted (Zoom, Google Meet/Hangouts, Microsoft Teams, phone calls via MacBook audio).

Core value:
- Universal capture independent of meeting platform
- Fast, searchable Markdown output for Obsidian or any notes app
- Optional privacy-first local processing mode

## Current implementation status

Status as of Jun 24, 2026:
- Native macOS Swift/SwiftUI menu-bar MVP has been implemented.
- The app currently runs as a local development `.app` bundle built from Swift Package Manager.
- Manual menu-bar recording works for the tested happy path.
- Microphone and system audio are captured into separate temporary files.
- OpenAI API mode can transcribe, summarize, and export Markdown successfully.
- Markdown output has been validated with a short real recording and saved to `~/Documents/AutoScribe/`.
- Local processing remains deferred.

Current development workflow:
- Build the local test app with `./scripts/build-dev-app.sh`.
- Launch the app with `open .build/AutoScribe.app`.
- For shortcut testing, grant Accessibility permission to `.build/AutoScribe.app`.
- Store the OpenAI API key through the app settings UI; the key is saved in macOS Keychain.

Validated output example:
- A short recording successfully generated a Markdown file with metadata, summary sections, and separate `Microphone` / `System Audio` transcript sections.

## 2) Problem statement

People regularly lose important meeting details because:
- Recording is not permitted by host settings
- Notes are incomplete while multitasking in live calls
- Existing tools are tied to specific meeting platforms

Users need a single Mac-native tool that works everywhere, starts/stops quickly, and produces reliable transcript + summary output without workflow friction.

## 3) Goals and non-goals

### Goals
- Run as a lightweight background macOS app
- Start/stop capture quickly via keyboard shortcut (double-tap Command key)
- Capture dual audio streams:
  - Local microphone input (user speech)
  - System/output audio (remote speaker audio from meeting app)
- Auto-stop when inactive for 5 minutes (configurable)
- Generate:
  - Full transcript in Markdown
  - Structured summary in Markdown
- Support two processing modes:
  - Local LLM/STT path (privacy-first, no API cost)
  - Third-party API path (simpler to ship first)

### Implementation choices made for MVP
- App stack: native macOS Swift/SwiftUI menu-bar app.
- Packaging during development: Swift Package Manager executable wrapped into a local `.app` bundle.
- API provider: OpenAI for speech-to-text and summarization.
- API key storage: macOS Keychain.
- Audio capture strategy:
  - Microphone: AVFoundation recording to `.wav`.
  - System audio: ScreenCaptureKit recording to `.m4a`.
- Speaker labeling in MVP: best-effort by capture stream (`Microphone` vs `System Audio`), not true diarization.

### Non-goals (v1)
- Live captions in-call
- Collaborative/shared notes
- Mobile app support
- Full meeting analytics dashboard
- Automatic CRM/task integrations

## 4) Target users

- Job seekers and interviewers
- Founders and operators in frequent remote meetings
- Consultants, PMs, engineers, and researchers
- Privacy-sensitive users who prefer local processing

## 5) User stories

- As a user, I can start recording from anywhere using a global shortcut without opening a full app window.
- As a user, I can capture both my voice and the other participant audio regardless of meeting platform.
- As a user, I receive a readable Markdown file with transcript and concise summary immediately after the meeting.
- As a user, I can rely on auto-stop if I forget to manually stop recording.
- As a privacy-focused user, I can keep processing fully local on my device.
- As a convenience-focused user, I can choose cloud/API processing for faster setup.

## 6) Functional requirements

### 6.1 Recording control
- Global hotkey: double-tap Command key to start/stop recording
- First-run UX should explain that double-tap Command requires macOS Accessibility permission.
- If Accessibility permission is not granted, manual menu-bar start/stop should still work.
- Tray/menu bar presence with clear state:
  - Idle
  - Recording
  - Processing
  - Complete
- Manual stop action from menu bar
- Auto-stop after 5 minutes of inactivity (no detected speech or audio above threshold)
- Optional confirmation sound or toast on start/stop

### 6.2 Audio capture
- Capture microphone input stream
- Capture system audio/output stream
- Timestamp and merge streams for aligned transcription context
- Handle device changes gracefully (mic unplug, audio route changes)
- Store temporary audio safely, then clean up after processing

### 6.3 Transcription + summarization
- Transcribe meeting audio into diarized or speaker-labeled text where possible
- For MVP, label transcript segments by capture source (`Microphone`, `System Audio`) rather than full speaker diarization.
- Produce meeting summary with:
  - Key points
  - Decisions
  - Action items
  - Follow-ups/questions
- Generate Markdown output with consistent template

### 6.4 File output
- Save `.md` output to configurable folder (default: `~/Documents/AutoScribe/`)
- Filename format: `YYYY-MM-DD_HH-mm_<meeting-title-or-generic>.md`
- Include metadata header:
  - Date/time
  - Duration
  - Processing mode (Local/API)
  - Audio sources captured

### 6.5 Settings
- Toggle processing mode (Local vs API)
- Configure inactivity timeout (default 5 min)
- Configure output folder
- Configure summary depth (brief/standard/detailed)
- Configure consent reminder prompt before capture
- Configure/store OpenAI API key securely via Keychain

## 7) User experience requirements

- Zero-friction launch at login (optional)
- Recording state always visible in menu bar icon state/color
- Post-processing should feel automatic and under 1-3 minutes for common meeting lengths
- Output Markdown should be immediately useful without manual cleanup

## 8) Privacy, security, and compliance requirements

- Explicitly warn users about local laws regarding recording consent
- First-run consent/compliance checklist
- First-run Accessibility permission guidance for global shortcut support
- Clear indicator when recording is active
- Local mode:
  - Audio/transcript stays on device
  - No network transfer for content processing
- API mode:
  - Disclose provider, retention behavior, and data handling
  - Offer "do not store" where provider supports it
- Secure temporary file handling and deletion after processing
- No background recording without explicit user start

## 9) Technical approaches

## 9.1 Path A: API-first (faster MVP)
Pros:
- Faster implementation and time-to-market
- Lower local compute requirements
- Better out-of-the-box transcription quality with managed models

Cons:
- Ongoing API cost
- Privacy concerns for some users
- Internet dependency

Recommended for:
- MVP launch to validate demand quickly

## 9.2 Path B: Local-first (privacy moat)
Pros:
- Strong privacy positioning ("notes never leave your machine")
- No per-minute API costs
- Works offline (for processing once recording is available)

Cons:
- Higher engineering complexity
- Model packaging/performance constraints on lower-end Macs
- More QA complexity across Apple Silicon generations

Recommended for:
- v1.5/v2 after MVP validation, or parallel track if resourced

## 10) Suggested rollout strategy

Phase 1 (MVP, 4-8 weeks):
- Implement stable dual-source recording
- Ship API-based transcription + summary
- Deliver Markdown export and core settings

Phase 2:
- Improve speaker labeling, summary quality, and reliability
- Add better post-meeting structure templates

Phase 3:
- Introduce local processing beta mode
- Benchmark accuracy/speed/cost vs API mode
- Promote privacy-first value in product messaging

## 11) Success metrics

- Activation:
  - % of installed users who complete first recording
- Reliability:
  - % sessions with successful dual-source capture
  - Crash-free sessions
- Output quality:
  - User rating for transcript usefulness
  - User rating for summary usefulness
- Engagement:
  - Weekly recordings per active user
- Business:
  - API cost per recorded hour (API mode)
  - Conversion to paid tier (if applicable)

## 12) Risks and mitigations

- Audio capture complexity on macOS
  - Mitigation: early prototype and stress test audio routing cases
- macOS permission friction
  - Mitigation: first-run onboarding, settings deep links, refresh status, and clear manual fallback
- Legal/compliance concerns
  - Mitigation: strong consent UX + jurisdiction reminders
- Summary hallucinations or missed context
  - Mitigation: keep transcript + summary side-by-side, improve prompts/models
- Transcription hallucinations on silent or near-empty audio
  - Mitigation: skip tiny system-audio files before sending to STT; add stronger silence detection in a future pass
- High latency for long recordings
  - Mitigation: chunked transcription and progress indicators

## 12.1 Bugs found and fixed during MVP testing

- Standard copy/paste did not work in the OpenAI API key field.
  - Cause: the menu-bar app did not install a normal macOS Edit menu.
  - Fix: added Cut, Copy, Paste, and Select All menu commands.
- Double-tap Command did not trigger recording during development testing.
  - Cause: macOS Accessibility permission was not granted to the launched app/process.
  - Fix: added diagnostics, first-run permission guidance, settings deep link, and a dev `.app` bundle so AutoScribe appears clearly in Accessibility settings.
- Accessibility settings were confusing when launching with `swift run`.
  - Cause: macOS associated permissions with the launcher/build artifact rather than a normal app.
  - Fix: added `scripts/build-dev-app.sh` to create `.build/AutoScribe.app` for realistic local permission testing.
- System audio recording failed with `The audio writer was not available`.
  - Cause: `.m4a` `AVAssetWriterInput` lacked explicit AAC output settings.
  - Fix: configured AAC sample rate, channel count, and bit rate for system audio output.
- OpenAI transcription rejected microphone audio.
  - Cause: microphone was recorded as `.caf`, which OpenAI speech-to-text does not support.
  - Fix: switched microphone recording to `.wav` and selected upload MIME types by extension.
- Processing failed with an invalid summary response.
  - Cause: summary parsing expected a single exact JSON response shape.
  - Fix: requested strict JSON schema from OpenAI, added response-shape fallbacks, and improved error diagnostics.
- Silent or near-silent system audio produced plausible fake transcript text.
  - Cause: STT can hallucinate on tiny/silent audio files.
  - Fix: added a first-pass guard that skips very small system-audio files and logs captured file sizes for tuning.

## 12.2 Known remaining issues and follow-ups

- Accessibility permission is still reported as not trusted in current testing until the user grants permission to `.build/AutoScribe.app` and relaunches.
- The current `.app` bundle is a development wrapper, not a signed/notarized production app.
- System-audio silence detection is currently based on file size; it should be upgraded to real audio-level/silence analysis.
- System audio capture needs broader testing across Zoom, Google Meet, Teams, browser playback, speakers, headphones, and phone-call routing.
- Keychain prompts are visible in the development build and may need a clearer production signing/access-group setup.
- Local processing mode is not implemented.
- Auto-start at login is not implemented.
- Long recordings are not chunked yet, so latency and API limits need more work.

## 13) Open questions

- Should inactivity auto-stop be based on silence, no system audio, or both?
- Is "double Command" the final shortcut, or should users configure any global hotkey after MVP?
- Should we store raw audio long-term or delete by default after transcript generation?
- Do we require speaker diarization in MVP or treat it as best-effort?
- Which OpenAI transcription/summarization models should be used for cost/quality tuning?
- What minimum Mac hardware should local mode officially support?
- What is the right production onboarding copy for Accessibility, microphone, and system audio permissions?

## 14) MVP definition (ship criteria)

AutoScribe MVP is ready when:
- User can start/stop recording from global shortcut or menu bar
- App reliably captures mic + system audio in common meeting apps
- App auto-stops after configurable inactivity timeout
- Transcript + summary Markdown file is generated and saved successfully
- User can choose API mode and complete processing end-to-end
- Basic compliance warning and recording-state visibility are in place
