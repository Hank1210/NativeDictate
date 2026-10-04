# NativeDictate 4.2.0 Community

FlowDictate is now NativeDictate. The project and visible macOS app were renamed to avoid confusion with an unrelated commercial product. This release is intentionally focused on identity, packaging and migration guidance; it does not add a new dictation or meeting feature.

## What changes

- The visible app, menus, onboarding, settings, permission guidance, diagnostics and new export filenames use NativeDictate.
- The installed app is `NativeDictate.app`.
- The Community download is `NativeDictate-4.2.0-Community-macOS.zip` with a matching `.sha256` file.
- Current documentation and the canonical GitHub project use the NativeDictate name. Existing tags, releases and historical notes remain in the same repository history.

## What stays compatible

NativeDictate 4.2.0 retains the bundle identifier `de.mcc.FlowDictate`. It continues to use FlowDictate 4.1.0's settings, History, Keychain service, local model, recordings-folder bookmark and legacy-compatible `Application Support/FlowDictate` directories. The rename does not copy, move or delete user data and does not change a data schema.

Some development identifiers also retain their internal FlowDictate names in 4.2, including the Xcode project, scheme and Swift module. They do not change the visible app or release artifact name.

## Upgrade from FlowDictate 4.1.0

Finder does not automatically replace `FlowDictate.app` with `NativeDictate.app` because the filenames differ:

1. Quit FlowDictate completely and confirm that no FlowDictate process remains.
2. Copy `NativeDictate.app` to `/Applications` without deleting the old app yet.
3. Open NativeDictate and verify settings, History, the local model, API-key status and recordings folder.
4. Test microphone dictation and insertion, plus System Audio if you use it.
5. Never run FlowDictate and NativeDictate at the same time.
6. If needed, renew macOS permissions and toggle Launch at login off and on once.
7. Remove the old `FlowDictate.app` only after the checks pass.

Removing the old app bundle does not remove the shared settings or legacy-compatible Application Support data. The German and English installation guides included in the ZIP contain the complete procedure.

## Installation and privacy

NativeDictate 4.2.0 supports macOS 14 or later. Local final transcription requires Apple Silicon and an approximately 650 MB model download; OpenAI transcription is available with the user's own API key. The Community build is ad hoc signed and not notarized, so macOS may require manual first-launch approval and may ask for Microphone, Accessibility, Speech Recognition or System Audio permission again after the renamed app is installed.

No video is captured or saved. Local transcription does not upload audio. The explicitly selected OpenAI path sends selected audio to OpenAI only when the privacy mode permits it; optional AI writing styles can separately send locally processed text. Meeting recording consent remains the user's responsibility.

## Known limitations and verification scope

The accepted 4.1 limitation remains: real 30-, 60- and 120-minute mixed tests preserved both original tracks but observed short System Audio gaps of 65 ms, 33 ms and 422 ms in total, respectively, with a longest individual gap of 137 ms. A gap can omit part of a word; zero-loss capture is not claimed for every Mac or audio route.

The 4.2 release gate requires the exact final ZIP to pass both a clean-install test and a real FlowDictate-4.1.0-to-NativeDictate-4.2.0 upgrade test. Earlier 4.1 long-duration and performance deviations do not become passed tests through the rename.
