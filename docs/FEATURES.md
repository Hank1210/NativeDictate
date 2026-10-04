# Features and settings

This is the detailed companion to the [main README](../README.md). NativeDictate 4.2 supports one dictation or meeting at a time.

## Recording and transcription

- Global start/stop and cancel shortcuts, with toggle or press-and-hold activation.
- Microphone recording with a local WAV backup, selectable input device, default-device fallback and live level metering.
- Microphone, digital System Audio or opt-in `Microphone + System Audio` recording. Each source has separate permission guidance and a local five-second source test.
- Mixed meetings require separate consent and preserve two original tracks. They provide independent level and quality warnings, a shared timeline and partial/retry recovery.
- Local final transcription through FluidAudio and Parakeet TDT 0.6B v3 on Apple Silicon, or explicit OpenAI BYOK cloud transcription.
- Fully offline, local-with-optional-enhancement and cloud-transcription privacy modes. Cloud audio streaming is not used.
- Long recordings are segmented automatically. Ordered partial transcripts, per-segment progress and persisted results allow retry or restart from the first unfinished segment.
- Compact M4A upload preparation, file-based multipart transfer and an early size check for cloud transcription.
- Optional on-device Apple Speech Live Preview; its five-second test does not call OpenAI or write to History.

Mixed recording does not create a combined original audio file or identify individual remote speakers. `You` labels the microphone track; `System Audio` labels captured output. Bulk export and profile import/export remain follow-up scope.

## Text and insertion

- German and English in-dictation correction and spoken formatting commands run before dictionary and style processing.
- A personal dictionary supports language, case and whole-word rules; dictionary and writing-style JSON can be imported and exported with versioned formats.
- Built-in and custom writing styles can optionally use OpenAI text enhancement. Original, Formatted, Dictionary and Final stages remain available in History.
- Failed enhancement supports retry, reprocessing and safe Local or Original fallback without retranscribing audio.
- Direct Accessibility insertion uses a bounded clipboard fallback. Microsoft Word uses the reliable clipboard route immediately; `Clipboard only` is available per app and password fields are never written.
- Restore Last Dictation has a configurable hotkey. Clipboard restoration delay is configurable.

## History and reliability

- Searchable persistent History offers audio playback, text export, crash recovery and orphaned-recording detection.
- A persistent job manifest supports restart-safe continuation and deferred insertion if the original target is unavailable.
- Temporary provider failures can be retried manually or with bounded automatic retry.
- Successful audio and visible History have separate configurable retention. Failed recordings and unfinished meeting work remain protected.
- Meeting History supports separate track playback and export, non-destructive archiving and confirmed session deletion.
- Optional local usage statistics show Total, 30-day and 14-day views and allow a non-destructive reset.

## Interface, setup and settings

- The non-activating recording/processing overlay follows the display containing the mouse and supports Compact, Standard and Expanded sizes with configurable placement. It shows source metadata.
- First-run setup covers the recordings folder, selected local or OpenAI transcription provider, permissions and hotkeys. API credentials are stored in macOS Keychain.
- A user-selected sandboxed recordings folder stores audio; `Documents/Recordings` is the recommended default.
- App-specific profiles selected by bundle identifier can override language, transcription model, writing style, spoken formatting and insertion preference. Provider, model, language and insertion target are frozen for each job.
- Launch at login is enabled on the first installed start and can be disabled in Settings.
- A daily, disableable GitHub release check opens the release page but never installs automatically.
- A dedicated macOS app icon identifies the app in Finder, Accessibility settings and installed builds.

Settings are grouped as follows:

- **General:** launch at login and permission status.
- **Dictation:** shortcuts, toggle/press-and-hold, Live Preview, overlay size and position, text limit and Preview test.
- **Audio:** recording source, source permissions and tests, input device, live levels and meeting consent.
- **Transcription:** privacy mode, provider, local model, optional Keychain credential and language.
- **Smart Dictation:** spoken formatting, dictionary, writing styles, optional enhancement model and fallback.
- **Storage:** recordings folder, retention and Phase 1 migration.
- **App Profiles:** per-app language, model, style, formatting and insertion overrides.
- **Productivity:** local statistics and Community update notices.
- **Advanced:** clipboard restoration delay and automatic retries.

Recordings are stored before upload in the selected folder. Mixed sessions keep originals and derived/transcription files in its `MeetingSessions` subfolder; History metadata remains in the app's local Application Support container.

New installations keep at most 1,000 visible History entries and 365 days by default. Existing installations remain unlimited until the user chooses limits. An entry whose audio must still be retained is archived rather than treated as an orphan; its compact archive marker is removed after the separate audio-retention rule removes the file.
