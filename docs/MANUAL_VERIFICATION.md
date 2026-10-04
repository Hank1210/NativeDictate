# Manual verification checklist

Use the exact NativeDictate package being evaluated. For a 4.1.0-to-4.2.0 upgrade, first follow the installation guide and confirm that FlowDictate is fully stopped; never run `FlowDictate.app` and `NativeDictate.app` in parallel.

Test short, long, German, English and mixed-language dictation in Notes, Safari, Chrome, Mail, VS Code and Word or an equivalent editor. Also verify:

- rapid shortcut presses do not create overlapping recordings
- cancel does not call the transcription provider
- the overlay appears on the display containing the mouse and never steals focus
- microphone switching and default-device fallback
- text and non-text clipboard restoration
- invalid key and offline errors retain the audio file
- interrupted transcription is recoverable from History
- `Documents/Recordings` access survives an app restart
- Restore Last Dictation inserts at the current cursor
- launch at login works from an installed, consistently signed build; if macOS requires approval, follow the link to Login Items shown in Settings
- Live Preview works for German and English and is clearly marked as provisional
- denying Speech Recognition or using an unsupported locale does not interrupt recording or final transcription
- disabling Live Preview causes no Speech prompt and leaves normal dictation unchanged
- Compact, Standard and Expanded remain non-activating at every supported position
- the five-second Preview test deletes its temporary recording and creates no History entry
- Original style performs only local processing and makes no enhancement request
- German and English formatting commands, literal escape and URL preservation
- dictionary word boundaries, capitalization, language filters and overlapping rules
- every writing style, custom style creation and dictionary/style import/export
- failed enhancement retains every text stage and supports Retry, Local and Original recovery
- numbers, URLs and dictionary terms remain intact after AI enhancement
- System Audio permission denial leaves microphone dictation usable
- the five-second System Audio test creates no History entry, makes no OpenAI request and removes its temporary file
- System Audio captures another app's playback without storing video and produces a transcribable M4A
- two app profiles apply different settings by bundle identifier and remain frozen for each recording
- direct insertion works where supported, falls back safely, and never writes into password fields
- toggle and press-and-hold both produce exactly one recording per gesture
- local statistics match History and disappear when disabled
- release checks ignore equal, older, draft and prerelease versions and never install anything

The phase-specific long-duration evidence and release gate are documented in the [Phase 4.1 work plan](engineering/ARBEITSPLAN_PHASE_4_1.md). Private test records stay outside Git.
