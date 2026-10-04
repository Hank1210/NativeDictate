# Privacy

NativeDictate does not include analytics, advertising, telemetry or a developer-operated backend.

## Data stored on the Mac

- The OpenAI API key is stored in the user's macOS Keychain.
- The legacy-compatible bundle identifier `de.mcc.FlowDictate` identifies NativeDictate to macOS; it is not a remote address and does not give the developer access to the user's Keychain. NativeDictate has no developer-operated credential service.
- Recordings are stored in the folder selected during setup. The recommended default is `Documents/Recordings`.
- Dictation history and recovery metadata remain in the app's local Application Support container.
- Ordinary resumable long-form session manifests and temporary audio segments remain in Application Support. A temporary segment is deleted after successful transcription; the manifest is deleted after the complete transcript is safely stored.
- Mixed meetings keep separate microphone and System Audio original tracks under `MeetingSessions` in the selected recordings folder. That session also contains its manifest, derived working files, track transcript artifacts and role-labelled timeline. A completed meeting can therefore use substantially more storage than a single dictation.
- Personal dictionary entries and custom writing styles are stored locally in the Application Support container.
- App profiles are stored locally by application bundle identifier. NativeDictate does not store window titles or document contents for profile selection.
- Usage statistics are calculated locally from History and are not telemetry.
- Persistent dictation-job manifests contain IDs, provider/model selection, target application identifier, status and error metadata. They contain no credential and no Accessibility object.
- Optional local speech models remain below the legacy-compatible `Application Support/FlowDictate` folder and can be removed in Settings. The path name is retained so the 4.2 rename does not split existing user data.

## Local final transcription and privacy modes

On supported Apple-Silicon Macs, NativeDictate can transcribe final recordings locally with FluidAudio and Parakeet. The model is downloaded separately from Hugging Face only after the user requests it; the Community ZIP contains no speech model. Local inference does not send audio or transcript content to FluidAudio, Hugging Face or OpenAI.

The **Fully offline** mode blocks transcription, enhancement, credential-validation and update-check network operations. **Local transcription** keeps audio local and permits cloud text enhancement only when separately enabled. **Cloud transcription** permits the explicitly selected cloud provider to receive audio. A failed local transcription never silently falls back to OpenAI.

## Optional System Audio and mixed capture

System Audio capture is off by default and requires explicit selection. Standalone System Audio uses macOS **Screen & System Audio Recording** permission and ScreenCaptureKit. Mixed recording uses the **System Audio Recording Only** permission with an audio-only Core Audio process tap on macOS 14.2+; on macOS 14.0/14.1 it uses ScreenCaptureKit's audio-only compatibility path. No path requests or saves video frames, screenshots or window images.

The five-second System Audio test writes a temporary local audio file only to validate the source. It does not contact OpenAI, does not add a History record and deletes the test file after completion or failure. Normal System Audio dictations follow the same local storage, transcription and retention rules as microphone recordings.

`Microphone + System Audio` requires a separate confirmation before recording. NativeDictate reminds the user to inform participants and obtain any consent required for their context; confirmation does not itself start capture. The overlay remains visible while recording. The two original tracks stay separate. `You` labels the microphone capture and `System Audio` labels output from other apps; NativeDictate does not identify individual speakers. Mixed sessions can be resumed or partially retried from retained originals. Automatic retention protects unfinished or uncertain insertion states; archiving is non-destructive, while the separately confirmed `Delete Meeting and Files` action removes the scoped session artifacts.

Provider and privacy settings are frozen separately for each meeting track. Local transcription does not upload either audio track. Cloud transcription sends only the explicitly selected track audio to OpenAI when the active privacy mode permits it; an offline or local failure never silently changes provider. Optional AI writing styles may separately send transcript text as described below.

## Data sent to OpenAI

Only when OpenAI is selected and the privacy mode permits cloud transcription, finishing a dictation sends its audio directly from NativeDictate to the OpenAI transcription API. Long or oversized recordings are split locally and sent as sequential audio segments; NativeDictate never sends more than one segment concurrently. OpenAI processes those requests according to the terms and privacy policy applying to the user's own OpenAI account. NativeDictate never bundles or receives a shared API key.

Cancelled recordings are not sent for transcription. Pausing an already-started long-form transcription prevents subsequent segments from being uploaded; any request already accepted by OpenAI may still finish. Users can review and delete locally retained recordings using Finder and NativeDictate's storage settings.

## Optional AI writing styles

Spoken formatting and personal-dictionary replacements run entirely on the Mac. The built-in **Original** style does not make an additional cloud request.

When the user explicitly selects an AI writing style, NativeDictate sends the locally processed transcript, the selected style instruction and language information directly to OpenAI through the Responses API. The enhancement request does not contain the audio file, target application, window title, clipboard content, personal-dictionary rule list or locally stored history. NativeDictate requests that OpenAI does not store the response through the API's `store: false` option. OpenAI's account terms and data policies still apply to the user's request.

If enhancement fails, all transcript stages remain local so the user can retry, use the locally processed text or use the original transcript.

## Local Live Preview

When Live Preview is enabled, NativeDictate can send in-memory audio buffers to Apple's Speech framework with on-device recognition required. There is no fallback to Apple's cloud recognition. The provisional Preview text exists only in memory: it is not saved in History, diagnostics or logs, is not inserted into another app and is not used as the final transcript.

Live Preview is optional. Existing installations keep it disabled until the user enables it. If it is disabled, NativeDictate neither starts Speech recognition nor requests Speech Recognition permission. If permission or an on-device recognizer is unavailable, normal recording and final OpenAI transcription continue without Preview.

Live Preview currently applies to microphone recordings. System Audio recording remains fully usable without a provisional Preview.

## App integration and updates

Reliable clipboard insertion is the default. Direct insertion is an explicit advanced per-app option and uses macOS Accessibility only on the focused editable control. NativeDictate refuses protected password fields and otherwise falls back to its clipboard-safe insertion path when the Accessibility request returns as unsupported. Some applications may delay that return; selecting the default clipboard path avoids this blocking request.

When Community update checks are enabled and NativeDictate is not in Fully offline mode, NativeDictate requests the latest stable release metadata from GitHub at most once per day. It sends no recordings, transcripts, History, settings, API key or app-profile data. NativeDictate never downloads or installs an update automatically.

## Independent project

NativeDictate is an independent open-source project and is not affiliated with or endorsed by OpenAI or Apple.
