# NativeDictate Release Guide

NativeDictate 4.2.0 is prepared as a standalone macOS menu bar app. A release contains neither API keys nor speech models. Each installation chooses local transcription or supplies its own OpenAI key during onboarding. `Microphone + System Audio` is opt-in and keeps two separate original tracks.

## Free Community release

The Community release is intended for personal Macs and a trusted circle. It does not require an Apple Developer account or paid membership.

```sh
./scripts/build-community-release.sh
```

The script performs an unsigned universal Release build, applies an ad hoc signature with the required sandbox entitlements, verifies that signature, and creates these files in `dist/`:

- `NativeDictate-4.2.0-Community-macOS.zip`
- `NativeDictate-4.2.0-Community-macOS.zip.sha256`

The ZIP contains the app, German and English installation guides (`INSTALLATION-DE.md` and `INSTALLATION-EN.md`), the project MIT license, third-party notices and license, Privacy notice and Changelog. Gatekeeper cannot establish an Apple developer identity for this build, so the recipient must use right-click → Open or approve it under Privacy & Security. Updates may require Microphone, Accessibility, Speech Recognition, System Audio Recording Only, Screen & System Audio Recording or Keychain permission to be granted again.

Verify the generated archive before uploading it:

```sh
cd dist
shasum -a 256 -c NativeDictate-4.2.0-Community-macOS.zip.sha256
```

## GitHub release checklist

1. Confirm `main` contains the intended source and documentation.
2. Run the automated tests and the manual Preview/recording smoke test.
3. Run `./scripts/build-community-release.sh` on a clean checkout.
4. Verify the SHA-256 checksum and test the ZIP on a second macOS account or Mac.
5. Create the annotated tag `v4.2.0` from the reviewed commit.
6. Create a GitHub Release for that tag using the reviewed release notes.
7. Attach only the Community ZIP and its `.sha256` file. GitHub supplies source archives automatically.
8. Keep the release marked as a prerelease until the downloaded asset has passed the installation test; then publish it as the latest stable release.

Do not commit the generated `dist/` or `build/` directories. They are intentionally ignored by Git.

## Updating an existing installation

NativeDictate 4.2.0 retains FlowDictate 4.1.0's bundle identifier `de.mcc.FlowDictate`, so settings, History, the Keychain service, local model, recordings-folder bookmark and `Application Support/FlowDictate` data remain shared. The app filenames differ, and Finder therefore does not replace the old bundle automatically. Quit FlowDictate completely, install `NativeDictate.app`, verify the shared state and core recording flow without starting FlowDictate again, renew permissions or Launch at login only if needed, and remove the old `FlowDictate.app` only after the checks pass. Never run both bundles in parallel. Installing or removing either app bundle must not delete the shared container or Application Support data.

The following sections describe the optional paid Developer ID workflow.

## Prerequisites

- Xcode with the macOS SDK
- the Apple Developer team configured for the `NativeDictate` target that builds `NativeDictate.app`
- a Developer ID Application certificate for distribution outside the Mac App Store
- an optional `notarytool` Keychain profile for notarization

## Build

```sh
./scripts/build-release.sh
```

The versioned NativeDictate ZIP is written to `dist/`. The build uses the bundle identifier `de.mcc.FlowDictate`, the Release configuration, App Sandbox, outgoing network access, microphone access, and user-selected read/write folder access.

## Notarize

Store notarization credentials once using Apple's `notarytool`, then pass the profile name:

```sh
NATIVEDICTATE_NOTARY_PROFILE=NativeDictateNotary ./scripts/build-release.sh
```

The script submits the ZIP, waits for Apple's result, staples the ticket to the app, and recreates the final ZIP.

## Verification on another Mac

1. Copy and extract the ZIP.
2. Move `NativeDictate.app` to Applications.
3. Launch it and complete onboarding.
4. Confirm `Documents/Recordings` or choose another folder.
5. Choose local transcription on Apple Silicon or add that person's OpenAI API key.
6. Grant Microphone and Accessibility permissions. Grant Speech Recognition only when testing Live Preview. Standalone System Audio uses Screen & System Audio Recording; mixed capture uses System Audio Recording Only on macOS 14.2+ or ScreenCaptureKit permission on 14.0/14.1.
7. Verify Live Preview, final transcription, Smart Dictation, a short mixed meeting and insertion in TextEdit or Notes.
8. Interrupt processing, relaunch, and verify recovery in History.

Never distribute builds containing an `.env` file, Xcode Scheme secret, personal API key, notarization credential, recording, transcript, downloaded model or private test note.

## NativeDictate 4.2 rebranding gate

Before creating tag `v4.2.0` or publishing assets:

1. Complete the documentation and GitHub-rename steps in the rebranding work plan.
2. Build the exact final Community ZIP from the reviewed commit; any later source or bundled-document change requires a new ZIP and checksum.
3. Verify the checksum, exactly one `NativeDictate.app`, version 4.2.0, final build number, bundle identifier `de.mcc.FlowDictate`, `arm64` and `x86_64`, strict code signature, entitlements and bundled documents.
4. Run the complete automated suite and controlled legacy-name scan.
5. On the exact ZIP, complete a clean installation and a real upgrade from the released FlowDictate 4.1.0 app. Verify shared settings, History, local model, Keychain access and recordings-folder bookmark, plus microphone, System Audio, mixed capture, insertion and restart recovery.
6. During the upgrade test, ensure only one product bundle runs at a time. Remove `FlowDictate.app` only after NativeDictate passes, then verify that the shared user data remains.
7. Confirm the canonical NativeDictate repository, release API and download links, and verify GitHub's old FlowDictate URL redirects without creating a replacement repository at the old name.
8. Record the exact commit and SHA-256, independently recheck the downloaded assets, document every accepted deviation, and obtain explicit publication authorization.

The 4.1 System Audio gap measurements and other accepted long-duration or performance gaps remain deviations unless separately remeasured. They must not be reported as passed 4.2 tests merely because the rebranding build succeeds.

## Historical release gates and 4.1 evidence

The following sections preserve the release requirements and evidence for earlier FlowDictate versions. They are historical records, not instructions for naming or publishing a new 4.2 artifact.

### Phase 3.4 gate (historical)

Before a Phase 3.4 release, test the exact generated Community ZIP with a recording that produces at least three segments. Pause after a successful segment, relaunch the packaged app and confirm that continuation does not upload the successful segment again. Also test one temporary segment failure, insufficient working storage guidance, ordered merged text, retained original audio and deletion of temporary segment files. Do not create a tag or GitHub Release until this packaged-app test and the existing checklist both pass.

### Phase 4.0 gate (historical)

Before a Phase 4.0 release, verify the exact generated ZIP on Apple Silicon with no API key: install the local model, transcribe short German and English recordings, run a long segmented recording, and complete at least three consecutive dictations. Confirm that each new recording becomes available after the previous dictation finishes, safe deferred insertion after relaunch, Fully offline network blocking, inline correction commands and model removal protection. Verify that the x86_64 slice builds with the OpenAI path even though local transcription is unavailable; perform a physical Intel launch test when suitable hardware is available and otherwise document that residual risk explicitly. Do not tag or publish until the available packaged-app tests pass and any unavailable hardware gate has been consciously accepted.

### Phase 4.1 gate (historical)

Before calling the 4.1.0 ZIP final, review the exact extracted archive on a fresh macOS user account, grant only the required permissions, verify a short single-source and mixed recording, the role-labelled result, History recovery/deletion, and normal insertion. Use the same ZIP for the following several-day user trial; any code change requires a new ZIP and checksum. Verify both architectures, the ad hoc signature, bundled notices and the checksum, and confirm the archive contains no recordings, transcripts, downloaded models, credentials or private test notes.

The earlier real 30-, 60- and 120-minute mixed sessions establish original-track preservation, bounded capture RAM and recoverability, but they recorded short System Audio gaps (65 ms, 33 ms and 422 ms total). The zero-buffer-loss budget was not met. The project owner does not plan additional long recordings solely to repeat those scenarios with the exact ZIP. This is an explicit release-gate deviation, not a pass; its product impact and the public known limitation must be accepted before publication. Any remaining unmeasured latency or drift targets likewise require an explicit decision rather than a checked box without evidence. Publication, merge to `main`, tag and asset upload require a separate instruction.

### Superseded 4.1.0 release preparation, Build 32

The project owner ended the test phase after confirming that the installed 4.1.0/32 build completes a mixed recording with microphone speech and silent System Audio. The complete isolated macOS suite passed 222/222 tests with no failures, skips or runtime warnings. The installed app's executable, Info.plist, assets and code-signature resources were byte-identical to the app extracted from the then-current Build 32 ZIP. That ZIP passed checksum and strict code-signature verification, contains `arm64` and `x86_64`, and excludes private test notes, recordings, transcripts, credentials and models.

Former release candidate: commit `7804e30`, original `FlowDictate-4.1.0-Community-macOS.zip`, SHA-256 `c18e5d29d5cafcfcabfa877e039bd89d39f2b273ffa79db1e3d56edbe73adc1c`. It remains a rollback candidate, not the publishable archive after the bundle-ID change. A replacement ZIP needs a new checksum and its own exact-artifact acceptance. Use [RELEASE_NOTES_4.1.0.md](docs/releases/RELEASE_NOTES_4.1.0.md) for the updated release description.

The owner requests no further long-duration tests. Accordingly, the earlier requirement to repeat 60/120-minute recordings with precisely this ZIP, a separate several-day trial of this exact build, and unmeasured p95/latency/drift budgets remain documented deviations, **not passed tests**. The measured System Audio gaps can be considered minor in practical use, but they do not satisfy the zero-buffer-loss target. The known gaps are stated in the public Changelog, README and release notes. The source remains on `codex/phase-4-1-prep`; pushing this preparation branch does not authorize a merge to `main`, a tag, GitHub Release or asset upload.

### Bundle-identity candidate, Build 33

The new `de.mcc.FlowDictate` identity intentionally starts with a fresh macOS sandbox, preferences and Keychain service. Build 32's ZIP was preserved locally at `dist/previous-candidates/build32/FlowDictate-4.1.0-Community-macOS-build32.zip` with its original SHA-256 `c18e5d29d5cafcfcabfa877e039bd89d39f2b273ffa79db1e3d56edbe73adc1c`; it is not the current release candidate.

The replacement `dist/FlowDictate-4.1.0-Community-macOS.zip` has SHA-256 `e22b1b4d73e0cea50986569bc14bc16ea0dd0be37a48b4e7b09ece12906b5002`. The archive's extracted app reports version 4.1.0, build 33 and bundle ID `de.mcc.FlowDictate`; `arm64` and `x86_64` slices and the strict ad hoc code signature were verified. Its bundled installation guides, Privacy notice and Changelog explain the identity break. The serial macOS suite passed 222/222 with no failures, skips or runtime warnings. The ZIP contains no private test notes, recordings, transcripts, credentials or downloaded model.

This static and automated verification does **not** establish fresh-user behavior for the new identity. Before publication, install and run this exact ZIP on a fresh macOS account or equivalent isolated setup: complete the selected local or OpenAI provider, folder selection and permissions, then verify a short microphone dictation, insertion and one short mixed recording. Do not infer that Build 32's prior live approval transfers to Build 33. The existing long-duration and performance deviations remain documented; no repeat 60/120-minute session is planned solely for this identifier change. No merge, tag, GitHub Release or asset upload is authorized yet.

The owner subsequently installed Build 33 and reported that the app works, after resolving a temporary Accessibility setup difficulty. The installed app's executable, Info.plist, assets and signature resources are byte-identical to the extracted Build 33 ZIP, and only one FlowDictate process was running at the time of inspection. A stale previous permission entry or app identity is plausible but unproven as the cause of the initial difficulty. Six real tests covered all three recording sources (microphone, System Audio and mixed), each with the local model and with OpenAI. The owner explicitly confirmed that all six transcribed successfully and insertion worked wherever intended. This passes the Build 33 source/provider smoke matrix. The test ran under the new app identity on the existing macOS account, not on an independently created fresh account; earlier long-duration and performance deviations remain unchanged.

### Stable publication decision, 2026-09-30

The owner explicitly authorized a stable 4.1.0 publication with the exact tested Build 33 ZIP despite the missing independent fresh-account installation test. This is an accepted release-gate deviation, **not a passed fresh-user test**. The earlier measured System Audio gaps and unmeasured long-duration/performance targets remain documented deviations, not passed tests. Publish the existing ZIP and checksum without rebuilding or substituting the Build 32 archive.
