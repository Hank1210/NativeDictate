# Installing NativeDictate Community

This is the free, ad hoc signed edition. It has not been notarized by Apple, so macOS displays a security warning the first time it is opened.

This guide applies to NativeDictate 4.2.0 Community.

## Verify the download

Download the ZIP and the matching `.sha256` file from the same GitHub Release. Open Terminal, change to the download folder, and verify the archive:

```sh
shasum -a 256 -c NativeDictate-4.2.0-Community-macOS.zip.sha256
```

Terminal must report `OK`. Do not install the app if verification fails.

## Installation

1. Extract the ZIP file.
2. Drag `NativeDictate.app` into the `Applications` folder.
3. In `Applications`, right-click NativeDictate and select `Open`.
4. Confirm the next dialog by clicking `Open` again.
5. If macOS only offers `Cancel`, open `System Settings → Privacy & Security` and click `Open Anyway` next to NativeDictate.

Only approve NativeDictate if you received the ZIP file directly from someone you trust.

## First-time setup

1. Choose the recordings folder. `Documents/Recordings` is recommended.
2. Choose transcription: on Apple Silicon, you can download the local Parakeet model and work without an API key. Alternatively, enter your own OpenAI API key; it is stored exclusively in the macOS Keychain. On Intel Macs, OpenAI remains the available final-transcription path.
3. Grant Microphone and Accessibility permissions.
4. Grant Speech Recognition only if you want to use the optional local Live Preview. If Preview still reports `Siri and Dictation are disabled`, also enable macOS Dictation under `System Settings → Keyboard → Dictation`. Final transcription works without Live Preview.
5. Standalone System Audio dictation needs `Screen & System Audio Recording` permission. Combined microphone-plus-system-audio recording uses the separate `System Audio Recording Only` switch on macOS 14.2+; on macOS 14.0/14.1 it uses the ScreenCaptureKit permission. NativeDictate captures audio only, never video.
6. Quit and reopen NativeDictate if macOS asks you to do so after granting a new permission.
7. Configure your preferred keyboard shortcuts.

The ZIP file contains neither an API key nor a speech model or any credentials belonging to the person who created it. The optional model download shows its source, size and license in Transcription settings.

For `Microphone + System Audio`, explicitly select that source and confirm the separate reminder to inform participants and obtain any required consent. Confirmation does not start recording. Each meeting keeps two original tracks plus working and transcript files in `MeetingSessions` under your selected recordings folder. At 48 kHz, the originals alone use about 1.4 GB per hour; allow extra space for working files. Short System Audio gaps can occur and are shown as quality warnings in History. `You` identifies the microphone track, not an individual-speaker detector.

## Updating

**Important when moving from FlowDictate 4.1.0 to NativeDictate 4.2.0:** the bundle identifier remains `de.mcc.FlowDictate`. NativeDictate therefore continues to use the same settings, History, local model, recordings-folder bookmark, and Keychain service. The app file is now named `NativeDictate.app`, so Finder does not automatically replace `FlowDictate.app`. Never run both apps at the same time.

Community editions are signed ad hoc. Because their code identity can change with a new build, macOS may occasionally treat an update as a new app. In particular, **Accessibility** and **Screen & System Audio Recording** may need to be granted again. This cannot be avoided reliably for a free, non-notarized Community edition.

Always test the exact Community ZIP that will be published. A separately built or differently signed test build is not identical to the release artifact.

### Recommended update procedure

1. Quit FlowDictate completely from its menu bar icon. If necessary, use Activity Monitor to confirm that no FlowDictate process is still running.
2. Extract the new Community ZIP.
3. Drag `NativeDictate.app` into `Applications`. Do not remove `FlowDictate.app` yet.
4. Right-click NativeDictate and select `Open`. Verify settings, History, the local model, API-key status, and the recordings folder.
5. Test at least one microphone recording and text insertion, plus System Audio if you use it. Do not start FlowDictate during this check.
6. Renew only a permission whose feature is not working. macOS may ask again for Microphone, Accessibility, Speech Recognition, or System Audio because the app filename or ad hoc signature changed.
7. If Launch at login was enabled, turn it off and back on once in NativeDictate.
8. Only after the checks pass, remove the old `FlowDictate.app`. Removing that app file does not delete the shared settings or `Application Support/FlowDictate` data.

Live Preview is optional and requires Apple's on-device speech recognition. Local final transcription, spoken corrections, formatting and the personal dictionary run on the Mac. `Fully offline` blocks transcription, enhancement and update-check network access. Only an explicitly selected cloud path sends audio or text to OpenAI; a local failure never triggers an automatic cloud upload.

### Keychain access after an update

NativeDictate 4.2.0 uses the same `de.mcc.FlowDictate` Keychain service as FlowDictate 4.1.0. macOS may ask for your login password once because the ad hoc signature changed. If the prompt keeps appearing, open `Settings → Transcription`, remove the existing API key, and then save it again. This recreates the existing Keychain entry for the currently installed edition. NativeDictate then loads it only once per app session.

### Repairing permissions

Use the following procedure only for the feature that is not working:

1. Open `System Settings → Privacy & Security`.
2. Open the affected section: **Microphone**, **Accessibility**, **Speech Recognition**, or **Screen & System Audio Recording**.
3. If NativeDictate is listed, first switch its permission off and back on. Restart NativeDictate and test again.
4. If the problem remains, quit NativeDictate, select the old entry, and remove it using the minus button. If no minus button is available, disable the entry.
5. Use the plus button to add exactly `/Applications/NativeDictate.app` and enable it. Alternatively, trigger the relevant feature in NativeDictate again and approve the new macOS prompt.
6. Quit NativeDictate completely and reopen it. If macOS offers `Quit & Reopen`, use that button.

Feature-to-permission reference:

- No microphone recording: **Microphone**
- Recording starts, but keyboard shortcuts or text insertion do not work: **Accessibility**
- No local Live Preview: check **Speech Recognition**; for `Siri and Dictation are disabled`, also enable `Keyboard → Dictation`.
- No standalone System Audio recording: **Screen & System Audio Recording**
- No System Audio track in a combined recording: on macOS 14.2+ **System Audio Recording Only**; on 14.0/14.1 **Screen & System Audio Recording**

For **standalone System Audio**, macOS may show a Screen & System Audio Recording prompt even though NativeDictate processes audio only. After a new ad hoc signed build, its switch can still appear on while macOS no longer accepts the older code identity. In that case remove NativeDictate from **Screen & System Audio Recording**, add the exact `/Applications/NativeDictate.app` again, and fully restart the app. This is separate from **Accessibility** permission.

Do not reset every privacy permission at once. This preserves permissions that still work and keeps the update process as short as possible.
