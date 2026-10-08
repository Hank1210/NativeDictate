//
//  FlowDictateTests.swift
//  FlowDictateTests
//
//  Created by Frank Euler on 16.08.26.
//

import AppKit
import AudioToolbox
import AVFoundation
import Carbon.HIToolbox
import Combine
import CoreAudio
import Foundation
import ServiceManagement
import Testing
@testable import FlowDictate

struct FlowDictateTests {
    @Test func rebrandingKeepsLegacyIdentityAndStorageContracts() throws {
        #expect(ProductIdentity.displayName == "NativeDictate")
        #expect(ProductIdentity.Legacy.bundleIdentifier == "de.mcc.FlowDictate")
        #expect(ProductIdentity.Legacy.testHostBundleIdentifier == "de.mcc.FlowDictate.TestHost")
        #expect(KeychainCredentialStore.defaultService == "de.mcc.FlowDictate")

        let fileManager = FileManager.default
        let applicationSupport = ProductIdentity.Legacy.applicationSupportDirectory(
            fileManager: fileManager
        )
        #expect(applicationSupport.lastPathComponent == "FlowDictate")
        #expect(applicationSupport.lastPathComponent != ProductIdentity.displayName)

        let expectedPaths = [
            applicationSupport.appendingPathComponent("Recordings", isDirectory: true),
            applicationSupport
                .appendingPathComponent("History", isDirectory: true)
                .appendingPathComponent("dictations.json"),
            applicationSupport.appendingPathComponent("Jobs", isDirectory: true),
            applicationSupport
                .appendingPathComponent("Profiles", isDirectory: true)
                .appendingPathComponent("app-profiles.json"),
            applicationSupport
                .appendingPathComponent("SmartDictation", isDirectory: true)
                .appendingPathComponent("dictionary.json"),
            applicationSupport
                .appendingPathComponent("SmartDictation", isDirectory: true)
                .appendingPathComponent("styles.json"),
            applicationSupport.appendingPathComponent("Models", isDirectory: true),
            applicationSupport.appendingPathComponent(
                "TranscriptionSessions",
                isDirectory: true
            )
        ]
        let actualPaths = [
            AudioStore.defaultRecordingsDirectory(fileManager: fileManager),
            DictationHistoryStore.defaultFileURL(fileManager: fileManager),
            DictationJobStore.defaultDirectory(fileManager: fileManager),
            AppProfileStore.defaultFileURL(fileManager: fileManager),
            DictionaryStore.defaultFileURL(fileManager: fileManager),
            WritingStyleStore.defaultFileURL(fileManager: fileManager),
            LocalModelManager.defaultModelsRoot(fileManager: fileManager),
            TranscriptionSessionStore.defaultRootURL(fileManager: fileManager)
        ]

        #expect(actualPaths == expectedPaths)
        #expect(actualPaths.allSatisfy { !$0.path.contains(ProductIdentity.displayName) })
    }

    @Test func productionBuildSettingsKeepLegacyBundleIdentity() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectFile = repositoryRoot
            .appendingPathComponent("FlowDictate.xcodeproj", isDirectory: true)
            .appendingPathComponent("project.pbxproj")
        let contents = try String(contentsOf: projectFile, encoding: .utf8)
        let productionSetting = "PRODUCT_BUNDLE_IDENTIFIER = \(ProductIdentity.Legacy.bundleIdentifier);"
        let testHostSetting = "PRODUCT_BUNDLE_IDENTIFIER = \(ProductIdentity.Legacy.testHostBundleIdentifier);"

        #expect(contents.components(separatedBy: productionSetting).count - 1 == 2)
        #expect(contents.components(separatedBy: testHostSetting).count - 1 == 1)
    }

    @Test func packagingBuildSettingsUseNativeDictateWithoutChangingModuleIdentity() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectFile = repositoryRoot
            .appendingPathComponent("FlowDictate.xcodeproj", isDirectory: true)
            .appendingPathComponent("project.pbxproj")
        let projectContents = try String(contentsOf: projectFile, encoding: .utf8)

        #expect(projectContents.components(separatedBy: "PRODUCT_NAME = NativeDictate;").count - 1 == 3)
        #expect(projectContents.components(separatedBy: "PRODUCT_MODULE_NAME = FlowDictate;").count - 1 == 3)
        #expect(projectContents.components(separatedBy: "MARKETING_VERSION = 4.2.0;").count - 1 == 3)
        #expect(projectContents.components(separatedBy: "CURRENT_PROJECT_VERSION = 34;").count - 1 == 3)
        #expect(
            projectContents.components(
                separatedBy: "$(BUILT_PRODUCTS_DIR)/NativeDictate.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/NativeDictate"
            ).count - 1 == 3
        )

        let schemeURL = repositoryRoot.appendingPathComponent(
            "FlowDictate.xcodeproj/xcshareddata/xcschemes/FlowDictate.xcscheme"
        )
        let schemeContents = try String(contentsOf: schemeURL, encoding: .utf8)
        #expect(schemeContents.components(separatedBy: "BuildableName = \"NativeDictate.app\"").count - 1 == 3)
        #expect(schemeContents.contains("BuildableName = \"FlowDictate.app\"") == false)

        let communityScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/build-community-release.sh"),
            encoding: .utf8
        )
        #expect(communityScript.contains("PACKAGE_NAME=NativeDictate-${VERSION}-Community"))
        #expect(communityScript.contains("PACKAGED_APP=${STAGING_DIRECTORY}/NativeDictate.app"))
        #expect(communityScript.contains("VERSION=${NATIVEDICTATE_VERSION:-${FLOWDICTATE_VERSION:-4.2.0}}"))
    }

    @Test func recordingFolderBookmarkKeepsLegacyUserDefaultsKeys() {
        let suiteName = "FlowDictateIdentityDefaults-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data([0x01]), forKey: "recordingDirectoryBookmark")
        defaults.set("/legacy/recordings", forKey: "recordingDirectoryDisplayPath")

        let store = RecordingLocationStore(defaults: defaults)

        #expect(RecordingLocationStore.bookmarkDefaultsKey == "recordingDirectoryBookmark")
        #expect(RecordingLocationStore.displayPathDefaultsKey == "recordingDirectoryDisplayPath")
        #expect(store.isConfigured)
        #expect(store.displayPath == "/legacy/recordings")
    }

    @Test func legacyAllowlistEntriesResolveToCurrentSources() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let allowlistURL = repositoryRoot
            .appendingPathComponent("docs/engineering/REBRANDING_LEGACY_ALLOWLIST.tsv")
        let rows = try String(contentsOf: allowlistURL, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst()

        #expect(!rows.isEmpty)
        for row in rows {
            let columns = row.split(separator: "\t", omittingEmptySubsequences: false)
            let path = try #require(columns.first.map(String.init))
            let allowedMatch = try #require(columns.dropFirst(2).first.map(String.init))
            let sourceURL = repositoryRoot.appendingPathComponent(path)
            let contents = try String(contentsOf: sourceURL, encoding: .utf8)
            let alternatives = allowedMatch.split(separator: "|").map(String.init)
            #expect(
                alternatives.contains(where: contents.contains),
                "Stale rebranding allowlist entry for \(path): \(allowedMatch)"
            )
        }
    }

    @Test func visibleProductBrandingUsesNativeDictate() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let visibleSourcePaths = [
            "FlowDictate/App/DictationCoordinator.swift",
            "FlowDictate/Audio/SystemAudioRecorder.swift",
            "FlowDictate/NativeDictateApp.swift",
            "FlowDictate/History/DictationHistoryStore.swift",
            "FlowDictate/History/HistoryView.swift",
            "FlowDictate/Insertion/AccessibilityTextInserter.swift",
            "FlowDictate/Jobs/DictationJobStore.swift",
            "FlowDictate/Meetings/CoreAudioTapCaptureProbe.swift",
            "FlowDictate/Meetings/MeetingRecordingConsentView.swift",
            "FlowDictate/Meetings/MixedRecordingSession.swift",
            "FlowDictate/Meetings/SystemAudioPermissionStatus.swift",
            "FlowDictate/Meetings/SystemAudioTrackRecorder.swift",
            "FlowDictate/MenuBar/NativeDictateMenu.swift",
            "FlowDictate/Onboarding/OnboardingView.swift",
            "FlowDictate/Permissions/PermissionManager.swift",
            "FlowDictate/Productivity/ProductivityServices.swift",
            "FlowDictate/Productivity/ProductivitySettingsView.swift",
            "FlowDictate/Profiles/AppProfilesSettingsView.swift",
            "FlowDictate/Settings/LaunchAtLoginManager.swift",
            "FlowDictate/Settings/SmartDictationSettingsView.swift",
            "FlowDictate/Storage/RecordingLocationStore.swift",
            "FlowDictate/Transcription/LongForm/LongFormTranscriptionModels.swift",
            "FlowDictate/Transcription/TranscriptionProvider.swift",
            "FlowDictate/Transcription/TranscriptionRunner.swift"
        ]
        let legacyVisibleName = try NSRegularExpression(
            pattern: #"(?:^|[\"\s])FlowDictate\b"#
        )
        for path in visibleSourcePaths {
            let contents = try String(
                contentsOf: repositoryRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            let uncommentedLines = contents
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            let range = NSRange(uncommentedLines.startIndex..., in: uncommentedLines)
            #expect(
                legacyVisibleName.firstMatch(in: uncommentedLines, range: range) == nil,
                "Legacy product name remains in user-facing source: \(path)"
            )
        }

        let infoPlistURL = repositoryRoot.appendingPathComponent("config/FlowDictateInfo.plist")
        let infoPlistData = try Data(contentsOf: infoPlistURL)
        let infoPlist = try #require(
            PropertyListSerialization.propertyList(from: infoPlistData, format: nil)
                as? [String: String]
        )
        #expect(infoPlist["CFBundleDisplayName"] == ProductIdentity.displayName)
        #expect(infoPlist["NSAudioCaptureUsageDescription"]?.contains("NativeDictate") == true)
        #expect(infoPlist.values.allSatisfy { !$0.contains("FlowDictate") })

        let projectFile = repositoryRoot
            .appendingPathComponent("FlowDictate.xcodeproj", isDirectory: true)
            .appendingPathComponent("project.pbxproj")
        let projectContents = try String(contentsOf: projectFile, encoding: .utf8)
        #expect(
            projectContents.components(
                separatedBy: "NativeDictate records your voice to create a transcription."
            ).count - 1 == 3
        )
        #expect(
            projectContents.components(
                separatedBy: "NativeDictate uses on-device speech recognition"
            ).count - 1 == 3
        )
        #expect(projectContents.contains("FlowDictate records your voice") == false)
        #expect(projectContents.contains("FlowDictate uses on-device speech recognition") == false)

        let coordinator = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "FlowDictate/App/DictationCoordinator.swift"
            ),
            encoding: .utf8
        )
        #expect(coordinator.contains("NativeDictate-Diagnostics.json"))
        #expect(coordinator.contains("NativeDictate-Dictionary.json"))
        #expect(coordinator.contains("NativeDictate-Writing-Styles.json"))
    }

    @Test func selectedMicrophoneRenderBufferAdvertisesWritablePCMBytes() throws {
        for channels: AVAudioChannelCount in [1, 2] {
            let format = try #require(AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: channels,
                interleaved: false
            ))
            let buffer = try #require(SelectedMicrophoneInput.makeRenderBuffer(
                format: format,
                frameCount: 1_024
            ))
            #expect(buffer.frameLength == 1_024)
            let audioBuffers = buffer.mutableAudioBufferList.pointee
            #expect(audioBuffers.mNumberBuffers == channels)
            #expect(audioBuffers.mBuffers.mData != nil)
            #expect(audioBuffers.mBuffers.mDataByteSize ==
                1_024 * UInt32(MemoryLayout<Float>.size))
        }
    }

    @Test func microphoneRecordingSinkMeasuresWrittenAudioAndRejectsEmptyCapture() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMicSink-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let sink = MicrophoneRecordingSink(
            file: file,
            previewHandler: nil,
            levelHandler: { _ in }
        )
        do {
            try await sink.waitForFirstBuffer(timeout: .milliseconds(20))
            Issue.record("An empty microphone capture must fail before transcription")
        } catch AudioRecorderError.noAudioReceived {
            // Expected: elapsed time is not captured audio.
        }
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        buffer.frameLength = 4_800
        sink.append(buffer)
        try await sink.waitForFirstBuffer(timeout: .milliseconds(20))
        #expect(abs(sink.close() - 0.1) < 0.000_001)
    }

    @Test func microphoneRecordingSinkForwardsPreviewWhenAttachedAfterCaptureStarts() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMicPreview-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let sink = MicrophoneRecordingSink(file: file, previewHandler: nil, levelHandler: { _ in })
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        buffer.frameLength = 4_800
        let previewCount = LockedTestCounter()

        sink.append(buffer)
        #expect(previewCount.value == 0)
        sink.setPreviewHandler { preview in
            if preview.frameCount == 4_800 { previewCount.increment() }
        }
        sink.append(buffer)
        #expect(previewCount.value == 1)
        sink.setPreviewHandler(nil)
        sink.append(buffer)
        #expect(previewCount.value == 1)
        #expect(abs(sink.close() - 0.3) < 0.000_001)
    }

    @Test func dictationStateStartRules() {
        #expect(DictationState.idle.acceptsStart)
        #expect(DictationState.failed(message: "test", retainedAudioURL: nil).acceptsStart)
        #expect(!DictationState.recording.acceptsStart)
        #expect(!DictationState.finalizing.acceptsStart)
        #expect(!DictationState.transcribing.acceptsStart)
        #expect(!DictationState.enhancing.acceptsStart)
        #expect(!DictationState.inserting.acceptsStart)
        #expect(DictationState.success.acceptsStart)
    }

    @Test func systemAudioOverlayDoesNotClaimLiveTranscription() {
        let presentation = OverlayPreviewPresentation.resolve(
            source: .systemAudio,
            state: .disabled
        )

        #expect(presentation.heading == "SYSTEM AUDIO")
        #expect(!presentation.showsActivityIndicator)
        #expect(presentation.statusMessage?.contains("created after recording stops") == true)

        let microphone = OverlayPreviewPresentation.resolve(
            source: .microphone,
            state: .waiting
        )
        #expect(microphone.heading == "LIVE PREVIEW")
        #expect(microphone.showsActivityIndicator)

        let mixed = OverlayPreviewPresentation.resolve(
            source: .mixed,
            state: .waiting
        )
        #expect(mixed.heading == "MEETING CAPTURE")
        #expect(!mixed.showsActivityIndicator)
        #expect(mixed.statusMessage?.contains("separate original tracks") == true)
    }

    @Test func standardOverlayUsesConfiguredPreviewWindow() {
        let text = String(repeating: "a", count: 800)

        #expect(OverlayPreviewPresentation.visibleText(text, for: .expanded).count == 800)
        #expect(OverlayPreviewPresentation.visibleText(text, for: .standard).count == 800)
        #expect(OverlayPreviewPresentation.visibleText(text, for: .compact).isEmpty)
    }

    @Test func multipartBodyContainsFieldsFileAndClosingBoundary() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMultipartSource-\(UUID()).wav")
        try Data([0x01, 0x02, 0x03]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let upload = try MultipartUploadFileBuilder(boundary: "boundary").build(
            fields: [("model", "test-model"), ("language", nil)],
            fileFieldName: "file",
            filename: "recording.wav",
            mimeType: "audio/wav",
            sourceURL: source
        )
        defer { upload.cleanup() }

        let text = String(decoding: try Data(contentsOf: upload.url), as: UTF8.self)
        #expect(text.contains("name=\"model\""))
        #expect(text.contains("test-model"))
        #expect(text.contains("filename=\"recording.wav\""))
        #expect(text.contains("Content-Type: audio/wav"))
        #expect(!text.contains("name=\"language\""))
        #expect(text.hasSuffix("--boundary--\r\n"))
    }

    @Test func openAITranscriptionPayloadDecodes() throws {
        let data = Data(#"{"text":"Hello from FlowDictate"}"#.utf8)
        let payload = try JSONDecoder().decode(OpenAITranscriptionPayload.self, from: data)
        #expect(payload.text == "Hello from FlowDictate")
    }

    @MainActor
    @Test func openAIRejectsOversizedPreparedAudioBeforeNetworkAccess() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateOversized-\(UUID()).m4a")
        #expect(FileManager.default.createFile(atPath: source.path, contents: nil))
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(OpenAITranscriptionProvider.maximumAudioFileBytes + 1))
        try handle.close()
        defer { try? FileManager.default.removeItem(at: source) }

        let provider = OpenAITranscriptionProvider(
            apiKey: "test-key",
            uploadPreparer: PassThroughAudioUploadPreparer()
        )
        do {
            _ = try await provider.transcribe(
                TranscriptionRequest(audioURL: source, language: nil)
            )
            Issue.record("Expected an oversized-audio error")
        } catch let error as TranscriptionProviderError {
            guard case .audioFileTooLarge = error else {
                Issue.record("Unexpected provider error: \(error)")
                return
            }
        }
    }

    @Test func openAIReturnsBeforeSlowTemporaryFileCleanupFinishes() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateCleanupSource-\(UUID()).m4a")
        try Data(repeating: 0x2A, count: 2_048).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SuccessfulOpenAIURLProtocol.self]
        let fileManager = SlowRemovalFileManager(delay: 0.6)
        let provider = OpenAITranscriptionProvider(
            apiKey: "test-key",
            session: URLSession(configuration: configuration),
            uploadPreparer: PassThroughAudioUploadPreparer(),
            fileManager: fileManager
        )

        let startedAt = ContinuousClock.now
        let result = try await provider.transcribe(
            TranscriptionRequest(audioURL: source, language: nil)
        )
        let elapsed = startedAt.duration(to: .now)

        #expect(result.text == "Cleanup stays off the response path")
        #expect(elapsed < .milliseconds(300))
        for _ in 0..<100 where fileManager.removalCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(fileManager.removalCount == 1)
    }

    @Test func openAIUploadsOnlySelectedAudioInMultipartBody() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateUploadScope-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let microphoneURL = directory.appendingPathComponent("microphone.m4a")
        let systemAudioURL = directory.appendingPathComponent("system-audio.m4a")
        let unrelatedVideoURL = directory.appendingPathComponent("screen-video.mov")
        let microphoneBytes = Data(repeating: 0x11, count: 2_048)
        let systemAudioBytes = Data(repeating: 0x22, count: 2_048)
        let unrelatedVideoBytes = Data(repeating: 0x33, count: 2_048)
        try microphoneBytes.write(to: microphoneURL)
        try systemAudioBytes.write(to: systemAudioURL)
        try unrelatedVideoBytes.write(to: unrelatedVideoURL)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MeetingPolicyOpenAIURLProtocol.self]
        let fileManager = CapturingMultipartFileManager()
        let provider = OpenAITranscriptionProvider(
            apiKey: "test-key",
            endpoint: URL(string: "https://meeting-policy.invalid/audio/transcriptions")!,
            session: URLSession(configuration: configuration),
            uploadPreparer: PassThroughAudioUploadPreparer(),
            fileManager: fileManager
        )

        _ = try await provider.transcribe(
            TranscriptionRequest(audioURL: microphoneURL, language: nil)
        )
        _ = try await provider.transcribe(
            TranscriptionRequest(audioURL: systemAudioURL, language: nil)
        )
        for _ in 0..<100 where fileManager.capturedBodies.count < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        let bodies = fileManager.capturedBodies
        #expect(bodies.count == 2)
        let microphoneBody = try #require(bodies.first {
            $0.range(of: microphoneBytes) != nil
        })
        let systemAudioBody = try #require(bodies.first {
            $0.range(of: systemAudioBytes) != nil
        })
        #expect(microphoneBody.range(of: systemAudioBytes) == nil)
        #expect(systemAudioBody.range(of: microphoneBytes) == nil)
        for body in bodies {
            let text = String(decoding: body, as: UTF8.self)
            #expect(text.contains("name=\"model\""))
            #expect(text.contains("name=\"file\""))
            #expect(!text.contains("name=\"language\""))
            #expect(!text.contains("name=\"prompt\""))
            #expect(!text.contains("name=\"video\""))
            #expect(body.range(of: unrelatedVideoBytes) == nil)
        }
    }

    @MainActor
    @Test func audioUploadPreparerCreatesAndCleansCompactM4A() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateUploadSource-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: source) }
        let format = try #require(AVAudioFormat(
            standardFormatWithSampleRate: 16_000,
            channels: 1
        ))
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            let buffer = try #require(AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: 1_600
            ))
            buffer.frameLength = buffer.frameCapacity
            try file.write(from: buffer)
        }

        let prepared = try await AudioUploadPreparer().prepareCompactUpload(source)
        #expect(prepared.fileURL.pathExtension == "m4a")
        #expect(prepared.temporaryFileURL != nil)
        #expect(FileManager.default.fileExists(atPath: prepared.fileURL.path))
        prepared.cleanup()
        #expect(!FileManager.default.fileExists(atPath: prepared.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    @Test func pasteboardSnapshotRestoresMultipleRepresentations() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("FlowDictateTests-\(UUID())"))
        pasteboard.clearContents()

        let originalItem = NSPasteboardItem()
        originalItem.setString("original", forType: .string)
        originalItem.setData(Data([0xCA, 0xFE]), forType: .init("dev.flowdictate.test"))
        #expect(pasteboard.writeObjects([originalItem]))

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        #expect(pasteboard.setString("transcript", forType: .string))
        #expect(snapshot.restore(to: pasteboard))

        #expect(pasteboard.string(forType: .string) == "original")
        #expect(
            pasteboard.data(forType: .init("dev.flowdictate.test")) == Data([0xCA, 0xFE])
        )
    }

    @MainActor
    @Test func appSettingsPersistPhaseOneConfiguration() {
        let suiteName = "FlowDictateTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.dictationHotKey = .custom(
            keyCode: 42,
            modifiers: UInt32(optionKey | cmdKey),
            keyName: "K"
        )
        settings.cancelHotKey = .controlShiftSpace
        settings.restoreHotKey = .controlShiftZ
        settings.inputDeviceUID = "test-microphone"
        settings.recordingAudioSource = .systemAudio
        settings.dictationActivationMode = .pressAndHold
        settings.transcriptionModel = "test-model"
        settings.transcriptionLanguage = .german
        settings.clipboardRestoreDelay = 1.2
        settings.onboardingVersion = 2
        settings.automaticRetryEnabled = false
        settings.audioRetentionDays = 90
        settings.historyRetentionDays = 365
        settings.historyMaximumRecordCount = 500
        settings.livePreviewEnabled = true
        settings.overlaySize = .expanded
        settings.livePreviewCharacterLimit = 320
        settings.overlayPosition = .bottomCenter
        let statisticsResetDate = Date(timeIntervalSince1970: 1_750_000_000)
        settings.usageStatisticsResetDate = statisticsResetDate

        let restored = AppSettings(defaults: defaults)

        #expect(restored.dictationHotKey == settings.dictationHotKey)
        #expect(restored.cancelHotKey == .controlShiftSpace)
        #expect(restored.restoreHotKey == .controlShiftZ)
        #expect(restored.inputDeviceUID == "test-microphone")
        #expect(restored.recordingAudioSource == .systemAudio)
        #expect(restored.dictationActivationMode == .pressAndHold)
        #expect(restored.transcriptionModel == "test-model")
        #expect(restored.transcriptionLanguage == .german)
        #expect(restored.clipboardRestoreDelay == 1.2)
        #expect(restored.onboardingVersion == 2)
        #expect(!restored.automaticRetryEnabled)
        #expect(restored.audioRetentionDays == 90)
        #expect(restored.historyRetentionDays == 365)
        #expect(restored.historyMaximumRecordCount == 500)
        #expect(restored.livePreviewEnabled)
        #expect(restored.overlaySize == .expanded)
        #expect(restored.livePreviewCharacterLimit == 320)
        #expect(restored.overlayPosition == .bottomCenter)
        #expect(restored.usageStatisticsResetDate == statisticsResetDate)
    }

    @MainActor
    @Test func restorePresetUsesCurrentLayoutAndNormalizesLegacyKeyCode() throws {
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        let property = try #require(TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData))
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        let bytes = try #require(CFDataGetBytePtr(data))
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var output = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout, UInt16(HotKeyConfiguration.optionShiftZ.keyCode),
            UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
            output.count, &length, &output
        )
        #expect(status == noErr)
        #expect(String(utf16CodeUnits: output, count: length).lowercased() == "z")

        let legacy = HotKeyConfiguration(
            id: "option-shift-z", keyCode: UInt32(kVK_ANSI_Z),
            modifiers: UInt32(optionKey | shiftKey), displayName: "Option + Shift + Z"
        )
        #expect(HotKeyConfiguration.normalizedRestorePreset(legacy) == .optionShiftZ)
        let custom = HotKeyConfiguration.custom(
            keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(optionKey | shiftKey), keyName: "Y"
        )
        #expect(HotKeyConfiguration.normalizedRestorePreset(custom) == custom)
    }

    @MainActor
    @Test func clipboardRestoreDelayIsClampedWhenLoadingLegacySettings() {
        let suiteName = "FlowDictateClipboardDelay-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(13.0, forKey: "clipboardRestoreDelay")
        #expect(AppSettings(defaults: defaults).clipboardRestoreDelay == 2.0)

        defaults.set(0.05, forKey: "clipboardRestoreDelay")
        #expect(AppSettings(defaults: defaults).clipboardRestoreDelay == 0.3)
    }

    @MainActor
    @Test func meetingRecordingConsentIsExplicitPersistentAndResettable() {
        let suiteName = "FlowDictateMeetingConsent-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = AppSettings(defaults: defaults)
        #expect(!settings.hasAcceptedCurrentMeetingRecordingConsent)
        #expect(
            MixedRecordingConsentGate.requirement(
                for: .mixed,
                hasCurrentConsent: settings.hasAcceptedCurrentMeetingRecordingConsent
            ) == .confirmationRequired
        )
        #expect(
            MixedRecordingConsentGate.requirement(
                for: .microphone,
                hasCurrentConsent: false
            ).allowsRecording
        )

        settings.acceptCurrentMeetingRecordingConsent()
        settings = AppSettings(defaults: defaults)
        #expect(settings.hasAcceptedCurrentMeetingRecordingConsent)
        #expect(
            MixedRecordingConsentGate.requirement(
                for: .mixed,
                hasCurrentConsent: settings.hasAcceptedCurrentMeetingRecordingConsent
            ) == .satisfied
        )

        settings.resetMeetingRecordingConsent()
        #expect(!AppSettings(defaults: defaults).hasAcceptedCurrentMeetingRecordingConsent)
    }

    @Test func systemAudioCaptureStrategyUsesCoreAudioTapFromMacOS14_2() {
        let macOS14_1 = SystemAudioCaptureStrategy.candidate(
            for: OperatingSystemVersion(majorVersion: 14, minorVersion: 1, patchVersion: 9)
        )
        #expect(macOS14_1.preferredBackend == .screenCaptureKit)
        #expect(!macOS14_1.requiresAudioCaptureUsageDescription)
        #expect(macOS14_1.permissionSettingsLabel == "Screen & System Audio Recording")

        for version in [
            OperatingSystemVersion(majorVersion: 14, minorVersion: 2, patchVersion: 0),
            OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0),
            OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 2)
        ] {
            let strategy = SystemAudioCaptureStrategy.candidate(for: version)
            #expect(strategy.preferredBackend == .coreAudioTap)
            #expect(strategy.requiresAudioCaptureUsageDescription)
            #expect(strategy.permissionSettingsLabel == "System Audio Recording Only")
            #expect(strategy.minimumOperatingSystem.majorVersion == 14)
            #expect(strategy.minimumOperatingSystem.minorVersion == 2)
        }
    }

    @Test func mixedSystemAudioRecorderPinsBackendForItsLifetime() {
        let compatibilityRecorder = SystemAudioTrackRecorder(
            version: OperatingSystemVersion(
                majorVersion: 14,
                minorVersion: 1,
                patchVersion: 9
            )
        )
        let coreAudioRecorder = SystemAudioTrackRecorder(
            version: OperatingSystemVersion(
                majorVersion: 14,
                minorVersion: 2,
                patchVersion: 0
            )
        )

        #expect(compatibilityRecorder.role == .systemAudio)
        #expect(compatibilityRecorder.backend == .screenCaptureKit)
        #expect(coreAudioRecorder.role == .systemAudio)
        #expect(coreAudioRecorder.backend == .coreAudioTap)
    }

    @Test func screenCaptureKitMixedTrackRequiresCAFOutput() async {
        let recorder = ScreenCaptureKitSystemTrackRecorder()
        let invalidURL = FileManager.default.temporaryDirectory
            .appending(path: "mixed-system-audio-\(UUID().uuidString).m4a")

        await #expect(throws: SystemAudioTrackRecorderError.invalidOutputURL) {
            try await recorder.prepare(outputURL: invalidURL)
        }
    }

    @Test func systemAudioPermissionStatusMatchesTheSelectedCaptureBackend() {
        let macOS14_1 = OperatingSystemVersion(
            majorVersion: 14,
            minorVersion: 1,
            patchVersion: 9
        )
        let macOS14_2 = OperatingSystemVersion(
            majorVersion: 14,
            minorVersion: 2,
            patchVersion: 0
        )

        let deniedScreenCapture = SystemAudioPermissionStatus.resolve(
            for: .systemAudio,
            version: macOS14_2,
            screenCaptureAuthorized: false,
            coreAudioTapSucceededThisSession: true
        )
        #expect(deniedScreenCapture.backend == .screenCaptureKit)
        #expect(deniedScreenCapture.readiness == .requestRequired)
        #expect(deniedScreenCapture.settingsLabel == "Screen & System Audio Recording")

        let allowedScreenCapture = SystemAudioPermissionStatus.resolve(
            for: .mixed,
            version: macOS14_1,
            screenCaptureAuthorized: true,
            coreAudioTapSucceededThisSession: false
        )
        #expect(allowedScreenCapture.backend == .screenCaptureKit)
        #expect(allowedScreenCapture.readiness == .authorized)

        let uncheckedCoreAudioTap = SystemAudioPermissionStatus.resolve(
            for: .mixed,
            version: macOS14_2,
            screenCaptureAuthorized: true,
            coreAudioTapSucceededThisSession: false
        )
        #expect(uncheckedCoreAudioTap.backend == .coreAudioTap)
        #expect(uncheckedCoreAudioTap.readiness == .verifiedWhenCaptureStarts)
        #expect(uncheckedCoreAudioTap.settingsLabel == "System Audio Recording Only")

        let verifiedCoreAudioTap = SystemAudioPermissionStatus.resolve(
            for: .mixed,
            version: macOS14_2,
            screenCaptureAuthorized: false,
            coreAudioTapSucceededThisSession: true
        )
        #expect(verifiedCoreAudioTap.readiness == .authorized)
    }

    @Test func systemAudioSettingsURLMatchesTheSelectedCaptureBackend() {
        #expect(
            SystemAudioPermissionService.systemSettingsURL(for: .screenCaptureKit)
                .absoluteString.contains("Privacy_ScreenCapture")
        )
        #expect(
            SystemAudioPermissionService.systemSettingsURL(for: .coreAudioTap)
                .absoluteString.contains("Privacy_AudioCapture")
        )
    }

    @Test func coreAudioTapProbeReportDerivesCapturedDurationFromFrames() {
        let cleanup = CoreAudioTapCleanupReport(
            stopStatus: noErr,
            destroyIOProcStatus: noErr,
            destroyAggregateDeviceStatus: noErr,
            destroyTapStatus: noErr,
            aggregateDeviceRemoved: true,
            tapRemoved: true
        )
        let report = CoreAudioTapProbeReport(
            requestedDuration: 5,
            wallDuration: 5.01,
            callbackCount: 100,
            nonSilentCallbackCount: 80,
            frameCount: 240_000,
            sampleRate: 48_000,
            channelCount: 1,
            firstHostTime: 1_000,
            lastHostTime: 6_000,
            firstSampleTime: 0,
            lastSampleTime: 239_000,
            missingHostTimeCount: 0,
            missingSampleTimeCount: 0,
            hostTimeRegressionCount: 0,
            sampleTimeRegressionCount: 0,
            sampleDiscontinuityCount: 0,
            largestPositiveSampleGapFrames: 0,
            largestHostTimeDeltaNanoseconds: 50_000_000,
            cleanup: cleanup
        )

        #expect(report.capturedDuration == 5)
        #expect(abs(report.stopDelay - 0.01) < 0.000_001)
        #expect(report.hasCapturedSignal)
        #expect(report.hasMonotonicTimeline)
        #expect(report.hasContinuousSampleTimeline)
        #expect(report.cleanup.succeeded)
        let repeated = CoreAudioTapRepeatedProbeReport(cycles: [report, report])
        #expect(repeated.completedCycleCount == 2)
        #expect(repeated.totalCallbackCount == 200)
        #expect(repeated.hasCapturedSignal)
        #expect(repeated.allCleanupSucceeded)
        #expect(repeated.allTimelinesMonotonic)

        let silentReport = CoreAudioTapProbeReport(
            requestedDuration: 5,
            wallDuration: 5,
            callbackCount: 100,
            nonSilentCallbackCount: 0,
            frameCount: 240_000,
            sampleRate: 48_000,
            channelCount: 1,
            firstHostTime: 1_000,
            lastHostTime: 6_000,
            firstSampleTime: 0,
            lastSampleTime: 239_000,
            missingHostTimeCount: 0,
            missingSampleTimeCount: 0,
            hostTimeRegressionCount: 0,
            sampleTimeRegressionCount: 0,
            sampleDiscontinuityCount: 0,
            largestPositiveSampleGapFrames: 0,
            largestHostTimeDeltaNanoseconds: 50_000_000,
            cleanup: cleanup
        )
        #expect(!silentReport.hasCapturedSignal)
        #expect(!CoreAudioTapRepeatedProbeReport(cycles: [silentReport]).hasCapturedSignal)

        let incompleteCleanup = CoreAudioTapCleanupReport(
            stopStatus: noErr,
            destroyIOProcStatus: nil,
            destroyAggregateDeviceStatus: noErr,
            destroyTapStatus: noErr,
            aggregateDeviceRemoved: true,
            tapRemoved: true
        )
        #expect(!incompleteCleanup.succeeded)
        #expect(incompleteCleanup.firstFailure != nil)
    }

    @Test func coreAudioTimedStopRunsOnlyOnce() async {
        let counter = LockedTestCounter()
        let timedStop = CoreAudioTapTimedStop {
            counter.increment()
            return noErr
        }

        let result = await withTaskGroup(of: CoreAudioTapTimedStop.Result.self) { group in
            group.addTask { await timedStop.wait(for: 60) }
            timedStop.stopNow()
            timedStop.stopNow()
            return await group.next()!
        }

        #expect(result.status == noErr)
        #expect(counter.value == 1)
    }

    @Test func coreAudioTimedStopFiresFromItsDedicatedTimer() async {
        let counter = LockedTestCounter()
        let timedStop = CoreAudioTapTimedStop {
            counter.increment()
            return noErr
        }

        let result = await timedStop.wait(for: 0.05)

        #expect(result.status == noErr)
        #expect(result.elapsed >= 0.04)
        #expect(result.elapsed < 1)
        #expect(counter.value == 1)
    }

    @Test func captureProbeArtifactsRemoveOnlyFilesFromStoppedProcesses() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateCaptureProbeArtifacts-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureProbeArtifactStore(directoryURL: directory)
        let activeURL = try store.makeURL(processID: 111)
        let abandonedURL = try store.makeURL(processID: 222)
        let unrelatedURL = directory.appendingPathComponent("user-recording.m4a")
        let matchingDirectoryURL = directory.appendingPathComponent(
            "\(CaptureProbeArtifactStore.filePrefix)222-\(UUID().uuidString).m4a",
            isDirectory: true
        )
        try Data("active".utf8).write(to: activeURL)
        try Data("abandoned".utf8).write(to: abandonedURL)
        try Data("unrelated".utf8).write(to: unrelatedURL)
        try FileManager.default.createDirectory(
            at: matchingDirectoryURL,
            withIntermediateDirectories: false
        )

        let removed = try store.removeAbandonedArtifacts { $0 == 111 }

        #expect(removed.map(\.lastPathComponent) == [abandonedURL.lastPathComponent])
        #expect(FileManager.default.fileExists(atPath: activeURL.path))
        #expect(!FileManager.default.fileExists(atPath: abandonedURL.path))
        #expect(FileManager.default.fileExists(atPath: unrelatedURL.path))
        #expect(FileManager.default.fileExists(atPath: matchingDirectoryURL.path))
    }

    @Test func captureProbeArtifactRemovalRejectsPathsOutsideItsDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateCaptureProbeScope-\(UUID())", isDirectory: true)
        let probeDirectory = root.appendingPathComponent("probes", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = CaptureProbeArtifactStore(directoryURL: probeDirectory)
        let probeURL = try store.makeURL(processID: 333)
        let outsideURL = root.appendingPathComponent(
            "\(CaptureProbeArtifactStore.filePrefix)333-outside.m4a"
        )
        try Data("probe".utf8).write(to: probeURL)
        try Data("outside".utf8).write(to: outsideURL)

        try store.removeArtifact(at: outsideURL)
        try store.removeArtifact(at: probeURL)

        #expect(FileManager.default.fileExists(atPath: outsideURL.path))
        #expect(!FileManager.default.fileExists(atPath: probeURL.path))
    }

    @Test func coreAudioTapTimelineAnalyzerDetectsGapsAndRegressions() {
        var continuous = CoreAudioTapTimelineAnalyzer()
        continuous.record(hostTime: 1_000, sampleTime: 0, frameCount: 480)
        continuous.record(hostTime: 2_000, sampleTime: 480, frameCount: 480)
        continuous.record(hostTime: 3_000, sampleTime: 960, frameCount: 480)
        #expect(continuous.hostTimeRegressionCount == 0)
        #expect(continuous.sampleTimeRegressionCount == 0)
        #expect(continuous.sampleDiscontinuityCount == 0)

        var discontinuous = continuous
        discontinuous.record(hostTime: 2_999, sampleTime: 1_920, frameCount: 480)
        #expect(discontinuous.hostTimeRegressionCount == 1)
        #expect(discontinuous.sampleTimeRegressionCount == 0)
        #expect(discontinuous.sampleDiscontinuityCount == 1)
        #expect(discontinuous.largestPositiveSampleGapFrames == 480)

        discontinuous.record(hostTime: nil, sampleTime: nil, frameCount: 480)
        #expect(discontinuous.missingHostTimeCount == 1)
        #expect(discontinuous.missingSampleTimeCount == 1)

        discontinuous.record(hostTime: 4_000, sampleTime: 1_000, frameCount: 480)
        #expect(discontinuous.sampleTimeRegressionCount == 1)
    }

    @Test func screenCaptureTimelineAnalyzerDetectsGapsAndRegressions() {
        var continuous = ScreenCaptureTimelineAnalyzer()
        continuous.record(presentationTimeSeconds: 10, frameCount: 480, sampleRate: 48_000)
        continuous.record(presentationTimeSeconds: 10.01, frameCount: 480, sampleRate: 48_000)
        continuous.record(presentationTimeSeconds: 10.02, frameCount: 480, sampleRate: 48_000)
        #expect(continuous.report.callbackCount == 3)
        #expect(continuous.report.frameCount == 1_440)
        #expect(continuous.report.sampleRate == 48_000)
        #expect(continuous.report.capturedDuration == 0.03)
        #expect(continuous.report.sampleRateChangeCount == 0)
        #expect(continuous.report.hasMonotonicTimeline)
        #expect(continuous.report.discontinuityCount == 0)

        var discontinuous = continuous
        discontinuous.record(presentationTimeSeconds: 10.04, frameCount: 480, sampleRate: 48_000)
        #expect(discontinuous.report.discontinuityCount == 1)
        #expect(discontinuous.report.largestPositiveGapFrames == 480)

        discontinuous.record(presentationTimeSeconds: nil, frameCount: 480, sampleRate: 48_000)
        #expect(discontinuous.report.missingPresentationTimeCount == 1)
        #expect(!discontinuous.report.hasMonotonicTimeline)

        discontinuous.record(presentationTimeSeconds: 10.03, frameCount: 480, sampleRate: 48_000)
        #expect(discontinuous.report.presentationTimeRegressionCount == 1)

        discontinuous.record(presentationTimeSeconds: 10.04, frameCount: 441, sampleRate: 44_100)
        #expect(discontinuous.report.sampleRateChangeCount == 1)
    }

    @Test func systemAudioProbeDurationsMatchTheLongFormGateMatrix() {
        #expect(SystemAudioProbeDuration.fiveSeconds.rawValue == 5)
        #expect(SystemAudioProbeDuration.fiveMinutes.rawValue == 300)
        #expect(SystemAudioProbeDuration.thirtyMinutes.rawValue == 1_800)
        #expect(SystemAudioProbeDuration.sixtyMinutes.rawValue == 3_600)
    }

    @MainActor
    @Test func selectingMixedSourceRequiresConfirmationBeforeChangingSetting() {
        let presenter = MockMeetingRecordingConsentPresenter()
        let harness = makeCoordinatorHarness(
            meetingRecordingConsentPresenter: presenter
        )

        harness.coordinator.selectRecordingAudioSource(.mixed)

        #expect(presenter.presentationCount == 1)
        #expect(harness.coordinator.isMeetingRecordingConsentPresented)
        #expect(harness.coordinator.settings.recordingAudioSource == .microphone)

        presenter.cancel()
        #expect(!harness.coordinator.isMeetingRecordingConsentPresented)
        #expect(harness.coordinator.settings.recordingAudioSource == .microphone)

        harness.coordinator.selectRecordingAudioSource(.mixed)
        presenter.confirm(remember: true)
        #expect(harness.coordinator.settings.recordingAudioSource == .mixed)
        #expect(harness.coordinator.hasCurrentMeetingRecordingConsent)
        #expect(harness.coordinator.settings.hasAcceptedCurrentMeetingRecordingConsent)
    }

    @MainActor
    @Test func sessionOnlyMeetingConsentIsNotPersisted() {
        let presenter = MockMeetingRecordingConsentPresenter()
        let harness = makeCoordinatorHarness(
            meetingRecordingConsentPresenter: presenter
        )
        harness.coordinator.selectRecordingAudioSource(.mixed)

        presenter.confirm(remember: false)

        #expect(harness.coordinator.hasCurrentMeetingRecordingConsent)
        #expect(!harness.coordinator.settings.hasAcceptedCurrentMeetingRecordingConsent)
        harness.coordinator.resetMeetingRecordingConsent()
        #expect(!harness.coordinator.hasCurrentMeetingRecordingConsent)
    }

    @Test func mixedRecordingSessionRoundTripsAndValidates() throws {
        let session = makeValidMixedRecordingSession()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(
            MixedRecordingSession.self,
            from: encoder.encode(session)
        )

        #expect(try restored.validated() == session)
        #expect(restored.tracks.map(\.role) == [.localSpeaker, .systemAudio])
    }

    @Test func mixedRecordingSessionRequiresExactlyOneTrackPerRole() {
        var session = makeValidMixedRecordingSession()
        session.tracks[1].role = .localSpeaker

        #expect(throws: MixedRecordingSessionValidationError.invalidTrackRoles) {
            try session.validated()
        }
    }

    @Test func mixedRecordingSessionRejectsBackwardTimestampsAndUnsafePaths() {
        var session = makeValidMixedRecordingSession()
        session.tracks[0].timestampAnchors.swapAt(0, 1)
        #expect(
            throws: MixedRecordingSessionValidationError.nonMonotonicTimeline(.localSpeaker)
        ) {
            try session.validated()
        }

        session = makeValidMixedRecordingSession()
        session.tracks[1].audioRelativePath = "../escaped.m4a"
        #expect(throws: MixedRecordingSessionValidationError.unsafeRelativePath("../escaped.m4a")) {
            try session.validated()
        }
    }

    @Test func completedMixedSessionRequiresExplicitValidCompletionMode() throws {
        var session = makeValidMixedRecordingSession()
        session.status = .completed
        session.finalTranscript = "[You] Hello\n[System Audio] Hi"
        session.mergedTimelineRelativePath = "transcription/merged-timeline.json"
        session.completionMode = .allTracks
        session.tracks[0].status = .transcribed
        session.tracks[0].transcriptionSessionID = UUID()
        session.tracks[0].transcriptRelativePath = "transcription/localSpeaker-transcript.json"
        session.tracks[1].status = .failed

        #expect(throws: MixedRecordingSessionValidationError.invalidCompletion) {
            try session.validated()
        }

        session.completionMode = .acceptedSingleTrack(.localSpeaker)
        #expect(try session.validated() == session)
    }

    @Test func synchronizationAnalyzerReconstructsOffsetAndRelativeDrift() throws {
        let analyzer = SynchronizationAnalyzer()
        let systemAudio = makeSynchronizationTrack(
            role: .systemAudio,
            startMilliseconds: 0,
            anchorSessionTimes: [0, 30_000, 60_000]
        )
        let delayedMicrophone = makeSynchronizationTrack(
            role: .localSpeaker,
            startMilliseconds: 50,
            anchorSessionTimes: [50, 30_053, 60_056]
        )

        let positive = analyzer.analyze(tracks: [delayedMicrophone, systemAudio])
        #expect(positive.quality == .good)
        #expect(positive.initialOffsetMilliseconds == 50)
        #expect(abs(try #require(positive.estimatedDriftPartsPerMillion) - 100) < 0.01)
        #expect((positive.residualDriftMilliseconds ?? 1) < 0.01)
        #expect(positive.analyzedAnchorCount == 6)

        let earlyMicrophone = makeSynchronizationTrack(
            role: .localSpeaker,
            startMilliseconds: 0,
            anchorSessionTimes: [0, 29_997, 59_994]
        )
        let delayedSystemAudio = makeSynchronizationTrack(
            role: .systemAudio,
            startMilliseconds: 50,
            anchorSessionTimes: [50, 30_050, 60_050]
        )
        let negative = analyzer.analyze(tracks: [earlyMicrophone, delayedSystemAudio])
        #expect(negative.quality == .good)
        #expect(negative.initialOffsetMilliseconds == -50)
        #expect(abs(try #require(negative.estimatedDriftPartsPerMillion) + 100) < 0.01)
    }

    @Test func synchronizationAnalyzerDoesNotHideGapsBehindGlobalDrift() {
        let analyzer = SynchronizationAnalyzer()
        let microphone = makeSynchronizationTrack(
            role: .localSpeaker,
            startMilliseconds: 0,
            anchorSessionTimes: [0, 30_000, 60_000],
            gaps: [
                TrackGap(
                    id: UUID(),
                    startMilliseconds: 10_000,
                    endMilliseconds: 12_000,
                    reason: .droppedBuffers
                )
            ]
        )
        let systemAudio = makeSynchronizationTrack(
            role: .systemAudio,
            startMilliseconds: 0,
            anchorSessionTimes: [0, 30_000, 60_000]
        )

        let report = analyzer.analyze(tracks: [microphone, systemAudio])
        let quality = MeetingQualityAnalyzer().analyze(
            tracks: [microphone, systemAudio],
            synchronization: report
        )

        #expect(report.quality == .degraded)
        #expect(report.estimatedDriftPartsPerMillion == nil)
        #expect(report.residualDriftMilliseconds == nil)
        #expect(quality.completeTrackRoles == [.localSpeaker, .systemAudio])
        #expect(quality.totalGapCount == 1)
        #expect(quality.totalGapDurationMilliseconds == 2_000)
    }

    @Test func synchronizationAnalyzerFlagsNonlinearAndIncompleteTimelines() {
        let analyzer = SynchronizationAnalyzer()
        let systemAudio = makeSynchronizationTrack(
            role: .systemAudio,
            startMilliseconds: 0,
            anchorSessionTimes: [0, 30_000, 60_000]
        )
        let nonlinearMicrophone = makeSynchronizationTrack(
            role: .localSpeaker,
            startMilliseconds: 0,
            anchorSessionTimes: [0, 30_000, 61_000]
        )
        let nonlinear = analyzer.analyze(tracks: [nonlinearMicrophone, systemAudio])
        #expect(nonlinear.quality == .unreliable)
        #expect((nonlinear.residualDriftMilliseconds ?? 0) > 100)

        var failedSystemAudio = systemAudio
        failedSystemAudio.status = .failed
        let incomplete = analyzer.analyze(tracks: [nonlinearMicrophone, failedSystemAudio])
        let quality = MeetingQualityAnalyzer().analyze(
            tracks: [nonlinearMicrophone, failedSystemAudio],
            synchronization: incomplete
        )
        #expect(incomplete.quality == .notAnalyzed)
        #expect(incomplete.initialOffsetMilliseconds == nil)
        #expect(quality.completeTrackRoles == [.localSpeaker])
    }

    @Test func derivedTrackRendererAlignsImpulsesWithoutChangingOriginals() async throws {
        let fixture = try makeDerivedTrackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let renderer = DerivedTrackRenderer()

        let result = try await renderer.render(
            session: fixture.session,
            sessionDirectory: fixture.directory
        )
        let microphone = try #require(
            result.tracks.first(where: { $0.role == .localSpeaker })
        )
        let systemAudio = try #require(
            result.tracks.first(where: { $0.role == .systemAudio })
        )
        let microphoneDerivedURL = fixture.directory.appendingPathComponent(
            microphone.relativePath
        )
        let systemDerivedURL = fixture.directory.appendingPathComponent(
            systemAudio.relativePath
        )

        #expect(microphone.prependedSilenceMilliseconds == 100)
        #expect(systemAudio.prependedSilenceMilliseconds == 0)
        #expect(abs(try peakFrame(in: microphoneDerivedURL) - 4_800) <= 128)
        #expect(abs(try peakFrame(in: systemDerivedURL) - 4_800) <= 128)
        #expect(
            try Data(contentsOf: fixture.microphoneURL) == fixture.microphoneOriginal
        )
        #expect(
            try Data(contentsOf: fixture.systemAudioURL) == fixture.systemAudioOriginal
        )
    }

    @Test func derivedTrackRendererInsertsGapsWithoutApplyingGlobalDrift() async throws {
        var fixture = try makeDerivedTrackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.session.synchronization?.estimatedDriftPartsPerMillion = 1_000
        let microphoneIndex = try #require(
            fixture.session.tracks.firstIndex(where: { $0.role == .localSpeaker })
        )
        fixture.session.tracks[microphoneIndex].gaps = [
            TrackGap(
                id: UUID(),
                startMilliseconds: 250,
                endMilliseconds: 300,
                reason: .droppedBuffers
            )
        ]

        let result = try await DerivedTrackRenderer().render(
            session: fixture.session,
            sessionDirectory: fixture.directory
        )
        let microphone = try #require(
            result.tracks.first(where: { $0.role == .localSpeaker })
        )

        #expect(microphone.insertedGapDurationMilliseconds == 50)
        #expect(microphone.appliedDriftPartsPerMillion == nil)
        #expect(microphone.durationMilliseconds == 650)
        #expect(
            try Data(contentsOf: fixture.microphoneURL) == fixture.microphoneOriginal
        )
    }

    @Test func derivedTrackRendererAppliesDriftOnlyToDerivedTrack() async throws {
        var fixture = try makeDerivedTrackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.session.synchronization?.estimatedDriftPartsPerMillion = 1_000

        let result = try await DerivedTrackRenderer().render(
            session: fixture.session,
            sessionDirectory: fixture.directory
        )
        let microphone = try #require(
            result.tracks.first(where: { $0.role == .localSpeaker })
        )

        #expect(microphone.appliedDriftPartsPerMillion == 1_000)
        #expect(microphone.durationMilliseconds >= 600)
        #expect(microphone.durationMilliseconds <= 602)
        #expect(
            try Data(contentsOf: fixture.microphoneURL) == fixture.microphoneOriginal
        )
    }

    @Test func derivedTrackRendererRejectsAnyOriginalAsDestination() async throws {
        let fixture = try makeDerivedTrackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let renderer = DerivedTrackRenderer(destinationPaths: [
            .localSpeaker: "tracks/microphone.caf",
            .systemAudio: "derived/aligned-system-audio.caf"
        ])

        await #expect(
            throws: DerivedTrackRendererError.destinationOverwritesOriginal(.localSpeaker)
        ) {
            _ = try await renderer.render(
                session: fixture.session,
                sessionDirectory: fixture.directory
            )
        }
        #expect(
            try Data(contentsOf: fixture.microphoneURL) == fixture.microphoneOriginal
        )
    }

    @Test func meetingSessionStoreCreatesLayoutAndRoundTripsManifest() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingStore-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        var session = makeValidMixedRecordingSession()

        let paths = try await store.prepareSession(id: session.id)
        #expect(FileManager.default.fileExists(atPath: paths.tracksDirectory.path))
        #expect(FileManager.default.fileExists(atPath: paths.derivedDirectory.path))
        #expect(FileManager.default.fileExists(atPath: paths.transcriptionDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: paths.manifestURL.path))

        try await store.create(session)
        #expect(try await store.load(sessionID: session.id) == session)

        session.status = .queued
        session.updatedAt = session.updatedAt.addingTimeInterval(1)
        try await store.save(session)
        #expect(try await store.all() == [session])
    }

    @Test func meetingSessionStoreCreateDoesNotOverwriteExistingManifest() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingCreate-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        let session = makeValidMixedRecordingSession()
        try await store.create(session)

        do {
            try await store.create(session)
            Issue.record("Creating the same meeting twice must not overwrite its manifest")
        } catch let error as MeetingSessionStoreError {
            #expect(error == .sessionAlreadyExists(session.id))
        }
        #expect(try await store.load(sessionID: session.id) == session)
    }

    @Test func meetingSessionRestartRecoveryPreservesOriginalTracks() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingRecovery-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        var session = makeValidMixedRecordingSession()
        session.status = .recording
        session.tracks[0].status = .recording
        session.tracks[1].status = .recording
        let paths = try await store.prepareSession(id: session.id)
        let microphoneURL = paths.sessionDirectory.appendingPathComponent(
            session.tracks[0].audioRelativePath!
        )
        let systemAudioURL = paths.sessionDirectory.appendingPathComponent(
            session.tracks[1].audioRelativePath!
        )
        try Data("microphone-original".utf8).write(to: microphoneURL)
        try Data("system-audio-original".utf8).write(to: systemAudioURL)
        try await store.create(session)
        let recoveryDate = session.updatedAt.addingTimeInterval(30)

        let normalized = try await store.normalizeInterruptedSessions(now: recoveryDate)
        let recovered = try #require(try await store.load(sessionID: session.id))

        #expect(normalized == [recovered])
        #expect(recovered.status == .paused)
        #expect(recovered.tracks.allSatisfy { $0.status == .interrupted })
        #expect(recovered.lastErrorCategory == .interrupted)
        #expect(recovered.updatedAt == recoveryDate)
        #expect(try Data(contentsOf: microphoneURL) == Data("microphone-original".utf8))
        #expect(try Data(contentsOf: systemAudioURL) == Data("system-audio-original".utf8))
    }

    @Test func meetingRestartNormalizesEverySessionAndTrackStatusWithoutChangingOriginals() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingStatusMatrix-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        let statuses: [MeetingSessionStatus] = [
            .preparing, .recording, .finalizing, .queued, .transcribing,
            .merging, .completed, .partial, .paused, .failed, .cancelled
        ]
        let interruptedSessionStatuses: [MeetingSessionStatus] = [
            .preparing, .recording, .finalizing, .transcribing, .merging
        ]
        let interruptedTrackStatuses: [TrackCaptureStatus] = [
            .preparing, .recording, .transcribing
        ]
        var originalSessions: [MixedRecordingSession] = []
        var originalFiles: [URL: Data] = [:]

        for status in statuses {
            var session = status == .completed
                ? makeCompletedMixedRecordingSession(insertionState: .completed)
                : makeValidMixedRecordingSession()
            session.id = UUID()
            session.recordID = UUID()
            session.status = status
            let trackStatuses: [TrackCaptureStatus] = switch status {
            case .preparing: [.preparing, .preparing]
            case .recording, .finalizing: [.recording, .recording]
            case .queued: [.transcriptionPending, .transcriptionPending]
            case .transcribing: [.transcribing, .transcribing]
            case .merging, .completed: [.transcribed, .transcribed]
            case .partial: [.transcribed, .unavailable]
            case .paused: [.interrupted, .interrupted]
            case .failed: [.failed, .failed]
            case .cancelled: [.finalized, .finalized]
            }
            for index in session.tracks.indices {
                session.tracks[index].status = trackStatuses[index]
                if trackStatuses[index] == .transcribed {
                    session.tracks[index].transcriptionSessionID = UUID()
                    session.tracks[index].transcriptRelativePath =
                        "transcription/\(session.tracks[index].role.rawValue)-transcript.json"
                }
            }
            let paths = try await store.prepareSession(id: session.id)
            for track in session.tracks {
                let url = paths.sessionDirectory.appendingPathComponent(
                    try #require(track.audioRelativePath)
                )
                let data = Data("original-\(status.rawValue)-\(track.role.rawValue)".utf8)
                try data.write(to: url)
                originalFiles[url] = data
            }
            try await store.create(session)
            originalSessions.append(session)
        }

        let recoveryDate = Date(timeIntervalSince1970: 1_800_000_100)
        let restartedStore = MeetingSessionStore(rootURL: root)
        let normalized = try await restartedStore.normalizeInterruptedSessions(now: recoveryDate)
        #expect(Set(normalized.map(\.id)) == Set(originalSessions.filter {
            interruptedSessionStatuses.contains($0.status)
        }.map(\.id)))

        for original in originalSessions {
            let restored = try #require(try await restartedStore.load(sessionID: original.id))
            let shouldPause = interruptedSessionStatuses.contains(original.status)
            #expect(restored.status == (shouldPause ? .paused : original.status))
            #expect(restored.updatedAt == (shouldPause ? recoveryDate : original.updatedAt))
            for (before, after) in zip(original.tracks, restored.tracks) {
                let expectedStatus: TrackCaptureStatus = interruptedTrackStatuses.contains(
                    before.status
                ) ? .interrupted : before.status
                #expect(after.status == expectedStatus)
                #expect(after.audioRelativePath == before.audioRelativePath)
                #expect(after.byteCount == before.byteCount)
                #expect(after.timestampAnchors == before.timestampAnchors)
            }
        }
        for (url, data) in originalFiles {
            #expect(try Data(contentsOf: url) == data)
        }
        #expect(try await restartedStore.normalizeInterruptedSessions(now: recoveryDate).isEmpty)
    }

    @Test func meetingSessionStoreRejectsFutureSchemaWithoutRewritingIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingFuture-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        var session = makeValidMixedRecordingSession()
        session.schemaVersion = 999
        let paths = try await store.prepareSession(id: session.id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let futureData = try encoder.encode(session)
        try futureData.write(to: paths.manifestURL)

        do {
            _ = try await store.load(sessionID: session.id)
            Issue.record("A future meeting schema must not be accepted")
        } catch let error as MixedRecordingSessionValidationError {
            #expect(error == .unsupportedSchema(999))
        }
        #expect(try Data(contentsOf: paths.manifestURL) == futureData)
    }

    @Test func cancellingMeetingManifestDoesNotDeleteOriginalTracks() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingCancel-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        var session = makeValidMixedRecordingSession()
        let paths = try await store.prepareSession(id: session.id)
        let originalURLs = session.tracks.map {
            paths.sessionDirectory.appendingPathComponent($0.audioRelativePath!)
        }
        for (index, url) in originalURLs.enumerated() {
            try Data("original-\(index)".utf8).write(to: url)
        }
        try await store.create(session)

        session.status = .cancelled
        session.updatedAt = session.updatedAt.addingTimeInterval(1)
        try await store.save(session)

        #expect(try await store.load(sessionID: session.id)?.status == .cancelled)
        #expect(originalURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func meetingSessionStoreResolvesOnlyOriginalTracksAndDeletesOnlySelectedSession() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingDelete-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sentinel = root.appendingPathComponent("keep-me.txt")
        try Data("unrelated".utf8).write(to: sentinel)
        let store = MeetingSessionStore(rootURL: root)

        let selected = makeValidMixedRecordingSession()
        let selectedPaths = try await store.prepareSession(id: selected.id)
        for track in selected.tracks {
            try Data("selected-\(track.role.rawValue)".utf8).write(
                to: selectedPaths.sessionDirectory.appendingPathComponent(track.audioRelativePath!)
            )
        }
        try await store.create(selected)

        var neighbor = makeValidMixedRecordingSession()
        neighbor.id = UUID()
        neighbor.recordID = UUID()
        neighbor.tracks[0].id = UUID()
        neighbor.tracks[1].id = UUID()
        let neighborPaths = try await store.prepareSession(id: neighbor.id)
        for track in neighbor.tracks {
            try Data("neighbor-\(track.role.rawValue)".utf8).write(
                to: neighborPaths.sessionDirectory.appendingPathComponent(track.audioRelativePath!)
            )
        }
        try await store.create(neighbor)

        let microphoneURL = try await store.audioURL(
            sessionID: selected.id,
            role: .localSpeaker
        )
        #expect(microphoneURL == selectedPaths.tracksDirectory
            .appendingPathComponent("microphone.caf")
            .standardizedFileURL.resolvingSymlinksInPath())

        try await store.delete(sessionID: selected.id)
        try await store.delete(sessionID: selected.id)

        #expect(!FileManager.default.fileExists(atPath: selectedPaths.sessionDirectory.path))
        #expect(FileManager.default.fileExists(atPath: neighborPaths.manifestURL.path))
        #expect(FileManager.default.fileExists(atPath: sentinel.path))
    }

    @Test func meetingSessionStoreRejectsTrackPathOutsideOriginalDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingUnsafeTrack-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        var session = makeValidMixedRecordingSession()
        session.tracks[0].audioRelativePath = "derived/not-an-original.caf"
        let paths = try await store.prepareSession(id: session.id)
        try Data("not-original".utf8).write(
            to: paths.sessionDirectory.appendingPathComponent("derived/not-an-original.caf")
        )
        try await store.create(session)

        await #expect(throws: MeetingSessionStoreError.unsafeTrackAudio(.localSpeaker)) {
            _ = try await store.audioURL(sessionID: session.id, role: .localSpeaker)
        }
    }

    @Test func meetingHistoryRecoveryUpdatesOnlyLinkedProductSessions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingHistoryRecovery-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionStore = MeetingSessionStore(
            rootURL: directory.appendingPathComponent("MeetingSessions", isDirectory: true)
        )
        let historyStore = DictationHistoryStore(
            fileURL: directory.appendingPathComponent("dictations.json")
        )
        let synchronizer = MeetingHistorySynchronizer(
            sessionStore: sessionStore,
            historyStore: historyStore
        )

        var linked = makeValidMixedRecordingSession()
        linked.status = .recording
        linked.tracks[0].status = .recording
        linked.tracks[1].status = .recording
        try await sessionStore.create(linked)
        _ = try await synchronizer.sync(
            linked,
            targetBundleIdentifier: "com.example.Editor",
            targetApplicationName: "Editor"
        )

        var diagnostic = makeValidMixedRecordingSession()
        diagnostic.id = UUID()
        diagnostic.recordID = UUID()
        diagnostic.status = .recording
        diagnostic.tracks[0].id = UUID()
        diagnostic.tracks[1].id = UUID()
        diagnostic.tracks[0].status = .recording
        diagnostic.tracks[1].status = .recording
        try await sessionStore.create(diagnostic)

        let recoveryDate = linked.updatedAt.addingTimeInterval(30)
        let recovered = try await synchronizer.recoverLinkedSessions(now: recoveryDate)
        let restored = try #require(try await historyStore.record(id: linked.recordID))

        #expect(recovered.count == 1)
        #expect(restored.meetingSummary?.status == .paused)
        #expect(restored.targetBundleIdentifier == "com.example.Editor")
        #expect(restored.targetApplicationName == "Editor")
        #expect(try await historyStore.record(id: diagnostic.recordID) == nil)
        #expect(try await sessionStore.load(sessionID: diagnostic.id)?.status == .recording)
    }

    @Test func meetingHistoryRefreshUsesManifestWithoutInterruptingActiveCapture() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingHistoryRefresh-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionStore = MeetingSessionStore(
            rootURL: directory.appendingPathComponent("MeetingSessions", isDirectory: true)
        )
        let historyStore = DictationHistoryStore(
            fileURL: directory.appendingPathComponent("dictations.json")
        )
        let synchronizer = MeetingHistorySynchronizer(
            sessionStore: sessionStore, historyStore: historyStore
        )

        var completed = makeCompletedMixedRecordingSession(insertionState: .completed)
        try await sessionStore.create(completed)
        _ = try await synchronizer.sync(completed)
        completed.transcriptInsertionState = .deferred
        try await sessionStore.save(completed)

        var recording = makeValidMixedRecordingSession()
        recording.id = UUID()
        recording.recordID = UUID()
        recording.status = .recording
        for index in recording.tracks.indices {
            recording.tracks[index].status = .recording
        }
        try await sessionStore.create(recording)
        _ = try await synchronizer.sync(recording)

        try await synchronizer.syncLinkedSessions()

        #expect(try await historyStore.record(id: completed.recordID)?
            .meetingSummary?.insertionState == .deferred)
        #expect(try await historyStore.record(id: recording.recordID)?
            .meetingSummary?.status == .recording)
        #expect(try await sessionStore.load(sessionID: recording.id) == recording)
    }

    @Test func interruptedMeetingCaptureRecoveryRepairsMetadataWithoutChangingOriginalTracks() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateInterruptedCapture-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        var session = makeValidMixedRecordingSession()
        session.status = .paused
        session.lastErrorCategory = .interrupted
        session.lastErrorMessage = "Capture interrupted"
        session.synchronization = nil
        session.qualityReport = nil
        let paths = try await store.prepareSession(id: session.id)

        var originalData: [RecordingTrackRole: Data] = [:]
        for index in session.tracks.indices {
            let role = session.tracks[index].role
            let relativePath = role == .localSpeaker
                ? "tracks/microphone.caf"
                : "tracks/system-audio.caf"
            session.tracks[index].status = .interrupted
            session.tracks[index].audioRelativePath = relativePath
            session.tracks[index].formatIdentifier = nil
            session.tracks[index].sampleRate = 0
            session.tracks[index].channelCount = 0
            session.tracks[index].lastHostTime = nil
            session.tracks[index].durationMilliseconds = 0
            session.tracks[index].byteCount = 0
            session.tracks[index].timestampAnchors = [
                TrackTimestampAnchor(
                    hostTime: role == .localSpeaker ? 1_010 : 1_000,
                    trackFramePosition: 0,
                    sessionTimeMilliseconds: role == .localSpeaker ? 10 : 0
                )
            ]
            let url = paths.sessionDirectory.appendingPathComponent(relativePath)
            try writeImpulseCAF(url: url, impulseFrame: role == .localSpeaker ? 10 : 20)
            originalData[role] = try Data(contentsOf: url)
        }
        try await store.create(session)

        let recovery = InterruptedMeetingCaptureRecovery(
            store: store,
            now: { Date(timeIntervalSince1970: 1_800_000_100) }
        )
        let recovered = try await recovery.recover(sessionID: session.id)

        #expect(recovered.status == .paused)
        #expect(recovered.tracks.allSatisfy { $0.status == .finalized })
        #expect(recovered.tracks.allSatisfy {
            $0.formatIdentifier == "lpcm"
                && $0.sampleRate == 48_000
                && $0.channelCount == 1
                && $0.durationMilliseconds == 500
                && $0.byteCount > 0
        })
        #expect(recovered.synchronization?.quality == .degraded)
        #expect(recovered.synchronization?.initialOffsetMilliseconds == 10)
        #expect(recovered.qualityReport?.synchronizationQuality == .degraded)
        for track in recovered.tracks {
            let url = paths.sessionDirectory.appendingPathComponent(track.audioRelativePath!)
            #expect(try Data(contentsOf: url) == originalData[track.role])
        }
    }

    @Test func interruptedCaptureRecoversReadableTrackWhenOtherOriginalIsCorruptOrMissing() async throws {
        let scenarios: [(
            damagedRole: RecordingTrackRole,
            writeCorruptFile: Bool,
            category: DictationErrorCategory
        )] = [
            (.systemAudio, true, .audioCorrupt),
            (.localSpeaker, false, .storageUnavailable)
        ]
        for scenario in scenarios {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("FlowDictatePartialCaptureRecovery-\(UUID())", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = MeetingSessionStore(rootURL: root)
            var session = makeValidMixedRecordingSession()
            session.status = .paused
            session.synchronization = nil
            session.qualityReport = nil
            let paths = try await store.prepareSession(id: session.id)
            let corruptBytes = Data("unreadable preserved original".utf8)
            var readableURL: URL?
            var damagedURL: URL?
            var readableBytes: Data?

            for index in session.tracks.indices {
                let role = session.tracks[index].role
                let relativePath = role == .localSpeaker
                    ? "tracks/microphone.caf" : "tracks/system-audio.caf"
                session.tracks[index].status = .interrupted
                session.tracks[index].audioRelativePath = relativePath
                session.tracks[index].formatIdentifier = nil
                session.tracks[index].sampleRate = 0
                session.tracks[index].channelCount = 0
                session.tracks[index].lastHostTime = nil
                session.tracks[index].durationMilliseconds = 0
                session.tracks[index].byteCount = 0
                session.tracks[index].timestampAnchors = [TrackTimestampAnchor(
                    hostTime: role == .localSpeaker ? 1_010 : 1_000,
                    trackFramePosition: 0,
                    sessionTimeMilliseconds: role == .localSpeaker ? 10 : 0
                )]
                let url = paths.sessionDirectory.appendingPathComponent(relativePath)
                if role == scenario.damagedRole {
                    damagedURL = url
                    if scenario.writeCorruptFile {
                        try corruptBytes.write(to: url)
                    }
                } else {
                    try writeImpulseCAF(url: url, impulseFrame: 10)
                    readableURL = url
                    readableBytes = try Data(contentsOf: url)
                }
            }
            try await store.create(session)
            let recovery = InterruptedMeetingCaptureRecovery(
                store: store,
                now: { Date(timeIntervalSince1970: 1_800_000_100) }
            )

            let recovered = try await recovery.recover(sessionID: session.id)
            let damaged = try #require(recovered.tracks.first {
                $0.role == scenario.damagedRole
            })
            let readable = try #require(recovered.tracks.first {
                $0.role != scenario.damagedRole
            })
            #expect(recovered.status == .paused)
            #expect(recovered.lastErrorCategory == scenario.category)
            #expect(damaged.status == .unavailable)
            #expect(damaged.errorCategory == scenario.category)
            #expect(readable.status == .finalized)
            #expect(readable.byteCount > 0)
            let readableFile = try #require(readableURL)
            let originalReadableBytes = try #require(readableBytes)
            let damagedFile = try #require(damagedURL)
            #expect(try Data(contentsOf: readableFile) == originalReadableBytes)
            if scenario.writeCorruptFile {
                #expect(try Data(contentsOf: damagedFile) == corruptBytes)
            } else {
                #expect(!FileManager.default.fileExists(atPath: damagedFile.path))
            }
            #expect(try await recovery.recover(sessionID: session.id) == recovered)

            let executor = MockTrackTranscriptionExecutor(behaviors: [
                readable.role: [.success("Recovered surviving track")]
            ])
            let processed = try await TrackTranscriptionRunner(
                store: store,
                executor: executor,
                now: { Date(timeIntervalSince1970: 1_800_000_101) }
            ).run(sessionID: session.id)
            #expect(processed.status == .partial)
            #expect(processed.lastErrorCategory == scenario.category)
            #expect(processed.tracks.first(where: { $0.role == readable.role })?.status == .transcribed)
            #expect(processed.tracks.first(where: { $0.role == scenario.damagedRole })?.status == .unavailable)
            #expect(await executor.requests.map(\.role) == [readable.role])
        }
    }

    @Test func meetingProcessingWorkflowPublishesTranscriptionAndMergeBoundaries() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingWorkflow-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionStore = MeetingSessionStore(
            rootURL: directory.appendingPathComponent("MeetingSessions", isDirectory: true)
        )
        let historyStore = DictationHistoryStore(
            fileURL: directory.appendingPathComponent("dictations.json")
        )
        let synchronizer = MeetingHistorySynchronizer(
            sessionStore: sessionStore,
            historyStore: historyStore
        )
        var initial = makeValidMixedRecordingSession()
        initial.status = .queued
        try await sessionStore.create(initial)

        var transcribed = initial
        transcribed.status = .merging
        transcribed.updatedAt = initial.updatedAt.addingTimeInterval(1)
        for index in transcribed.tracks.indices {
            transcribed.tracks[index].status = .transcribed
            transcribed.tracks[index].transcriptionSessionID = UUID()
            transcribed.tracks[index].transcriptRelativePath =
                "transcription/\(transcribed.tracks[index].role.rawValue)-transcript.json"
        }
        var completed = transcribed
        completed.status = .completed
        completed.updatedAt = transcribed.updatedAt.addingTimeInterval(1)
        completed.completionMode = .allTracks
        completed.mergedTimelineRelativePath = MeetingTranscriptMergeRunner.timelineRelativePath
        completed.finalTranscript = "[You] Hello\n[System Audio] Welcome"
        completed.transcriptInsertionState = .ready
        completed.transcriptInsertionAttemptCount = 0

        let trackRunner = StubMeetingTrackRunner(result: transcribed)
        let mergeRunner = StubMeetingMergeRunner(result: completed)
        let workflow = MeetingProcessingWorkflow(
            sessionStore: sessionStore,
            trackRunner: trackRunner,
            mergeRunner: mergeRunner,
            historySynchronizer: synchronizer
        )

        let result = try await workflow.run(sessionID: initial.id)
        let record = try #require(try await historyStore.record(id: initial.recordID))

        #expect(result == completed)
        #expect(await trackRunner.runCount == 1)
        #expect(await mergeRunner.runCount == 1)
        #expect(record.meetingSummary?.status == .completed)
        #expect(record.meetingSummary?.insertionState == .ready)
        #expect(record.finalText == completed.finalTranscript)
    }

    @Test func meetingHistorySyncDoesNotRehydrateArchivedTranscript() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingArchive-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionStore = MeetingSessionStore(
            rootURL: directory.appendingPathComponent("MeetingSessions", isDirectory: true)
        )
        let historyStore = DictationHistoryStore(
            fileURL: directory.appendingPathComponent("dictations.json")
        )
        let synchronizer = MeetingHistorySynchronizer(
            sessionStore: sessionStore,
            historyStore: historyStore
        )
        var session = makeValidMixedRecordingSession()
        session.status = .completed
        session.completionMode = .allTracks
        session.mergedTimelineRelativePath = MeetingTranscriptMergeRunner.timelineRelativePath
        session.finalTranscript = "Private meeting timeline"
        session.transcriptInsertionState = .completed
        session.transcriptInsertionAttemptCount = 1
        for index in session.tracks.indices {
            session.tracks[index].status = .transcribed
            session.tracks[index].transcriptionSessionID = UUID()
            session.tracks[index].transcriptRelativePath =
                "transcription/\(session.tracks[index].role.rawValue)-transcript.json"
        }
        try await sessionStore.create(session)
        _ = try await synchronizer.sync(
            session,
            targetBundleIdentifier: "com.example.Editor",
            targetApplicationName: "Editor"
        )
        try await historyStore.archive(id: session.recordID)

        _ = try await synchronizer.sync(session)
        let archived = try #require(
            try await historyStore.all(includeArchived: true).first
        )

        #expect(archived.archivedAt != nil)
        #expect(archived.finalText == nil)
        #expect(archived.originalTranscript == nil)
        #expect(archived.targetBundleIdentifier == nil)
        #expect(archived.targetApplicationName == nil)
        #expect(try await sessionStore.load(sessionID: session.id) == session)
    }

    @Test func trackTranscriptionRunnerPersistsIndependentResultsAndFrozenConfiguration() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateTrackTranscription-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeTrackTranscriptionFixture(rootURL: root)
        let executor = MockTrackTranscriptionExecutor(behaviors: [
            .localSpeaker: [.success("Local speaker transcript")],
            .systemAudio: [.success("System Audio transcript")]
        ])
        let runner = TrackTranscriptionRunner(
            store: fixture.store,
            executor: executor,
            now: { Date(timeIntervalSince1970: 1_800_000_100) }
        )

        let result = try await runner.run(sessionID: fixture.session.id)
        let requests = await executor.requests

        #expect(result.status == .merging)
        #expect(result.tracks.allSatisfy { $0.status == .transcribed })
        #expect(requests.map(\.role) == [.localSpeaker, .systemAudio])
        #expect(Set(requests.map(\.transcriptionSessionID)).count == 2)
        #expect(requests.allSatisfy {
            $0.providerID == fixture.session.providerID
                && $0.engineID == fixture.session.engineID
                && $0.modelID == fixture.session.modelID
                && $0.language == fixture.session.language
                && $0.privacyMode == fixture.session.privacyMode
                && $0.profileID == fixture.session.profileID
        })

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for track in result.tracks {
            let relativePath = try #require(track.transcriptRelativePath)
            let artifact = try decoder.decode(
                MeetingTrackTranscript.self,
                from: Data(contentsOf: fixture.paths.sessionDirectory.appendingPathComponent(relativePath))
            )
            #expect(artifact.meetingSessionID == result.id)
            #expect(artifact.trackID == track.id)
            #expect(artifact.role == track.role)
            #expect(artifact.transcriptionSessionID == track.transcriptionSessionID)
            #expect(artifact.segmentCount == 2)
            #expect(artifact.completedSegmentCount == 2)
        }
    }

    @Test func partialMeetingHistoryExplainsThatOnlyFailedTrackWorkWillRetry() throws {
        var session = makeValidMixedRecordingSession()
        session.status = .partial
        let microphoneIndex = try #require(
            session.tracks.firstIndex(where: { $0.role == .localSpeaker })
        )
        session.tracks[microphoneIndex].status = .transcribed
        session.tracks[microphoneIndex].transcriptionSessionID = UUID()
        session.tracks[microphoneIndex].transcriptRelativePath =
            "transcription/localSpeaker-transcript.json"
        let systemIndex = try #require(
            session.tracks.firstIndex(where: { $0.role == .systemAudio })
        )
        session.tracks[systemIndex].status = .failed
        session.tracks[systemIndex].errorCategory = .network
        session.tracks[systemIndex].errorMessage = "Injected test failure"

        let summary = try MeetingHistorySummary(session: session).validated()

        #expect(summary.statusTitle == "Partial transcription")
        #expect(summary.processingActionTitle == "Retry Failed Track")
        #expect(summary.processingNotice
            == "1 of 2 tracks transcribed. Retrying keeps completed track work.")
        #expect(summary.canResumeProcessing)

        var capturePartial = makeValidMixedRecordingSession()
        capturePartial.status = .partial
        let captureSystemIndex = try #require(
            capturePartial.tracks.firstIndex(where: { $0.role == .systemAudio })
        )
        capturePartial.tracks[captureSystemIndex].status = .failed
        let captureSummary = try MeetingHistorySummary(session: capturePartial).validated()
        #expect(captureSummary.statusTitle == "Partial recording")
        #expect(captureSummary.processingActionTitle == "Continue Processing")
        #expect(captureSummary.processingNotice == nil)
    }

    @Test func meetingHistorySurfacesTrackLossAndClippingWithoutHidingPreservedTracks() throws {
        var session = makeValidMixedRecordingSession()
        session.status = .partial
        let microphoneIndex = try #require(
            session.tracks.firstIndex(where: { $0.role == .localSpeaker })
        )
        session.tracks[microphoneIndex].quality.clippedFrameCount = 48
        let systemIndex = try #require(
            session.tracks.firstIndex(where: { $0.role == .systemAudio })
        )
        session.tracks[systemIndex].status = .failed

        let summary = try MeetingHistorySummary(session: session).validated()

        #expect(summary.captureWarningNotices == [
            "Microphone clipping was detected. The original track was preserved; review its audio quality.",
            "System Audio was not fully captured. Any available original track remains preserved."
        ])
        #expect(summary.tracks.first(where: { $0.role == .localSpeaker })?.canPlayAudio == true)
        #expect(summary.tracks.first(where: { $0.role == .systemAudio })?.canPlayAudio == true)
    }

    @Test func trackTranscriptionOwnsExclusiveQueueLaneAndReleasesIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateTrackQueue-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeTrackTranscriptionFixture(
            rootURL: root.appendingPathComponent("meetings", isDirectory: true)
        )
        let jobStore = DictationJobStore(
            directory: root.appendingPathComponent("jobs", isDirectory: true)
        )
        let queue = DictationProcessingQueue(store: jobStore)
        let executor = QueueAssertingTrackTranscriptionExecutor(queue: queue)
        let runner = TrackTranscriptionRunner(
            store: fixture.store,
            executor: executor,
            processingQueue: queue
        )

        let result = try await runner.run(sessionID: fixture.session.id)

        #expect(result.status == .merging)
        #expect(await executor.blockedReservationCount == 2)
        #expect(try await queue.snapshot().totalActiveCount == 0)
        _ = try await queue.reserveRecordingSlot()
        #expect(try await queue.snapshot().reservationCount == 1)
        _ = try await queue.releaseRecordingSlot()
    }

    @Test func trackTranscriptionFailureDoesNotDiscardOtherTrackAndRetrySkipsSuccess() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateTrackRetry-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeTrackTranscriptionFixture(rootURL: root)
        let executor = MockTrackTranscriptionExecutor(behaviors: [
            .localSpeaker: [.success("Kept microphone transcript")],
            .systemAudio: [.networkFailure, .success("Recovered System Audio transcript")]
        ])
        let runner = TrackTranscriptionRunner(store: fixture.store, executor: executor)

        let partial = try await runner.run(sessionID: fixture.session.id)
        let firstMicrophone = try #require(
            partial.tracks.first(where: { $0.role == .localSpeaker })
        )
        let firstSystemAudio = try #require(
            partial.tracks.first(where: { $0.role == .systemAudio })
        )
        #expect(partial.status == .partial)
        #expect(firstMicrophone.status == .transcribed)
        #expect(firstSystemAudio.status == .failed)
        #expect(firstSystemAudio.errorCategory == .network)
        #expect(FileManager.default.fileExists(atPath: fixture.paths.sessionDirectory
            .appendingPathComponent(try #require(firstMicrophone.transcriptRelativePath)).path))

        let recovered = try await runner.run(sessionID: fixture.session.id)
        let requests = await executor.requests
        let recoveredSystemAudio = try #require(
            recovered.tracks.first(where: { $0.role == .systemAudio })
        )

        #expect(recovered.status == .merging)
        #expect(recovered.tracks.allSatisfy { $0.status == .transcribed })
        #expect(requests.map(\.role) == [.localSpeaker, .systemAudio, .systemAudio])
        #expect(requests[1].transcriptionSessionID == requests[2].transcriptionSessionID)
        #expect(recoveredSystemAudio.transcriptionSessionID == firstSystemAudio.transcriptionSessionID)
        #expect(recovered.tracks.first(where: { $0.role == .localSpeaker })?.transcriptionSessionID
            == firstMicrophone.transcriptionSessionID)
    }

#if DEBUG
    @Test func debugOneShotTrackFailureExercisesPartialThenRetryWithoutRepeatingSuccess() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateDebugTrackRetry-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeTrackTranscriptionFixture(rootURL: root)
        let base = MockTrackTranscriptionExecutor(behaviors: [
            .localSpeaker: [.success("Kept microphone transcript")],
            .systemAudio: [.success("Recovered System Audio transcript")]
        ])
        let executor = DebugOneShotTrackTranscriptionFailureExecutor(
            base: base,
            failing: .systemAudio
        )
        let runner = TrackTranscriptionRunner(store: fixture.store, executor: executor)

        let partial = try await runner.run(sessionID: fixture.session.id)
        #expect(partial.status == .partial)
        #expect(partial.tracks.first(where: { $0.role == .localSpeaker })?.status == .transcribed)
        #expect(partial.tracks.first(where: { $0.role == .systemAudio })?.status == .failed)
        #expect(partial.tracks.first(where: { $0.role == .systemAudio })?.errorCategory == .network)

        let recovered = try await runner.run(sessionID: fixture.session.id)
        let requests = await base.requests

        #expect(recovered.status == .merging)
        #expect(recovered.tracks.allSatisfy { $0.status == .transcribed })
        #expect(requests.map(\.role) == [.localSpeaker, .systemAudio])
    }
#endif

    @Test func cancellingTrackTranscriptionPreservesCompletedTrackAndResumeIdentity() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateTrackCancel-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeTrackTranscriptionFixture(rootURL: root)
        let executor = MockTrackTranscriptionExecutor(behaviors: [
            .localSpeaker: [.success("Completed before cancellation")],
            .systemAudio: [.cancellation]
        ])
        let runner = TrackTranscriptionRunner(store: fixture.store, executor: executor)

        await #expect(throws: CancellationError.self) {
            _ = try await runner.run(sessionID: fixture.session.id)
        }
        let paused = try #require(try await fixture.store.load(sessionID: fixture.session.id))
        let microphone = try #require(
            paused.tracks.first(where: { $0.role == .localSpeaker })
        )
        let systemAudio = try #require(
            paused.tracks.first(where: { $0.role == .systemAudio })
        )

        #expect(paused.status == .paused)
        #expect(microphone.status == .transcribed)
        #expect(systemAudio.status == .interrupted)
        #expect(systemAudio.errorCategory == .interrupted)
        #expect(microphone.transcriptRelativePath != nil)
        #expect(systemAudio.transcriptionSessionID != nil)
    }

    @MainActor
    @Test func longFormTrackExecutorUsesExistingPipelineWithoutUserHistoryRows() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateTrackAdapter-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeTrackTranscriptionFixture(rootURL: root)
        let provider = MockTranscriptionProvider()
        let executor = LongFormTrackTranscriptionExecutor(maximumAttempts: 1) { request in
            #expect(request.providerID == TranscriptionProviderID.local.rawValue)
            #expect(request.privacyMode == .offline)
            return provider
        }
        let runner = TrackTranscriptionRunner(store: fixture.store, executor: executor)

        let result = try await runner.run(sessionID: fixture.session.id)
        let isolatedHistoryURL = fixture.paths.transcriptionDirectory
            .appendingPathComponent("track-workflows/records.json")

        #expect(result.status == .merging)
        #expect(result.tracks.allSatisfy { $0.status == .transcribed })
        #expect(provider.transcribeCount == 2)
        #expect(FileManager.default.fileExists(atPath: isolatedHistoryURL.path))
    }

    @MainActor
    @Test func localTrackProviderWordTimingReachesMeetingTranscriptArtifact() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateTrackTiming-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeTrackTranscriptionFixture(rootURL: root)
        let provider = TimedTrackTranscriptionProvider()
        let executor = LongFormTrackTranscriptionExecutor(maximumAttempts: 1) { _ in provider }
        let runner = TrackTranscriptionRunner(store: fixture.store, executor: executor)

        let result = try await runner.run(sessionID: fixture.session.id)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for track in result.tracks {
            let relativePath = try #require(track.transcriptRelativePath)
            let artifact = try decoder.decode(
                MeetingTrackTranscript.self,
                from: Data(contentsOf: fixture.paths.sessionDirectory
                    .appendingPathComponent(relativePath))
            )
            let entries = try #require(artifact.timedEntries)
            #expect(entries.map(\.text) == ["Timed", "words."])
            #expect(entries.map(\.precision) == [.word, .word])
            #expect(entries.map(\.startMilliseconds) == [100, 400])
        }
    }

    @MainActor
    @Test func longFormTrackKeepsWordTimingAcrossSegmentsAndCachedResume() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateLongFormTiming-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeLongFormTrackTranscriptionFixture(
            rootURL: root,
            providerID: TranscriptionProviderID.local.rawValue,
            engineID: TranscriptionProviderRegistry.local.capabilities.engineID,
            modelID: "timed-local-test",
            privacyMode: .offline
        )
        var configuration = LongFormConfiguration.default
        configuration.targetDurationMilliseconds = 2_000
        configuration.minimumDurationMilliseconds = 1_000
        configuration.maximumDurationMilliseconds = 3_000
        configuration.boundarySearchRadiusMilliseconds = 0
        configuration.fallbackOverlapMilliseconds = 100
        configuration.softUploadByteLimit = 100_000
        configuration.hardUploadByteLimit = 1_000_000
        configuration.workingStorageReserveBytes = 0
        let provider = TimedTrackTranscriptionProvider()
        let executor = LongFormTrackTranscriptionExecutor(
            maximumAttempts: 1,
            longFormConfiguration: configuration
        ) { _ in provider }
        let runner = TrackTranscriptionRunner(store: fixture.store, executor: executor)
        let result = try await runner.run(sessionID: fixture.session.id)
        #expect(result.status == .merging)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for track in result.tracks {
            let relativePath = try #require(track.transcriptRelativePath)
            let artifact = try decoder.decode(
                MeetingTrackTranscript.self,
                from: Data(contentsOf: fixture.paths.sessionDirectory
                    .appendingPathComponent(relativePath))
            )
            let entries = try #require(artifact.timedEntries)
            #expect(entries.map(\.precision) == [.word, .word, .word, .word])
            #expect(entries.map(\.startMilliseconds) == [100, 400, 2_000, 2_300])

            let request = TrackTranscriptionRequest(
                meetingSessionID: fixture.session.id,
                trackID: track.id,
                role: track.role,
                audioURL: fixture.paths.sessionDirectory.appendingPathComponent(
                    try #require(track.audioRelativePath)
                ),
                audioRelativePath: try #require(track.audioRelativePath),
                durationMilliseconds: track.durationMilliseconds,
                byteCount: track.byteCount,
                sampleRate: track.sampleRate,
                channelCount: track.channelCount,
                transcriptionDirectory: fixture.paths.transcriptionDirectory,
                transcriptionSessionID: try #require(track.transcriptionSessionID),
                providerID: fixture.session.providerID,
                engineID: fixture.session.engineID,
                modelID: fixture.session.modelID,
                language: fixture.session.language,
                privacyMode: try #require(fixture.session.privacyMode),
                profileID: fixture.session.profileID
            )
            let cached = try await executor.transcribe(request)
            #expect(cached.timedEntries == entries)
        }
    }

    @MainActor
    @Test func longFormTimingDropsWordsStartingInsideSegmentOverlap() async throws {
        var configuration = LongFormConfiguration.default
        configuration.targetDurationMilliseconds = 2_000
        configuration.minimumDurationMilliseconds = 1_000
        configuration.maximumDurationMilliseconds = 3_000
        configuration.boundarySearchRadiusMilliseconds = 0
        configuration.fallbackOverlapMilliseconds = 100
        var segments = try await AudioSegmentPlanner(configuration: configuration)
            .plan(durationMilliseconds: 4_000)
        #expect(segments.count == 2)
        segments[0].status = .succeeded
        segments[0].transcript = "Previous."
        segments[0].timedUnits = [TranscriptionTimedUnit(
            text: "Previous.", startMilliseconds: 1_970,
            endMilliseconds: 1_990, precision: .word
        )]
        segments[1].status = .succeeded
        segments[1].transcript = "Overlap Next. Edge."
        segments[1].timedUnits = [
            TranscriptionTimedUnit(
                text: "Overlap", startMilliseconds: 50,
                endMilliseconds: 120, precision: .word
            ),
            TranscriptionTimedUnit(
                text: "Next.", startMilliseconds: 120,
                endMilliseconds: 250, precision: .word
            ),
            TranscriptionTimedUnit(
                text: "Edge.", startMilliseconds: 2_070,
                endMilliseconds: 2_147, precision: .word
            )
        ]

        let units = LongFormTranscriptionRunner.timedUnits(from: segments)
        #expect(units.map(\.text) == ["Previous.", "Next.", "Edge."])
        #expect(units.map(\.startMilliseconds) == [1_970, 2_020, 3_970])
        #expect(units.last?.endMilliseconds == 4_000)
    }

    @MainActor
    @Test func twoTrackLongFormRestartSkipsSuccessfulSegmentsForLocalAndOpenAI() async throws {
        let scenarios: [(
            name: String,
            providerID: String,
            engineID: String,
            modelID: String,
            privacyMode: PrivacyMode,
            resultProviderID: String
        )] = [
            (
                "local",
                TranscriptionProviderID.local.rawValue,
                TranscriptionProviderRegistry.local.capabilities.engineID,
                "parakeet-tdt-0.6b-v3-coreml",
                .offline,
                TranscriptionProviderID.local.rawValue
            ),
            (
                "openai",
                TranscriptionProviderID.openAI.rawValue,
                TranscriptionProviderRegistry.openAI.capabilities.engineID,
                "gpt-4o-mini-transcribe",
                .cloudTranscription,
                "OpenAI"
            )
        ]
        var configuration = LongFormConfiguration.default
        configuration.targetDurationMilliseconds = 2_000
        configuration.minimumDurationMilliseconds = 1_000
        configuration.maximumDurationMilliseconds = 3_000
        configuration.boundarySearchRadiusMilliseconds = 0
        configuration.fallbackOverlapMilliseconds = 100
        configuration.softUploadByteLimit = 100_000
        configuration.hardUploadByteLimit = 1_000_000
        configuration.workingStorageReserveBytes = 0

        for scenario in scenarios {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "FlowDictateTrackLongForm-\(scenario.name)-\(UUID())",
                isDirectory: true
            )
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = try await makeLongFormTrackTranscriptionFixture(
                rootURL: root,
                providerID: scenario.providerID,
                engineID: scenario.engineID,
                modelID: scenario.modelID,
                privacyMode: scenario.privacyMode
            )
            // The deliberately empty second provider response must remain a
            // failure for audible audio; a silent fixture would now be skipped.
            let audibleFormat = try #require(AVAudioFormat(
                standardFormatWithSampleRate: 16_000, channels: 1
            ))
            for track in fixture.session.tracks {
                let relativePath = try #require(track.audioRelativePath)
                let url = fixture.paths.sessionDirectory.appendingPathComponent(relativePath)
                let file = try AVAudioFile(forWriting: url, settings: audibleFormat.settings)
                let buffer = try #require(AVAudioPCMBuffer(
                    pcmFormat: audibleFormat, frameCapacity: 80_000
                ))
                buffer.frameLength = buffer.frameCapacity
                let samples = try #require(buffer.floatChannelData?[0])
                for frame in 0..<Int(buffer.frameLength) { samples[frame] = 0.05 }
                try file.write(from: buffer)
            }
            let firstMicrophone = SequenceTranscriptionProvider(
                texts: ["Microphone shared boundary phrase."],
                providerID: scenario.resultProviderID,
                modelID: scenario.modelID
            )
            let firstSystemAudio = SequenceTranscriptionProvider(
                texts: ["System Audio shared boundary phrase."],
                providerID: scenario.resultProviderID,
                modelID: scenario.modelID
            )
            let firstExecutor = LongFormTrackTranscriptionExecutor(
                maximumAttempts: 1,
                longFormConfiguration: configuration
            ) { request in
                request.role == .localSpeaker ? firstMicrophone : firstSystemAudio
            }
            let firstRunner = TrackTranscriptionRunner(
                store: fixture.store,
                executor: firstExecutor
            )

            let failed = try await firstRunner.run(sessionID: fixture.session.id)
            #expect(failed.status == .failed)
            #expect(failed.tracks.allSatisfy { $0.status == .failed })
            #expect(firstMicrophone.requestCount == 2)
            #expect(firstSystemAudio.requestCount == 2)
            #expect(firstMicrophone.transcribeCount == 1)
            #expect(firstSystemAudio.transcribeCount == 1)

            let longFormStore = TranscriptionSessionStore(
                rootURL: fixture.paths.transcriptionDirectory
                    .appendingPathComponent("track-workflows/long-form", isDirectory: true)
            )
            for track in failed.tracks {
                let workflowID = try #require(track.transcriptionSessionID)
                let manifest = try #require(
                    try await longFormStore.load(recordID: workflowID)
                )
                #expect(manifest.segments.count == 2)
                #expect(manifest.completedSegmentCount == 1)
                #expect(manifest.segments[0].status == .succeeded)
            }

            // New executor and runner instances model an app restart. Both use
            // only one result: repeating segment zero would make this run fail.
            let resumedMicrophone = SequenceTranscriptionProvider(
                texts: ["shared boundary phrase. Microphone end."],
                providerID: scenario.resultProviderID,
                modelID: scenario.modelID
            )
            let resumedSystemAudio = SequenceTranscriptionProvider(
                texts: ["shared boundary phrase. System Audio end."],
                providerID: scenario.resultProviderID,
                modelID: scenario.modelID
            )
            let resumedExecutor = LongFormTrackTranscriptionExecutor(
                maximumAttempts: 1,
                longFormConfiguration: configuration
            ) { request in
                request.role == .localSpeaker ? resumedMicrophone : resumedSystemAudio
            }
            let resumedRunner = TrackTranscriptionRunner(
                store: fixture.store,
                executor: resumedExecutor
            )

            let completed = try await resumedRunner.run(sessionID: fixture.session.id)
            #expect(completed.status == .merging)
            #expect(completed.tracks.allSatisfy { $0.status == .transcribed })
            #expect(resumedMicrophone.requestCount == 1)
            #expect(resumedSystemAudio.requestCount == 1)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            for track in completed.tracks {
                let relativePath = try #require(track.transcriptRelativePath)
                let artifact = try decoder.decode(
                    MeetingTrackTranscript.self,
                    from: Data(contentsOf: fixture.paths.sessionDirectory
                        .appendingPathComponent(relativePath))
                )
                #expect(artifact.segmentCount == 2)
                #expect(artifact.completedSegmentCount == 2)
            }
        }
    }

    @MainActor
    @Test func meetingLongFormAcceptsSilentMicrophoneTrackWithoutLosingSystemSpeech() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSilentMeetingTrack-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeLongFormTrackTranscriptionFixture(
            rootURL: root,
            providerID: TranscriptionProviderID.local.rawValue,
            engineID: TranscriptionProviderRegistry.local.capabilities.engineID,
            modelID: "parakeet-tdt-0.6b-v3-coreml",
            privacyMode: .offline
        )
        var configuration = LongFormConfiguration.default
        configuration.targetDurationMilliseconds = 2_000
        configuration.minimumDurationMilliseconds = 1_000
        configuration.maximumDurationMilliseconds = 3_000
        configuration.boundarySearchRadiusMilliseconds = 0
        configuration.fallbackOverlapMilliseconds = 100
        configuration.softUploadByteLimit = 100_000
        configuration.hardUploadByteLimit = 1_000_000
        configuration.workingStorageReserveBytes = 0
        let microphone = SequenceTranscriptionProvider(texts: ["", ""])
        let systemAudio = SequenceTranscriptionProvider(texts: ["Remote first.", "Remote second."])
        let executor = LongFormTrackTranscriptionExecutor(
            maximumAttempts: 1, longFormConfiguration: configuration
        ) { request in
            request.role == .localSpeaker ? microphone : systemAudio
        }
        let completed = try await TrackTranscriptionRunner(
            store: fixture.store, executor: executor
        ).run(sessionID: fixture.session.id)
        #expect(completed.status == .merging)
        #expect(completed.tracks.allSatisfy { $0.status == .transcribed })
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let microphoneTrack = try #require(completed.tracks.first { $0.role == .localSpeaker })
        let relativePath = try #require(microphoneTrack.transcriptRelativePath)
        let transcript = try decoder.decode(
            MeetingTrackTranscript.self,
            from: Data(contentsOf: fixture.paths.sessionDirectory.appendingPathComponent(relativePath))
        )
        #expect(transcript.isSilent == true)
        #expect(transcript.transcript.isEmpty)
        #expect(transcript.segmentCount == 2)
        #expect(transcript.completedSegmentCount == 2)
        #expect(microphone.requestCount == 2)
        #expect(systemAudio.requestCount == 2)
    }

    @MainActor
    @Test func shortMeetingWithOnlyMicrophoneSpeechSkipsSilentSystemTrack() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSilentShortTrack-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeLongFormTrackTranscriptionFixture(
            rootURL: root,
            providerID: TranscriptionProviderID.local.rawValue,
            engineID: TranscriptionProviderRegistry.local.capabilities.engineID,
            modelID: "parakeet-tdt-0.6b-v3-coreml",
            privacyMode: .offline
        )
        let microphoneURL = fixture.paths.sessionDirectory.appendingPathComponent(
            "tracks/microphone.caf"
        )
        let format = try #require(AVAudioFormat(
            standardFormatWithSampleRate: 16_000, channels: 1
        ))
        do {
            let file = try AVAudioFile(forWriting: microphoneURL, settings: format.settings)
            let buffer = try #require(AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: 80_000
            ))
            buffer.frameLength = buffer.frameCapacity
            let samples = try #require(buffer.floatChannelData?[0])
            for frame in 0..<Int(buffer.frameLength) { samples[frame] = 0.05 }
            try file.write(from: buffer)
        }

        let microphone = SequenceTranscriptionProvider(
            texts: ["Only the microphone has speech."],
            providerID: TranscriptionProviderID.local.rawValue,
            modelID: fixture.session.modelID
        )
        let systemAudio = SequenceTranscriptionProvider(texts: ["Should not be requested."])
        let executor = LongFormTrackTranscriptionExecutor(maximumAttempts: 1) { request in
            request.role == .localSpeaker ? microphone : systemAudio
        }
        let transcribed = try await TrackTranscriptionRunner(
            store: fixture.store, executor: executor
        ).run(sessionID: fixture.session.id)

        #expect(transcribed.status == .merging)
        #expect(transcribed.tracks.allSatisfy { $0.status == .transcribed })
        #expect(microphone.requestCount == 1)
        #expect(systemAudio.requestCount == 0)
        let systemTrack = try #require(
            transcribed.tracks.first { $0.role == .systemAudio }
        )
        let systemTranscriptPath = try #require(systemTrack.transcriptRelativePath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let systemTranscript = try decoder.decode(
            MeetingTrackTranscript.self,
            from: Data(contentsOf: fixture.paths.sessionDirectory.appendingPathComponent(
                systemTranscriptPath
            ))
        )
        #expect(systemTranscript.isSilent == true)
        #expect(systemTranscript.transcript.isEmpty)

        let completed = try await MeetingTranscriptMergeRunner(store: fixture.store)
            .run(sessionID: fixture.session.id)
        #expect(completed.status == .completed)
        #expect(completed.finalTranscript == "[You] Only the microphone has speech.")
        #expect(FileManager.default.fileExists(atPath: microphoneURL.path))
        let systemAudioPath = try #require(systemTrack.audioRelativePath)
        #expect(FileManager.default.fileExists(atPath: fixture.paths.sessionDirectory
            .appendingPathComponent(systemAudioPath).path))
    }

    @MainActor
    @Test func retryOfPreviouslyFailedSilentTrackKeepsMicrophoneTranscript() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSilentTrackRetry-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeLongFormTrackTranscriptionFixture(
            rootURL: root,
            providerID: TranscriptionProviderID.local.rawValue,
            engineID: TranscriptionProviderRegistry.local.capabilities.engineID,
            modelID: "parakeet-tdt-0.6b-v3-coreml",
            privacyMode: .offline
        )
        var session = fixture.session
        session.status = .partial
        let microphoneIndex = try #require(session.tracks.firstIndex { $0.role == .localSpeaker })
        let systemIndex = try #require(session.tracks.firstIndex { $0.role == .systemAudio })
        session.tracks[microphoneIndex].status = .transcribed
        session.tracks[microphoneIndex].transcriptionSessionID = UUID()
        session.tracks[microphoneIndex].transcriptRelativePath =
            "transcription/localSpeaker-transcript.json"
        session.tracks[systemIndex].status = .failed
        session.tracks[systemIndex].errorCategory = .providerPermanent
        session.tracks[systemIndex].errorMessage = "The transcription service returned no text."
        session.lastErrorCategory = .providerPermanent
        session.lastErrorMessage = session.tracks[systemIndex].errorMessage
        try await fixture.store.save(session)

        let microphoneTranscript = makeMeetingTrackTranscript(
            session: session,
            role: .localSpeaker,
            text: "Previously transcribed microphone speech.",
            entries: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let transcriptURL = fixture.paths.sessionDirectory.appendingPathComponent(
            try #require(session.tracks[microphoneIndex].transcriptRelativePath)
        )
        let originalTranscriptData = try encoder.encode(microphoneTranscript)
        try originalTranscriptData.write(to: transcriptURL)

        let provider = SequenceTranscriptionProvider(texts: ["Should not be requested."])
        let executor = LongFormTrackTranscriptionExecutor(maximumAttempts: 1) { _ in provider }
        let transcribed = try await TrackTranscriptionRunner(
            store: fixture.store, executor: executor
        ).run(sessionID: session.id)
        #expect(transcribed.status == .merging)
        #expect(transcribed.tracks.allSatisfy { $0.status == .transcribed })
        #expect(provider.requestCount == 0)
        #expect(try Data(contentsOf: transcriptURL) == originalTranscriptData)

        let completed = try await MeetingTranscriptMergeRunner(store: fixture.store)
            .run(sessionID: session.id)
        #expect(completed.status == .completed)
        #expect(completed.finalTranscript == "[You] Previously transcribed microphone speech.")
    }

    @MainActor
    @Test func longFormTrackExecutorBlocksCloudBeforeResolvingProviderWhenOffline() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateTrackPrivacy-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeTrackTranscriptionFixture(rootURL: root)
        var session = fixture.session
        session.providerID = TranscriptionProviderID.openAI.rawValue
        session.engineID = TranscriptionProviderRegistry.openAI.capabilities.engineID
        session.modelID = "gpt-4o-mini-transcribe"
        session.privacyMode = .offline
        try await fixture.store.save(session)
        let provider = MockTranscriptionProvider()
        let resolver = TrackProviderResolverProbe(provider: provider)
        let executor = LongFormTrackTranscriptionExecutor(maximumAttempts: 1) { request in
            await resolver.resolve(request)
        }
        let runner = TrackTranscriptionRunner(store: fixture.store, executor: executor)

        let result = try await runner.run(sessionID: session.id)

        #expect(result.status == .failed)
        #expect(result.tracks.allSatisfy {
            $0.status == .failed && $0.errorCategory == .networkBlocked
        })
        #expect(await resolver.resolveCount == 0)
        #expect(provider.transcribeCount == 0)
    }

    @MainActor
    @Test func meetingTrackProviderPolicyMatrixFreezesModeForBothRoles() async throws {
        let scenarios: [(
            provider: TranscriptionProviderID,
            privacy: PrivacyMode,
            allowed: Bool
        )] = [
            (.local, .offline, true),
            (.local, .localWithOptionalCloudEnhancement, true),
            (.local, .cloudTranscription, true),
            (.openAI, .offline, false),
            (.openAI, .localWithOptionalCloudEnhancement, false),
            (.openAI, .cloudTranscription, true)
        ]
        for scenario in scenarios {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("FlowDictateMeetingPolicy-\(UUID())", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = try await makeTrackTranscriptionFixture(rootURL: root)
            var session = fixture.session
            session.providerID = scenario.provider.rawValue
            session.engineID = scenario.provider == .local
                ? TranscriptionProviderRegistry.local.capabilities.engineID
                : TranscriptionProviderRegistry.openAI.capabilities.engineID
            session.modelID = scenario.provider == .local
                ? "parakeet-tdt-0.6b-v3-coreml"
                : "gpt-4o-mini-transcribe"
            session.privacyMode = scenario.privacy
            try await fixture.store.save(session)
            let provider = MockTranscriptionProvider()
            let resolver = TrackProviderResolverProbe(provider: provider)
            let executor = LongFormTrackTranscriptionExecutor(maximumAttempts: 1) { request in
                await resolver.resolve(request)
            }
            let runner = TrackTranscriptionRunner(store: fixture.store, executor: executor)

            let result = try await runner.run(sessionID: session.id)
            let requests = await resolver.requests
            #expect(result.privacyMode == scenario.privacy)
            if scenario.allowed {
                #expect(result.status == .merging)
                #expect(result.tracks.allSatisfy { $0.status == .transcribed })
                #expect(requests.map(\.role) == [.localSpeaker, .systemAudio])
                #expect(requests.allSatisfy {
                    $0.providerID == scenario.provider.rawValue
                        && $0.privacyMode == scenario.privacy
                })
                #expect(provider.transcribeCount == 2)
            } else {
                #expect(result.status == .failed)
                #expect(result.tracks.allSatisfy {
                    $0.status == .failed && $0.errorCategory == .networkBlocked
                })
                #expect(requests.isEmpty)
                #expect(provider.transcribeCount == 0)
            }
        }
    }

    @MainActor
    @Test func meetingPrivacyPolicyControlsActualOpenAIHTTPUploads() async throws {
        for privacyMode in [
            PrivacyMode.offline,
            .localWithOptionalCloudEnhancement,
            .cloudTranscription
        ] {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("FlowDictateMeetingHTTPPolicy-\(UUID())", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = try await makeLongFormTrackTranscriptionFixture(
                rootURL: root,
                providerID: TranscriptionProviderID.openAI.rawValue,
                engineID: TranscriptionProviderRegistry.openAI.capabilities.engineID,
                modelID: "gpt-4o-mini-transcribe",
                privacyMode: privacyMode,
                sampleAmplitude: 0.05
            )
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MeetingPolicyOpenAIURLProtocol.self]
            let provider = OpenAITranscriptionProvider(
                apiKey: "test-key",
                endpoint: URL(string: "https://meeting-policy.invalid/audio/transcriptions")!,
                session: URLSession(configuration: configuration),
                uploadPreparer: PassThroughAudioUploadPreparer()
            )
            let executor = LongFormTrackTranscriptionExecutor(maximumAttempts: 1) { request in
                #expect(request.privacyMode == privacyMode)
                return provider
            }
            let before = MeetingPolicyOpenAIURLProtocol.requestCount
            let result = try await TrackTranscriptionRunner(
                store: fixture.store,
                executor: executor
            ).run(sessionID: fixture.session.id)
            let requestCount = MeetingPolicyOpenAIURLProtocol.requestCount - before

            if privacyMode == .cloudTranscription {
                #expect(result.status == .merging)
                #expect(result.tracks.allSatisfy { $0.status == .transcribed })
                #expect(requestCount == 2)
            } else {
                #expect(result.status == .failed)
                #expect(result.tracks.allSatisfy {
                    $0.status == .failed && $0.errorCategory == .networkBlocked
                })
                #expect(requestCount == 0)
            }
        }
    }

    @MainActor
    @Test func missingLocalModelPausesMeetingWithoutCloudFallback() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateTrackMissingModel-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeTrackTranscriptionFixture(
            rootURL: root.appendingPathComponent("meetings", isDirectory: true)
        )
        let queue = DictationProcessingQueue(
            store: DictationJobStore(
                directory: root.appendingPathComponent("jobs", isDirectory: true)
            )
        )
        var resolutionCount = 0
        let executor = LongFormTrackTranscriptionExecutor(maximumAttempts: 1) {
            _ -> any TranscriptionProvider in
            resolutionCount += 1
            throw TranscriptionProviderError.localModelMissing(
                modelID: fixture.session.modelID
            )
        }
        let runner = TrackTranscriptionRunner(
            store: fixture.store,
            executor: executor,
            processingQueue: queue
        )

        let paused = try await runner.run(sessionID: fixture.session.id)
        let microphone = try #require(
            paused.tracks.first(where: { $0.role == .localSpeaker })
        )
        let systemAudio = try #require(
            paused.tracks.first(where: { $0.role == .systemAudio })
        )

        #expect(paused.status == .paused)
        #expect(paused.lastErrorCategory == .localModelMissing)
        #expect(microphone.status == .transcriptionPending)
        #expect(microphone.errorCategory == .localModelMissing)
        #expect(systemAudio.status == .finalized)
        #expect(resolutionCount == 1)
        #expect(try await queue.snapshot().totalActiveCount == 0)
    }

    @Test func timedTranscriptMergeOrdersSerialAndOverlappingSpeechDeterministically() throws {
        var session = makeValidMixedRecordingSession()
        session.status = .merging
        for index in session.tracks.indices {
            session.tracks[index].status = .transcribed
            session.tracks[index].transcriptionSessionID = UUID()
            session.tracks[index].transcriptRelativePath =
                "transcription/\(session.tracks[index].role.rawValue)-transcript.json"
        }
        let microphone = makeMeetingTrackTranscript(
            session: session,
            role: .localSpeaker,
            text: "Microphone first. Shared sentence.",
            entries: [
                TrackTranscriptEntry(
                    index: 0,
                    startMilliseconds: 100,
                    endMilliseconds: 400,
                    text: "Microphone first.",
                    precision: .segment
                ),
                TrackTranscriptEntry(
                    index: 1,
                    startMilliseconds: 500,
                    endMilliseconds: 800,
                    text: "Shared sentence.",
                    precision: .word
                )
            ]
        )
        let systemAudio = makeMeetingTrackTranscript(
            session: session,
            role: .systemAudio,
            text: "System overlap. Shared sentence.",
            entries: [
                TrackTranscriptEntry(
                    index: 0,
                    startMilliseconds: 190,
                    endMilliseconds: 350,
                    text: "System overlap.",
                    precision: .segment
                ),
                TrackTranscriptEntry(
                    index: 1,
                    startMilliseconds: 490,
                    endMilliseconds: 900,
                    text: "Shared sentence.",
                    precision: .word
                )
            ]
        )

        let first = try TimedTranscriptMerger().merge(
            session: session,
            transcripts: [systemAudio, microphone],
            createdAt: session.updatedAt
        )
        let retry = try TimedTranscriptMerger().merge(
            session: session,
            transcripts: [microphone, systemAudio],
            createdAt: session.updatedAt
        )

        #expect(first == retry)
        #expect(first.entries.map(\.role) == [
            .localSpeaker, .systemAudio, .localSpeaker, .systemAudio
        ])
        #expect(first.entries.map(\.sessionStartMilliseconds) == [100, 200, 500, 500])
        #expect(first.entries[0].sessionEndMilliseconds == 400)
        #expect(first.entries[1].sessionEndMilliseconds == 360)
        #expect(first.entries[0].sessionEndMilliseconds
            > first.entries[1].sessionStartMilliseconds)
        #expect(first.entries.filter { $0.text == "Shared sentence." }.count == 2)
        #expect(first.renderedText == """
            [You] Microphone first.
            [System Audio] System overlap.
            [You · overlaps System Audio] Shared sentence.
            [System Audio · overlaps You] Shared sentence.
            """)
    }

    @Test func timedTranscriptMergeRendersOverlappingWordsAsReadableSpeakerTurns() throws {
        var session = makeValidMixedRecordingSession()
        session.status = .merging
        for index in session.tracks.indices {
            session.tracks[index].status = .transcribed
            session.tracks[index].transcriptionSessionID = UUID()
            session.tracks[index].transcriptRelativePath =
                "transcription/\(session.tracks[index].role.rawValue)-transcript.json"
        }
        let systemWords: [(Int64, String)] = [
            (0, "Remote"), (300, "speaker"), (600, "explains"),
            (900, "the"), (1_200, "plan.")
        ]
        let microphoneWords: [(Int64, String)] = [
            (900, "I"), (1_200, "agree"), (1_500, "now.")
        ]
        func entries(_ words: [(Int64, String)]) -> [TrackTranscriptEntry] {
            words.enumerated().map { index, word in
                TrackTranscriptEntry(
                    index: index,
                    startMilliseconds: word.0,
                    endMilliseconds: word.0 + 220,
                    text: word.1,
                    precision: .word
                )
            }
        }
        let systemAudio = makeMeetingTrackTranscript(
            session: session, role: .systemAudio,
            text: "Remote speaker explains the plan.", entries: entries(systemWords)
        )
        let microphone = makeMeetingTrackTranscript(
            session: session, role: .localSpeaker,
            text: "I agree now.", entries: entries(microphoneWords)
        )

        let timeline = try TimedTranscriptMerger().merge(
            session: session, transcripts: [microphone, systemAudio],
            createdAt: session.updatedAt
        )

        #expect(timeline.entries.count == 8)
        #expect(timeline.entries.allSatisfy { $0.precision == .word })
        #expect(timeline.renderedText == """
            [System Audio · overlaps You] Remote speaker explains the plan.
            [You · overlaps System Audio] I agree now.
            """)
    }

    @Test func timedTranscriptMergeInterleavesLongSpeechAtSpeakerEntry() throws {
        var session = makeValidMixedRecordingSession()
        session.status = .merging
        for index in session.tracks.indices {
            session.tracks[index].status = .transcribed
            session.tracks[index].transcriptionSessionID = UUID()
            session.tracks[index].transcriptRelativePath =
                "transcription/\(session.tracks[index].role.rawValue)-transcript.json"
            session.tracks[index].durationMilliseconds = 30_000
            session.tracks[index].lastHostTime = session.tracks[index].firstHostTime! + 30_000
            session.tracks[index].timestampAnchors[1].hostTime =
                session.tracks[index].lastHostTime!
            session.tracks[index].timestampAnchors[1].trackFramePosition = 1_440_000
        }
        let systemWords = (0...20).map { index in
            TrackTranscriptEntry(
                index: index,
                startMilliseconds: Int64(index * 1_000),
                endMilliseconds: Int64(index * 1_000 + 220),
                text: index == 0 ? "Remote" :
                    index == 18 ? "end." :
                    index == 19 ? "Next" :
                    index == 20 ? "sentence." : "word",
                precision: .word
            )
        }
        let microphoneWords = ["I", "respond."].enumerated().map { index, word in
            TrackTranscriptEntry(
                index: index,
                startMilliseconds: Int64(10_000 + index * 1_000),
                endMilliseconds: Int64(10_220 + index * 1_000),
                text: word,
                precision: .word
            )
        }
        let systemAudio = makeMeetingTrackTranscript(
            session: session, role: .systemAudio,
            text: "Remote sentence. Next sentence.", entries: systemWords
        )
        let microphone = makeMeetingTrackTranscript(
            session: session, role: .localSpeaker,
            text: "I respond.", entries: microphoneWords
        )

        let timeline = try TimedTranscriptMerger().merge(
            session: session, transcripts: [microphone, systemAudio],
            createdAt: session.updatedAt
        )
        let lines = timeline.renderedText.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("[System Audio] Remote "))
        #expect(lines[1] == "[You · overlaps System Audio] I respond.")
        #expect(lines[2].hasPrefix("[System Audio · overlaps You] word"))
        #expect(lines[2].hasSuffix("Next sentence."))
        #expect(timeline.entries.count == 23)
    }

    @Test func timedTranscriptMergeOmitsVerifiedSilentTrack() throws {
        var session = makeValidMixedRecordingSession()
        session.status = .merging
        for index in session.tracks.indices {
            session.tracks[index].status = .transcribed
            session.tracks[index].transcriptionSessionID = UUID()
            session.tracks[index].transcriptRelativePath =
                "transcription/\(session.tracks[index].role.rawValue)-transcript.json"
        }
        let microphone = MeetingTrackTranscript(
            schemaVersion: MeetingTrackTranscript.currentSchemaVersion,
            meetingSessionID: session.id,
            trackID: session.tracks.first { $0.role == .localSpeaker }!.id,
            role: .localSpeaker,
            transcriptionSessionID: session.tracks.first { $0.role == .localSpeaker }!
                .transcriptionSessionID!,
            providerID: "local", modelID: "test", language: nil,
            transcript: "", segmentCount: 2, completedSegmentCount: 2,
            timedEntries: nil, isSilent: true, createdAt: session.updatedAt
        )
        let systemAudio = makeMeetingTrackTranscript(
            session: session, role: .systemAudio, text: "Remote speaks.",
            entries: [TrackTranscriptEntry(
                index: 0, startMilliseconds: 100, endMilliseconds: 800,
                text: "Remote speaks.", precision: .word
            )]
        )
        let timeline = try TimedTranscriptMerger().merge(
            session: session, transcripts: [microphone, systemAudio], createdAt: session.updatedAt
        )
        #expect(timeline.entries.count == 1)
        #expect(timeline.renderedText == "[System Audio] Remote speaks.")
    }

    @Test func timedTranscriptMergeFallsBackHonestlyAndMapsGapAndDrift() throws {
        var session = makeValidMixedRecordingSession()
        session.status = .merging
        session.synchronization?.estimatedDriftPartsPerMillion = 1_000
        let gap = TrackGap(
            id: UUID(),
            startMilliseconds: 1_000,
            endMilliseconds: 1_100,
            reason: .droppedBuffers
        )
        for index in session.tracks.indices {
            session.tracks[index].status = .transcribed
            session.tracks[index].transcriptionSessionID = UUID()
            session.tracks[index].transcriptRelativePath =
                "transcription/\(session.tracks[index].role.rawValue)-transcript.json"
            if session.tracks[index].role == .localSpeaker {
                session.tracks[index].gaps = [gap]
            }
        }
        let microphone = makeMeetingTrackTranscript(
            session: session,
            role: .localSpeaker,
            text: "Precise local words",
            entries: [
                TrackTranscriptEntry(
                    index: 0,
                    startMilliseconds: 2_000,
                    endMilliseconds: 3_000,
                    text: "Precise local words",
                    precision: .word
                )
            ]
        )
        let systemAudio = makeMeetingTrackTranscript(
            session: session,
            role: .systemAudio,
            text: "Provider returned text without timestamps",
            entries: nil
        )

        let timeline = try TimedTranscriptMerger().merge(
            session: session,
            transcripts: [microphone, systemAudio],
            createdAt: session.updatedAt
        )
        let localEntry = try #require(
            timeline.entries.first(where: { $0.role == .localSpeaker })
        )
        let fallback = try #require(
            timeline.entries.first(where: { $0.role == .systemAudio })
        )

        #expect(localEntry.precision == .word)
        #expect(localEntry.sessionStartMilliseconds == 2_102)
        #expect(localEntry.sessionEndMilliseconds == 3_103)
        #expect(fallback.precision == .trackChunk)
        #expect(fallback.trackStartMilliseconds == 0)
        #expect(fallback.trackEndMilliseconds == 10_000)
        #expect(fallback.sessionStartMilliseconds == 10)
        #expect(!timeline.renderedText.contains("overlaps"))
    }

    @Test func timedTranscriptMergeRejectsUnreliableSynchronization() throws {
        var session = makeValidMixedRecordingSession()
        session.status = .merging
        session.synchronization?.quality = .unreliable
        session.qualityReport?.synchronizationQuality = .unreliable
        for index in session.tracks.indices {
            session.tracks[index].status = .transcribed
            session.tracks[index].transcriptionSessionID = UUID()
            session.tracks[index].transcriptRelativePath =
                "transcription/\(session.tracks[index].role.rawValue)-transcript.json"
        }
        let transcripts = RecordingTrackRole.allCases.map { role in
            makeMeetingTrackTranscript(
                session: session,
                role: role,
                text: "Must not merge",
                entries: nil
            )
        }

        #expect(throws: TimedTranscriptMergeError.unreliableSynchronization) {
            _ = try TimedTranscriptMerger().merge(
                session: session,
                transcripts: transcripts,
                createdAt: session.updatedAt
            )
        }
    }

    @Test func meetingTranscriptMergePersistsTimelineAndRecoversAfterArtifactFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateTimedMerge-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        var session = makeValidMixedRecordingSession()
        session.status = .merging
        for index in session.tracks.indices {
            session.tracks[index].status = .transcribed
            session.tracks[index].transcriptionSessionID = UUID()
            session.tracks[index].transcriptRelativePath =
                "transcription/\(session.tracks[index].role.rawValue)-transcript.json"
        }
        let paths = try await store.prepareSession(id: session.id)
        try await store.create(session)
        let microphone = makeMeetingTrackTranscript(
            session: session,
            role: .localSpeaker,
            text: "One",
            entries: [TrackTranscriptEntry(
                index: 0,
                startMilliseconds: 100,
                endMilliseconds: 200,
                text: "One",
                precision: .segment
            )]
        )
        let systemAudio = makeMeetingTrackTranscript(
            session: session,
            role: .systemAudio,
            text: "Two",
            entries: [TrackTranscriptEntry(
                index: 0,
                startMilliseconds: 300,
                endMilliseconds: 400,
                text: "Two",
                precision: .segment
            )]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for artifact in [microphone, systemAudio] {
            let relativePath = try #require(
                session.tracks.first(where: { $0.role == artifact.role })?.transcriptRelativePath
            )
            try encoder.encode(artifact).write(
                to: paths.sessionDirectory.appendingPathComponent(relativePath),
                options: .atomic
            )
        }
        let systemURL = paths.sessionDirectory.appendingPathComponent(
            try #require(session.tracks.first(where: { $0.role == .systemAudio })?.transcriptRelativePath)
        )
        let systemData = try Data(contentsOf: systemURL)
        try Data("invalid transcript artifact".utf8).write(to: systemURL, options: .atomic)
        let runner = MeetingTranscriptMergeRunner(
            store: store,
            now: { Date(timeIntervalSince1970: 1_800_000_200) }
        )

        await #expect(throws: (any Error).self) {
            _ = try await runner.run(sessionID: session.id)
        }
        let paused = try #require(try await store.load(sessionID: session.id))
        #expect(paused.status == .paused)
        #expect(paused.lastErrorCategory == .transcriptMerge)
        #expect(paused.tracks.allSatisfy { $0.status == .transcribed })
        #expect(paused.tracks.allSatisfy { track in
            guard let relativePath = track.transcriptRelativePath else { return false }
            return FileManager.default.fileExists(
                atPath: paths.sessionDirectory.appendingPathComponent(relativePath).path
            )
        })

        try systemData.write(to: systemURL, options: .atomic)
        let completed = try await runner.run(sessionID: session.id)
        let timelineURL = paths.sessionDirectory.appendingPathComponent(
            MeetingTranscriptMergeRunner.timelineRelativePath
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let timeline = try decoder.decode(
            TimedTranscriptTimeline.self,
            from: Data(contentsOf: timelineURL)
        )

        #expect(completed.status == .completed)
        #expect(completed.completionMode == .allTracks)
        #expect(completed.mergedTimelineRelativePath
            == MeetingTranscriptMergeRunner.timelineRelativePath)
        #expect(completed.finalTranscript == "[You] One\n[System Audio] Two")
        #expect(timeline.meetingSessionID == session.id)
        #expect(timeline.entries.map(\.text) == ["One", "Two"])
        #expect(try Data(contentsOf: systemURL) == systemData)
    }

    @Test func meetingTranscriptInsertionGateAuthorizesExactlyOnce() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingInsertion-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        var session = makeValidMixedRecordingSession()
        session.status = .completed
        session.finalTranscript = "[You] Ready"
        session.mergedTimelineRelativePath = MeetingTranscriptMergeRunner.timelineRelativePath
        session.completionMode = .allTracks
        session.transcriptInsertionState = .ready
        session.transcriptInsertionAttemptCount = 0
        for index in session.tracks.indices {
            session.tracks[index].status = .transcribed
            session.tracks[index].transcriptionSessionID = UUID()
            session.tracks[index].transcriptRelativePath =
                "transcription/\(session.tracks[index].role.rawValue)-transcript.json"
        }
        try await store.create(session)
        let gate = MeetingTranscriptInsertionGate(store: store)

        #expect(try await gate.begin(sessionID: session.id, targetIsAvailable: true)
            == .authorized("[You] Ready"))
        #expect(try await store.load(sessionID: session.id)?.transcriptInsertionState
            == .attempting)
        try await gate.markCompleted(sessionID: session.id)
        #expect(try await gate.begin(sessionID: session.id, targetIsAvailable: true)
            == .alreadyCompleted)
        let completed = try #require(try await store.load(sessionID: session.id))
        #expect(completed.transcriptInsertionState == .completed)
        #expect(completed.transcriptInsertionAttemptCount == 1)
    }

    @Test func meetingTranscriptInsertionGateDefersUnavailableAndUncertainTargets() async throws {
        func completedSession(id: UUID) -> MixedRecordingSession {
            var session = makeValidMixedRecordingSession()
            session.id = id
            session.recordID = UUID()
            session.status = .completed
            session.finalTranscript = "[System Audio] Deferred"
            session.mergedTimelineRelativePath = MeetingTranscriptMergeRunner.timelineRelativePath
            session.completionMode = .allTracks
            session.transcriptInsertionState = .ready
            session.transcriptInsertionAttemptCount = 0
            for index in session.tracks.indices {
                session.tracks[index].id = UUID()
                session.tracks[index].status = .transcribed
                session.tracks[index].transcriptionSessionID = UUID()
                session.tracks[index].transcriptRelativePath =
                    "transcription/\(session.tracks[index].role.rawValue)-transcript.json"
            }
            return session
        }

        let unavailableRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingDeferred-\(UUID())", isDirectory: true)
        let uncertainRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingUnknown-\(UUID())", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: unavailableRoot)
            try? FileManager.default.removeItem(at: uncertainRoot)
        }
        let unavailableStore = MeetingSessionStore(rootURL: unavailableRoot)
        let unavailable = completedSession(id: UUID())
        try await unavailableStore.create(unavailable)
        let unavailableGate = MeetingTranscriptInsertionGate(store: unavailableStore)
        #expect(try await unavailableGate.begin(
            sessionID: unavailable.id,
            targetIsAvailable: false
        ) == .deferred)
        #expect(try await unavailableStore.load(sessionID: unavailable.id)?
            .transcriptInsertionState == .deferred)

        let uncertainStore = MeetingSessionStore(rootURL: uncertainRoot)
        let uncertain = completedSession(id: UUID())
        try await uncertainStore.create(uncertain)
        let firstProcess = MeetingTranscriptInsertionGate(store: uncertainStore)
        #expect(try await firstProcess.begin(
            sessionID: uncertain.id,
            targetIsAvailable: true
        ) == .authorized("[System Audio] Deferred"))
        let restartedProcess = MeetingTranscriptInsertionGate(store: uncertainStore)
        #expect(try await restartedProcess.begin(
            sessionID: uncertain.id,
            targetIsAvailable: true
        ) == .requiresReview)
        let recovered = try #require(try await uncertainStore.load(sessionID: uncertain.id))
        #expect(recovered.transcriptInsertionState == .unknown)
        #expect(recovered.transcriptInsertionAttemptCount == 1)
    }

    @Test func mixedCoordinatorRejectsLowDiskSpaceBeforePreparingEitherTrack() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMixedStorage-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        let events = MixedTrackTestEventLog()
        let coordinator = MixedRecordingSessionCoordinator(
            microphoneRecorder: MockMixedTrackRecorder(role: .localSpeaker, events: events),
            systemAudioRecorder: MockMixedTrackRecorder(role: .systemAudio, events: events),
            store: store,
            availableStorageBytes: { _ in 0 }
        )
        let request = MixedRecordingSessionRequest(
            providerID: "local", engineID: "fluid-audio",
            modelID: "test-model", language: "de"
        )

        await #expect(throws: MixedRecordingCoordinatorError.insufficientRecordingStorage(
            requiredBytes: MixedRecordingSessionCoordinator.minimumRecordingStorageBytes,
            availableBytes: 0
        )) {
            _ = try await coordinator.start(request)
        }
        let recordedEvents = await events.values
        #expect(!recordedEvents.contains { event in
            if case .prepare = event { return true }
            if case .start = event { return true }
            return false
        })
        #expect(await coordinator.state == .idle)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func mixedCoordinatorWarnsButStartsShortCaptureBelowOldStorageThreshold() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMixedStorageWarning-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let events = MixedTrackTestEventLog()
        let warnings = LockedMixedWarningLog()
        let coordinator = MixedRecordingSessionCoordinator(
            microphoneRecorder: MockMixedTrackRecorder(role: .localSpeaker, events: events),
            systemAudioRecorder: MockMixedTrackRecorder(role: .systemAudio, events: events),
            store: MeetingSessionStore(rootURL: root),
            availableStorageBytes: { _ in 100_000_000 }
        )
        await coordinator.setWarningHandler { warning in warnings.append(warning) }
        let started = try await coordinator.start(MixedRecordingSessionRequest(
            providerID: "local", engineID: "fluid-audio",
            modelID: "test-model", language: "de"
        ))

        #expect(started.status == .recording)
        #expect(warnings.values == [.lowStorage])
        #expect(warnings.values[0].message.contains("Low disk space"))
        #expect(await events.values.contains(.prepare(.localSpeaker)))
        _ = try await coordinator.stop()
    }

    @Test func mixedCoordinatorStartsBothTracksAfterSharedPreparationBarrier() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMixedStart-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        let events = MixedTrackTestEventLog()
        let microphone = MockMixedTrackRecorder(role: .localSpeaker, events: events)
        let systemAudio = MockMixedTrackRecorder(role: .systemAudio, events: events)
        let requestedHostTime: UInt64 = 50_000
        let coordinator = MixedRecordingSessionCoordinator(
            microphoneRecorder: microphone,
            systemAudioRecorder: systemAudio,
            store: store,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            hostTime: { requestedHostTime }
        )
        let request = MixedRecordingSessionRequest(
            providerID: "local",
            engineID: "fluid-audio",
            modelID: "test-model",
            language: "de"
        )

        let session = try await coordinator.start(request)
        let recordedEvents = await events.values
        let firstStartIndex = try #require(recordedEvents.firstIndex {
            if case .start = $0 { true } else { false }
        })

        #expect(session.status == .recording)
        #expect(session.tracks.allSatisfy { $0.status == .recording })
        #expect(session.tracks.map(\.audioRelativePath) == [
            "tracks/microphone.caf",
            "tracks/system-audio.caf"
        ])
        #expect(recordedEvents[..<firstStartIndex].contains(.prepare(.localSpeaker)))
        #expect(recordedEvents[..<firstStartIndex].contains(.prepare(.systemAudio)))
        #expect(await microphone.receivedStartHostTime == requestedHostTime)
        #expect(await systemAudio.receivedStartHostTime == requestedHostTime)
        #expect(await coordinator.state == .recording(request.sessionID))
        #expect(try await store.load(sessionID: request.sessionID) == session)
    }

    @Test func mixedCoordinatorCompletesTenConsecutiveSessionsWithoutReusingTracks() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMixedTenSessions-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        let events = MixedTrackTestEventLog()
        let coordinator = MixedRecordingSessionCoordinator(
            microphoneRecorder: MockMixedTrackRecorder(role: .localSpeaker, events: events),
            systemAudioRecorder: MockMixedTrackRecorder(role: .systemAudio, events: events),
            store: store,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            hostTime: { 50_000 }
        )
        var sessionIDs = Set<UUID>()
        var recordIDs = Set<UUID>()

        for _ in 0..<10 {
            let request = MixedRecordingSessionRequest(
                providerID: "local",
                engineID: "fluid-audio",
                modelID: "test-model",
                language: nil
            )
            let started = try await coordinator.start(request)
            #expect(started.status == .recording)
            await #expect(throws: MixedRecordingCoordinatorError.alreadyActive) {
                _ = try await coordinator.start(request)
            }

            let stopped = try await coordinator.stop()
            #expect(stopped.status == .queued)
            #expect(stopped.tracks.allSatisfy { $0.status == .finalized })
            #expect(stopped.tracks.allSatisfy { $0.byteCount > 0 })
            #expect(try await store.load(sessionID: request.sessionID) == stopped)
            #expect(await coordinator.state == .idle)
            await #expect(throws: MixedRecordingCoordinatorError.notRecording) {
                _ = try await coordinator.stop()
            }

            sessionIDs.insert(request.sessionID)
            recordIDs.insert(request.recordID)
        }

        #expect(sessionIDs.count == 10)
        #expect(recordIDs.count == 10)
    }

    @Test func mixedCoordinatorRejectsConcurrentTransitionsWhileStopIsFinalizing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMixedStopRace-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        let events = MixedTrackTestEventLog()
        let stopGate = MockMixedStopGate()
        let coordinator = MixedRecordingSessionCoordinator(
            microphoneRecorder: MockMixedTrackRecorder(
                role: .localSpeaker, events: events, stopGate: stopGate
            ),
            systemAudioRecorder: MockMixedTrackRecorder(
                role: .systemAudio, events: events
            ),
            store: store,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let request = MixedRecordingSessionRequest(
            providerID: "local", engineID: "fluid-audio",
            modelID: "test-model", language: nil
        )
        _ = try await coordinator.start(request)

        let firstStop = Task { try await coordinator.stop() }
        await stopGate.waitUntilEntered()
        #expect(await coordinator.state == .finalizing(request.sessionID))
        await #expect(throws: MixedRecordingCoordinatorError.transitionInProgress) {
            _ = try await coordinator.stop()
        }
        await #expect(throws: MixedRecordingCoordinatorError.transitionInProgress) {
            _ = try await coordinator.cancel()
        }
        await #expect(throws: MixedRecordingCoordinatorError.alreadyActive) {
            _ = try await coordinator.start(request)
        }

        await stopGate.release()
        let stopped = try await firstStop.value
        #expect(stopped.status == .queued)
        #expect(stopped.tracks.allSatisfy { $0.status == .finalized })
        #expect(try await store.load(sessionID: request.sessionID) == stopped)
        #expect(await coordinator.state == .idle)
    }

    @Test func mixedCoordinatorForwardsTypedTrackWarnings() async {
        let events = MixedTrackTestEventLog()
        let microphone = MockMixedTrackRecorder(role: .localSpeaker, events: events)
        let systemAudio = MockMixedTrackRecorder(role: .systemAudio, events: events)
        let warnings = LockedMixedWarningLog()
        let coordinator = MixedRecordingSessionCoordinator(
            microphoneRecorder: microphone,
            systemAudioRecorder: systemAudio,
            store: MeetingSessionStore(
                rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "FlowDictateWarningForwarding-\(UUID())",
                    isDirectory: true
                )
            )
        )
        await coordinator.setWarningHandler { warning in
            warnings.append(warning)
        }

        await microphone.emitWarning(.clipping)
        await systemAudio.emitWarning(.sourceLost)
        await microphone.emitWarning(.writerFailed)

        #expect(warnings.values == [
            MixedRecordingWarning(role: .localSpeaker, kind: .clipping),
            MixedRecordingWarning(role: .systemAudio, kind: .sourceLost),
            MixedRecordingWarning(role: .localSpeaker, kind: .writerFailed)
        ])
        #expect(warnings.values[0].message.contains("Microphone clipping"))
        #expect(warnings.values[1].message.contains("System Audio lost"))
        #expect(warnings.values[2].message.contains("could not be written"))
    }

    @Test func mixedClippingWarningExpiresAfterLastEventButTrackLossPersists() {
        var state = MixedCaptureWarningState()
        let clipping = MixedRecordingWarning(role: .localSpeaker, kind: .clipping)
        let trackLoss = MixedRecordingWarning(role: .systemAudio, kind: .sourceLost)

        let firstClipping = state.receive(clipping, at: 10)
        let firstTrackLoss = state.receive(trackLoss, at: 10)
        let repeatedClipping = state.receive(clipping, at: 13)
        let earlyExpiry = state.expire(at: 17.9)
        #expect(firstClipping)
        #expect(firstTrackLoss)
        #expect(!repeatedClipping)
        #expect(!earlyExpiry)
        #expect(state.warnings == [clipping, trackLoss])
        let finalExpiry = state.expire(at: 18)
        #expect(finalExpiry)
        #expect(state.warnings == [trackLoss])
        #expect(!state.hasTransientWarnings)
        let newClipping = state.receive(clipping, at: 20)
        #expect(newClipping)
        #expect(state.warnings == [trackLoss, clipping])

        state.reset()
        #expect(state.warnings.isEmpty)
        #expect(!state.hasTransientWarnings)
    }

#if REAL_LOW_DISK
    @Test func realLowDiskVolumeWarnsBlocksAndReportsWriterExhaustion() async throws {
        let fileManager = FileManager.default
        let candidates = try fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: "/private/tmp", isDirectory: true),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("FlowDictate-4.1-LowDisk.") }
        let testDirectory = try #require(candidates.count == 1 ? candidates[0] : nil)
        let mount = testDirectory.appendingPathComponent("mount", isDirectory: true)
            .standardizedFileURL
        let temporaryRoot = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .standardizedFileURL
        try #require(mount.deletingLastPathComponent().deletingLastPathComponent().path
            == temporaryRoot.path)
        try #require(mount.lastPathComponent == "mount")
        try #require(mount.deletingLastPathComponent().lastPathComponent
            .hasPrefix("FlowDictate-4.1-LowDisk."))
        let volumeAttributes = try fileManager.attributesOfFileSystem(forPath: mount.path)
        let volumeSize = try #require(
            (volumeAttributes[.systemSize] as? NSNumber)?.int64Value
        )
        try #require((64_000_000...256_000_000).contains(volumeSize))

        let sessionRoot = mount.appendingPathComponent("MeetingSessions", isDirectory: true)
        let fillURL = mount.appendingPathComponent("bounded-fill.bin")
        let writerURL = mount.appendingPathComponent("writer-original.caf")
        try #require(!fileManager.fileExists(atPath: sessionRoot.path))
        try #require(!fileManager.fileExists(atPath: fillURL.path))
        try #require(!fileManager.fileExists(atPath: writerURL.path))
        defer {
            try? fileManager.removeItem(at: writerURL)
            try? fileManager.removeItem(at: fillURL)
            try? fileManager.removeItem(at: sessionRoot)
        }
        func freeBytes() throws -> Int64 {
            let attributes = try fileManager.attributesOfFileSystem(forPath: mount.path)
            return try #require((attributes[.systemFreeSize] as? NSNumber)?.int64Value)
        }

        #expect(try freeBytes() > 50_000_000)
        #expect(try freeBytes() < 500_000_000)
        let events = MixedTrackTestEventLog()
        let warnings = LockedMixedWarningLog()
        let store = MeetingSessionStore(rootURL: sessionRoot)
        let coordinator = MixedRecordingSessionCoordinator(
            microphoneRecorder: MockMixedTrackRecorder(role: .localSpeaker, events: events),
            systemAudioRecorder: MockMixedTrackRecorder(role: .systemAudio, events: events),
            store: store
        )
        await coordinator.setWarningHandler { warnings.append($0) }
        let firstRequest = MixedRecordingSessionRequest(
            providerID: "local", engineID: "fluid-audio",
            modelID: "test-model", language: nil
        )
        _ = try await coordinator.start(firstRequest)
        #expect(warnings.values.contains(.lowStorage))
        let stopped = try await coordinator.stop()
        #expect(stopped.tracks.allSatisfy { $0.status == .finalized })

        #expect(fileManager.createFile(atPath: fillURL.path, contents: nil))
        let fillHandle = try FileHandle(forWritingTo: fillURL)
        let fillChunk = Data(repeating: 0xA5, count: 1_000_000)
        while try freeBytes() >= 48_000_000 {
            try fillHandle.write(contentsOf: fillChunk)
        }
        try fillHandle.close()
        #expect(try freeBytes() < 50_000_000)
        let blockedRequest = MixedRecordingSessionRequest(
            providerID: "local", engineID: "fluid-audio",
            modelID: "test-model", language: nil
        )
        do {
            _ = try await coordinator.start(blockedRequest)
            Issue.record("Expected a real-volume low-storage start block")
        } catch let error as MixedRecordingCoordinatorError {
            guard case .insufficientRecordingStorage = error else {
                Issue.record("Unexpected mixed capture error: \(error)")
                return
            }
        }
        #expect(!fileManager.fileExists(atPath: sessionRoot
            .appendingPathComponent(blockedRequest.sessionID.uuidString).path))

        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let frameCount: AVAudioFrameCount = 262_144
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let samples = try #require(buffer.floatChannelData?[0])
        samples.initialize(repeating: 0.25, count: Int(frameCount))
        let sink = try MicrophoneTrackCaptureSink(
            outputURL: writerURL,
            sourceFormat: format,
            outputFormat: format,
            warningHandler: { warnings.append(.track(role: .localSpeaker, kind: $0)) }
        )
        let hostTime = mach_continuous_time()
        sink.begin(requestedHostTime: hostTime)
        for index in 0..<64 {
            sink.append(
                buffer,
                at: AVAudioTime(
                    hostTime: hostTime + UInt64(index + 1) * 1_000_000,
                    sampleTime: AVAudioFramePosition(index) * AVAudioFramePosition(frameCount),
                    atRate: 48_000
                )
            )
        }
        do {
            _ = try sink.finish()
            Issue.record("Expected the isolated volume to exhaust during PCM writing")
        } catch let error as MicrophoneTrackRecorderError {
            guard case let .writerFailed(_, outOfSpace) = error else {
                Issue.record("Unexpected microphone writer error: \(error)")
                return
            }
            if !outOfSpace {
                Issue.record("Writer exhaustion was not classified as out of space: \(error)")
            }
        }
        #expect(warnings.values.contains(
            .track(role: .localSpeaker, kind: .writerFailed)
        ))
        #expect(fileManager.fileExists(atPath: writerURL.path))
    }
#endif

    @Test func mixedTrackFailureOriginKeepsDiagnosticsContentFreeAndConservative() {
        let cases: [(any Error, MixedTrackFailureOrigin)] = [
            (MicrophoneTrackRecorderError.writerFailed("synthetic", outOfSpace: true), .writer),
            (SystemAudioTrackRecorderError.writerFailed("synthetic", outOfSpace: false), .writer),
            (MicrophoneTrackRecorderError.unavailableInput, .device),
            (SystemAudioTrackRecorderError.operationFailed(
                operation: "synthetic", status: -1
            ), .device),
            (MicrophoneTrackRecorderError.noAudioReceived, .source),
            (SystemAudioTrackRecorderError.permissionDenied, .source),
            (MicrophoneTrackRecorderError.conversionFailed("synthetic"), .other),
            (MockMixedTrackError.requested("synthetic"), .other)
        ]
        for (error, expectedOrigin) in cases {
            #expect(MixedTrackFailureOrigin.classify(error) == expectedOrigin)
        }
        #expect(MixedTrackFailureOrigin.classify(NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(ENOSPC)
        )) == .writer)
    }

    @Test func mixedCoordinatorPersistsPartialSessionWhenOneTrackCannotStop() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMixedPartial-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        let events = MixedTrackTestEventLog()
        let microphone = MockMixedTrackRecorder(role: .localSpeaker, events: events)
        let systemAudio = MockMixedTrackRecorder(
            role: .systemAudio,
            events: events,
            stopError: MockMixedTrackError.requested("system track finalization failed")
        )
        let coordinator = MixedRecordingSessionCoordinator(
            microphoneRecorder: microphone,
            systemAudioRecorder: systemAudio,
            store: store,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            hostTime: { 75_000 }
        )
        let request = MixedRecordingSessionRequest(
            providerID: "local",
            engineID: "fluid-audio",
            modelID: "test-model",
            language: nil
        )

        _ = try await coordinator.start(request)
        let session = try await coordinator.stop()
        let microphoneTrack = try #require(
            session.tracks.first(where: { $0.role == .localSpeaker })
        )
        let systemAudioTrack = try #require(
            session.tracks.first(where: { $0.role == .systemAudio })
        )
        let sessionDirectory = root.appendingPathComponent(
            request.sessionID.uuidString,
            isDirectory: true
        )
        let microphoneURL = sessionDirectory.appendingPathComponent(
            try #require(microphoneTrack.audioRelativePath)
        )
        let systemAudioURL = sessionDirectory.appendingPathComponent(
            try #require(systemAudioTrack.audioRelativePath)
        )

        #expect(session.status == .partial)
        #expect(microphoneTrack.status == .finalized)
        #expect(systemAudioTrack.status == .failed)
        #expect(systemAudioTrack.errorCategory == .systemAudioInterrupted)
        #expect(session.lastErrorCategory == .interrupted)
        #expect(session.synchronization?.quality == .notAnalyzed)
        #expect(session.qualityReport?.completeTrackRoles == [.localSpeaker])
        #expect(FileManager.default.fileExists(atPath: microphoneURL.path))
        #expect(FileManager.default.fileExists(atPath: systemAudioURL.path))
        #expect(try await store.load(sessionID: request.sessionID) == session)
        #expect(await coordinator.state == .idle)
    }

    @Test func mixedCoordinatorPersistsTypedWriterFailuresWithoutDeletingOriginals() async throws {
        let scenarios: [(
            role: RecordingTrackRole,
            error: any Error & Sendable,
            category: DictationErrorCategory
        )] = [
            (
                .localSpeaker,
                MicrophoneTrackRecorderError.writerFailed("disk full", outOfSpace: true),
                .storageFull
            ),
            (
                .systemAudio,
                SystemAudioTrackRecorderError.writerFailed("write failed", outOfSpace: false),
                .storageUnavailable
            )
        ]
        for scenario in scenarios {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("FlowDictateMixedWriterFailure-\(UUID())", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = MeetingSessionStore(rootURL: root)
            let events = MixedTrackTestEventLog()
            let microphone = MockMixedTrackRecorder(
                role: .localSpeaker,
                events: events,
                stopError: scenario.role == .localSpeaker ? scenario.error : nil
            )
            let systemAudio = MockMixedTrackRecorder(
                role: .systemAudio,
                events: events,
                stopError: scenario.role == .systemAudio ? scenario.error : nil
            )
            let coordinator = MixedRecordingSessionCoordinator(
                microphoneRecorder: microphone,
                systemAudioRecorder: systemAudio,
                store: store,
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            )
            let request = MixedRecordingSessionRequest(
                providerID: "local", engineID: "fluid-audio",
                modelID: "test-model", language: "de"
            )

            _ = try await coordinator.start(request)
            let session = try await coordinator.stop()
            let failedTrack = try #require(session.tracks.first {
                $0.role == scenario.role
            })
            let survivingTrack = try #require(session.tracks.first {
                $0.role != scenario.role
            })
            #expect(session.status == .partial)
            #expect(failedTrack.status == .failed)
            #expect(failedTrack.errorCategory == scenario.category)
            #expect(survivingTrack.status == .finalized)
            #expect(session.lastErrorCategory == scenario.category)
            for track in session.tracks {
                let relativePath = try #require(track.audioRelativePath)
                let audioURL = root.appendingPathComponent(request.sessionID.uuidString)
                    .appendingPathComponent(relativePath)
                #expect(FileManager.default.fileExists(atPath: audioURL.path))
            }
            #expect(try await store.load(sessionID: session.id) == session)
        }
    }

    @Test func mixedRecordingRecognizesNestedOutOfSpaceErrors() {
        let diskFull = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(ENOSPC)
        )
        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileWriteUnknown.rawValue,
            userInfo: [NSUnderlyingErrorKey: diskFull]
        )
        #expect(MixedRecordingWriteFailure.isOutOfSpace(wrapped))
        #expect(!MixedRecordingWriteFailure.isOutOfSpace(
            NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue)
        ))
        let genericAudioFileError = NSError(
            domain: "com.apple.coreaudio.avfaudio",
            code: -40
        )
        #expect(!MixedRecordingWriteFailure.isOutOfSpace(genericAudioFileError))
        #expect(!MixedRecordingWriteFailure.isOutOfSpace(
            genericAudioFileError,
            writingTo: FileManager.default.temporaryDirectory
                .appendingPathComponent("healthy-volume.caf")
        ))
    }

    @Test func mixedCoordinatorPersistsWriterFailureDuringTrackStart() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMixedWriterStart-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        let events = MixedTrackTestEventLog()
        let coordinator = MixedRecordingSessionCoordinator(
            microphoneRecorder: MockMixedTrackRecorder(role: .localSpeaker, events: events),
            systemAudioRecorder: MockMixedTrackRecorder(
                role: .systemAudio,
                events: events,
                startError: SystemAudioTrackRecorderError.writerFailed(
                    "disk full", outOfSpace: true
                )
            ),
            store: store,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let request = MixedRecordingSessionRequest(
            providerID: "local", engineID: "fluid-audio",
            modelID: "test-model", language: "de"
        )

        await #expect(throws: MixedRecordingCoordinatorError.trackFailed(
            role: .systemAudio,
            phase: .start,
            message: "The system audio original could not be written: disk full"
        )) {
            _ = try await coordinator.start(request)
        }
        let saved = try #require(try await store.load(sessionID: request.sessionID))
        #expect(saved.status == .failed)
        #expect(saved.lastErrorCategory == .storageFull)
        #expect(saved.tracks.first(where: { $0.role == .systemAudio })?.errorCategory == .storageFull)
        #expect(saved.tracks.first(where: { $0.role == .localSpeaker })?.status == .interrupted)
        for track in saved.tracks {
            let relativePath = try #require(track.audioRelativePath)
            let audioURL = root.appendingPathComponent(request.sessionID.uuidString)
                .appendingPathComponent(relativePath)
            #expect(FileManager.default.fileExists(atPath: audioURL.path))
        }
    }

    @Test func mixedCoordinatorStartFailureCancelsBothTracksAndPersistsFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMixedStartFailure-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        let events = MixedTrackTestEventLog()
        let microphone = MockMixedTrackRecorder(role: .localSpeaker, events: events)
        let systemAudio = MockMixedTrackRecorder(
            role: .systemAudio,
            events: events,
            startError: MockMixedTrackError.requested("system source disappeared")
        )
        let coordinator = MixedRecordingSessionCoordinator(
            microphoneRecorder: microphone,
            systemAudioRecorder: systemAudio,
            store: store,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            hostTime: { 80_000 }
        )
        let request = MixedRecordingSessionRequest(
            providerID: "local",
            engineID: "fluid-audio",
            modelID: "test-model",
            language: nil
        )

        await #expect(
            throws: MixedRecordingCoordinatorError.trackFailed(
                role: .systemAudio,
                phase: .start,
                message: "system source disappeared"
            )
        ) {
            _ = try await coordinator.start(request)
        }
        let session = try #require(try await store.load(sessionID: request.sessionID))
        let recordedEvents = await events.values

        #expect(session.status == .failed)
        #expect(session.tracks.first(where: { $0.role == .localSpeaker })?.status == .interrupted)
        #expect(session.tracks.first(where: { $0.role == .systemAudio })?.status == .unavailable)
        #expect(recordedEvents.contains(.cancel(.localSpeaker)))
        #expect(recordedEvents.contains(.cancel(.systemAudio)))
        #expect(await coordinator.state == .idle)
    }

    @Test func mixedCoordinatorMicrophonePrepareFailurePreservesFailedManifest() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMixedMicPrepareFailure-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        let events = MixedTrackTestEventLog()
        let coordinator = MixedRecordingSessionCoordinator(
            microphoneRecorder: MockMixedTrackRecorder(
                role: .localSpeaker, events: events,
                prepareError: .requested("microphone unavailable")
            ),
            systemAudioRecorder: MockMixedTrackRecorder(
                role: .systemAudio, events: events
            ),
            store: store,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let request = MixedRecordingSessionRequest(
            providerID: "local", engineID: "fluid-audio",
            modelID: "test-model", language: nil
        )

        await #expect(throws: MixedRecordingCoordinatorError.trackFailed(
            role: .localSpeaker, phase: .prepare,
            message: "microphone unavailable"
        )) {
            _ = try await coordinator.start(request)
        }
        let failed = try #require(try await store.load(sessionID: request.sessionID))
        let recordedEvents = await events.values
        #expect(failed.status == .failed)
        #expect(failed.tracks.first(where: { $0.role == .localSpeaker })?.status == .unavailable)
        #expect(failed.tracks.first(where: { $0.role == .systemAudio })?.status == .interrupted)
        #expect(recordedEvents.contains(.cancel(.localSpeaker)))
        #expect(recordedEvents.contains(.cancel(.systemAudio)))
        #expect(await coordinator.state == .idle)
    }

    @Test func mixedCoordinatorMicrophoneStopFailurePreservesSystemOriginal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMixedMicStopFailure-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        let events = MixedTrackTestEventLog()
        let coordinator = MixedRecordingSessionCoordinator(
            microphoneRecorder: MockMixedTrackRecorder(
                role: .localSpeaker, events: events,
                stopError: MockMixedTrackError.requested("microphone writer failed")
            ),
            systemAudioRecorder: MockMixedTrackRecorder(
                role: .systemAudio, events: events
            ),
            store: store,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let request = MixedRecordingSessionRequest(
            providerID: "local", engineID: "fluid-audio",
            modelID: "test-model", language: nil
        )

        _ = try await coordinator.start(request)
        let partial = try await coordinator.stop()
        let systemTrack = try #require(partial.tracks.first {
            $0.role == .systemAudio
        })
        let systemAudioURL = root.appendingPathComponent(request.sessionID.uuidString)
            .appendingPathComponent(try #require(systemTrack.audioRelativePath))

        #expect(partial.status == .partial)
        #expect(partial.tracks.first(where: { $0.role == .localSpeaker })?.status == .failed)
        #expect(systemTrack.status == .finalized)
        #expect(systemTrack.byteCount > 0)
        #expect(FileManager.default.fileExists(atPath: systemAudioURL.path))
        #expect(try await store.load(sessionID: request.sessionID) == partial)
    }

    @Test func mixedCoordinatorCancelPreservesTracksAndAllowsAnotherSession() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMixedCancel-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        let events = MixedTrackTestEventLog()
        let microphone = MockMixedTrackRecorder(
            role: .localSpeaker,
            events: events,
            returnsCaptureOnCancel: true
        )
        let systemAudio = MockMixedTrackRecorder(
            role: .systemAudio,
            events: events,
            returnsCaptureOnCancel: true
        )
        let coordinator = MixedRecordingSessionCoordinator(
            microphoneRecorder: microphone,
            systemAudioRecorder: systemAudio,
            store: store,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            hostTime: { 90_000 }
        )
        let firstRequest = MixedRecordingSessionRequest(
            providerID: "local",
            engineID: "fluid-audio",
            modelID: "test-model",
            language: "en"
        )

        _ = try await coordinator.start(firstRequest)
        await #expect(throws: MixedRecordingCoordinatorError.alreadyActive) {
            _ = try await coordinator.start(
                MixedRecordingSessionRequest(
                    providerID: "local",
                    engineID: "fluid-audio",
                    modelID: "test-model",
                    language: nil
                )
            )
        }
        let cancelled = try await coordinator.cancel()
        let sessionDirectory = root.appendingPathComponent(
            firstRequest.sessionID.uuidString,
            isDirectory: true
        )
        let originalURLs = cancelled.tracks.compactMap(\.audioRelativePath).map {
            sessionDirectory.appendingPathComponent($0)
        }

        #expect(cancelled.status == .cancelled)
        #expect(cancelled.tracks.allSatisfy { $0.status == .finalized })
        #expect(cancelled.synchronization?.quality == .good)
        #expect(cancelled.synchronization?.initialOffsetMilliseconds == -1)
        #expect(cancelled.qualityReport?.completeTrackRoles == [.localSpeaker, .systemAudio])
        #expect(originalURLs.count == 2)
        #expect(originalURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(try await store.load(sessionID: firstRequest.sessionID) == cancelled)
        #expect(await coordinator.state == .idle)
        await #expect(throws: MixedRecordingCoordinatorError.notRecording) {
            _ = try await coordinator.stop()
        }

        let secondRequest = MixedRecordingSessionRequest(
            providerID: "local",
            engineID: "fluid-audio",
            modelID: "test-model",
            language: nil
        )
        let restarted = try await coordinator.start(secondRequest)
        #expect(restarted.status == .recording)
        _ = try await coordinator.cancel()
    }

    @Test func microphoneTrackSinkWritesMonoFloatCAFWithTimelineMetadata() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMicrophoneTrack-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let sourceFormat = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ))
        let outputFormat = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: 4_800
        ))
        buffer.frameLength = 4_800
        let channelData = try #require(buffer.floatChannelData)
        for channel in 0..<2 {
            for frame in 0..<Int(buffer.frameLength) {
                channelData[channel][frame] = 0.25
            }
        }
        let hostTime = mach_continuous_time()
        let sink = try MicrophoneTrackCaptureSink(
            outputURL: outputURL,
            sourceFormat: sourceFormat,
            outputFormat: outputFormat
        )

        sink.begin(requestedHostTime: hostTime)
        sink.append(
            buffer,
            at: AVAudioTime(hostTime: hostTime, sampleTime: 0, atRate: 48_000)
        )
        let result = try sink.finish()
        let file = try AVAudioFile(forReading: outputURL)

        #expect(result.formatIdentifier == "lpcm")
        #expect(result.sampleRate == 48_000)
        #expect(result.channelCount == 1)
        #expect(result.durationMilliseconds >= 99)
        #expect(result.durationMilliseconds <= 101)
        #expect(result.byteCount > 0)
        #expect(result.timestampAnchors.count == 2)
        #expect(result.timestampAnchors.first?.trackFramePosition == 0)
        #expect(result.timestampAnchors.last?.trackFramePosition == 4_800)
        #expect(abs((result.quality.peakLevel ?? 0) - 0.25) < 0.01)
        #expect(result.gaps.isEmpty)
        #expect(file.processingFormat.commonFormat == .pcmFormatFloat32)
        #expect(file.processingFormat.channelCount == 1)
        #expect(file.length == 4_800)
    }

    @Test func systemAudioTrackSinkWritesFloatCAFAndRejectsLateCallbacks() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSystemAudioTrack-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: 4_800
        ))
        buffer.frameLength = 4_800
        let samples = try #require(buffer.floatChannelData?[0])
        for frame in 0..<Int(buffer.frameLength) {
            samples[frame] = 0.125
        }
        let hostTime = mach_continuous_time()
        let sink = try SystemAudioTrackCaptureSink(
            outputURL: outputURL,
            sourceFormat: format,
            outputFormat: format
        )
        let audioTime = AVAudioTime(
            hostTime: hostTime,
            sampleTime: 0,
            atRate: 48_000
        )
        var timeStamp = audioTime.audioTimeStamp

        sink.begin(requestedHostTime: hostTime)
        withUnsafePointer(to: &timeStamp) { timePointer in
            sink.append(
                inputData: UnsafePointer(buffer.audioBufferList),
                inputTime: timePointer
            )
        }
        sink.endCapture()

        var lateTimeStamp = AVAudioTime(
            hostTime: hostTime + AudioConvertNanosToHostTime(100_000_000),
            sampleTime: 4_800,
            atRate: 48_000
        ).audioTimeStamp
        withUnsafePointer(to: &lateTimeStamp) { timePointer in
            sink.append(
                inputData: UnsafePointer(buffer.audioBufferList),
                inputTime: timePointer
            )
        }

        let result = try sink.finish()
        let file = try AVAudioFile(forReading: outputURL)

        #expect(result.formatIdentifier == "lpcm")
        #expect(result.sampleRate == 48_000)
        #expect(result.channelCount == 1)
        #expect(result.durationMilliseconds >= 99)
        #expect(result.durationMilliseconds <= 101)
        #expect(result.timestampAnchors.count == 2)
        #expect(result.timestampAnchors.last?.trackFramePosition == 4_800)
        #expect(abs((result.quality.peakLevel ?? 0) - 0.125) < 0.01)
        #expect(result.gaps.isEmpty)
        #expect(file.processingFormat.commonFormat == .pcmFormatFloat32)
        #expect(file.processingFormat.channelCount == 1)
        #expect(file.length == 4_800)
    }

    @Test func systemAudioTrackAcceptsInterleavedTapPCM() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateInterleavedSystemTrack-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let sourceFormat = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: true
        ))
        let outputFormat = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        #expect(!sourceFormat.isStandard)
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: 4_800
        ))
        buffer.frameLength = 4_800
        let audioBuffer = buffer.mutableAudioBufferList.pointee.mBuffers
        let samples = try #require(audioBuffer.mData?.assumingMemoryBound(to: Float.self))
        for frame in 0..<Int(buffer.frameLength) {
            samples[frame * 2] = 0.25
            samples[frame * 2 + 1] = 0.25
        }

        let hostTime = mach_continuous_time()
        let sink = try SystemAudioTrackCaptureSink(
            outputURL: outputURL,
            sourceFormat: sourceFormat,
            outputFormat: outputFormat
        )
        var timeStamp = AVAudioTime(
            hostTime: hostTime,
            sampleTime: 0,
            atRate: 48_000
        ).audioTimeStamp
        sink.begin(requestedHostTime: hostTime)
        withUnsafePointer(to: &timeStamp) { timePointer in
            sink.append(
                inputData: UnsafePointer(buffer.audioBufferList),
                inputTime: timePointer
            )
        }
        sink.endCapture()

        let result = try sink.finish()
        let file = try AVAudioFile(forReading: outputURL)
        #expect(result.channelCount == 1)
        #expect(result.durationMilliseconds >= 99)
        #expect(result.durationMilliseconds <= 101)
        #expect(abs((result.quality.peakLevel ?? 0) - 0.25) < 0.01)
        #expect(file.processingFormat.commonFormat == .pcmFormatFloat32)
        #expect(file.processingFormat.channelCount == 1)
        #expect(file.length == 4_800)
    }

    @Test func sharedPCMTrackMetricsDetectGapClippingAndSilence() throws {
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let clipped = try #require(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: 480
        ))
        let silent = try #require(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: 480
        ))
        clipped.frameLength = 480
        silent.frameLength = 480
        let clippedSamples = try #require(clipped.floatChannelData?[0])
        let silentSamples = try #require(silent.floatChannelData?[0])
        for frame in 0..<480 {
            clippedSamples[frame] = 1
            silentSamples[frame] = 0
        }
        let firstHostTime = mach_continuous_time()
        let secondHostTime = firstHostTime + AudioConvertNanosToHostTime(20_000_000)
        var metrics = PCMTrackMetrics(
            requestedHostTime: firstHostTime,
            sampleRate: 48_000
        )

        metrics.record(
            buffer: clipped,
            time: AVAudioTime(hostTime: firstHostTime, sampleTime: 0, atRate: 48_000)
        )
        metrics.record(
            buffer: silent,
            time: AVAudioTime(hostTime: secondHostTime, sampleTime: 960, atRate: 48_000)
        )
        let result = try metrics.captureResult(byteCount: 100)

        #expect(result.gaps.count == 1)
        #expect(result.gaps.first?.reason == .droppedBuffers)
        #expect(result.gaps.first?.startMilliseconds == 10)
        #expect(result.gaps.first?.endMilliseconds == 20)
        #expect(result.quality.peakLevel == 1)
        #expect(result.quality.clippedFrameCount == 480)
        #expect(result.quality.silentDurationMilliseconds == 10)
        #expect(result.quality.droppedBufferCount == 1)
    }

    @Test func meetingSessionStoreSurfacesCorruptManifestWithoutReplacingIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingCorrupt-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingSessionStore(rootURL: root)
        let sessionID = UUID()
        let paths = try await store.prepareSession(id: sessionID)
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: paths.manifestURL)

        do {
            _ = try await store.load(sessionID: sessionID)
            Issue.record("A corrupt meeting manifest must not be silently accepted")
        } catch is DecodingError {
            // Expected: recovery UI can surface the damaged manifest explicitly.
        }
        #expect(try Data(contentsOf: paths.manifestURL) == corruptData)
    }

    @MainActor
    @Test func privacyModeAndProviderRemainCompatible() {
        let suiteName = "FlowDictateProviderPrivacy-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.privacyMode = .offline
        #expect(settings.transcriptionProviderID == .local)

        settings.privacyMode = .cloudTranscription
        #expect(settings.transcriptionProviderID == .openAI)

        settings.transcriptionProviderID = .local
        #expect(settings.privacyMode == .localWithOptionalCloudEnhancement)

        settings.transcriptionProviderID = .openAI
        #expect(settings.privacyMode == .cloudTranscription)
    }

    @MainActor
    @Test func privacySelectionPublishesOneNormalizedProviderTransition() {
        let suiteName = "FlowDictateAtomicProviderPrivacy-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        var observedModes: [PrivacyMode] = []
        var observedProviders: [TranscriptionProviderID] = []
        var cancellables: Set<AnyCancellable> = []

        settings.$privacyMode.dropFirst().sink { observedModes.append($0) }
            .store(in: &cancellables)
        settings.$transcriptionProviderID.dropFirst().sink { observedProviders.append($0) }
            .store(in: &cancellables)

        settings.selectPrivacyMode(.offline)

        #expect(observedModes == [.offline])
        #expect(observedProviders == [.local])
        #expect(settings.privacyMode == .offline)
        #expect(settings.transcriptionProviderID == .local)
    }

    @Test func localModelStoragePreparationWorksForFreshUser() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateFreshUser-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let modelsRoot = root.appendingPathComponent(
            "Library/Application Support/FlowDictate/Models",
            isDirectory: true
        )
        let manager = LocalModelManager(modelsRoot: modelsRoot)
        #expect(!FileManager.default.fileExists(atPath: root.path))

        let modelParent = try await manager.prepareModelStorage()

        #expect(modelParent == modelsRoot.appendingPathComponent(
            LocalModelCatalog.parakeetV3.id,
            isDirectory: true
        ))
        #expect(FileManager.default.fileExists(atPath: modelParent.path))
        #expect(try await manager.prepareModelStorage() == modelParent)
    }

    @Test func localModelPromotionMovesFluidAudioRepositoryAndPreservesReplacement() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateModelPromotion-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = LocalModelManager(modelsRoot: root)
        let repository = await manager.repositoryDirectory
        #expect(repository.lastPathComponent == "parakeet-tdt-0.6b-v3")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: repository.appendingPathComponent("marker"))

        let stagingRoot = repository.deletingLastPathComponent()
            .appendingPathComponent("staging-test", isDirectory: true)
        let stagedRepository = stagingRoot.appendingPathComponent(
            "parakeet-tdt-0.6b-v3",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: stagedRepository, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: stagedRepository.appendingPathComponent("marker"))

        try await manager.promoteDownloadedModel(from: stagingRoot)

        #expect(try String(contentsOf: repository.appendingPathComponent("marker"), encoding: .utf8) == "new")
        #expect(!FileManager.default.fileExists(atPath: stagedRepository.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: repository.deletingLastPathComponent().path)
        #expect(!leftovers.contains(where: { $0.hasPrefix("previous-") }))
    }

    @Test func removingLocalModelDeletesFluidAudioRepositoryRatherThanAnchor() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateModelRemoval-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = LocalModelManager(modelsRoot: root)
        let repository = await manager.repositoryDirectory
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: repository.appendingPathComponent("marker"))

        try await manager.remove()

        #expect(!FileManager.default.fileExists(atPath: repository.path))
    }

    @MainActor
    @Test func livePreviewDefaultsAreMigrationSafeAndCharacterLimitIsClamped() {
        let newSuite = "FlowDictateNewPreviewSettings-\(UUID())"
        let newDefaults = UserDefaults(suiteName: newSuite)!
        defer { newDefaults.removePersistentDomain(forName: newSuite) }
        let newSettings = AppSettings(defaults: newDefaults)
        #expect(newSettings.livePreviewEnabled)
        #expect(newSettings.overlaySize == .standard)
        #expect(newSettings.livePreviewCharacterLimit == 150)
        #expect(newSettings.overlayPosition == .bottomTrailing)
        newSettings.livePreviewCharacterLimit = 5_000
        #expect(newSettings.livePreviewCharacterLimit == 800)
        newSettings.overlaySize = .compact
        #expect(newSettings.livePreviewCharacterLimit == 800)
        #expect(!newSettings.overlaySize.showsLivePreviewText)
        #expect(newSettings.overlaySize.livePreviewCharacterRange == nil)
        newSettings.overlaySize = .standard
        #expect(newSettings.overlaySize.clampedLivePreviewCharacterLimit(newSettings.livePreviewCharacterLimit) == 200)

        let existingSuite = "FlowDictateExistingPreviewSettings-\(UUID())"
        let existingDefaults = UserDefaults(suiteName: existingSuite)!
        defer { existingDefaults.removePersistentDomain(forName: existingSuite) }
        existingDefaults.set(2, forKey: "onboardingVersion")
        let existingSettings = AppSettings(defaults: existingDefaults)
        #expect(!existingSettings.livePreviewEnabled)
    }

    @Test func transcriptionLanguageMapsAutomaticToNil() {
        #expect(TranscriptionLanguage.automatic.apiValue == nil)
        #expect(TranscriptionLanguage.german.apiValue == "de")
        #expect(TranscriptionLanguage.english.apiValue == "en")
    }

    @Test func spokenFormattingSupportsGermanCommandsAndLiteralEscape() {
        let processor = SpokenFormattingProcessor()
        let result = processor.process(
            "Hallo Komma das ist wörtlich Punkt Punkt neuer Absatz Aufzählung Ende Ausrufezeichen",
            language: "de"
        )
        #expect(result.text == "Hallo, das ist Punkt.\n\n• Ende!")
        #expect(result.replacementCount == 5)
    }

    @Test func spokenFormattingSupportsEnglishAndProtectsURLs() {
        let processor = SpokenFormattingProcessor()
        let result = processor.process(
            "Visit https://example.com/period and continue comma new line done period",
            language: "en"
        )
        #expect(result.text == "Visit https://example.com/period and continue,\ndone.")
    }

    @Test func spokenFormattingRemovesAutomaticCommasAndFormatsNumberedItems() {
        let processor = SpokenFormattingProcessor()
        let result = processor.process(
            "Ja, guten Morgen, neue Zeile, dies ist eine Testzeile, neue Zeile, Doppelpunkt, Punkt 1, bla bla, Punkt 2, Miau.",
            language: "de"
        )
        #expect(result.text == "Ja, guten Morgen\ndies ist eine Testzeile\n:\n1. bla bla\n2. Miau.")
        #expect(result.replacementCount == 5)
    }

    @Test func spokenFormattingConsumesTerminalPunctuationAfterCommands() {
        let processor = SpokenFormattingProcessor()

        let german = processor.process(
            "Ein neuer Test Doppelpunkt. Neue Zeile. Guten Morgen Punkt. Neue Zeile.",
            language: "de"
        )
        #expect(german.text == "Ein neuer Test:\nGuten Morgen.")

        let germanCommandSequence = processor.process(
            "Überschrift Doppelpunkt Neue Zeile erster Satz Punkt Neue Zeile zweiter Satz Punkt neuer Absatz Ende",
            language: "de"
        )
        #expect(germanCommandSequence.text == "Überschrift:\nerster Satz.\nzweiter Satz.\n\nEnde")

        let english = processor.process(
            "First line colon. New line. Continue period. New paragraph. Done exclamation mark.",
            language: "en"
        )
        #expect(english.text == "First line:\nContinue.\n\nDone!")

        let englishCommandSequence = processor.process(
            "Heading colon new line period new line new paragraph done period",
            language: "en"
        )
        #expect(englishCommandSequence.text == "Heading:\n.\n\ndone.")
    }

    @Test func spokenFormattingSupportsAbsatzAlias() {
        let processor = SpokenFormattingProcessor()
        let result = processor.process(
            "Erster Teil Absatz zweiter Teil",
            language: "de"
        )
        #expect(result.text == "Erster Teil\n\nzweiter Teil")
        #expect(result.replacementCount == 1)
    }

    @Test func personalDictionaryUsesWholeWordsLongestFirstAndDoesNotCascade() {
        let now = Date()
        let entries = [
            DictionaryEntry(
                id: UUID(), spokenForm: "Flow Diktat", replacement: "FlowDictate",
                language: "de", caseSensitive: false, matchWholeWordsOnly: true,
                isEnabled: true, createdAt: now, updatedAt: now
            ),
            DictionaryEntry(
                id: UUID(), spokenForm: "Flow", replacement: "Stream",
                language: "de", caseSensitive: false, matchWholeWordsOnly: true,
                isEnabled: true, createdAt: now.addingTimeInterval(1), updatedAt: now
            ),
            DictionaryEntry(
                id: UUID(), spokenForm: "FlowDictate", replacement: "MustNotCascade",
                language: "de", caseSensitive: false, matchWholeWordsOnly: true,
                isEnabled: true, createdAt: now.addingTimeInterval(2), updatedAt: now
            )
        ]
        let result = PersonalDictionaryProcessor().process(
            "Flow Diktat und Workflow Flow", entries: entries, language: "de"
        )
        #expect(result.text == "FlowDictate und Workflow Stream")
        #expect(result.replacementCount == 2)
    }

    @MainActor
    @Test func smartDictationSettingsPersistWithSafeDefaults() {
        let suite = "FlowDictateSmartSettings-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = AppSettings(defaults: defaults)
        #expect(!settings.spokenFormattingEnabled)
        #expect(settings.personalDictionaryEnabled)
        #expect(settings.writingStyleID == BuiltInWritingStyles.originalID)
        #expect(settings.smartDictationFallback == .ask)

        settings.spokenFormattingEnabled = true
        settings.personalDictionaryEnabled = false
        settings.writingStyleID = BuiltInWritingStyles.emailID
        settings.enhancementModel = "test-enhancement-model"
        settings.smartDictationFallback = .useLocallyProcessed
        settings = AppSettings(defaults: defaults)
        #expect(settings.spokenFormattingEnabled)
        #expect(!settings.personalDictionaryEnabled)
        #expect(settings.writingStyleID == BuiltInWritingStyles.emailID)
        #expect(settings.enhancementModel == "test-enhancement-model")
        #expect(settings.smartDictationFallback == .useLocallyProcessed)
    }

    @Test func dictionaryAndWritingStyleStoresRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSmartStores-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let dictionaryStore = DictionaryStore(fileURL: directory.appendingPathComponent("dictionary.json"))
        let entry = DictionaryEntry(
            id: UUID(), spokenForm: "Eulersche Zahl", replacement: "e",
            language: "de", caseSensitive: false, matchWholeWordsOnly: true,
            isEnabled: true, createdAt: now, updatedAt: now
        )
        try await dictionaryStore.upsert(entry)
        #expect(try await dictionaryStore.all() == [entry])

        let styleStore = WritingStyleStore(fileURL: directory.appendingPathComponent("styles.json"))
        let style = WritingStyleProfile(
            id: UUID(), name: "Concise", instruction: "Make the text concise without losing facts.",
            isBuiltIn: false, isEnabled: true, schemaVersion: 1
        )
        try await styleStore.upsert(style)
        #expect(try await styleStore.profile(id: style.id) == style)
        #expect(try await styleStore.all().count == BuiltInWritingStyles.all.count + 1)
    }

    @MainActor
    @Test func smartPipelineOriginalNeverCallsEnhancer() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSmartOriginal-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = DictationHistoryStore(fileURL: fileURL)
        let pipeline = SmartDictationPipeline(historyStore: store)
        let enhancer = MockTranscriptEnhancer(output: "must not be used")
        var record = makeTranscribedRecord(text: "Hallo Punkt")
        record = try await pipeline.run(
            record: record,
            spokenFormattingEnabled: true,
            dictionaryEntries: [],
            style: BuiltInWritingStyles.all[0],
            enhancementModel: "test",
            fallback: .ask,
            enhancer: enhancer
        )
        #expect(record.originalTranscript == "Hallo Punkt")
        #expect(record.finalText == "Hallo.")
        #expect(record.processingStatus == .completed)
        #expect(enhancer.callCount == 0)
    }

    @MainActor
    @Test func smartPipelineEnhancesAndFallbackKeepsLocalText() async throws {
        let successURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSmartSuccess-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: successURL) }
        let successPipeline = SmartDictationPipeline(historyStore: DictationHistoryStore(fileURL: successURL))
        let successEnhancer = MockTranscriptEnhancer(output: "Professioneller Text 42")
        let success = try await successPipeline.run(
            record: makeTranscribedRecord(text: "Text 42"), spokenFormattingEnabled: false,
            dictionaryEntries: [], style: BuiltInWritingStyles.all[4], enhancementModel: "test-model",
            fallback: .ask, enhancer: successEnhancer
        )
        #expect(success.finalText == "Professioneller Text 42")
        #expect(success.enhancementAttemptCount == 1)
        #expect(success.processingStatus == .completed)

        let failureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSmartFallback-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: failureURL) }
        let failurePipeline = SmartDictationPipeline(historyStore: DictationHistoryStore(fileURL: failureURL))
        let fallback = try await failurePipeline.run(
            record: makeTranscribedRecord(text: "Lokaler Text"), spokenFormattingEnabled: false,
            dictionaryEntries: [], style: BuiltInWritingStyles.all[4], enhancementModel: "test-model",
            fallback: .useLocallyProcessed, enhancer: MockTranscriptEnhancer(error: URLError(.notConnectedToInternet))
        )
        #expect(fallback.finalText == "Lokaler Text")
        #expect(fallback.processingStatus == .completed)
        #expect(fallback.enhancementErrorCategory == .network)
        #expect(fallback.enhancementFallback == .useLocallyProcessed)
    }

    @MainActor
    @Test func smartPipelineRejectsAssistantAnswerAndFallsBackToLocalText() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSmartAssistantAnswer-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let pipeline = SmartDictationPipeline(historyStore: DictationHistoryStore(fileURL: fileURL))

        let localText = """
        Ich habe eine Gmail-Adresse, die heißt 123traudich@gmail.com, und diese möchte ich gerne nutzen für Arbeiten in n8n. Dazu brauche ich eine Registrierung auf der Google-Konsole und die entsprechenden API-Zugänge. Kannst du das bitte für mich übernehmen?
        """
        let assistantAnswer = """
        Ich kann die Registrierung auf der Google-Konsole und die API-Zugänge nicht für dich übernehmen, aber ich kann dir erklären, wie du es selbst machen kannst.
        """
        let result = try await pipeline.run(
            record: makeTranscribedRecord(text: localText),
            spokenFormattingEnabled: false,
            dictionaryEntries: [],
            style: BuiltInWritingStyles.all[1],
            enhancementModel: "test-model",
            fallback: .useLocallyProcessed,
            enhancer: MockTranscriptEnhancer(output: assistantAnswer)
        )

        #expect(result.finalText == localText)
        #expect(result.processingStatus == .completed)
        #expect(result.enhancementErrorCategory == .providerPermanent)
        #expect(result.enhancementErrorMessage?.contains("answer the dictated text") == true)
        #expect(result.enhancementFallback == .useLocallyProcessed)
    }

    @Test func enhancementValidatorRejectsAssistantStyleAnswerToDictatedRequest() throws {
        let input = """
        Kannst du bitte für mich die Registrierung auf der Google-Konsole und die API-Zugänge übernehmen?
        """
        let output = """
        Ich kann die Registrierung auf der Google-Konsole und die API-Zugänge nicht für dich übernehmen, aber ich kann dir erklären, wie du es selbst machen kannst.
        """

        #expect(throws: TranscriptEnhancementError.self) {
            _ = try EnhancementResponseValidator().validate(
                output: output,
                input: input,
                protectedTerms: []
            )
        }
    }

    @MainActor
    @Test func queuedAIStyleStagesAllHistoryUntilOneFinalFlush() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateQueuedAIHistory-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("history.json")
        let store = DictationHistoryStore(fileURL: fileURL)
        let pipeline = SmartDictationPipeline(historyStore: store)

        let result = try await pipeline.run(
            record: makeTranscribedRecord(text: "Locally staged input"),
            spokenFormattingEnabled: false,
            dictionaryEntries: [],
            style: BuiltInWritingStyles.all[1],
            enhancementModel: "test-model",
            fallback: .ask,
            enhancer: MockTranscriptEnhancer(output: "Cloud-enhanced output"),
            deferSuccessfulPersistence: true
        )

        #expect(result.finalText == "Cloud-enhanced output")
        #expect(result.processingStatus == .completed)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try await store.record(id: result.id)?.finalText == "Cloud-enhanced output")

        try await store.flush()
        let reloaded = DictationHistoryStore(fileURL: fileURL)
        #expect(try await reloaded.record(id: result.id)?.finalText == "Cloud-enhanced output")
    }

    @MainActor
    @Test func smartPipelineSkipsDisallowedAIStyleAndKeepsLocalText() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSmartPrivacySkip-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let pipeline = SmartDictationPipeline(
            historyStore: DictationHistoryStore(fileURL: fileURL)
        )
        let enhancer = MockTranscriptEnhancer(output: "Must not be used")

        let result = try await pipeline.run(
            record: makeTranscribedRecord(text: "Lokaler Text Punkt"),
            spokenFormattingEnabled: true,
            dictionaryEntries: [],
            style: BuiltInWritingStyles.all[1],
            enhancementModel: "test-model",
            fallback: .ask,
            enhancer: enhancer,
            enhancementAllowed: false
        )

        #expect(result.finalText == "Lokaler Text.")
        #expect(result.writingStyleID == BuiltInWritingStyles.cleanedID)
        #expect(result.processingStatus == .completed)
        #expect(result.enhancementAttemptCount == 0)
        #expect(result.enhancementFallback == .useLocallyProcessed)
        #expect(enhancer.callCount == 0)
    }

    @MainActor
    @Test func smartPipelinePreservesFormattedLayoutThroughEnhancement() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSmartLayout-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let pipeline = SmartDictationPipeline(historyStore: DictationHistoryStore(fileURL: fileURL))
        let enhancer = EchoingLayoutMarkerEnhancer(outputPrefix: "Bereinigter Anfang", outputSuffix: "bereinigtes Ende")

        let result = try await pipeline.run(
            record: makeTranscribedRecord(text: "Erster Teil Neue Zeile. zweiter Teil"),
            spokenFormattingEnabled: true,
            dictionaryEntries: [],
            style: BuiltInWritingStyles.all[1],
            enhancementModel: "test-model",
            fallback: .ask,
            enhancer: enhancer
        )

        #expect(enhancer.receivedTexts.first?.contains("[[FLOWDICTATE_LAYOUT_BREAK_") == true)
        #expect(result.formattedTranscript == "Erster Teil\nzweiter Teil")
        #expect(result.finalText == "Bereinigter Anfang\nbereinigtes Ende")
        #expect(result.processingStatus == .completed)
    }

    @MainActor
    @Test func smartPipelineRejectsEnhancementThatDropsLayoutMarkers() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSmartMissingLayout-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let pipeline = SmartDictationPipeline(historyStore: DictationHistoryStore(fileURL: fileURL))

        await #expect(throws: SmartDictationRunFailure.self) {
            _ = try await pipeline.run(
                record: makeTranscribedRecord(text: "Erster Teil Neue Zeile zweiter Teil"),
                spokenFormattingEnabled: true,
                dictionaryEntries: [],
                style: BuiltInWritingStyles.all[1],
                enhancementModel: "test-model",
                fallback: .ask,
                enhancer: MockTranscriptEnhancer(output: "Bereinigter Anfang bereinigtes Ende")
            )
        }

        let stored = try await DictationHistoryStore(fileURL: fileURL).all().first
        #expect(stored?.processingStatus == .enhancementFailed)
        #expect(stored?.enhancementErrorMessage?.contains("layout marker is missing") == true)
    }

    @MainActor
    @Test func changingWritingStyleStartsFromExistingLocalStage() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateStyleOnly-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let pipeline = SmartDictationPipeline(historyStore: DictationHistoryStore(fileURL: fileURL))
        var record = makeTranscribedRecord(text: "Raw Punkt")
        record.formattedTranscript = "Previously formatted."
        record.dictionaryTranscript = "Protected local result 42"
        let enhancer = MockTranscriptEnhancer(output: "Styled local result 42")

        let result = try await pipeline.processWithStyle(
            record: record,
            style: BuiltInWritingStyles.all[4],
            model: "test-model",
            fallback: .ask,
            dictionaryEntries: [],
            enhancer: enhancer
        )

        #expect(enhancer.receivedTexts == ["Protected local result 42"])
        #expect(result.originalTranscript == "Raw Punkt")
        #expect(result.formattedTranscript == "Previously formatted.")
        #expect(result.finalText == "Styled local result 42")
    }

    @Test func interruptedLocalProcessingIsMarkedForDeterministicRecovery() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateInterruptedLocal-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = DictationHistoryStore(fileURL: fileURL)
        var record = makeTranscribedRecord(text: "Recover me")
        record.processingStatus = .formatting
        try await store.upsert(record)

        let recovered = try await store.recoverInterrupted()

        #expect(recovered.first?.processingStatus == .notStarted)
        #expect(recovered.first?.enhancementErrorCategory == .interrupted)
        #expect(try await store.record(id: record.id)?.originalTranscript == "Recover me")
    }

    @Test func phaseThreeHistoryMigrationCreatesBackupAndPreservesText() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSmartMigration-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("dictations.json")
        let record = makeTranscribedRecord(text: "Existing transcript")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(record)) as? [String: Any])
        for key in ["formattedTranscript", "dictionaryTranscript", "writingStyleID", "processingStatus",
                    "enhancementProviderID", "enhancementModelID", "enhancementAttemptCount",
                    "enhancementErrorCategory", "enhancementErrorMessage", "enhancementFallback",
                    "dictionaryReplacementCount",
                    "spokenFormattingEnabled"] {
            object.removeValue(forKey: key)
        }
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 2, "records": [object]])
            .write(to: fileURL)
        let store = DictationHistoryStore(fileURL: fileURL)
        let migrated = try #require(await store.all().first)
        #expect(migrated.originalTranscript == "Existing transcript")
        #expect(migrated.finalText == "Existing transcript")
        #expect(migrated.writingStyleID == BuiltInWritingStyles.originalID)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("dictations-pre-3.2.json").path))
    }

    @Test func audioLevelNormalizationHandlesSilenceAndClipping() {
        let silence: [Float] = [0, 0, 0]
        let quiet: [Float] = [0.05, -0.05]
        let loud: [Float] = [1, -1]

        let silenceLevel = silence.withUnsafeBufferPointer(AudioLevelMeter.normalizedRMS)
        let quietLevel = quiet.withUnsafeBufferPointer(AudioLevelMeter.normalizedRMS)
        let loudLevel = loud.withUnsafeBufferPointer(AudioLevelMeter.normalizedRMS)
        let aggregatedQuietLevel = AudioLevelMeter.normalizedRMS(
            sumOfSquares: 0.005,
            sampleCount: 2
        )

        #expect(silenceLevel == 0)
        #expect(quietLevel > 0.6 && quietLevel < 1)
        #expect(abs(aggregatedQuietLevel - quietLevel) < 0.000_1)
        #expect(loudLevel == 1)
    }

    @MainActor
    @Test func cancelStopsRecordingWithoutCallingProviderOrInserter() async throws {
        let harness = makeCoordinatorHarness()

        await harness.coordinator.toggleDictation()
        #expect(harness.coordinator.state == .recording)

        harness.coordinator.requestCancel()

        for _ in 0..<40 where harness.recorder.stopCount == 0 {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(harness.coordinator.state == .idle)
        #expect(harness.recorder.startCount == 1)
        #expect(harness.recorder.stopCount == 1)
        #expect(harness.provider.transcribeCount == 0)
        #expect(harness.inserter.insertCount == 0)
        #expect(harness.overlay.hideCount == 1)
    }

    @MainActor
    @Test func stopTranscribesAndInsertsExactlyOnce() async throws {
        let harness = makeCoordinatorHarness()

        await harness.coordinator.toggleDictation()
        await harness.coordinator.toggleDictation()

        #expect(harness.recorder.startCount == 1)
        #expect(harness.recorder.stopCount == 1)
        #expect(harness.provider.transcribeCount == 1)
        #expect(harness.inserter.insertCount == 1)
        #expect(harness.inserter.insertedText == "Transcribed text")
        #expect(harness.coordinator.state == .idle)
        #expect(harness.overlay.presentations.contains(.inserting))
        #expect(harness.overlay.presentations.last == .success(message: "Text inserted"))
        #expect(harness.overlay.presentations.filter {
            if case .success = $0 { true } else { false }
        }.count == 1)
        #expect(harness.processActivityManager.beginCount == 1)
        #expect(harness.processActivityManager.endCount == 1)
    }

    @MainActor
    @Test func pressAndHoldReleaseStopsTranscribesAndInserts() async throws {
        let harness = makeCoordinatorHarness()
        harness.coordinator.settings.dictationActivationMode = .pressAndHold

        harness.dictationHotKeyRegistrar.press()
        for _ in 0..<40 where !harness.recorder.isRecording {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(harness.recorder.isRecording)
        #expect(harness.recorder.startCount == 1)

        harness.dictationHotKeyRegistrar.release()
        for _ in 0..<80 where harness.inserter.insertCount == 0 {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(harness.recorder.stopCount == 1)
        #expect(harness.provider.transcribeCount == 1)
        #expect(harness.inserter.insertCount == 1)
        #expect(harness.coordinator.state == .idle)
    }

    @MainActor
    @Test func pressAndHoldConsentConsumesFirstShortcutCycleWithoutRecording() async throws {
        let presenter = MockMeetingRecordingConsentPresenter()
        let harness = makeCoordinatorHarness(
            recordingSource: .mixed,
            meetingRecordingConsentPresenter: presenter
        )
        harness.coordinator.settings.dictationActivationMode = .pressAndHold

        harness.dictationHotKeyRegistrar.press()
        for _ in 0..<40 where presenter.presentationCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        harness.dictationHotKeyRegistrar.release()

        #expect(presenter.presentationCount == 1)
        #expect(harness.recorder.startCount == 0)
        presenter.confirm(remember: true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(harness.recorder.startCount == 0)
        #expect(harness.coordinator.state == .idle)
        #expect(harness.coordinator.setupMessage?.contains("again") == true)
    }

    @MainActor
    @Test func mixedCaptureTestUsesSessionCoordinatorWithoutStartingTranscription() async throws {
        var completedSession = makeValidMixedRecordingSession()
        completedSession.status = .queued
        let mixedCoordinator = MockMixedRecordingSessionCoordinator(
            startResult: completedSession,
            stopResult: completedSession
        )
        let harness = makeCoordinatorHarness(
            recordingSource: .mixed,
            mixedRecordingCoordinatorFactory: { _ in mixedCoordinator },
            mixedCaptureTestDuration: .milliseconds(1)
        )
        harness.coordinator.settings.acceptCurrentMeetingRecordingConsent()

        harness.coordinator.runMixedCaptureTest()
        for _ in 0..<80 where harness.coordinator.isMixedCaptureTestRunning {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(await mixedCoordinator.startCount == 1)
        #expect(await mixedCoordinator.stopCount == 1)
        #expect(await mixedCoordinator.cancelCount == 0)
        #expect(harness.recorder.startCount == 0)
        #expect(harness.provider.transcribeCount == 0)
        #expect(harness.inserter.insertCount == 0)
        #expect(harness.coordinator.mixedCaptureTestMessage?.contains("completed") == true)
        #expect(harness.coordinator.latestOutputURL?.lastPathComponent == completedSession.id.uuidString)
        #expect(harness.overlay.presentations.contains(.recording))
        #expect(harness.overlay.presentations.contains(.finalizing))
        #expect(harness.overlay.meetingLevels.contains { update in
            update.microphone == 0.25 && update.systemAudio == 0
        })
        #expect(harness.overlay.meetingLevels.contains { update in
            update.microphone == 0.25 && update.systemAudio == 0.75
        })
    }

    @MainActor
    @Test func mixedToggleRunsCaptureProcessingAndInsertionExactlyOnce() async throws {
        var recording = makeValidMixedRecordingSession()
        recording.status = .recording
        for index in recording.tracks.indices {
            recording.tracks[index].status = .recording
        }
        var queued = makeValidMixedRecordingSession()
        queued.status = .queued
        var completed = queued
        completed.status = .completed
        completed.mergedTimelineRelativePath = "transcription/merged-timeline.json"
        completed.finalTranscript = "[You] Hello\n[System Audio] Welcome"
        completed.completionMode = .allTracks
        completed.transcriptInsertionState = .ready
        completed.transcriptInsertionAttemptCount = 0
        for index in completed.tracks.indices {
            completed.tracks[index].status = .transcribed
            completed.tracks[index].transcriptionSessionID = UUID()
            completed.tracks[index].transcriptRelativePath = index == 0
                ? "transcription/microphone.json"
                : "transcription/system-audio.json"
        }
        let mixedCoordinator = MockMixedRecordingSessionCoordinator(
            startResult: recording,
            stopResult: queued
        )
        let workflow = StubMeetingProcessingWorkflow(result: completed)
        let insertionGate = StubMeetingTranscriptInsertionGate(
            beginDecision: .authorized(completed.finalTranscript!)
        )
        let harness = makeCoordinatorHarness(
            recordingSource: .mixed,
            mixedRecordingCoordinatorFactory: { _ in mixedCoordinator },
            meetingProcessingWorkflow: workflow,
            meetingTranscriptInsertionGate: insertionGate
        )
        harness.coordinator.settings.acceptCurrentMeetingRecordingConsent()

        await harness.coordinator.toggleDictation()
        #expect(harness.coordinator.state == .recording)
        #expect(harness.coordinator.isRecording)

        await harness.coordinator.toggleDictation()

        #expect(await mixedCoordinator.startCount == 1)
        #expect(await mixedCoordinator.stopCount == 1)
        #expect(await mixedCoordinator.cancelCount == 0)
        #expect(await workflow.runCount == 1)
        #expect(await insertionGate.beginCount == 1)
        #expect(await insertionGate.completedCount == 1)
        #expect(await insertionGate.deferredCount == 0)
        #expect(harness.recorder.startCount == 0)
        #expect(harness.provider.transcribeCount == 0)
        #expect(harness.inserter.insertCount == 1)
        #expect(harness.inserter.insertedText == completed.finalTranscript)
        #expect(harness.coordinator.state == .idle)
        #expect(harness.processActivityManager.beginCount == 1)
        #expect(harness.processActivityManager.endCount == 1)
    }

    @MainActor
    @Test func mixedPressAndHoldReleaseStopsAndProcessesOnce() async throws {
        var recording = makeValidMixedRecordingSession()
        recording.status = .recording
        for index in recording.tracks.indices {
            recording.tracks[index].status = .recording
        }
        var queued = makeValidMixedRecordingSession()
        queued.status = .queued
        var completed = queued
        completed.status = .completed
        completed.mergedTimelineRelativePath = "transcription/merged-timeline.json"
        completed.finalTranscript = "[You] Held shortcut"
        completed.completionMode = .allTracks
        completed.transcriptInsertionState = .ready
        completed.transcriptInsertionAttemptCount = 0
        for index in completed.tracks.indices {
            completed.tracks[index].status = .transcribed
            completed.tracks[index].transcriptionSessionID = UUID()
            completed.tracks[index].transcriptRelativePath = "transcription/track-\(index).json"
        }
        let mixedCoordinator = MockMixedRecordingSessionCoordinator(
            startResult: recording,
            stopResult: queued
        )
        let workflow = StubMeetingProcessingWorkflow(result: completed)
        let insertionGate = StubMeetingTranscriptInsertionGate(
            beginDecision: .authorized(completed.finalTranscript!)
        )
        let harness = makeCoordinatorHarness(
            recordingSource: .mixed,
            mixedRecordingCoordinatorFactory: { _ in mixedCoordinator },
            meetingProcessingWorkflow: workflow,
            meetingTranscriptInsertionGate: insertionGate
        )
        harness.coordinator.settings.acceptCurrentMeetingRecordingConsent()
        harness.coordinator.settings.dictationActivationMode = .pressAndHold

        harness.dictationHotKeyRegistrar.press()
        for _ in 0..<80 where !harness.coordinator.isRecording {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(harness.coordinator.isRecording)

        harness.dictationHotKeyRegistrar.release()
        for _ in 0..<120 where harness.inserter.insertCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(await mixedCoordinator.startCount == 1)
        #expect(await mixedCoordinator.stopCount == 1)
        #expect(await workflow.runCount == 1)
        #expect(harness.inserter.insertCount == 1)
        #expect(harness.coordinator.state == .idle)
    }

    @MainActor
    @Test func completedExternalMixedInsertionIsNeverDowngradedWhenGatePersistenceFails() async throws {
        var recording = makeValidMixedRecordingSession()
        recording.status = .recording
        for index in recording.tracks.indices {
            recording.tracks[index].status = .recording
        }
        var queued = makeValidMixedRecordingSession()
        queued.status = .queued
        var completed = queued
        completed.status = .completed
        completed.mergedTimelineRelativePath = "transcription/merged-timeline.json"
        completed.finalTranscript = "[You] Persist conservatively"
        completed.completionMode = .allTracks
        completed.transcriptInsertionState = .ready
        completed.transcriptInsertionAttemptCount = 0
        for index in completed.tracks.indices {
            completed.tracks[index].status = .transcribed
            completed.tracks[index].transcriptionSessionID = UUID()
            completed.tracks[index].transcriptRelativePath = "transcription/track-\(index).json"
        }
        let mixedCoordinator = MockMixedRecordingSessionCoordinator(
            startResult: recording,
            stopResult: queued
        )
        let insertionGate = StubMeetingTranscriptInsertionGate(
            beginDecision: .authorized(completed.finalTranscript!),
            failMarkCompleted: true
        )
        let harness = makeCoordinatorHarness(
            recordingSource: .mixed,
            mixedRecordingCoordinatorFactory: { _ in mixedCoordinator },
            meetingProcessingWorkflow: StubMeetingProcessingWorkflow(result: completed),
            meetingTranscriptInsertionGate: insertionGate
        )
        harness.coordinator.settings.acceptCurrentMeetingRecordingConsent()

        await harness.coordinator.toggleDictation()
        await harness.coordinator.toggleDictation()

        #expect(harness.inserter.insertCount == 1)
        #expect(await insertionGate.completedCount == 1)
        #expect(await insertionGate.deferredCount == 0)
        guard case .failed = harness.coordinator.state else {
            Issue.record("Expected uncertain insertion persistence to require recovery")
            return
        }
    }

    @MainActor
    @Test func cancellingMixedRecordingPreservesSessionWithoutProcessing() async throws {
        var recording = makeValidMixedRecordingSession()
        recording.status = .recording
        for index in recording.tracks.indices {
            recording.tracks[index].status = .recording
        }
        var queued = makeValidMixedRecordingSession()
        queued.status = .queued
        var cancelled = queued
        cancelled.status = .cancelled
        let mixedCoordinator = MockMixedRecordingSessionCoordinator(
            startResult: recording,
            stopResult: queued,
            cancelResult: cancelled
        )
        let workflow = StubMeetingProcessingWorkflow(result: queued)
        let insertionGate = StubMeetingTranscriptInsertionGate(beginDecision: .deferred)
        let harness = makeCoordinatorHarness(
            recordingSource: .mixed,
            mixedRecordingCoordinatorFactory: { _ in mixedCoordinator },
            meetingProcessingWorkflow: workflow,
            meetingTranscriptInsertionGate: insertionGate
        )
        harness.coordinator.settings.acceptCurrentMeetingRecordingConsent()

        await harness.coordinator.toggleDictation()
        harness.coordinator.requestCancel()
        for _ in 0..<80 {
            if await mixedCoordinator.cancelCount > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(await mixedCoordinator.cancelCount == 1)
        #expect(await mixedCoordinator.stopCount == 0)
        #expect(await workflow.runCount == 0)
        #expect(await insertionGate.beginCount == 0)
        #expect(harness.inserter.insertCount == 0)
        #expect(harness.coordinator.state == .idle)
        #expect(harness.overlay.hideCount == 1)
    }

    @MainActor
    @Test func pausedMixedProcessingStaysRecoverableWithoutAttemptingInsertion() async throws {
        var recording = makeValidMixedRecordingSession()
        recording.status = .recording
        for index in recording.tracks.indices {
            recording.tracks[index].status = .recording
        }
        var queued = makeValidMixedRecordingSession()
        queued.status = .queued
        var paused = queued
        paused.status = .paused
        paused.lastErrorMessage = "One track still needs transcription."
        let mixedCoordinator = MockMixedRecordingSessionCoordinator(
            startResult: recording,
            stopResult: queued
        )
        let workflow = StubMeetingProcessingWorkflow(result: paused)
        let insertionGate = StubMeetingTranscriptInsertionGate(beginDecision: .deferred)
        let harness = makeCoordinatorHarness(
            recordingSource: .mixed,
            mixedRecordingCoordinatorFactory: { _ in mixedCoordinator },
            meetingProcessingWorkflow: workflow,
            meetingTranscriptInsertionGate: insertionGate
        )
        harness.coordinator.settings.acceptCurrentMeetingRecordingConsent()

        await harness.coordinator.toggleDictation()
        await harness.coordinator.toggleDictation()

        #expect(await workflow.runCount == 1)
        #expect(await insertionGate.beginCount == 0)
        #expect(harness.inserter.insertCount == 0)
        guard case let .failed(message, retainedAudioURL) = harness.coordinator.state else {
            Issue.record("Expected paused mixed processing to remain recoverable")
            return
        }
        #expect(message == paused.lastErrorMessage)
        #expect(retainedAudioURL?.lastPathComponent == paused.id.uuidString)
        #expect(harness.coordinator.latestOutputNotice?.contains("History") == true)
    }

    @MainActor
    @Test func continuingMeetingFromHistoryDefersInsertionUntilExplicitUserAction() async throws {
        var paused = makeValidMixedRecordingSession()
        paused.status = .paused
        paused.lastErrorCategory = .interrupted
        paused.lastErrorMessage = "Meeting processing was interrupted."
        paused.tracks[0].status = .interrupted
        let record = try DictationRecord.meetingSession(paused)

        var completed = makeValidMixedRecordingSession()
        completed.id = paused.id
        completed.recordID = paused.recordID
        completed.status = .completed
        completed.mergedTimelineRelativePath = MeetingTranscriptMergeRunner.timelineRelativePath
        completed.finalTranscript = "[You] Recovered\n[System Audio] Safely"
        completed.completionMode = .allTracks
        completed.transcriptInsertionState = .ready
        completed.transcriptInsertionAttemptCount = 0
        for index in completed.tracks.indices {
            completed.tracks[index].status = .transcribed
            completed.tracks[index].transcriptionSessionID = UUID()
            completed.tracks[index].transcriptRelativePath =
                "transcription/track-\(index).json"
        }
        let workflow = StubMeetingProcessingWorkflow(result: completed)
        let insertionGate = StubMeetingTranscriptInsertionGate(beginDecision: .deferred)
        let harness = makeCoordinatorHarness(
            recordingSource: .mixed,
            meetingProcessingWorkflow: workflow,
            meetingTranscriptInsertionGate: insertionGate
        )

        harness.coordinator.continueMeetingProcessing(record)
        for _ in 0..<80 {
            if await workflow.runCount > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        for _ in 0..<80 where harness.coordinator.state != .idle {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(await workflow.runCount == 1)
        #expect(await insertionGate.beginCount == 1)
        #expect(await insertionGate.lastTargetIsAvailable == false)
        #expect(harness.inserter.insertCount == 0)
        #expect(harness.coordinator.latestOutputNotice?.contains("History") == true)
        #expect(harness.coordinator.state == .idle)
    }

    @MainActor
    @Test func confirmedMeetingDeletionRemovesHistoryAndEntireSessionDirectory() async throws {
        let harness = makeCoordinatorHarness(recordingSource: .mixed)
        let store = MeetingSessionStore(
            recordingLocationStore: harness.recordingLocationStore
        )
        var session = makeValidMixedRecordingSession()
        session.status = .completed
        session.finalTranscript = "[You] Delete me"
        session.mergedTimelineRelativePath = MeetingTranscriptMergeRunner.timelineRelativePath
        session.completionMode = .allTracks
        session.transcriptInsertionState = .deferred
        session.transcriptInsertionAttemptCount = 0
        for index in session.tracks.indices {
            session.tracks[index].status = .transcribed
            session.tracks[index].transcriptionSessionID = UUID()
            session.tracks[index].transcriptRelativePath =
                "transcription/track-\(index).json"
        }
        let paths = try await store.prepareSession(id: session.id)
        for track in session.tracks {
            try Data("original-\(track.role.rawValue)".utf8).write(
                to: paths.sessionDirectory.appendingPathComponent(track.audioRelativePath!)
            )
            try Data("track transcript".utf8).write(
                to: paths.sessionDirectory.appendingPathComponent(track.transcriptRelativePath!)
            )
        }
        try Data("derived".utf8).write(
            to: paths.derivedDirectory.appendingPathComponent("normalized.caf")
        )
        try Data("timeline".utf8).write(
            to: paths.sessionDirectory.appendingPathComponent(
                MeetingTranscriptMergeRunner.timelineRelativePath
            )
        )
        try await store.create(session)
        let linkedJob = makePhaseFourJob(sequence: 1)
        let unrelatedJob = makePhaseFourJob(sequence: 2)
        try await harness.jobStore.create(linkedJob)
        try await harness.jobStore.create(unrelatedJob)
        var record = try DictationRecord.meetingSession(session)
        record.jobID = linkedJob.id
        try await harness.historyStore.upsert(record)
        await harness.coordinator.refreshHistory()

        harness.coordinator.deleteMeetingSession(record)
        for _ in 0..<100 {
            let historyWasDeleted = try await harness.historyStore.record(id: record.id) == nil
            let filesWereDeleted = !FileManager.default.fileExists(
                atPath: paths.sessionDirectory.path
            )
            if historyWasDeleted && filesWereDeleted { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(try await harness.historyStore.record(id: record.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: paths.sessionDirectory.path))
        #expect(try await harness.jobStore.job(id: linkedJob.id) == nil)
        #expect(try await harness.jobStore.job(id: unrelatedJob.id)?.id == unrelatedJob.id)
        #expect(harness.coordinator.setupMessage
            == "Meeting session and both original tracks were deleted.")
    }

    @MainActor
    @Test func tooShortRecordingFailsBeforeTranscriptionProvider() async throws {
        let harness = makeCoordinatorHarness(recordingSource: .systemAudio)
        harness.coordinator.settings.dictationActivationMode = .pressAndHold
        harness.recorder.resultDuration = 0.2

        harness.dictationHotKeyRegistrar.press()
        for _ in 0..<40 where !harness.recorder.isRecording {
            try await Task.sleep(for: .milliseconds(25))
        }

        harness.dictationHotKeyRegistrar.release()
        for _ in 0..<80 where harness.recorder.stopCount == 0 {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(harness.recorder.stopCount == 1)
        #expect(harness.provider.transcribeCount == 0)
        #expect(harness.inserter.insertCount == 0)
        guard case let .failed(message, _) = harness.coordinator.state else {
            Issue.record("Expected too-short recording to fail before transcription")
            return
        }
        #expect(message.contains("too short"))
        #expect(harness.coordinator.historyRecords.first?.status == .transcriptionFailed)
        #expect(harness.coordinator.historyRecords.first?.errorCategory == .transcriptionPreflight)
    }

    @MainActor
    @Test func emptyTranscriptionUnlocksRecordingSourceAfterFailure() async throws {
        let harness = makeCoordinatorHarness()
        harness.provider.error = TranscriptionProviderError.emptyTranscript

        await harness.coordinator.toggleDictation()
        await harness.coordinator.toggleDictation()

        guard case .failed = harness.coordinator.state else {
            Issue.record("Expected an empty recording to end in a recoverable failed state")
            return
        }
        #expect(!harness.coordinator.isRecording)
        #expect(!harness.coordinator.isProcessing)

        harness.coordinator.selectRecordingAudioSource(.systemAudio)
        #expect(harness.coordinator.settings.recordingAudioSource == .systemAudio)
    }

    @MainActor
    @Test func insertedOverlayDismissesPromptlyAndReturnsToIdle() async throws {
        let harness = makeCoordinatorHarness()

        await harness.coordinator.toggleDictation()
        await harness.coordinator.toggleDictation()

        for _ in 0..<50 where harness.overlay.hideCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(harness.overlay.hideCount == 1)
        #expect(harness.coordinator.state == .idle)
    }

    @MainActor
    @Test func newRecordingRemainsDisabledUntilCurrentDictationCompletes() async throws {
        let harness = makeCoordinatorHarness()
        harness.provider.delay = .milliseconds(400)

        await harness.coordinator.toggleDictation()
        let processing = Task { await harness.coordinator.toggleDictation() }
        for _ in 0..<40 where harness.provider.transcribeCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(harness.provider.transcribeCount == 1)
        #expect(!harness.coordinator.canStartNewRecording)
        harness.coordinator.requestToggle()
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.recorder.startCount == 1)

        await processing.value
        #expect(harness.coordinator.canStartNewRecording)
    }

    @MainActor
    @Test func completedInsertionDoesNotWaitForOverlayDismissal() async throws {
        let harness = makeCoordinatorHarness()

        await harness.coordinator.toggleDictation()
        await harness.coordinator.toggleDictation()

        #expect(harness.coordinator.state == .idle)
        #expect(harness.overlay.hideCount == 0)
        await harness.coordinator.toggleDictation()
        #expect(harness.coordinator.state == .recording)
        #expect(harness.overlay.presentations.last == .recording)
        #expect(harness.overlay.hideCount == 0)
    }

    @MainActor
    @Test func acceptedNewHotkeyClearsPendingSuccessOverlayImmediately() async throws {
        let harness = makeCoordinatorHarness()

        await harness.coordinator.toggleDictation()
        await harness.coordinator.toggleDictation()
        #expect(harness.coordinator.state == .idle)
        #expect(harness.overlay.hideCount == 0)

        harness.coordinator.requestToggle()

        #expect(harness.overlay.hideCount == 1)
        for _ in 0..<50 where harness.recorder.startCount < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(harness.recorder.startCount == 2)
        #expect(harness.coordinator.state == .recording)

        await harness.coordinator.toggleDictation()
    }

    @MainActor
    @Test func providerChangeRequiresRestartAndBlocksNewRecording() async {
        let harness = makeCoordinatorHarness(
            transcriptionProviderID: .openAI,
            privacyMode: .cloudTranscription
        )

        #expect(!harness.coordinator.transcriptionRestartRequired)
        harness.coordinator.settings.selectTranscriptionProvider(.local)

        #expect(harness.coordinator.transcriptionRestartRequired)
        #expect(!harness.coordinator.canStartNewRecording)
        await harness.coordinator.toggleDictation()
        #expect(harness.recorder.startCount == 0)
    }

    @MainActor
    @Test func recognitionModelChangeRequiresRestart() {
        let harness = makeCoordinatorHarness()

        #expect(!harness.coordinator.transcriptionRestartRequired)
        harness.coordinator.settings.transcriptionModel = "another-transcription-model"

        #expect(harness.coordinator.transcriptionRestartRequired)
        #expect(!harness.coordinator.canStartNewRecording)
    }

    @MainActor
    @Test func restartReleasesEveryHotkeyBeforeOpeningTheNewInstance() async throws {
        let restarter = MockApplicationRestarter()
        let harness = makeCoordinatorHarness(applicationRestarter: restarter)
        let registrars = [
            harness.dictationHotKeyRegistrar,
            harness.cancelHotKeyRegistrar,
            harness.restoreHotKeyRegistrar
        ]
        #expect(registrars.allSatisfy { $0.isRegistered })
        restarter.onOpen = {
            #expect(registrars.allSatisfy { !$0.isRegistered })
        }

        harness.coordinator.quitAndRestart()
        harness.coordinator.quitAndRestart()
        #expect(registrars.allSatisfy { !$0.isRegistered })
        for _ in 0..<100 where restarter.terminateCount == 0 {
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(restarter.openCount == 1)
        #expect(restarter.terminateCount == 1)
        #expect(registrars.allSatisfy { $0.unregisterCount == 1 })
    }

    @MainActor
    @Test func failedRestartRestoresEveryHotkeyInTheOriginalInstance() async throws {
        let restarter = MockApplicationRestarter()
        restarter.openError = NSError(domain: "FlowDictateRestartTest", code: 1)
        let harness = makeCoordinatorHarness(applicationRestarter: restarter)
        let registrars = [
            harness.dictationHotKeyRegistrar,
            harness.cancelHotKeyRegistrar,
            harness.restoreHotKeyRegistrar
        ]

        harness.coordinator.quitAndRestart()
        for _ in 0..<100 where registrars.contains(where: { !$0.isRegistered }) {
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(restarter.openCount == 1)
        #expect(restarter.terminateCount == 0)
        #expect(registrars.allSatisfy { $0.isRegistered })
        #expect(registrars.allSatisfy { $0.registerCount == 2 })
        #expect(harness.coordinator.setupMessage?.contains("could not restart") == true)
    }

    @MainActor
    @Test func systemAudioCompletionConfirmsAndRetainsClipboardText() async throws {
        let pasteboard = NSPasteboard.general
        let originalClipboard = PasteboardSnapshot.capture(from: pasteboard)
        defer { originalClipboard.restore(to: pasteboard) }
        let harness = makeCoordinatorHarness(recordingSource: .systemAudio)

        await harness.coordinator.toggleDictation()
        await harness.coordinator.toggleDictation()

        #expect(pasteboard.string(forType: .string) == "Transcribed text")
        #expect(
            harness.coordinator.latestOutputNotice
                == "System Audio transcript copied to the clipboard."
        )
        #expect(
            harness.overlay.presentations.last
                == .success(message: "Text inserted · copied to clipboard")
        )
    }

    @MainActor
    @Test func stopShortcutIsAcknowledgedBeforeSlowRecorderFinalization() async throws {
        let harness = makeCoordinatorHarness()
        await harness.coordinator.toggleDictation()
        harness.recorder.stopDelay = .milliseconds(250)

        harness.coordinator.requestToggle()

        #expect(harness.coordinator.state == .finalizing)
        #expect(harness.overlay.presentations.last == .finalizing)

        for _ in 0..<60 where !harness.coordinator.canStartNewRecording {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(harness.recorder.stopCount == 1)
        #expect(harness.coordinator.canStartNewRecording)
    }

    @MainActor
    @Test func duplicateToggleDuringStartDoesNotImmediatelyStopRecording() async throws {
        let harness = makeCoordinatorHarness()
        harness.recorder.startDelay = .milliseconds(150)

        harness.coordinator.requestToggle()
        harness.coordinator.requestToggle()

        for _ in 0..<40 where !harness.recorder.isRecording {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(harness.recorder.startCount == 1)
        #expect(harness.recorder.stopCount == 0)
        #expect(harness.recorder.isRecording)
        #expect(harness.coordinator.state == .recording)
    }

    @MainActor
    @Test func openingSettingsDuringRecordingReassertsOverlayWithoutRestartingAudio() async throws {
        let harness = makeCoordinatorHarness()
        await harness.coordinator.toggleDictation()
        let presentationCount = harness.overlay.presentations.count

        harness.coordinator.restoreRecordingOverlayAfterSettingsActivation()

        #expect(harness.coordinator.state == .recording)
        #expect(harness.recorder.startCount == 1)
        #expect(harness.overlay.presentations.count == presentationCount + 1)
        #expect(harness.overlay.presentations.last == .recording)
    }

    @MainActor
    @Test func restoreUsesRecordedApplicationWhenNoExternalAppIsFrontmost() async throws {
        let harness = makeCoordinatorHarness()
        await harness.coordinator.toggleDictation()
        await harness.coordinator.toggleDictation()
        #expect(harness.inserter.insertCount == 1)

        harness.focusTargetBox.target = nil
        harness.coordinator.restoreLastDictation()
        for _ in 0..<40 where harness.inserter.insertCount < 2 {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(harness.inserter.insertCount == 2)
        #expect(harness.inserter.insertedText == "Transcribed text")
    }

    @MainActor
    @Test func restoreDoesNotInterruptAnActiveRecording() async throws {
        let harness = makeCoordinatorHarness()
        await harness.coordinator.toggleDictation()

        harness.coordinator.restoreLastDictation()
        try await Task.sleep(for: .milliseconds(50))

        #expect(harness.coordinator.state == .recording)
        #expect(harness.recorder.isRecording)
        #expect(harness.inserter.insertCount == 0)
    }

    @MainActor
    @Test func previewFailureDoesNotInterruptRecordingOrFinalTranscription() async throws {
        let previewProvider = MockLivePreviewProvider()
        let harness = makeCoordinatorHarness(
            livePreviewProvider: previewProvider,
            livePreviewEnabled: true
        )

        await harness.coordinator.toggleDictation()
        #expect(harness.recorder.previewBufferHandler != nil)
        #expect(previewProvider.startCount == 1)
        previewProvider.emit(.failed("Preview test failure"))
        #expect(harness.coordinator.state == .recording)
        #expect(harness.recorder.previewBufferHandler == nil)

        await harness.coordinator.toggleDictation()
        #expect(harness.provider.transcribeCount == 1)
        #expect(harness.inserter.insertCount == 1)
        #expect(harness.coordinator.state == .idle)
    }

    @MainActor
    @Test func overlaySizeAndPositionChangesApplyImmediatelyDuringRecording() async throws {
        let previewProvider = MockLivePreviewProvider()
        let harness = makeCoordinatorHarness(
            livePreviewProvider: previewProvider,
            livePreviewEnabled: true
        )
        await harness.coordinator.toggleDictation()
        #expect(harness.coordinator.state == .recording)
        #expect(harness.recorder.previewBufferHandler != nil)
        #expect(previewProvider.startCount == 1)

        harness.coordinator.settings.overlaySize = .expanded
        #expect(harness.overlay.configurations.last?.size == .expanded)
        #expect(previewProvider.startCount == 1)
        harness.coordinator.settings.overlaySize = .compact
        #expect(harness.overlay.configurations.last?.size == .compact)
        #expect(harness.recorder.previewBufferHandler == nil)
        harness.coordinator.settings.overlayPosition = .bottomCenter
        #expect(harness.overlay.configurations.last?.position == .bottomCenter)
        #expect(harness.overlay.configurations.last?.size == .compact)
        #expect(previewProvider.startCount == 1)

        harness.coordinator.settings.overlaySize = .standard
        #expect(harness.overlay.configurations.last?.size == .standard)
        #expect(harness.recorder.previewBufferHandler != nil)
        #expect(previewProvider.startCount == 2)
        harness.coordinator.settings.overlayPosition = .bottomTrailing
        #expect(harness.overlay.configurations.last?.position == .bottomTrailing)
        #expect(previewProvider.startCount == 2)

        harness.coordinator.requestCancel()
        for _ in 0..<40 where harness.recorder.stopCount == 0 {
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    @MainActor
    @Test func livePreviewCharacterLimitUpdatesDuringActiveRecording() async throws {
        let previewProvider = MockLivePreviewProvider()
        let harness = makeCoordinatorHarness(
            livePreviewProvider: previewProvider,
            livePreviewEnabled: true
        )
        harness.coordinator.settings.livePreviewCharacterLimit = 50

        await harness.coordinator.toggleDictation()
        #expect(harness.recorder.previewBufferHandler != nil)

        previewProvider.emit(.partial(String(repeating: "a", count: 80)))
        let firstExpected = LivePreviewState.active(String(repeating: "a", count: 50))
        for _ in 0..<40 where !harness.overlay.previewStates.contains(firstExpected) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(harness.overlay.previewStates.contains(firstExpected))

        harness.coordinator.settings.livePreviewCharacterLimit = 100
        previewProvider.emit(.partial(String(repeating: "b", count: 120)))
        let secondExpected = LivePreviewState.active(String(repeating: "b", count: 100))
        for _ in 0..<40 where !harness.overlay.previewStates.contains(secondExpected) {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(harness.overlay.previewStates.contains(secondExpected))
        harness.coordinator.requestCancel()
        for _ in 0..<40 where harness.recorder.stopCount == 0 {
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    @MainActor
    @Test func livePreviewAvailabilityIsCachedAcrossRepeatedUIReads() {
        var resolutionCount = 0
        let harness = makeCoordinatorHarness(
            livePreviewAvailabilityProvider: { _, _ in
                resolutionCount += 1
                return .available(localeIdentifier: "de-DE")
            }
        )

        let initialResolutionCount = resolutionCount
        #expect(initialResolutionCount >= 1)
        for _ in 0..<100 {
            _ = harness.coordinator.livePreviewAvailability.statusText
        }
        #expect(resolutionCount == initialResolutionCount)
    }

    @MainActor
    @Test func changingRecordingSourceCancelsStaleLivePreviewResources() {
        let previewProvider = MockLivePreviewProvider()
        let harness = makeCoordinatorHarness(livePreviewProvider: previewProvider)
        let previousCancelCount = previewProvider.cancelCount

        harness.coordinator.selectRecordingAudioSource(.systemAudio)

        #expect(harness.coordinator.settings.recordingAudioSource == .systemAudio)
        #expect(previewProvider.cancelCount == previousCancelCount + 1)
        #expect(harness.recorder.previewBufferHandler == nil)
    }

    @MainActor
    @Test func disabledPreviewDoesNotStartProviderOrAttachAudioHandler() async throws {
        let previewProvider = MockLivePreviewProvider()
        let harness = makeCoordinatorHarness(livePreviewProvider: previewProvider)

        await harness.coordinator.toggleDictation()

        #expect(harness.coordinator.state == .recording)
        #expect(previewProvider.startCount == 0)
        #expect(harness.recorder.previewBufferHandler == nil)

        harness.coordinator.requestCancel()
        for _ in 0..<40 where harness.recorder.stopCount == 0 {
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    @MainActor
    @Test func launchAtLoginStatusMapsApprovalRequirement() {
        #expect(LaunchAtLoginState(serviceStatus: .enabled) == .enabled)
        #expect(LaunchAtLoginState(serviceStatus: .notRegistered) == .disabled)
        #expect(LaunchAtLoginState(serviceStatus: .requiresApproval) == .requiresApproval)
        #expect(LaunchAtLoginState(serviceStatus: .notFound) == .unavailable)
    }

    @Test func failureClassifierRetriesOnlyTemporaryFailures() {
        #expect(DictationFailureClassifier.isRetryable(URLError(.notConnectedToInternet)))
        #expect(DictationFailureClassifier.isRetryable(
            TranscriptionProviderError.server(statusCode: 503, message: "Unavailable")
        ))
        #expect(!DictationFailureClassifier.isRetryable(
            TranscriptionProviderError.server(statusCode: 401, message: "Unauthorized")
        ))
        #expect(DictationFailureClassifier.category(for:
            TranscriptionProviderError.server(statusCode: 429, message: "Limited")
        ) == .rateLimit)
    }

    @Test func historyStorePersistsAndRecoversInterruptedStates() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateHistoryTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("history.json")
        let store = DictationHistoryStore(fileURL: fileURL)
        let now = Date()
        let id = UUID()
        let record = DictationRecord(
            id: id, createdAt: now, recordingStartedAt: now, recordingEndedAt: now,
            duration: 1, status: .transcribing, audioRelativePath: "test.wav",
            audioFileSize: 1, originalTranscript: nil, finalText: nil,
            providerID: "OpenAI", modelID: "test", language: "de",
            targetBundleIdentifier: "test.app", targetApplicationName: "Test",
            attemptCount: 1, lastAttemptAt: now, errorCategory: nil, errorCode: nil,
            errorMessage: nil, cancelled: false, updatedAt: now, schemaVersion: 1,
            archivedAt: nil
        )
        try await store.upsert(record)
        #expect(try await store.record(id: id)?.status == .transcribing)

        let recovered = try await store.recoverInterrupted()
        #expect(recovered.count == 1)
        #expect(try await store.record(id: id)?.status == .transcriptionFailed)

        let reloaded = DictationHistoryStore(fileURL: fileURL)
        #expect(try await reloaded.record(id: id)?.errorCategory == .interrupted)
    }

    @Test func stagedHistoryStateRemainsInMemoryUntilFinalFlush() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateStagedHistory-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("history.json")
        let store = DictationHistoryStore(fileURL: fileURL)
        let now = Date()
        var record = DictationRecord.newRecording(
            id: UUID(), startedAt: now, endedAt: now, duration: 1,
            status: .transcribed, audioRelativePath: "test.wav", audioFileSize: 1,
            providerID: "OpenAI", modelID: "test", language: "de",
            targetBundleIdentifier: nil, targetApplicationName: nil
        )
        record.originalTranscript = "Staged text"
        record.finalText = "Staged text"

        try await store.stage(record)
        #expect(try await store.record(id: record.id)?.finalText == "Staged text")
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        record.status = .completed
        try await store.stage(record)
        try await store.flush()
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let reloaded = DictationHistoryStore(fileURL: fileURL)
        #expect(try await reloaded.record(id: record.id)?.status == .completed)
    }

    @Test func meetingHistorySummaryRoundTripsWithoutReplacingSessionManifest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingHistory-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("dictations.json")
        var session = makeValidMixedRecordingSession()
        session.status = .completed
        session.finalTranscript = "[You] Hello\n[System Audio] Welcome"
        session.mergedTimelineRelativePath = MeetingTranscriptMergeRunner.timelineRelativePath
        session.completionMode = .allTracks
        session.transcriptInsertionState = .ready
        session.transcriptInsertionAttemptCount = 0
        for index in session.tracks.indices {
            session.tracks[index].status = .transcribed
            session.tracks[index].transcriptionSessionID = UUID()
            session.tracks[index].transcriptRelativePath =
                "transcription/\(session.tracks[index].role.rawValue)-transcript.json"
        }
        let record = try DictationRecord.meetingSession(
            session,
            targetBundleIdentifier: "com.example.Editor",
            targetApplicationName: "Editor"
        )
        let store = DictationHistoryStore(fileURL: fileURL)
        try await store.upsert(record)

        let restored = try #require(
            try await DictationHistoryStore(fileURL: fileURL).record(id: session.recordID)
        )
        let summary = try #require(restored.meetingSummary)
        #expect(restored.audioSource == .mixed)
        #expect(restored.finalText == session.finalTranscript)
        #expect(restored.audioRelativePath == "MeetingSessions/\(session.id.uuidString)")
        #expect(summary.sessionID == session.id)
        #expect(summary.status == .completed)
        #expect(summary.completeTrackCount == 2)
        #expect(summary.tracks.map(\.role) == [.localSpeaker, .systemAudio])
        #expect(summary.synchronizationQuality == .good)
        #expect(summary.insertionState == .ready)
        #expect(restored.isAutomaticallyProtected)
        #expect(!summary.canArchiveHistoryEntry)
    }

    @Test func phaseTwoHistoryWithoutArchivedAtStillDecodes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateLegacyHistory-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("history.json")
        let now = Date()
        let record = DictationRecord.newRecording(
            id: UUID(), startedAt: now, endedAt: now, duration: 1, status: .completed,
            audioRelativePath: "legacy.wav", audioFileSize: 0, providerID: "OpenAI",
            modelID: "test", language: nil, targetBundleIdentifier: nil,
            targetApplicationName: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let recordData = try encoder.encode(record)
        var recordJSON = try #require(
            JSONSerialization.jsonObject(with: recordData) as? [String: Any]
        )
        recordJSON.removeValue(forKey: "archivedAt")
        recordJSON.removeValue(forKey: "audioSource")
        recordJSON.removeValue(forKey: "audioSampleRate")
        recordJSON.removeValue(forKey: "audioChannelCount")
        let envelope = ["schemaVersion": 1, "records": [recordJSON]] as [String: Any]
        try JSONSerialization.data(withJSONObject: envelope).write(to: fileURL)

        let store = DictationHistoryStore(fileURL: fileURL)
        #expect(try await store.all().count == 1)
        #expect(try await store.all().first?.archivedAt == nil)
        #expect(try await store.all().first?.audioSource == .microphone)
        #expect(try await store.all().first?.audioSampleRate == 0)
    }

    @Test func phaseThreeThreeUsageStatisticsRemainLocalAndDeterministic() {
        let now = Date()
        var completed = DictationRecord.newRecording(
            id: UUID(), startedAt: now.addingTimeInterval(-10), endedAt: now,
            duration: 10, status: .completed, audioRelativePath: "one.wav",
            audioFileSize: 1, providerID: "Test", modelID: "test", language: "de",
            targetBundleIdentifier: nil, targetApplicationName: nil
        )
        completed.finalText = "one two three four"
        completed.attemptCount = 2
        var failed = completed
        failed.id = UUID()
        failed.status = .transcriptionFailed

        let result = UsageStatistics.calculate(
            records: [completed, failed], typingWordsPerMinute: 60
        )
        #expect(result.successfulDictations == 1)
        #expect(result.wordCount == 4)
        #expect(result.retryCount == 1)
        #expect(result.totalDuration == 10)
        #expect(result.estimatedSecondsSaved == 0)
        #expect(result.averageWordsPerDictation == 4)
        #expect(result.averageDuration == 10)
    }

    @Test func usageStatisticsPeriodsAndResetDateExcludeOlderRecords() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var recent = DictationRecord.newRecording(
            id: UUID(), startedAt: now.addingTimeInterval(-10), endedAt: now,
            duration: 10, status: .completed, audioRelativePath: "recent.wav",
            audioFileSize: 1, providerID: "Test", modelID: "test", language: "en",
            targetBundleIdentifier: nil, targetApplicationName: nil
        )
        recent.finalText = "one two"
        var old = recent
        old.id = UUID()
        old.createdAt = now.addingTimeInterval(-20 * 86_400)
        old.finalText = "old words should be excluded"

        let fourteenDays = UsageStatistics.calculate(
            records: [recent, old],
            typingWordsPerMinute: 40,
            since: UsageStatisticsPeriod.fourteenDays.startDate(relativeTo: now)
        )
        #expect(fourteenDays.successfulDictations == 1)
        #expect(fourteenDays.wordCount == 2)
        #expect(UsageStatisticsPeriod.total.startDate(relativeTo: now) == nil)
    }

    @Test func phaseThreeThreeReleaseComparisonUsesSemanticComponents() {
        #expect(GitHubReleaseChecker.isNewer("3.3.0", than: "3.2.9"))
        #expect(GitHubReleaseChecker.isNewer("3.2.10", than: "3.2.9"))
        #expect(!GitHubReleaseChecker.isNewer("3.2.0", than: "3.2.0"))
        #expect(!GitHubReleaseChecker.isNewer("3.1.9", than: "3.2.0"))
    }

    @Test func appProfilesRoundTripByBundleIdentifier() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateProfiles-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppProfileStore(fileURL: directory.appendingPathComponent("profiles.json"))
        var profile = AppDictationProfile.new(
            bundleIdentifier: "com.example.editor", displayName: "Editor"
        )
        profile.language = .german
        profile.transcriptionModel = "custom-model"
        profile.insertionPreference = .clipboard
        try await store.upsert(profile)

        let restored = try #require(await store.all().first)
        #expect(restored.bundleIdentifier == "com.example.editor")
        #expect(restored.language == .german)
        #expect(restored.transcriptionModel == "custom-model")
        #expect(restored.insertionPreference == .clipboard)
    }

    @Test func historyRetentionArchivesAudioAndRemovesTextOnlyRecords() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateRetention-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = DictationHistoryStore(fileURL: fileURL)
        let now = Date()
        var withAudio = DictationRecord.newRecording(
            id: UUID(), startedAt: now, endedAt: now, duration: 1, status: .completed,
            audioRelativePath: "audio.wav", audioFileSize: 100, providerID: "Test",
            modelID: "test", language: nil, targetBundleIdentifier: nil,
            targetApplicationName: nil
        )
        withAudio.finalText = "Audio"
        var textOnly = DictationRecord.newRecording(
            id: UUID(), startedAt: now.addingTimeInterval(-1),
            endedAt: now.addingTimeInterval(-1), duration: 1, status: .completed,
            audioRelativePath: "removed.wav", audioFileSize: 0, providerID: "Test",
            modelID: "test", language: nil, targetBundleIdentifier: nil,
            targetApplicationName: nil
        )
        textOnly.finalText = "Text"
        try await store.upsert(withAudio)
        try await store.upsert(textOnly)

        let result = try await store.applyRetention(
            maximumAgeDays: -1,
            maximumRecordCount: 0,
            now: now
        )

        #expect(result.archivedCount == 1)
        #expect(result.removedCount == 1)
        #expect(try await store.all().isEmpty)
        #expect(try await store.knownAudioRelativePaths().contains("audio.wav"))

        var archived = try #require(await store.all(includeArchived: true).first)
        #expect(archived.finalText == nil)
        archived.audioFileSize = 0
        try await store.upsert(archived)
        let purgeResult = try await store.applyRetention(
            maximumAgeDays: -1,
            maximumRecordCount: -1,
            now: now
        )
        #expect(purgeResult.removedCount == 1)
        #expect(try await store.all(includeArchived: true).isEmpty)
    }

    @Test func historyRetentionProtectsFailedRecords() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateProtectedRetention-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = DictationHistoryStore(fileURL: fileURL)
        let now = Date()
        var record = DictationRecord.newRecording(
            id: UUID(), startedAt: now, endedAt: now, duration: 1,
            status: .transcriptionFailed, audioRelativePath: "failed.wav",
            audioFileSize: 0, providerID: "Test", modelID: "test", language: nil,
            targetBundleIdentifier: nil, targetApplicationName: nil
        )
        record.errorCategory = .network
        try await store.upsert(record)

        let result = try await store.applyRetention(
            maximumAgeDays: 0,
            maximumRecordCount: 0,
            now: now.addingTimeInterval(1)
        )
        #expect(result == HistoryRetentionResult())
        #expect(try await store.record(id: record.id) != nil)
    }

    @Test func historyRetentionProtectsPartialMeetingSessions() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingRetentionProtected-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = DictationHistoryStore(fileURL: fileURL)
        var session = makeValidMixedRecordingSession()
        session.status = .partial
        session.lastErrorCategory = .network
        session.lastErrorMessage = "System Audio transcription can be retried."
        var record = try DictationRecord.meetingSession(session)
        record.createdAt = Date(timeIntervalSince1970: 1)
        try await store.upsert(record)

        let result = try await store.applyRetention(
            maximumAgeDays: 0,
            maximumRecordCount: 0,
            now: Date(timeIntervalSince1970: 2_000_000_000)
        )

        #expect(result == HistoryRetentionResult())
        #expect(try await store.all() == [record])
        #expect(try await store.record(id: record.id)?.archivedAt == nil)
    }

    @Test func pendingMeetingInsertionCannotBeAutomaticallyOrManuallyArchived() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictatePendingMeetingArchive-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = DictationHistoryStore(fileURL: fileURL)
        let states: [MeetingTranscriptInsertionState] = [
            .ready, .attempting, .deferred, .unknown
        ]
        var records: [DictationRecord] = []
        for state in states {
            var session = makeCompletedMixedRecordingSession(insertionState: state)
            session.id = UUID()
            session.recordID = UUID()
            session.createdAt = Date(timeIntervalSince1970: 1)
            var record = try DictationRecord.meetingSession(session)
            record.createdAt = session.createdAt
            #expect(record.isAutomaticallyProtected)
            #expect(record.meetingSummary?.canArchiveHistoryEntry == false)
            try await store.upsert(record)
            records.append(record)

            await #expect(throws: DictationHistoryError.meetingRequiresAttention) {
                try await store.archive(id: record.id)
            }
        }

        var cancelled = makeValidMixedRecordingSession()
        cancelled.id = UUID()
        cancelled.recordID = UUID()
        cancelled.status = .cancelled
        var cancelledRecord = try DictationRecord.meetingSession(cancelled)
        cancelledRecord.createdAt = Date(timeIntervalSince1970: 1)
        #expect(cancelledRecord.isAutomaticallyProtected)
        #expect(cancelledRecord.meetingSummary?.canArchiveHistoryEntry == false)
        try await store.upsert(cancelledRecord)
        records.append(cancelledRecord)
        await #expect(throws: DictationHistoryError.meetingRequiresAttention) {
            try await store.archive(id: cancelledRecord.id)
        }

        let result = try await store.applyRetention(
            maximumAgeDays: 0,
            maximumRecordCount: 0,
            now: Date(timeIntervalSince1970: 2_000_000_000)
        )
        #expect(result == HistoryRetentionResult())
        #expect(Set(try await store.all().map(\.id)) == Set(records.map(\.id)))
    }

    @MainActor
    @Test func meetingAudioRetentionPreservesPendingInsertionOriginals() async throws {
        let harness = makeCoordinatorHarness()
        harness.coordinator.settings.audioRetentionDays = 30
        let store = MeetingSessionStore(
            recordingLocationStore: harness.recordingLocationStore
        )
        let states: [MeetingTranscriptInsertionState] = [
            .ready, .attempting, .deferred, .unknown
        ]
        var sessions: [(id: UUID, directory: URL)] = []
        for state in states {
            var session = makeCompletedMixedRecordingSession(insertionState: state)
            session.id = UUID()
            session.recordID = UUID()
            session.createdAt = Date(timeIntervalSince1970: 1_800_000_000)
            session.updatedAt = session.createdAt.addingTimeInterval(10)
            let paths = try await store.prepareSession(id: session.id)
            try await store.create(session)
            try await harness.historyStore.upsert(
                DictationRecord.meetingSession(session)
            )
            sessions.append((session.id, paths.sessionDirectory))
        }

        try await harness.coordinator.applyRetentionPolicy(
            now: Date(timeIntervalSince1970: 1_810_000_000)
        )

        for session in sessions {
            #expect(FileManager.default.fileExists(atPath: session.directory.path))
            #expect(try await store.load(sessionID: session.id) != nil)
        }
        #expect(try await harness.historyStore.all().count == states.count)
    }

    @MainActor
    @Test func meetingAudioRetentionTrustsManifestOverStaleHistorySummary() async throws {
        let harness = makeCoordinatorHarness()
        harness.coordinator.settings.audioRetentionDays = 30
        let store = MeetingSessionStore(
            recordingLocationStore: harness.recordingLocationStore
        )
        var session = makeCompletedMixedRecordingSession(insertionState: .completed)
        session.createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        session.updatedAt = session.createdAt.addingTimeInterval(10)
        let paths = try await store.prepareSession(id: session.id)
        let originalURL = paths.tracksDirectory.appendingPathComponent("microphone.caf")
        try Data("preserve original".utf8).write(to: originalURL)
        try await store.create(session)
        let staleRecord = try DictationRecord.meetingSession(session)
        try await harness.historyStore.upsert(staleRecord)

        session.transcriptInsertionState = .deferred
        session.updatedAt = session.updatedAt.addingTimeInterval(1)
        try await store.save(session)

        try await harness.coordinator.applyRetentionPolicy(
            now: session.createdAt.addingTimeInterval(100 * 86_400)
        )

        #expect(try Data(contentsOf: originalURL) == Data("preserve original".utf8))
        #expect(try await store.load(sessionID: session.id) == session)
        #expect(try await harness.historyStore.record(id: staleRecord.id)?.audioFileSize
            == staleRecord.audioFileSize)
    }

    @Test func historyRetentionArchivesCompletedMeetingWithoutDeletingSessionReference() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingRetentionArchive-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = DictationHistoryStore(fileURL: fileURL)
        var session = makeCompletedMixedRecordingSession(insertionState: .completed)
        session.createdAt = Date(timeIntervalSince1970: 1)
        session.updatedAt = Date(timeIntervalSince1970: 2)
        var record = try DictationRecord.meetingSession(
            session,
            targetBundleIdentifier: "com.example.Editor",
            targetApplicationName: "Editor"
        )
        record.createdAt = session.createdAt
        try await store.upsert(record)

        let result = try await store.applyRetention(
            maximumAgeDays: 0,
            maximumRecordCount: 0,
            now: Date(timeIntervalSince1970: 2_000_000_000)
        )

        #expect(result == HistoryRetentionResult(archivedCount: 1))
        #expect(try await store.all().isEmpty)
        let archived = try #require(try await store.all(includeArchived: true).first)
        #expect(archived.archivedAt != nil)
        #expect(archived.finalText == nil)
        #expect(archived.targetBundleIdentifier == nil)
        #expect(archived.meetingSummary?.sessionID == session.id)
        #expect(archived.audioFileSize > 0)
    }

    @MainActor
    @Test func meetingAudioRetentionRemovesAllSessionArtifactsAndKeepsVisibleTimeline() async throws {
        let harness = makeCoordinatorHarness()
        harness.coordinator.settings.audioRetentionDays = 30
        let store = MeetingSessionStore(
            recordingLocationStore: harness.recordingLocationStore
        )
        var session = makeCompletedMixedRecordingSession(insertionState: .completed)
        session.createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        session.updatedAt = session.createdAt.addingTimeInterval(10)
        let paths = try await store.prepareSession(id: session.id)
        for track in session.tracks {
            let relativePath = try #require(track.audioRelativePath)
            try Data("original-\(track.role.rawValue)".utf8).write(
                to: paths.sessionDirectory.appendingPathComponent(relativePath)
            )
            let transcriptPath = try #require(track.transcriptRelativePath)
            try Data("track transcript".utf8).write(
                to: paths.sessionDirectory.appendingPathComponent(transcriptPath)
            )
        }
        try Data("derived".utf8).write(
            to: paths.derivedDirectory.appendingPathComponent("aligned.m4a")
        )
        try Data("timeline".utf8).write(
            to: paths.sessionDirectory.appendingPathComponent(
                try #require(session.mergedTimelineRelativePath)
            )
        )
        try await store.create(session)
        let record = try DictationRecord.meetingSession(session)
        try await harness.historyStore.upsert(record)

        let retentionDate = session.createdAt.addingTimeInterval(100 * 86_400)
        try await harness.coordinator.applyRetentionPolicy(now: retentionDate)

        let retained = try #require(try await harness.historyStore.record(id: record.id))
        #expect(retained.finalText == session.finalTranscript)
        #expect(retained.audioFileSize == 0)
        #expect(retained.meetingSummary?.tracks.allSatisfy { $0.byteCount == 0 } == true)
        #expect(retained.meetingSummary?.tracks.allSatisfy { !$0.canPlayAudio } == true)
        #expect(try await harness.historyStore.all().map(\.id) == [record.id])
        #expect(!FileManager.default.fileExists(atPath: paths.sessionDirectory.path))
        #expect(try await store.load(sessionID: session.id) == nil)
    }

    @MainActor
    @Test func meetingAudioRetentionFinishesArchivedSessionLifecycle() async throws {
        let harness = makeCoordinatorHarness()
        harness.coordinator.settings.audioRetentionDays = 30
        let store = MeetingSessionStore(
            recordingLocationStore: harness.recordingLocationStore
        )
        var session = makeCompletedMixedRecordingSession(insertionState: .completed)
        session.createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        session.updatedAt = session.createdAt.addingTimeInterval(10)
        let paths = try await store.prepareSession(id: session.id)
        try Data("private derived content".utf8).write(
            to: paths.derivedDirectory.appendingPathComponent("preview.m4a")
        )
        try await store.create(session)
        let record = try DictationRecord.meetingSession(session)
        try await harness.historyStore.upsert(record)
        try await harness.historyStore.archive(id: record.id, now: session.updatedAt)

        #expect(try await harness.historyStore.all().isEmpty)
        #expect(FileManager.default.fileExists(atPath: paths.sessionDirectory.path))

        let retentionDate = session.createdAt.addingTimeInterval(100 * 86_400)
        try await harness.coordinator.applyRetentionPolicy(now: retentionDate)

        let retainedArchive = try #require(
            try await harness.historyStore.record(id: record.id)
        )
        #expect(retainedArchive.archivedAt != nil)
        #expect(retainedArchive.audioFileSize == 0)
        #expect(!FileManager.default.fileExists(atPath: paths.sessionDirectory.path))

        let purge = try await harness.historyStore.applyRetention(
            maximumAgeDays: -1,
            maximumRecordCount: -1,
            now: retentionDate
        )
        #expect(purge.removedCount == 1)
        #expect(try await harness.historyStore.record(id: record.id) == nil)
    }

    @Test func historyStoreHandlesOneThousandRecordsIncludingMeetingSummaries() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateHistoryPerformance-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let now = Date()
        let longText = String(repeating: "FlowDictate phase three transcript. ", count: 30)
        let records = try (0..<1_000).map { index -> DictationRecord in
            if index.isMultiple(of: 10) {
                var session = makeValidMixedRecordingSession()
                session.id = UUID()
                session.recordID = UUID()
                session.createdAt = now.addingTimeInterval(Double(-index))
                session.updatedAt = session.createdAt.addingTimeInterval(20)
                session.status = .paused
                session.lastErrorCategory = .interrupted
                session.lastErrorMessage = "Resume from History."
                return try DictationRecord.meetingSession(session)
            }
            var record = DictationRecord.newRecording(
                id: UUID(), startedAt: now.addingTimeInterval(Double(-index)),
                endedAt: now.addingTimeInterval(Double(-index)), duration: 20,
                status: .completed, audioRelativePath: "\(index).wav", audioFileSize: 0,
                providerID: "OpenAI", modelID: "test", language: "de",
                targetBundleIdentifier: "test.app", targetApplicationName: "Test"
            )
            record.originalTranscript = longText
            record.finalText = longText
            return record
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(TestHistoryEnvelope(
            schemaVersion: NativeDictateVersion.historySchema,
            records: records
        )).write(to: fileURL, options: .atomic)

        let clock = ContinuousClock()
        let start = clock.now
        let store = DictationHistoryStore(fileURL: fileURL)
        #expect(try await store.all().count == 1_000)
        #expect(try await store.all().filter { $0.meetingSummary != nil }.count == 100)
        var newest = records[0]
        newest.updatedAt = Date()
        try await store.upsert(newest)
        let elapsed = start.duration(to: clock.now)
        #expect(elapsed < .seconds(2))
    }

    @Test func livePreviewBufferChannelDropsOldestBuffers() async {
        let channel = LivePreviewBufferChannel(limit: 2)
        for value in 1...3 {
            channel.yield(LivePreviewAudioBuffer(
                sampleRate: 16_000,
                channelCount: 1,
                frameCount: 1,
                channelSamples: [[Float(value)]]
            ))
        }
        channel.finish()

        var values: [Float] = []
        for await buffer in channel.stream {
            values.append(buffer.channelSamples[0][0])
        }
        #expect(values == [2, 3])
        #expect(channel.droppedBufferCount == 1)
    }

    @Test func livePreviewBufferOwnsImmutableAudioSamples() throws {
        let format = try #require(AVAudioFormat(
            standardFormatWithSampleRate: 16_000,
            channels: 1
        ))
        let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        source.frameLength = 4
        source.floatChannelData?[0][0] = 0.75

        let preview = try #require(LivePreviewAudioBuffer(copying: source))
        source.floatChannelData?[0][0] = 0.25
        let speechBuffer = try #require(preview.makePCMBuffer())

        #expect(preview.channelSamples[0][0] == 0.75)
        #expect(speechBuffer.floatChannelData?[0][0] == 0.75)
    }

    @Test func audioLevelUpdatesAreLimitedToTenPerSecond() {
        let gate = AudioLevelUpdateGate(updatesPerSecond: 10)
        #expect(gate.shouldPublish(at: 1))
        #expect(!gate.shouldPublish(at: 1.05))
        #expect(gate.shouldPublish(at: 1.11))
    }

    @MainActor
    @Test func livePreviewCoordinatorLimitsTextAndIgnoresEventsAfterCancel() async throws {
        let provider = MockLivePreviewProvider()
        let coordinator = LivePreviewCoordinator(
            provider: provider,
            updateInterval: .milliseconds(1)
        )
        var states: [LivePreviewState] = []
        coordinator.stateDidChange = { states.append($0) }
        let handler = try coordinator.start(configuration: LivePreviewConfiguration(
            localeIdentifier: "de-DE",
            characterLimit: 50
        ))
        handler(LivePreviewAudioBuffer(
            sampleRate: 16_000,
            channelCount: 1,
            frameCount: 1,
            channelSamples: [[0]]
        ))
        provider.emit(.partial(String(repeating: "a", count: 70)))
        let expectedState = LivePreviewState.active(String(repeating: "a", count: 50))
        for _ in 0..<20 where !states.contains(expectedState) {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(provider.startCount == 1)
        #expect(states.contains(expectedState))
        coordinator.cancel()
        provider.emit(.partial("must be ignored"))
        try await Task.sleep(for: .milliseconds(10))
        #expect(coordinator.state == .disabled)
        #expect(provider.cancelCount >= 1)
    }

    @MainActor
    @Test func transcriptionRunnerRetriesTemporaryFailure() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateRunner-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = DictationHistoryStore(fileURL: fileURL)
        let provider = RetryingMockTranscriptionProvider()
        let runner = TranscriptionRunner(historyStore: store, sleeper: { _ in })
        let now = Date()
        let record = DictationRecord.newRecording(
            id: UUID(), startedAt: now, endedAt: now, duration: 1,
            status: .recorded, audioRelativePath: "test.wav", audioFileSize: 1,
            providerID: "Test", modelID: "test", language: "de",
            targetBundleIdentifier: nil, targetApplicationName: nil
        )

        let result = try await runner.run(
            record: record,
            audioURL: URL(fileURLWithPath: "/tmp/test.wav"),
            language: "de",
            maximumAttempts: 3,
            provider: provider
        )

        #expect(provider.transcribeCount == 2)
        #expect(result.attemptCount == 2)
        #expect(result.status == .transcribed)
        #expect(result.finalText == "Recovered transcription")
    }

    @Test @MainActor func apiKeyIsReadOnlyOncePerAppSession() async {
        let credentialStore = CountingCredentialStore()
        let harness = makeCoordinatorHarness(credentialStore: credentialStore)
        #expect(credentialStore.readCount == 1)

        await harness.coordinator.toggleDictation()
        await harness.coordinator.toggleDictation()

        #expect(credentialStore.readCount == 1)
    }

    @Test @MainActor func openAIEnhancerRuntimeIsReusedAcrossDictations() async {
        var factoryCallCount = 0
        let enhancer = MockTranscriptEnhancer(output: "Enhanced text")
        let harness = makeCoordinatorHarness(
            transcriptEnhancerFactory: { _ in
                factoryCallCount += 1
                return enhancer
            }
        )
        harness.coordinator.settings.writingStyleID = BuiltInWritingStyles.cleanedID

        await harness.coordinator.toggleDictation()
        await harness.coordinator.toggleDictation()
        await harness.coordinator.toggleDictation()
        await harness.coordinator.toggleDictation()

        #expect(factoryCallCount == 1)
        #expect(enhancer.callCount == 2)
    }

    @Test func longFormPlannerCoversRecordingInOrderWithBoundedOverlap() async throws {
        let planner = AudioSegmentPlanner()
        let duration: Int64 = 40 * 60 * 1_000
        let segments = try await planner.plan(durationMilliseconds: duration)

        #expect(segments.count == 3)
        #expect(segments.first?.startMilliseconds == 0)
        #expect(segments.last?.endMilliseconds == duration)
        #expect(segments.map(\.index) == [0, 1, 2])
        #expect(segments[1].overlapBeforeMilliseconds == 1_500)
        #expect(segments[0].endMilliseconds - segments[1].startMilliseconds == 1_500)
        #expect(segments[1].endMilliseconds - segments[2].startMilliseconds == 1_500)
    }

    @Test func longFormPlannerUsesSafeResolvedBoundary() async throws {
        let planner = AudioSegmentPlanner()
        let requested: Int64 = 14 * 60 * 1_000
        let segments = try await planner.plan(
            durationMilliseconds: 32 * 60 * 1_000,
            boundaryResolver: { _, _, _ in requested }
        )

        #expect(segments.count == 3)
        #expect(segments[0].endMilliseconds == requested)
        #expect(segments[1].startMilliseconds == requested - 1_500)
    }

    @Test func partialTranscriptMergerRemovesOnlyConfidentBoundaryDuplicate() throws {
        let transcripts = [
            "This is the first section with a reliable shared boundary phrase.",
            "a reliable shared boundary phrase. This is the second section."
        ]
        let segments = transcripts.enumerated().map { index, transcript in
            TranscriptionSegment(
                id: UUID(), index: index, startMilliseconds: Int64(index * 10_000),
                endMilliseconds: Int64((index + 1) * 10_000),
                overlapBeforeMilliseconds: index == 0 ? 0 : 0,
                status: .succeeded, preparedRelativePath: nil, preparedByteCount: nil,
                transcript: transcript, attemptCount: 1, lastAttemptAt: nil,
                errorCategory: nil, errorMessage: nil
            )
        }
        let result = try PartialTranscriptMerger().merge(segments)
        #expect(result == "This is the first section with a reliable shared boundary phrase. This is the second section.")

        let ambiguous = PartialTranscriptMerger().mergeBoundary(
            left: "One ending",
            right: "ending but unrelated"
        )
        #expect(ambiguous == "One ending ending but unrelated")
    }

    @Test func partialTranscriptMergerPreservesSpeechAcrossVerifiedSilence() throws {
        let segments = [
            TranscriptionSegment(
                id: UUID(), index: 0, startMilliseconds: 0, endMilliseconds: 2_000,
                overlapBeforeMilliseconds: 0, status: .succeeded,
                preparedRelativePath: nil, preparedByteCount: nil,
                transcript: "A repeated phrase.", attemptCount: 1, lastAttemptAt: nil,
                errorCategory: nil, errorMessage: nil
            ),
            TranscriptionSegment(
                id: UUID(), index: 1, startMilliseconds: 1_900, endMilliseconds: 4_000,
                overlapBeforeMilliseconds: 100, status: .silent,
                preparedRelativePath: nil, preparedByteCount: nil,
                transcript: nil, attemptCount: 1, lastAttemptAt: nil,
                errorCategory: nil, errorMessage: nil
            ),
            TranscriptionSegment(
                id: UUID(), index: 2, startMilliseconds: 3_900, endMilliseconds: 6_000,
                overlapBeforeMilliseconds: 100, status: .succeeded,
                preparedRelativePath: nil, preparedByteCount: nil,
                transcript: "A repeated phrase.", attemptCount: 1, lastAttemptAt: nil,
                errorCategory: nil, errorMessage: nil
            )
        ]
        #expect(try PartialTranscriptMerger().merge(segments) ==
            "A repeated phrase. A repeated phrase.")
        var allSilent = segments[1]
        allSilent.index = 0
        #expect(try PartialTranscriptMerger().merge([allSilent]) == "")
    }

    @Test func interruptedManifestBecomesResumableWithoutLosingSuccessfulText() async throws {
        let now = Date()
        var segments = try await AudioSegmentPlanner().plan(durationMilliseconds: 20 * 60 * 1_000)
        segments[0].status = .succeeded
        segments[0].transcript = "Already uploaded text"
        segments[1].status = .uploading
        var manifest = TranscriptionSessionManifest(
            schemaVersion: 1, id: UUID(), recordID: UUID(),
            source: TranscriptionSourceFingerprint(
                audioRelativePath: "long.m4a", byteCount: 10_000,
                durationMilliseconds: 20 * 60 * 1_000, modificationDate: now
            ),
            providerID: "Test", modelID: "test", language: "de",
            status: .transcribing, segments: segments, mergedTranscript: nil,
            mergeAlgorithmVersion: 1, createdAt: now, updatedAt: now,
            lastErrorCategory: nil, lastErrorMessage: nil
        )

        manifest.normalizeInterruptedWork(now: now.addingTimeInterval(1))

        #expect(manifest.status == .paused)
        #expect(manifest.completedSegmentCount == 1)
        #expect(manifest.segments[0].transcript == "Already uploaded text")
        #expect(manifest.segments[1].status == .interrupted)
        _ = try manifest.validated()
    }

    @Test func phase34RecordMigrationDefaultsSegmentState() throws {
        let record = makeTranscribedRecord(text: "Legacy")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(record)) as? [String: Any]
        )
        for key in ["transcriptionSessionID", "transcriptionSegmentCount",
                    "completedTranscriptionSegmentCount", "hasPartialTranscript", "partialTranscript"] {
            object.removeValue(forKey: key)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let migrated = try decoder.decode(
            DictationRecord.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(migrated.transcriptionSessionID == nil)
        #expect(migrated.transcriptionSegmentCount == nil)
        #expect(migrated.completedTranscriptionSegmentCount == 0)
        #expect(!migrated.hasPartialTranscript)
        #expect(migrated.schemaVersion == NativeDictateVersion.dictationRecordSchema)
    }

    @Test func sessionStorePersistsAndNormalizesInterruptedWork() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSessionStore-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TranscriptionSessionStore(rootURL: root)
        let now = Date()
        let recordID = UUID()
        var segments = try await AudioSegmentPlanner().plan(durationMilliseconds: 20 * 60 * 1_000)
        segments[0].status = .preparing
        let manifest = TranscriptionSessionManifest(
            schemaVersion: 1, id: UUID(), recordID: recordID,
            source: TranscriptionSourceFingerprint(
                audioRelativePath: "long.m4a", byteCount: 20_000,
                durationMilliseconds: 20 * 60 * 1_000, modificationDate: now
            ), providerID: "Test", modelID: "test", language: nil,
            status: .transcribing, segments: segments, mergedTranscript: nil,
            mergeAlgorithmVersion: 1, createdAt: now, updatedAt: now,
            lastErrorCategory: nil, lastErrorMessage: nil
        )
        try await store.save(manifest)

        #expect(try await store.load(recordID: recordID)?.status == .transcribing)
        let normalized = try await store.normalizeInterruptedSessions()
        #expect(normalized.count == 1)
        #expect(try await store.load(recordID: recordID)?.status == .paused)
        #expect(try await store.load(recordID: recordID)?.segments[0].status == .interrupted)
    }

    @MainActor
    @Test func longFormRunnerExportsTranscribesMergesAndCleansSession() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateLongFormRunner-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audioURL = root.appendingPathComponent("long.wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        do {
            let file = try AVAudioFile(forWriting: audioURL, settings: format.settings)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 80_000))
            buffer.frameLength = buffer.frameCapacity
            if let samples = buffer.floatChannelData?[0] {
                for frame in 0..<Int(buffer.frameLength) { samples[frame] = 0.05 }
            }
            try file.write(from: buffer)
        }
        let bytes = Int64(try audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        let history = DictationHistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let sessions = TranscriptionSessionStore(rootURL: root.appendingPathComponent("sessions"))
        var configuration = LongFormConfiguration.default
        configuration.targetDurationMilliseconds = 2_000
        configuration.minimumDurationMilliseconds = 1_000
        configuration.maximumDurationMilliseconds = 3_000
        configuration.boundarySearchRadiusMilliseconds = 0
        configuration.fallbackOverlapMilliseconds = 100
        configuration.softUploadByteLimit = 100_000
        configuration.hardUploadByteLimit = 1_000_000
        configuration.workingStorageReserveBytes = 0
        let provider = SequenceTranscriptionProvider(texts: [
            "Alpha shared boundary phrase here."
        ])
        let runner = LongFormTranscriptionRunner(
            historyStore: history,
            sessionStore: sessions,
            configuration: configuration,
            sleeper: { _ in }
        )
        let now = Date()
        let record = DictationRecord.newRecording(
            id: UUID(), startedAt: now.addingTimeInterval(-5), endedAt: now, duration: 5,
            status: .recorded, audioRelativePath: "long.wav", audioFileSize: bytes,
            providerID: "Test", modelID: "test", language: "en",
            targetBundleIdentifier: nil, targetApplicationName: nil,
            sourceMetadata: AudioSourceMetadata(source: .systemAudio, sampleRate: 16_000, channelCount: 1)
        )
        try await history.upsert(record)
        var progress: [LongFormProgress] = []

        let resumableRecord: DictationRecord
        do {
            _ = try await runner.runIfNeeded(
                record: record,
                audioURL: audioURL,
                language: "en",
                maximumAttempts: 1,
                provider: provider,
                progress: { progress.append($0) }
            )
            Issue.record("Expected the second segment to fail")
            return
        } catch let failure as TranscriptionRunFailure {
            resumableRecord = failure.record
        }
        let loadedFailedManifest = try await sessions.load(recordID: record.id)
        let failedManifest = try #require(loadedFailedManifest)
        #expect(provider.requestCount == 2)
        #expect(failedManifest.segments[0].status == .succeeded)
        #expect(failedManifest.segments[1].status == .failed)
        #expect(resumableRecord.hasPartialTranscript)

        let resumeProvider = SequenceTranscriptionProvider(texts: [
            "shared boundary phrase here. Omega"
        ])
        let optionalResult = try await runner.runIfNeeded(
            record: resumableRecord,
            audioURL: audioURL,
            language: "en",
            maximumAttempts: 1,
            provider: resumeProvider,
            progress: { progress.append($0) }
        )
        let result = try #require(optionalResult)

        #expect(provider.transcribeCount == 1)
        #expect(resumeProvider.requestCount == 1)
        #expect(result.status == .transcribed)
        #expect(result.finalText == "Alpha shared boundary phrase here. Omega")
        #expect(result.transcriptionSegmentCount == 2)
        #expect(result.completedTranscriptionSegmentCount == 2)
        #expect(result.transcriptionSessionID == nil)
        #expect(progress.contains(.merging(total: 2)))
        #expect(try await sessions.load(recordID: record.id) == nil)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @MainActor
    @Test func longFormResumeSkipsVerifiedSilentSegmentsButNotAudibleEmptyResponses() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSilentLongForm-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audioURL = root.appendingPathComponent("long.wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        do {
            let file = try AVAudioFile(forWriting: audioURL, settings: format.settings)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128_000))
            buffer.frameLength = buffer.frameCapacity
            let samples = try #require(buffer.floatChannelData?[0])
            // Near-silent room noise, not just digital zeroes.
            for frame in 0..<Int(buffer.frameLength) { samples[frame] = 0.0008 }
            for frame in 8_000..<24_000 { samples[frame] = 0.05 }
            for frame in 100_800..<116_800 { samples[frame] = 0.05 }
            try file.write(from: buffer)
        }
        let detector = SilentAudioSegmentDetector()
        var configuration = LongFormConfiguration.default
        configuration.targetDurationMilliseconds = 2_000
        configuration.minimumDurationMilliseconds = 1_000
        configuration.maximumDurationMilliseconds = 3_000
        configuration.boundarySearchRadiusMilliseconds = 0
        configuration.fallbackOverlapMilliseconds = 100
        configuration.softUploadByteLimit = 100_000
        configuration.hardUploadByteLimit = 1_000_000
        configuration.workingStorageReserveBytes = 0
        let planned = try await AudioSegmentPlanner(configuration: configuration)
            .plan(durationMilliseconds: 8_000)
        #expect(planned.count == 4)
        #expect(try await detector.isSilent(in: audioURL, segment: planned[1]))
        #expect(try await detector.isSilent(in: audioURL, segment: planned[2]))
        #expect(try await !detector.isSilent(in: audioURL, segment: planned[3]))

        let history = DictationHistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let sessions = TranscriptionSessionStore(rootURL: root.appendingPathComponent("sessions"))
        let now = Date()
        let record = DictationRecord.newRecording(
            id: UUID(), startedAt: now.addingTimeInterval(-8), endedAt: now, duration: 8,
            status: .recorded, audioRelativePath: "long.wav",
            audioFileSize: Int64(try audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0),
            providerID: "Test", modelID: "test", language: "en",
            targetBundleIdentifier: nil, targetApplicationName: nil,
            sourceMetadata: AudioSourceMetadata(
                source: .microphone, sampleRate: 16_000, channelCount: 1
            )
        )
        try await history.upsert(record)
        let runner = LongFormTranscriptionRunner(
            historyStore: history,
            sessionStore: sessions,
            configuration: configuration,
            sleeper: { _ in }
        )
        let firstProvider = SequenceTranscriptionProvider(texts: ["Opening.", "", "", ""])
        let failedRecord: DictationRecord
        do {
            _ = try await runner.runIfNeeded(
                record: record, audioURL: audioURL, language: "en", maximumAttempts: 1,
                provider: firstProvider, allowsEmptyTranscript: true, progress: { _ in }
            )
            Issue.record("Expected an audible empty-response segment to remain failed")
            return
        } catch let failure as TranscriptionRunFailure {
            failedRecord = failure.record
        }
        let failedManifest = try #require(try await sessions.load(recordID: record.id))
        #expect(failedManifest.segments.map(\.status) ==
            [.succeeded, .silent, .silent, .failed])
        #expect(failedManifest.completedSegmentCount == 3)
        #expect(failedRecord.partialTranscript == "Opening.")
        #expect(firstProvider.requestCount == 4)

        let resumedProvider = SequenceTranscriptionProvider(texts: ["Closing."])
        let completed = try #require(try await runner.runIfNeeded(
            record: failedRecord, audioURL: audioURL, language: "en", maximumAttempts: 1,
            provider: resumedProvider, allowsEmptyTranscript: true, progress: { _ in }
        ))
        #expect(completed.status == .transcribed)
        #expect(completed.finalText == "Opening. Closing.")
        #expect(completed.completedTranscriptionSegmentCount == 4)
        #expect(resumedProvider.requestCount == 1)
        #expect(try await sessions.load(recordID: record.id) == nil)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @MainActor
    @Test func longFormLowStorageBeforeAndDuringSegmentsKeepsCompletedWork() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateLongFormStorage-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeLongFormTrackTranscriptionFixture(
            rootURL: root,
            providerID: TranscriptionProviderID.local.rawValue,
            engineID: TranscriptionProviderRegistry.local.capabilities.engineID,
            modelID: "parakeet-tdt-0.6b-v3-coreml",
            privacyMode: .offline
        )
        let track = try #require(fixture.session.tracks.first)
        let relativePath = try #require(track.audioRelativePath)
        let audioURL = fixture.paths.sessionDirectory.appendingPathComponent(relativePath)
        let history = DictationHistoryStore(
            fileURL: root.appendingPathComponent("storage-test-history.json")
        )
        let sessions = TranscriptionSessionStore(
            rootURL: root.appendingPathComponent("storage-test-sessions", isDirectory: true)
        )
        var configuration = LongFormConfiguration.default
        configuration.targetDurationMilliseconds = 2_000
        configuration.minimumDurationMilliseconds = 1_000
        configuration.maximumDurationMilliseconds = 3_000
        configuration.boundarySearchRadiusMilliseconds = 0
        configuration.fallbackOverlapMilliseconds = 100
        configuration.softUploadByteLimit = 100_000
        configuration.hardUploadByteLimit = 1_000_000
        configuration.workingStorageReserveBytes = 0
        let now = Date()
        let record = DictationRecord.newRecording(
            id: UUID(), startedAt: now.addingTimeInterval(-5), endedAt: now,
            duration: 5, status: .recorded, audioRelativePath: relativePath,
            audioFileSize: track.byteCount, providerID: "Test", modelID: "test",
            language: "en", targetBundleIdentifier: nil, targetApplicationName: nil,
            sourceMetadata: AudioSourceMetadata(
                source: .microphone, sampleRate: 16_000, channelCount: 1
            )
        )
        try await history.upsert(record)

        let noStorageProvider = SequenceTranscriptionProvider(texts: ["Should not run"])
        let noStorageRunner = LongFormTranscriptionRunner(
            historyStore: history, sessionStore: sessions,
            configuration: configuration, capacityProvider: { _ in 0 }
        )
        var pendingRecord = record
        do {
            _ = try await noStorageRunner.runIfNeeded(
                record: record, audioURL: audioURL, language: "en",
                maximumAttempts: 1, provider: noStorageProvider, progress: { _ in }
            )
            Issue.record("Expected insufficient storage before segment planning")
            return
        } catch let failure as TranscriptionRunFailure {
            pendingRecord = failure.record
        }
        #expect(noStorageProvider.requestCount == 0)
        #expect(pendingRecord.errorCategory == .insufficientWorkingStorage)
        #expect(try await sessions.load(recordID: record.id) == nil)

        let capacity = StorageCapacityProbe(values: [1_000_000, 1_000_000, 0])
        let firstProvider = SequenceTranscriptionProvider(texts: ["First segment kept."])
        let firstRunner = LongFormTranscriptionRunner(
            historyStore: history, sessionStore: sessions,
            configuration: configuration,
            capacityProvider: { url in capacity.availableCapacity(at: url) }
        )
        do {
            _ = try await firstRunner.runIfNeeded(
                record: pendingRecord, audioURL: audioURL, language: "en",
                maximumAttempts: 1, provider: firstProvider, progress: { _ in }
            )
            Issue.record("Expected storage exhaustion before the second segment")
            return
        } catch let failure as TranscriptionRunFailure {
            pendingRecord = failure.record
        }
        let partial = try #require(try await sessions.load(recordID: record.id))
        #expect(capacity.callCount == 3)
        #expect(firstProvider.requestCount == 1)
        #expect(partial.completedSegmentCount == 1)
        #expect(partial.segments[0].transcript == "First segment kept.")
        #expect(pendingRecord.errorCategory == .insufficientWorkingStorage)

        let resumeProvider = SequenceTranscriptionProvider(texts: ["Should not run"])
        do {
            _ = try await noStorageRunner.runIfNeeded(
                record: pendingRecord, audioURL: audioURL, language: "en",
                maximumAttempts: 1, provider: resumeProvider, progress: { _ in }
            )
            Issue.record("Expected insufficient storage on resume")
            return
        } catch let failure as TranscriptionRunFailure {
            #expect(failure.record.errorCategory == .insufficientWorkingStorage)
        }
        let resumed = try #require(try await sessions.load(recordID: record.id))
        #expect(resumeProvider.requestCount == 0)
        #expect(resumed.completedSegmentCount == 1)
        #expect(resumed.segments[0].transcript == "First segment kept.")
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @MainActor
    @Test func phaseFourProviderCapabilitiesAndPrivacyPolicyAreExplicit() throws {
        let registry = TranscriptionProviderRegistry()
        let local = try #require(registry.descriptor(for: .local))
        let cloud = try #require(registry.descriptor(for: .openAI))

        #expect(local.capabilities.executionLocation == .local)
        #expect(!local.capabilities.requiresCredential)
        #expect(local.capabilities.supportedLanguages?.contains("de") == true)
        #expect(cloud.capabilities.executionLocation == .cloud)
        #expect(cloud.capabilities.requiresCredential)
        #expect(!registry.availability(for: .local, architecture: "x86_64").isAvailable)
        #expect(registry.availability(for: .local, architecture: "arm64").isAvailable)

        let offline = NetworkPolicy(mode: .offline, cloudEnhancementEnabled: true)
        for purpose in [NetworkPurpose.transcription, .enhancement, .credentialValidation,
                        .updateCheck, .modelDownload] {
            #expect(!offline.allows(purpose))
        }
        let localPolicy = NetworkPolicy(
            mode: .localWithOptionalCloudEnhancement,
            cloudEnhancementEnabled: false
        )
        #expect(!localPolicy.allows(.transcription))
        #expect(!localPolicy.allows(.enhancement))
        #expect(localPolicy.allows(.modelDownload))
    }

    @MainActor
    @Test func phaseFourSettingsMigrationKeepsExistingInstallationsOnOpenAI() {
        let suite = "FlowDictatePhaseFourSettings-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(3, forKey: "onboardingVersion")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.transcriptionProviderID == .openAI)
        #expect(settings.privacyMode == .cloudTranscription)
        #expect(settings.localTranscriptionModelID == LocalModelCatalog.parakeetV3.id)
    }

    @MainActor
    @Test func localProviderDoesNotRequireAPIKeyAndOfflineForcesLocalSelection() async {
        let local = makeCoordinatorHarness(
            credentialStore: EmptyCredentialStore(),
            transcriptionProviderID: .local,
            privacyMode: .offline
        )
        await local.coordinator.toggleDictation()
        await local.coordinator.toggleDictation()
        #expect(local.provider.transcribeCount == 1)
        #expect(local.inserter.insertCount == 1)

        let normalizedOffline = makeCoordinatorHarness(
            transcriptionProviderID: .openAI,
            privacyMode: .offline
        )
        #expect(normalizedOffline.coordinator.settings.transcriptionProviderID == .local)
        #expect(normalizedOffline.coordinator.settings.privacyMode == .offline)
        #expect(!NetworkPolicy(mode: .offline, cloudEnhancementEnabled: false).allows(.transcription))
    }

    @MainActor
    @Test func onboardingAcceptsReadySelectedProviderWithoutRequiringTheOther() {
        // The selected-provider readiness is true for an installed local model
        // even when no OpenAI API key exists; it is false for an unconfigured
        // OpenAI selection even when a local model happens to be installed.
        #expect(OnboardingView.canContinue(
            step: 2,
            recordingLocationConfigured: true,
            transcriptionSetupReady: true
        ))
        #expect(OnboardingView.isReady(
            recordingLocationConfigured: true,
            transcriptionSetupReady: true
        ))
        #expect(!OnboardingView.canContinue(
            step: 2,
            recordingLocationConfigured: true,
            transcriptionSetupReady: false
        ))
        #expect(!OnboardingView.isReady(
            recordingLocationConfigured: true,
            transcriptionSetupReady: false
        ))
        #expect(!OnboardingView.canContinue(
            step: 1,
            recordingLocationConfigured: false,
            transcriptionSetupReady: true
        ))
    }

    @MainActor
    @Test func onboardingMicrophoneActionDoesNotRequestAccessibility() async {
        let permissions = CountingPermissionManager()
        let harness = makeCoordinatorHarness(permissionManager: permissions)

        await harness.coordinator.requestMicrophonePermission()

        #expect(permissions.microphoneRequestCount == 1)
        #expect(permissions.eventPostingRequestCount == 0)
        #expect(harness.coordinator.microphonePermissionGranted)
    }

    @MainActor
    @Test func offlineLocalDictationWithAIStyleStillInsertsLocalText() async {
        let harness = makeCoordinatorHarness(
            credentialStore: EmptyCredentialStore(),
            transcriptionProviderID: .local,
            privacyMode: .offline
        )
        harness.coordinator.settings.writingStyleID = BuiltInWritingStyles.cleanedID
        harness.coordinator.settings.cloudEnhancementEnabled = false

        await harness.coordinator.toggleDictation()
        await harness.coordinator.toggleDictation()
        await harness.coordinator.refreshHistory()

        #expect(harness.provider.transcribeCount == 1)
        #expect(harness.inserter.insertCount == 1)
        #expect(harness.coordinator.historyRecords.first?.processingStatus == .completed)
        #expect(harness.coordinator.historyRecords.first?.writingStyleID == BuiltInWritingStyles.cleanedID)
        #expect(harness.coordinator.historyRecords.first?.enhancementAttemptCount == 0)
    }

    @Test func inlineCorrectionsAreDeterministicLiteralAndProtected() {
        let processor = InlineCorrectionProcessor()

        let last = processor.process(
            "Alpha beta alpha. Ersetze alpha durch gamma.",
            language: "de"
        )
        #expect(last.text == "Alpha beta gamma.")
        #expect(last.summary.appliedCount == 1)

        let all = processor.process(
            "Alpha beta alpha. Ersetze alle alpha durch gamma.",
            language: "de"
        )
        #expect(all.text == "gamma beta gamma.")

        let english = processor.process(
            "One two three delete the last word. Undo the last correction.",
            language: "en"
        )
        #expect(english.text == "One two three.")
        #expect(english.summary.undoneCount == 1)

        let literal = processor.process(
            "Say literal replace alpha with beta.",
            language: "en"
        )
        #expect(literal.text == "Say replace alpha with beta.")

        let protected = processor.process(
            "https://alpha.example alpha. Replace all alpha with beta.",
            language: "en"
        )
        #expect(protected.text == "https://alpha.example beta.")

        let dictionaryProtected = processor.process(
            "FlowDictate works. Replace FlowDictate with Other.",
            language: "en",
            protectedTerms: ["FlowDictate"]
        )
        #expect(dictionaryProtected.text.contains("FlowDictate"))
        #expect(dictionaryProtected.summary.ignoredAmbiguousCount == 1)
    }

    @Test func automaticInsertionUsesAccessibilityBeforeClipboardFallback() {
        #expect(InsertionPreference.automatic.attemptsDirectAccessibility)
        #expect(!InsertionPreference.clipboard.attemptsDirectAccessibility)
        #expect(InsertionPreference.accessibility.attemptsDirectAccessibility)
    }

    @MainActor
    @Test func wordSkipsKnownSlowAccessibilityProbeAndUsesClipboardImmediately() async throws {
        let application = NSRunningApplication(
            processIdentifier: ProcessInfo.processInfo.processIdentifier
        ) ?? NSWorkspace.shared.frontmostApplication!
        let target = FocusTarget(
            application: application,
            processIdentifier: application.processIdentifier,
            bundleIdentifier: "com.microsoft.Word",
            localizedName: "Microsoft Word"
        )
        let direct = MockTextInserter()
        let clipboard = MockTextInserter()
        let inserter = FallbackTextInserter(direct: direct, clipboard: clipboard)

        try await inserter.insert("Fast Word insertion", into: target)

        #expect(direct.insertCount == 0)
        #expect(clipboard.insertCount == 1)
        #expect(clipboard.insertedText == "Fast Word insertion")
    }

    @MainActor
    @Test func chatGPTUsesClipboardWhileOtherAppsRemainAccessibilityFirst() async throws {
        #expect(PasteboardTextInserter.usesTargetedPaste(for: "com.openai.codex"))
        for bundleIdentifier in [
            "com.microsoft.Word",
            "com.anthropic.claudefordesktop",
            "com.apple.Notes",
            "com.apple.mail",
            "com.apple.TextEdit"
        ] {
            #expect(!PasteboardTextInserter.usesTargetedPaste(for: bundleIdentifier))
        }
        let application = NSRunningApplication(
            processIdentifier: ProcessInfo.processInfo.processIdentifier
        ) ?? NSWorkspace.shared.frontmostApplication!
        let direct = MockTextInserter()
        let clipboard = MockTextInserter()
        let inserter = FallbackTextInserter(direct: direct, clipboard: clipboard)

        let chatGPT = FocusTarget(
            application: application,
            processIdentifier: application.processIdentifier,
            bundleIdentifier: "com.openai.codex",
            localizedName: "ChatGPT"
        )
        try await inserter.insert("Chat text", into: chatGPT)
        #expect(direct.insertCount == 0)
        #expect(clipboard.insertCount == 1)
        #expect(clipboard.insertedText == "Chat text")

        let textEdit = FocusTarget(
            application: application,
            processIdentifier: application.processIdentifier,
            bundleIdentifier: "com.apple.TextEdit",
            localizedName: "TextEdit"
        )
        try await inserter.insert("Other app text", into: textEdit)
        #expect(direct.insertCount == 1)
        #expect(direct.insertedText == "Other app text")
        #expect(clipboard.insertCount == 1)
    }

    @Test func dictationJobStoreRoundTripsSequencesAndNormalizesInterruption() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateJobStore-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DictationJobStore(directory: directory)
        let firstSequence = try await store.nextSequence()
        let secondSequence = try await store.nextSequence()
        #expect(secondSequence == firstSequence + 1)

        var job = makePhaseFourJob(sequence: firstSequence, status: .transcribing)
        try await store.create(job)
        let loaded = try #require(try await store.job(id: job.id))
        #expect(loaded.id == job.id)
        #expect(loaded.queueSequence == job.queueSequence)
        #expect(loaded.effectiveConfiguration == job.effectiveConfiguration)
        #expect(loaded.status == job.status)

        let normalized = try await store.normalizeInterrupted()
        #expect(normalized.count == 1)
        job.status = .failed
        #expect(try await store.job(id: job.id)?.status == job.status)
        #expect(try await store.job(id: job.id)?.lastErrorCategory == .interrupted)
    }

    @Test func dictationQueueIsFIFOAndLimitsWaitingJobs() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateQueue-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DictationJobStore(directory: directory)
        let queue = DictationProcessingQueue(store: store, maximumWaitingJobs: 5)

        for sequence in 1...5 {
            _ = try await queue.reserveRecordingSlot()
            _ = try await queue.commit(makePhaseFourJob(sequence: Int64(sequence)))
        }
        do {
            _ = try await queue.reserveRecordingSlot()
            Issue.record("A sixth waiting job should be rejected")
        } catch let error as DictationQueueError {
            guard case .full(maximumWaiting: 5) = error else {
                Issue.record("Unexpected queue error: \(error)")
                return
            }
        }

        let first = try #require(try await queue.next())
        #expect(first.queueSequence == 1)
        var completed = first
        completed.status = .completed
        _ = try await queue.didFinish(completed)
        let second = try #require(try await queue.next())
        #expect(second.queueSequence == 2)
    }

    @Test func meetingQueueLaneRejectsQueuedDictationsAndNewRecordings() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateMeetingQueue-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DictationJobStore(directory: directory)
        let queue = DictationProcessingQueue(store: store)
        let meetingID = UUID()

        let active = try await queue.beginMeetingProcessing(sessionID: meetingID)
        #expect(active.processingCount == 1)
        await #expect(throws: DictationQueueError.self) {
            _ = try await queue.reserveRecordingSlot()
        }
        #expect(try await queue.next() == nil)

        let released = await queue.finishMeetingProcessing(sessionID: meetingID)
        #expect(released.totalActiveCount == 0)
        _ = try await queue.reserveRecordingSlot()
        _ = try await queue.commit(makePhaseFourJob(sequence: 1))
        await #expect(throws: DictationQueueError.self) {
            _ = try await queue.beginMeetingProcessing(sessionID: UUID())
        }
    }

    @Test func queuedJobCanBeCancelledWithoutDeletingItsHistoryAudio() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateQueueCancel-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DictationJobStore(directory: directory)
        let queue = DictationProcessingQueue(store: store)
        let job = makePhaseFourJob(sequence: 1)
        _ = try await queue.reserveRecordingSlot()
        _ = try await queue.commit(job)

        let snapshot = try await queue.cancelQueued(id: job.id)

        #expect(snapshot.queuedCount == 0)
        #expect(try await store.job(id: job.id)?.status == .cancelled)
    }

    @Test func queuedHistoryRecordsAreProtectedFromRetention() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateQueuedRetention-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DictationHistoryStore(fileURL: directory.appendingPathComponent("history.json"))
        var record = makeTranscribedRecord(text: "Queued")
        record.createdAt = Date(timeIntervalSince1970: 1)
        record.audioFileSize = 500
        record.jobID = UUID()
        record.jobStatus = .queued
        record.queueSequence = 1
        try await store.upsert(record)

        let result = try await store.applyRetention(
            maximumAgeDays: 0,
            maximumRecordCount: 0,
            now: Date()
        )

        #expect(result == HistoryRetentionResult())
        #expect(try await store.record(id: record.id)?.archivedAt == nil)
    }

    @Test func phaseThreeAppProfileMigratesByInheritingProvider() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateProfileMigration-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("app-profiles.json")
        let id = UUID()
        let legacy: [String: Any] = [
            "schemaVersion": 1,
            "profiles": [[
                "id": id.uuidString,
                "bundleIdentifier": "com.example.Editor",
                "displayName": "Editor",
                "insertionPreference": "automatic",
                "isEnabled": true,
                "schemaVersion": 1
            ]]
        ]
        try JSONSerialization.data(withJSONObject: legacy).write(to: fileURL)

        let store = AppProfileStore(fileURL: fileURL)
        let profile = try #require(try await store.all().first)

        #expect(profile.id == id)
        #expect(profile.transcriptionProviderID == nil)
        #expect(profile.schemaVersion == 1)
        try await store.upsert(profile)
        #expect(try await store.all().first?.schemaVersion == 2)
    }

    @Test func schemaFiveHistoryCreatesPhaseFourBackupAndRejectsFutureSchema() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSchemaSix-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("dictations.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let recordData = try encoder.encode(makeTranscribedRecord(text: "Preserved"))
        let recordObject = try #require(JSONSerialization.jsonObject(with: recordData) as? [String: Any])
        let legacy = try JSONSerialization.data(
            withJSONObject: ["schemaVersion": 5, "records": [recordObject]]
        )
        try legacy.write(to: fileURL)

        let store = DictationHistoryStore(fileURL: fileURL)
        #expect(try await store.all().first?.finalText == "Preserved")
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("dictations-pre-4.0.json").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("dictations-pre-4.1.json").path
        ))

        let futureURL = directory.appendingPathComponent("future.json")
        try JSONSerialization.data(
            withJSONObject: ["schemaVersion": 999, "records": []]
        ).write(to: futureURL)
        let future = DictationHistoryStore(fileURL: futureURL)
        do {
            _ = try await future.all()
            Issue.record("A future History schema must not be overwritten")
        } catch let error as DictationHistoryError {
            guard case .unsupportedSchema(999) = error else {
                Issue.record("Unexpected History error: \(error)")
                return
            }
        }
    }

    @Test func schemaSixHistoryCreatesOneTimePhaseFourOneBackup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateSchemaSeven-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("dictations.json")
        let backupURL = directory.appendingPathComponent("dictations-pre-4.1.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let recordData = try encoder.encode(makeTranscribedRecord(text: "Schema six"))
        var recordObject = try #require(
            JSONSerialization.jsonObject(with: recordData) as? [String: Any]
        )
        recordObject.removeValue(forKey: "meetingSummary")
        let legacy = try JSONSerialization.data(
            withJSONObject: ["schemaVersion": 6, "records": [recordObject]]
        )
        try legacy.write(to: fileURL)

        let store = DictationHistoryStore(fileURL: fileURL)
        let migrated = try #require(try await store.all().first)
        #expect(migrated.finalText == "Schema six")
        #expect(migrated.meetingSummary == nil)
        #expect(try Data(contentsOf: backupURL) == legacy)
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("dictations-pre-4.0.json").path
        ))

        let backup = try Data(contentsOf: backupURL)
        _ = try await DictationHistoryStore(fileURL: fileURL).all()
        #expect(try Data(contentsOf: backupURL) == backup)
        let persisted = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        )
        #expect(persisted["schemaVersion"] as? Int == 7)
    }

    private func makePhaseFourJob(
        sequence: Int64,
        status: DictationJobStatus = .queued
    ) -> DictationJob {
        let now = Date()
        let configuration = PersistedDictationConfiguration(
            providerID: .local,
            engineID: "fluidaudio-parakeet-v3",
            modelID: LocalModelCatalog.parakeetV3.id,
            executionLocation: .local,
            language: "de",
            writingStyleID: BuiltInWritingStyles.originalID,
            spokenFormattingEnabled: true,
            personalDictionaryEnabled: true,
            insertionPreference: .automatic,
            privacyMode: .offline,
            cloudEnhancementEnabled: false,
            enhancementModel: "unused",
            enhancementFallback: .useLocallyProcessed,
            profileID: nil
        )
        return DictationJob(
            schemaVersion: DictationJob.currentSchemaVersion,
            id: UUID(),
            recordID: UUID(),
            createdAt: now,
            updatedAt: now,
            queueSequence: sequence,
            audioRelativePath: "recording.m4a",
            audioSource: .microphone,
            providerID: TranscriptionProviderID.local.rawValue,
            engineID: configuration.engineID,
            modelID: configuration.modelID,
            executionLocation: .local,
            language: "de",
            targetBundleIdentifier: "test.app",
            targetApplicationName: "Test",
            effectiveConfiguration: configuration,
            status: status,
            correctionSummary: nil,
            insertionAttemptCount: 0,
            automaticInsertionCompleted: false,
            lastErrorCategory: nil,
            lastErrorMessage: nil
        )
    }

    @MainActor
    private func makeCoordinatorHarness(
        credentialStore: any CredentialStoring = MockCredentialStore(),
        permissionManager: (any PermissionManaging)? = nil,
        transcriptEnhancerFactory: @escaping @MainActor (String) -> any TranscriptEnhancing = {
            OpenAITranscriptEnhancer(apiKey: $0)
        },
        livePreviewProvider: (any LivePreviewProviding)? = nil,
        livePreviewAvailabilityProvider:
            (@MainActor (TranscriptionLanguage, SpeechPermissionState) -> LivePreviewAvailability)? = nil,
        livePreviewEnabled: Bool = false,
        recordingSource: RecordingAudioSource = .microphone,
        transcriptionProviderID: TranscriptionProviderID = .openAI,
        privacyMode: PrivacyMode = .cloudTranscription,
        meetingRecordingConsentPresenter: (any MeetingRecordingConsentPresenting)? = nil,
        mixedRecordingCoordinatorFactory:
            (@MainActor (AudioDeviceID?) -> any MixedRecordingSessionCoordinating)? = nil,
        meetingProcessingWorkflow: (any MeetingProcessingRunning)? = nil,
        meetingTranscriptInsertionGate:
            (any MeetingTranscriptInsertionGating)? = nil,
        mixedCaptureTestDuration: Duration = .seconds(5),
        applicationRestarter: (any ApplicationRestarting)? = nil
    ) -> CoordinatorHarness {
        let suiteName = "FlowDictateCoordinatorTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let recorder = MockAudioRecorder()
        recorder.sourceMetadata = AudioSourceMetadata(
            source: recordingSource,
            sampleRate: 48_000,
            channelCount: 1
        )
        let provider = MockTranscriptionProvider()
        let inserter = MockTextInserter()
        let overlay = MockRecordingOverlay()
        let processActivityManager = MockProcessActivityManager()
        let application = NSRunningApplication(
            processIdentifier: ProcessInfo.processInfo.processIdentifier
        ) ?? NSWorkspace.shared.frontmostApplication!
        let target = FocusTarget(
            application: application,
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            localizedName: "FlowDictate Tests"
        )
        let focusTargetBox = FocusTargetBox(target)
        let settings = AppSettings(defaults: defaults)
        settings.livePreviewEnabled = livePreviewEnabled
        settings.recordingAudioSource = recordingSource
        settings.transcriptionProviderID = transcriptionProviderID
        settings.privacyMode = privacyMode

        let recordingLocationStore = configuredRecordingLocationStore(defaults: defaults)
        let historyStore = DictationHistoryStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("FlowDictateHistory-\(UUID()).json")
        )
        let jobStore = DictationJobStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("FlowDictateJobs-\(UUID())", isDirectory: true)
        )

        let dictationHotKeyRegistrar = MockHotKeyRegistrar()
        let cancelHotKeyRegistrar = MockHotKeyRegistrar()
        let restoreHotKeyRegistrar = MockHotKeyRegistrar()
        let coordinator = DictationCoordinator(
            settings: settings,
            dictationHotKeyRegistrar: dictationHotKeyRegistrar,
            cancelHotKeyRegistrar: cancelHotKeyRegistrar,
            restoreHotKeyRegistrar: restoreHotKeyRegistrar,
            applicationRestarter: applicationRestarter ?? WorkspaceApplicationRestarter(),
            permissionManager: permissionManager ?? MockPermissionManager(),
            recorder: recorder,
            systemAudioRecorder: recorder,
            provider: provider,
            inserter: inserter,
            credentialStore: credentialStore,
            audioDeviceService: MockAudioDeviceService(),
            launchAtLogin: LaunchAtLoginManager(automaticallyEnableOnFirstLaunch: false),
            overlay: overlay,
            focusTargetProvider: { focusTargetBox.target },
            environment: [:],
            recordingLocationStore: recordingLocationStore,
            historyStore: historyStore,
            livePreviewProvider: livePreviewProvider,
            transcriptEnhancerFactory: transcriptEnhancerFactory,
            jobStore: jobStore,
            processActivityManager: processActivityManager,
            meetingRecordingConsentPresenter: meetingRecordingConsentPresenter,
            mixedRecordingCoordinatorFactory: mixedRecordingCoordinatorFactory,
            meetingProcessingWorkflow: meetingProcessingWorkflow,
            meetingTranscriptInsertionGate: meetingTranscriptInsertionGate,
            mixedCaptureTestDuration: mixedCaptureTestDuration,
            livePreviewAvailabilityProvider: livePreviewAvailabilityProvider ?? { _, _ in
                .available(localeIdentifier: "de-DE")
            }
        )

        return CoordinatorHarness(
            coordinator: coordinator,
            recorder: recorder,
            provider: provider,
            inserter: inserter,
            overlay: overlay,
            focusTargetBox: focusTargetBox,
            processActivityManager: processActivityManager,
            dictationHotKeyRegistrar: dictationHotKeyRegistrar,
            cancelHotKeyRegistrar: cancelHotKeyRegistrar,
            restoreHotKeyRegistrar: restoreHotKeyRegistrar,
            recordingLocationStore: recordingLocationStore,
            historyStore: historyStore,
            jobStore: jobStore
        )
    }

    private func configuredRecordingLocationStore(defaults: UserDefaults) -> RecordingLocationStore {
        let store = RecordingLocationStore(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateRecordings-\(UUID())", isDirectory: true)
        try? store.configure(directory: directory)
        return store
    }

    private func makeTrackTranscriptionFixture(
        rootURL: URL
    ) async throws -> (
        store: MeetingSessionStore,
        session: MixedRecordingSession,
        paths: MeetingSessionPaths
    ) {
        let store = MeetingSessionStore(rootURL: rootURL)
        var session = makeValidMixedRecordingSession()
        session.status = .queued
        let paths = try await store.prepareSession(id: session.id)
        for track in session.tracks {
            let relativePath = try #require(track.audioRelativePath)
            try Data("audio-\(track.role.rawValue)".utf8).write(
                to: paths.sessionDirectory.appendingPathComponent(relativePath)
            )
        }
        try await store.create(session)
        return (store, session, paths)
    }

    private func makeLongFormTrackTranscriptionFixture(
        rootURL: URL,
        providerID: String,
        engineID: String,
        modelID: String,
        privacyMode: PrivacyMode,
        sampleAmplitude: Float = 0
    ) async throws -> (
        store: MeetingSessionStore,
        session: MixedRecordingSession,
        paths: MeetingSessionPaths
    ) {
        let store = MeetingSessionStore(rootURL: rootURL)
        var session = makeValidMixedRecordingSession()
        session.status = .queued
        session.providerID = providerID
        session.engineID = engineID
        session.modelID = modelID
        session.privacyMode = privacyMode
        let paths = try await store.prepareSession(id: session.id)
        let format = try #require(AVAudioFormat(
            standardFormatWithSampleRate: 16_000,
            channels: 1
        ))
        let frameCount: AVAudioFrameCount = 80_000

        for index in session.tracks.indices {
            let relativePath = try #require(session.tracks[index].audioRelativePath)
            let url = paths.sessionDirectory.appendingPathComponent(relativePath)
            do {
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                let buffer = try #require(AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: frameCount
                ))
                buffer.frameLength = frameCount
                if sampleAmplitude != 0 {
                    let samples = try #require(buffer.floatChannelData?[0])
                    for frame in 0..<Int(frameCount) {
                        samples[frame] = sampleAmplitude
                    }
                }
                try file.write(from: buffer)
            }
            session.tracks[index].durationMilliseconds = 5_000
            session.tracks[index].byteCount = Int64(
                try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            )
            session.tracks[index].sampleRate = 16_000
            session.tracks[index].channelCount = 1
        }
        try await store.create(session)
        return (store, session, paths)
    }

    private func makeSynchronizationTrack(
        role: RecordingTrackRole,
        startMilliseconds: Int64,
        anchorSessionTimes: [Int64],
        gaps: [TrackGap] = []
    ) -> MeetingAudioTrack {
        let sampleRate = 48_000.0
        let anchorIntervalMilliseconds: Int64 = 30_000
        let anchors = anchorSessionTimes.enumerated().map { index, sessionTime in
            TrackTimestampAnchor(
                hostTime: UInt64(1_000_000 + index * 1_000_000),
                trackFramePosition: Int64(index) * Int64(sampleRate)
                    * anchorIntervalMilliseconds / 1_000,
                sessionTimeMilliseconds: sessionTime
            )
        }
        return MeetingAudioTrack(
            id: UUID(),
            role: role,
            status: .finalized,
            audioRelativePath: role == .localSpeaker
                ? "tracks/microphone.caf"
                : "tracks/system-audio.caf",
            formatIdentifier: "lpcm",
            sampleRate: sampleRate,
            channelCount: 1,
            firstHostTime: UInt64(max(0, startMilliseconds)) + 1_000_000,
            lastHostTime: UInt64(max(0, startMilliseconds)) + 3_000_000,
            durationMilliseconds: 60_000,
            byteCount: 11_520_000,
            timestampAnchors: anchors,
            gaps: gaps,
            quality: TrackQualityMetrics(
                peakLevel: 0.5,
                clippedFrameCount: 0,
                silentDurationMilliseconds: 0,
                droppedBufferCount: Int64(gaps.count)
            ),
            transcriptionSessionID: nil,
            transcriptRelativePath: nil,
            errorCategory: nil,
            errorMessage: nil
        )
    }

    private func makeDerivedTrackFixture() throws -> (
        directory: URL,
        session: MixedRecordingSession,
        microphoneURL: URL,
        systemAudioURL: URL,
        microphoneOriginal: Data,
        systemAudioOriginal: Data
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateDerivedTracks-\(UUID())", isDirectory: true)
        let tracksDirectory = directory.appendingPathComponent("tracks", isDirectory: true)
        let derivedDirectory = directory.appendingPathComponent("derived", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tracksDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: derivedDirectory,
            withIntermediateDirectories: true
        )
        let microphoneURL = tracksDirectory.appendingPathComponent("microphone.caf")
        let systemAudioURL = tracksDirectory.appendingPathComponent("system-audio.caf")
        try writeImpulseCAF(url: microphoneURL, impulseFrame: 0)
        try writeImpulseCAF(url: systemAudioURL, impulseFrame: 4_800)
        let microphoneOriginal = try Data(contentsOf: microphoneURL)
        let systemAudioOriginal = try Data(contentsOf: systemAudioURL)

        var session = makeValidMixedRecordingSession()
        session.status = .queued
        session.synchronization = SynchronizationReport(
            quality: .good,
            initialOffsetMilliseconds: 100,
            estimatedDriftPartsPerMillion: nil,
            residualDriftMilliseconds: nil,
            analyzedAnchorCount: 2
        )
        session.qualityReport = MeetingQualityReport(
            synchronizationQuality: .good,
            completeTrackRoles: [.localSpeaker, .systemAudio],
            totalGapCount: 0,
            totalGapDurationMilliseconds: 0,
            totalClippedFrameCount: 0
        )
        for index in session.tracks.indices {
            let isMicrophone = session.tracks[index].role == .localSpeaker
            session.tracks[index].audioRelativePath = isMicrophone
                ? "tracks/microphone.caf"
                : "tracks/system-audio.caf"
            session.tracks[index].formatIdentifier = "lpcm"
            session.tracks[index].sampleRate = 48_000
            session.tracks[index].channelCount = 1
            session.tracks[index].durationMilliseconds = 500
            session.tracks[index].byteCount = Int64(
                isMicrophone ? microphoneOriginal.count : systemAudioOriginal.count
            )
            session.tracks[index].timestampAnchors = [
                TrackTimestampAnchor(
                    hostTime: isMicrophone ? 1_100 : 1_000,
                    trackFramePosition: 0,
                    sessionTimeMilliseconds: isMicrophone ? 100 : 0
                )
            ]
            session.tracks[index].gaps = []
        }
        return (
            directory,
            session,
            microphoneURL,
            systemAudioURL,
            microphoneOriginal,
            systemAudioOriginal
        )
    }

    private func writeImpulseCAF(url: URL, impulseFrame: Int) throws {
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let frameCount: AVAudioFrameCount = 24_000
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ))
        buffer.frameLength = frameCount
        let samples = try #require(buffer.floatChannelData?[0])
        samples.initialize(repeating: 0, count: Int(frameCount))
        samples[impulseFrame] = 0.75
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }

    private func peakFrame(in url: URL) throws -> Int {
        let file = try AVAudioFile(forReading: url)
        let capacity = AVAudioFrameCount(file.length)
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: capacity
        ))
        try file.read(into: buffer)
        let samples = try #require(buffer.floatChannelData?[0])
        var peakIndex = 0
        var peak: Float = 0
        for index in 0..<Int(buffer.frameLength) where abs(samples[index]) > peak {
            peak = abs(samples[index])
            peakIndex = index
        }
        return peakIndex
    }

    private func makeMeetingTrackTranscript(
        session: MixedRecordingSession,
        role: RecordingTrackRole,
        text: String,
        entries: [TrackTranscriptEntry]?
    ) -> MeetingTrackTranscript {
        let track = session.tracks.first { $0.role == role }!
        return MeetingTrackTranscript(
            schemaVersion: MeetingTrackTranscript.currentSchemaVersion,
            meetingSessionID: session.id,
            trackID: track.id,
            role: role,
            transcriptionSessionID: track.transcriptionSessionID!,
            providerID: session.providerID,
            modelID: session.modelID,
            language: session.language,
            transcript: text,
            segmentCount: max(entries?.count ?? 1, 1),
            completedSegmentCount: max(entries?.count ?? 1, 1),
            timedEntries: entries,
            createdAt: session.updatedAt
        )
    }

    private func makeValidMixedRecordingSession() -> MixedRecordingSession {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let baseQuality = TrackQualityMetrics(
            peakLevel: 0.75,
            clippedFrameCount: 0,
            silentDurationMilliseconds: 250,
            droppedBufferCount: 0
        )
        let microphone = MeetingAudioTrack(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            role: .localSpeaker,
            status: .finalized,
            audioRelativePath: "tracks/microphone.caf",
            formatIdentifier: "lpcm",
            sampleRate: 48_000,
            channelCount: 1,
            firstHostTime: 1_000,
            lastHostTime: 11_000,
            durationMilliseconds: 10_000,
            byteCount: 960_000,
            timestampAnchors: [
                TrackTimestampAnchor(
                    hostTime: 1_000,
                    trackFramePosition: 0,
                    sessionTimeMilliseconds: 0
                ),
                TrackTimestampAnchor(
                    hostTime: 11_000,
                    trackFramePosition: 480_000,
                    sessionTimeMilliseconds: 10_000
                )
            ],
            gaps: [],
            quality: baseQuality,
            transcriptionSessionID: nil,
            transcriptRelativePath: nil,
            errorCategory: nil,
            errorMessage: nil
        )
        let systemAudio = MeetingAudioTrack(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            role: .systemAudio,
            status: .finalized,
            audioRelativePath: "tracks/system-audio.m4a",
            formatIdentifier: "aac",
            sampleRate: 48_000,
            channelCount: 2,
            firstHostTime: 1_010,
            lastHostTime: 11_010,
            durationMilliseconds: 10_000,
            byteCount: 180_000,
            timestampAnchors: [
                TrackTimestampAnchor(
                    hostTime: 1_010,
                    trackFramePosition: 0,
                    sessionTimeMilliseconds: 10
                ),
                TrackTimestampAnchor(
                    hostTime: 11_010,
                    trackFramePosition: 480_000,
                    sessionTimeMilliseconds: 10_010
                )
            ],
            gaps: [],
            quality: baseQuality,
            transcriptionSessionID: nil,
            transcriptRelativePath: nil,
            errorCategory: nil,
            errorMessage: nil
        )
        return MixedRecordingSession(
            schemaVersion: MixedRecordingSession.currentSchemaVersion,
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            recordID: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
            dictationJobID: nil,
            status: .finalizing,
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(10),
            providerID: "local",
            engineID: "fluid-audio",
            modelID: "parakeet-tdt-0.6b-v3-coreml",
            language: "en",
            privacyMode: .offline,
            profileID: UUID(uuidString: "50000000-0000-0000-0000-000000000005"),
            tracks: [microphone, systemAudio],
            synchronization: SynchronizationReport(
                quality: .good,
                initialOffsetMilliseconds: 10,
                estimatedDriftPartsPerMillion: 0,
                residualDriftMilliseconds: 0,
                analyzedAnchorCount: 4
            ),
            qualityReport: MeetingQualityReport(
                synchronizationQuality: .good,
                completeTrackRoles: [.localSpeaker, .systemAudio],
                totalGapCount: 0,
                totalGapDurationMilliseconds: 0,
                totalClippedFrameCount: 0
            ),
            completionMode: nil,
            mergedTimelineRelativePath: nil,
            finalTranscript: nil,
            lastErrorCategory: nil,
            lastErrorMessage: nil
        )
    }

    private func makeCompletedMixedRecordingSession(
        insertionState: MeetingTranscriptInsertionState
    ) -> MixedRecordingSession {
        var session = makeValidMixedRecordingSession()
        session.status = .completed
        session.completionMode = .allTracks
        session.mergedTimelineRelativePath = MeetingTranscriptMergeRunner.timelineRelativePath
        session.finalTranscript = "[You] Hello\n[System Audio] Welcome"
        session.transcriptInsertionState = insertionState
        session.transcriptInsertionAttemptCount = switch insertionState {
        case .attempting, .completed: 1
        case .ready, .deferred, .unknown: 0
        }
        for index in session.tracks.indices {
            session.tracks[index].status = .transcribed
            session.tracks[index].transcriptionSessionID = UUID()
            session.tracks[index].transcriptRelativePath =
                "transcription/\(session.tracks[index].role.rawValue)-transcript.json"
        }
        return session
    }

    private func makeTranscribedRecord(text: String) -> DictationRecord {
        let now = Date()
        var record = DictationRecord.newRecording(
            id: UUID(), startedAt: now, endedAt: now, duration: 1,
            status: .transcribed, audioRelativePath: "test.wav", audioFileSize: 100,
            providerID: "Test", modelID: "test-transcribe", language: "de",
            targetBundleIdentifier: nil, targetApplicationName: nil
        )
        record.originalTranscript = text
        record.finalText = text
        return record
    }
}

private actor TrackProviderResolverProbe {
    private let provider: any TranscriptionProvider
    private(set) var resolveCount = 0
    private(set) var requests: [TrackTranscriptionRequest] = []

    init(provider: any TranscriptionProvider) {
        self.provider = provider
    }

    func resolve(_ request: TrackTranscriptionRequest) -> any TranscriptionProvider {
        resolveCount += 1
        requests.append(request)
        return provider
    }
}

private nonisolated final class TimedTrackTranscriptionProvider: TranscriptionProvider,
    @unchecked Sendable {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        TranscriptionResult(
            text: "Timed words.",
            provider: TranscriptionProviderID.local.rawValue,
            model: "timed-local-test",
            timedUnits: [
                TranscriptionTimedUnit(
                    text: "Timed",
                    startMilliseconds: 100,
                    endMilliseconds: 300,
                    precision: .word
                ),
                TranscriptionTimedUnit(
                    text: "words.",
                    startMilliseconds: 400,
                    endMilliseconds: 700,
                    precision: .word
                )
            ]
        )
    }
}

private nonisolated enum MockTrackTranscriptionBehavior: Sendable {
    case success(String)
    case networkFailure
    case cancellation
}

private actor MockTrackTranscriptionExecutor: TrackTranscriptionExecuting {
    private var behaviors: [RecordingTrackRole: [MockTrackTranscriptionBehavior]]
    private(set) var requests: [TrackTranscriptionRequest] = []

    init(behaviors: [RecordingTrackRole: [MockTrackTranscriptionBehavior]]) {
        self.behaviors = behaviors
    }

    func transcribe(_ request: TrackTranscriptionRequest) async throws -> TrackTranscriptionOutput {
        requests.append(request)
        guard var queued = behaviors[request.role], !queued.isEmpty else {
            throw MockMixedTrackError.requested("No track transcription behavior was configured")
        }
        let behavior = queued.removeFirst()
        behaviors[request.role] = queued

        switch behavior {
        case let .success(text):
            return TrackTranscriptionOutput(
                transcript: text,
                providerID: request.providerID,
                modelID: request.modelID,
                segmentCount: 2,
                completedSegmentCount: 2
            )
        case .networkFailure:
            throw URLError(.notConnectedToInternet)
        case .cancellation:
            throw CancellationError()
        }
    }
}

private actor QueueAssertingTrackTranscriptionExecutor: TrackTranscriptionExecuting {
    private let queue: DictationProcessingQueue
    private(set) var blockedReservationCount = 0

    init(queue: DictationProcessingQueue) {
        self.queue = queue
    }

    func transcribe(_ request: TrackTranscriptionRequest) async throws -> TrackTranscriptionOutput {
        do {
            _ = try await queue.reserveRecordingSlot()
            _ = try await queue.releaseRecordingSlot()
            throw MockMixedTrackError.requested(
                "A new recording reservation was accepted during meeting processing"
            )
        } catch DictationQueueError.meetingProcessingBusy {
            blockedReservationCount += 1
        }
        return TrackTranscriptionOutput(
            transcript: "\(request.role.rawValue) transcript",
            providerID: request.providerID,
            modelID: request.modelID,
            segmentCount: 1,
            completedSegmentCount: 1
        )
    }
}

private nonisolated enum MixedTrackTestEvent: Sendable, Equatable {
    case prepare(RecordingTrackRole)
    case start(RecordingTrackRole, UInt64)
    case stop(RecordingTrackRole)
    case cancel(RecordingTrackRole)
}

private actor MixedTrackTestEventLog {
    private(set) var values: [MixedTrackTestEvent] = []

    func append(_ event: MixedTrackTestEvent) {
        values.append(event)
    }
}

private nonisolated final class LockedMixedWarningLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [MixedRecordingWarning] = []

    var values: [MixedRecordingWarning] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ warning: MixedRecordingWarning) {
        lock.lock()
        storedValues.append(warning)
        lock.unlock()
    }
}

private nonisolated enum MockMixedTrackError: LocalizedError, Sendable, Equatable {
    case requested(String)

    var errorDescription: String? {
        switch self {
        case let .requested(message): message
        }
    }
}

private actor MockMixedStopGate {
    private var entered = false
    private var released = false
    private var enterWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func block() async {
        entered = true
        enterWaiters.forEach { $0.resume() }
        enterWaiters.removeAll()
        guard !released else { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enterWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor MockMixedTrackRecorder: MixedTrackRecording {
    nonisolated let role: RecordingTrackRole

    private let events: MixedTrackTestEventLog
    private let prepareError: MockMixedTrackError?
    private let startError: (any Error & Sendable)?
    private let stopError: (any Error & Sendable)?
    private let stopGate: MockMixedStopGate?
    private let returnsCaptureOnCancel: Bool
    private var outputURL: URL?
    private var warningHandler: MixedTrackWarningHandler?
    private(set) var receivedStartHostTime: UInt64?

    init(
        role: RecordingTrackRole,
        events: MixedTrackTestEventLog,
        prepareError: MockMixedTrackError? = nil,
        startError: (any Error & Sendable)? = nil,
        stopError: (any Error & Sendable)? = nil,
        stopGate: MockMixedStopGate? = nil,
        returnsCaptureOnCancel: Bool = false
    ) {
        self.role = role
        self.events = events
        self.prepareError = prepareError
        self.startError = startError
        self.stopError = stopError
        self.stopGate = stopGate
        self.returnsCaptureOnCancel = returnsCaptureOnCancel
    }

    func setLevelHandler(_ handler: MixedTrackLevelHandler?) async {}

    func setWarningHandler(_ handler: MixedTrackWarningHandler?) async {
        warningHandler = handler
    }

    func emitWarning(_ kind: MixedTrackWarningKind) {
        warningHandler?(kind)
    }

    func prepare(outputURL: URL) async throws {
        await events.append(.prepare(role))
        if let prepareError { throw prepareError }
        self.outputURL = outputURL
        try Data("original-\(role.rawValue)".utf8).write(to: outputURL)
    }

    func start(requestedHostTime: UInt64) async throws -> MixedTrackStartResult {
        await events.append(.start(role, requestedHostTime))
        if let startError { throw startError }
        guard outputURL != nil else {
            throw MockMixedTrackError.requested("track was not prepared")
        }
        receivedStartHostTime = requestedHostTime
        let offset = role == .systemAudio ? UInt64(10) : UInt64(0)
        return MixedTrackStartResult(
            firstAnchor: TrackTimestampAnchor(
                hostTime: requestedHostTime + offset,
                trackFramePosition: 0,
                sessionTimeMilliseconds: role == .systemAudio ? 1 : 0
            )
        )
    }

    func stop() async throws -> MixedTrackCaptureResult {
        await events.append(.stop(role))
        if let stopGate { await stopGate.block() }
        if let stopError { throw stopError }
        return try captureResult()
    }

    func cancel() async -> MixedTrackCaptureResult? {
        await events.append(.cancel(role))
        defer {
            outputURL = nil
            receivedStartHostTime = nil
        }
        guard returnsCaptureOnCancel else { return nil }
        return try? captureResult()
    }

    private func captureResult() throws -> MixedTrackCaptureResult {
        guard let outputURL else {
            throw MockMixedTrackError.requested("track has no output URL")
        }
        let byteCount = Int64(
            try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        )
        let firstHostTime = receivedStartHostTime ?? 1
        let roleOffset = role == .systemAudio ? UInt64(10) : UInt64(0)
        let firstAnchorHostTime = firstHostTime + roleOffset
        return MixedTrackCaptureResult(
            formatIdentifier: "lpcm",
            sampleRate: 48_000,
            channelCount: 1,
            firstHostTime: firstAnchorHostTime,
            lastHostTime: firstAnchorHostTime + 48_000,
            durationMilliseconds: 1_000,
            byteCount: byteCount,
            timestampAnchors: [
                TrackTimestampAnchor(
                    hostTime: firstAnchorHostTime,
                    trackFramePosition: 0,
                    sessionTimeMilliseconds: role == .systemAudio ? 1 : 0
                ),
                TrackTimestampAnchor(
                    hostTime: firstAnchorHostTime + 48_000,
                    trackFramePosition: 48_000,
                    sessionTimeMilliseconds: role == .systemAudio ? 1_001 : 1_000
                )
            ],
            gaps: [],
            quality: TrackQualityMetrics(
                peakLevel: 0.5,
                clippedFrameCount: 0,
                silentDurationMilliseconds: 0,
                droppedBufferCount: 0
            )
        )
    }
}

private actor MockMixedRecordingSessionCoordinator: MixedRecordingSessionCoordinating {
    private let startResult: MixedRecordingSession
    private let stopResult: MixedRecordingSession
    private let cancelResult: MixedRecordingSession
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    private var levelHandler: MixedRecordingLevelHandler?

    init(
        startResult: MixedRecordingSession,
        stopResult: MixedRecordingSession,
        cancelResult: MixedRecordingSession? = nil
    ) {
        self.startResult = startResult
        self.stopResult = stopResult
        self.cancelResult = cancelResult ?? stopResult
    }

    func setLevelHandler(_ handler: MixedRecordingLevelHandler?) async {
        levelHandler = handler
    }

    func start(_ request: MixedRecordingSessionRequest) async throws -> MixedRecordingSession {
        startCount += 1
        levelHandler?(.localSpeaker, 0.25)
        levelHandler?(.systemAudio, 0.75)
        return startResult
    }

    func stop() async throws -> MixedRecordingSession {
        stopCount += 1
        return stopResult
    }

    func cancel() async throws -> MixedRecordingSession {
        cancelCount += 1
        return cancelResult
    }
}

private actor StubMeetingProcessingWorkflow: MeetingProcessingRunning {
    private let result: MixedRecordingSession
    private(set) var runCount = 0

    init(result: MixedRecordingSession) {
        self.result = result
    }

    func run(sessionID: UUID) async throws -> MixedRecordingSession {
        runCount += 1
        return result
    }
}

private actor StubMeetingTranscriptInsertionGate: MeetingTranscriptInsertionGating {
    private let beginDecision: MeetingTranscriptInsertionDecision
    private let failMarkCompleted: Bool
    private(set) var beginCount = 0
    private(set) var completedCount = 0
    private(set) var deferredCount = 0
    private(set) var lastTargetIsAvailable: Bool?

    init(
        beginDecision: MeetingTranscriptInsertionDecision,
        failMarkCompleted: Bool = false
    ) {
        self.beginDecision = beginDecision
        self.failMarkCompleted = failMarkCompleted
    }

    func begin(
        sessionID: UUID,
        targetIsAvailable: Bool
    ) async throws -> MeetingTranscriptInsertionDecision {
        beginCount += 1
        lastTargetIsAvailable = targetIsAvailable
        return beginDecision
    }

    func markCompleted(sessionID: UUID) async throws {
        completedCount += 1
        if failMarkCompleted {
            throw MockMixedTrackError.requested("Insertion completion persistence failed")
        }
    }

    func markDeferred(sessionID: UUID) async throws {
        deferredCount += 1
    }
}

private actor StubMeetingTrackRunner: MeetingTrackTranscriptionRunning {
    private let result: MixedRecordingSession
    private(set) var runCount = 0

    init(result: MixedRecordingSession) {
        self.result = result
    }

    func run(sessionID: UUID) async throws -> MixedRecordingSession {
        runCount += 1
        return result
    }
}

private actor StubMeetingMergeRunner: MeetingTranscriptMerging {
    private let result: MixedRecordingSession
    private(set) var runCount = 0

    init(result: MixedRecordingSession) {
        self.result = result
    }

    func run(sessionID: UUID) async throws -> MixedRecordingSession {
        runCount += 1
        return result
    }
}

@MainActor
private struct CoordinatorHarness {
    let coordinator: DictationCoordinator
    let recorder: MockAudioRecorder
    let provider: MockTranscriptionProvider
    let inserter: MockTextInserter
    let overlay: MockRecordingOverlay
    let focusTargetBox: FocusTargetBox
    let processActivityManager: MockProcessActivityManager
    let dictationHotKeyRegistrar: MockHotKeyRegistrar
    let cancelHotKeyRegistrar: MockHotKeyRegistrar
    let restoreHotKeyRegistrar: MockHotKeyRegistrar
    let recordingLocationStore: RecordingLocationStore
    let historyStore: DictationHistoryStore
    let jobStore: DictationJobStore
}

@MainActor
private final class MockProcessActivityManager: ProcessActivityManaging {
    private final class Token: NSObject {}
    private(set) var beginCount = 0
    private(set) var endCount = 0

    func beginUserInitiatedActivity(reason: String) -> NSObjectProtocol {
        beginCount += 1
        return Token()
    }

    func endActivity(_ activity: NSObjectProtocol) {
        endCount += 1
    }
}

@MainActor
private final class FocusTargetBox {
    var target: FocusTarget?

    init(_ target: FocusTarget?) {
        self.target = target
    }
}

@MainActor
private final class MockAudioRecorder: AudioRecording {
    var isRecording = false
    var levelHandler: (@MainActor (Float) -> Void)?
    var previewBufferHandler: (@Sendable (LivePreviewAudioBuffer) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var startDelay: Duration?
    var stopDelay: Duration?
    var resultDuration: TimeInterval = 1
    var sourceMetadata = AudioSourceMetadata.microphoneDefault

    func selectInputDevice(_ deviceID: AudioDeviceID?) {}

    func start() async throws {
        startCount += 1
        if let startDelay { try await Task.sleep(for: startDelay) }
        isRecording = true
    }

    func stop() async throws -> AudioRecordingResult {
        stopCount += 1
        isRecording = false
        if let stopDelay { try await Task.sleep(for: stopDelay) }
        return AudioRecordingResult(
            id: UUID(),
            url: FileManager.default.temporaryDirectory.appendingPathComponent("test.wav"),
            startedAt: Date(),
            duration: resultDuration,
            sourceMetadata: sourceMetadata
        )
    }
}

private nonisolated final class MockTranscriptionProvider: TranscriptionProvider, @unchecked Sendable {
    private(set) var transcribeCount = 0
    var error: Error?
    var delay: Duration?

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        transcribeCount += 1
        if let delay { try await Task.sleep(for: delay) }
        if let error { throw error }
        return TranscriptionResult(
            text: "Transcribed text",
            provider: "Test",
            model: "test-model"
        )
    }
}

private nonisolated final class RetryingMockTranscriptionProvider: TranscriptionProvider, @unchecked Sendable {
    private(set) var transcribeCount = 0

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        transcribeCount += 1
        if transcribeCount == 1 {
            throw URLError(.networkConnectionLost)
        }
        return TranscriptionResult(
            text: "Recovered transcription",
            provider: "Test",
            model: "test-model"
        )
    }
}

@MainActor
private final class StorageCapacityProbe {
    private let values: [Int64]
    private(set) var callCount = 0

    init(values: [Int64]) {
        self.values = values
    }

    func availableCapacity(at _: URL) -> Int64 {
        let value = values[min(callCount, values.count - 1)]
        callCount += 1
        return value
    }
}

private nonisolated final class SequenceTranscriptionProvider: TranscriptionProvider, @unchecked Sendable {
    private let texts: [String]
    private let providerID: String
    private let modelID: String
    private(set) var transcribeCount = 0
    private(set) var requestCount = 0

    init(
        texts: [String],
        providerID: String = "Test",
        modelID: String = "test"
    ) {
        self.texts = texts
        self.providerID = providerID
        self.modelID = modelID
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        requestCount += 1
        guard transcribeCount < texts.count else { throw TranscriptionProviderError.emptyTranscript }
        let text = texts[transcribeCount]
        transcribeCount += 1
        guard !text.isEmpty else { throw TranscriptionProviderError.emptyTranscript }
        return TranscriptionResult(text: text, provider: providerID, model: modelID)
    }
}

@MainActor
private final class MockLivePreviewProvider: LivePreviewProviding {
    var isAvailable = true
    private(set) var startCount = 0
    private(set) var finishCount = 0
    private(set) var cancelCount = 0
    private var eventHandler: (@MainActor (LivePreviewEvent) -> Void)?

    func start(
        buffers: AsyncStream<LivePreviewAudioBuffer>,
        localeIdentifier: String,
        eventHandler: @escaping @MainActor (LivePreviewEvent) -> Void
    ) throws {
        startCount += 1
        self.eventHandler = eventHandler
    }

    func finish() { finishCount += 1 }
    func cancel() { cancelCount += 1 }
    func emit(_ event: LivePreviewEvent) { eventHandler?(event) }
}

@MainActor
private final class MockTextInserter: TextInserting {
    private(set) var insertCount = 0
    private(set) var insertedText: String?

    func insert(_ text: String, into target: FocusTarget) async throws {
        insertCount += 1
        insertedText = text
    }
}

@MainActor
private final class MockHotKeyRegistrar: HotKeyRegistering {
    private var pressHandler: (@MainActor () -> Void)?
    private var releaseHandler: (@MainActor () -> Void)?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    var isRegistered: Bool { pressHandler != nil }

    func register(
        _ configuration: HotKeyConfiguration,
        pressed: @escaping @MainActor () -> Void,
        released: @escaping @MainActor () -> Void
    ) throws {
        registerCount += 1
        pressHandler = pressed
        releaseHandler = released
    }

    func press() { pressHandler?() }
    func release() { releaseHandler?() }

    func unregister() {
        unregisterCount += 1
        pressHandler = nil
        releaseHandler = nil
    }
}

@MainActor
private final class MockApplicationRestarter: ApplicationRestarting {
    var onOpen: (() -> Void)?
    var openError: Error?
    private(set) var openCount = 0
    private(set) var terminateCount = 0

    func openNewInstance() async throws {
        openCount += 1
        onOpen?()
        if let openError { throw openError }
    }

    func terminateCurrentInstance() {
        terminateCount += 1
    }
}

@MainActor
private final class MockMeetingRecordingConsentPresenter: MeetingRecordingConsentPresenting {
    private(set) var presentationCount = 0
    private var onConfirm: ((Bool) -> Void)?
    private var onCancel: (() -> Void)?

    func present(
        onConfirm: @escaping @MainActor (Bool) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        presentationCount += 1
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    func confirm(remember: Bool) {
        let action = onConfirm
        clear()
        action?(remember)
    }

    func cancel() {
        let action = onCancel
        clear()
        action?()
    }

    private func clear() {
        onConfirm = nil
        onCancel = nil
    }
}

@MainActor
private struct MockPermissionManager: PermissionManaging {
    func ensureMicrophoneAccess() async throws {}
    func ensureEventPostingAccess() throws {}
    var hasMicrophoneAccess: Bool { true }
    var hasEventPostingAccess: Bool { true }
    var speechRecognitionStatus: SpeechPermissionState { .authorized }
    func requestSpeechRecognitionAccess() async -> SpeechPermissionState { .authorized }
    func openMicrophoneSettings() {}
    func openAccessibilitySettings() {}
    func openSpeechRecognitionSettings() {}
}

@MainActor
private final class CountingPermissionManager: PermissionManaging {
    var microphoneRequestCount = 0
    var eventPostingRequestCount = 0
    private var microphoneAuthorized = false

    func ensureMicrophoneAccess() async throws {
        microphoneRequestCount += 1
        microphoneAuthorized = true
    }
    func ensureEventPostingAccess() throws { eventPostingRequestCount += 1 }
    var hasMicrophoneAccess: Bool { microphoneAuthorized }
    var hasEventPostingAccess: Bool { false }
    var speechRecognitionStatus: SpeechPermissionState { .notDetermined }
    func requestSpeechRecognitionAccess() async -> SpeechPermissionState { .authorized }
    func openMicrophoneSettings() {}
    func openAccessibilitySettings() {}
    func openSpeechRecognitionSettings() {}
}

private struct MockCredentialStore: CredentialStoring {
    func readAPIKey() throws -> String? { "test-key" }
    func saveAPIKey(_ value: String) throws {}
    func deleteAPIKey() throws {}
}

private struct EmptyCredentialStore: CredentialStoring {
    func readAPIKey() throws -> String? { nil }
    func saveAPIKey(_ value: String) throws {}
    func deleteAPIKey() throws {}
}

private nonisolated final class PassThroughAudioUploadPreparer: AudioUploadPreparing, @unchecked Sendable {
    func prepare(_ sourceURL: URL) async throws -> PreparedAudioUpload {
        PreparedAudioUpload(
            fileURL: sourceURL,
            filename: sourceURL.lastPathComponent,
            mimeType: "audio/m4a",
            temporaryFileURL: nil
        )
    }
}

private nonisolated final class SuccessfulOpenAIURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(
            self,
            didLoad: Data(#"{"text":"Cleanup stays off the response path"}"#.utf8)
        )
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private nonisolated final class MeetingPolicyOpenAIURLProtocol: URLProtocol, @unchecked Sendable {
    private static let counter = LockedTestCounter()

    static var requestCount: Int { counter.value }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "meeting-policy.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.counter.increment()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"text":"Meeting policy HTTP fixture"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private nonisolated final class SlowRemovalFileManager: FileManager, @unchecked Sendable {
    private let delay: TimeInterval
    private let lock = NSLock()
    private var storedRemovalCount = 0

    init(delay: TimeInterval) {
        self.delay = delay
        super.init()
    }

    var removalCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedRemovalCount
    }

    override func removeItem(at URL: URL) throws {
        Thread.sleep(forTimeInterval: delay)
        try super.removeItem(at: URL)
        lock.lock()
        storedRemovalCount += 1
        lock.unlock()
    }
}

private nonisolated final class CapturingMultipartFileManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private var storedBodies: [Data] = []

    var capturedBodies: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return storedBodies
    }

    override func removeItem(at URL: URL) throws {
        if URL.lastPathComponent.hasPrefix("FlowDictate-Multipart-") {
            let body = try Data(contentsOf: URL)
            lock.lock()
            storedBodies.append(body)
            lock.unlock()
        }
        try super.removeItem(at: URL)
    }
}

private nonisolated final class LockedTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }
}

private struct TestHistoryEnvelope: Encodable {
    let schemaVersion: Int
    let records: [DictationRecord]
}

private final class CountingCredentialStore: CredentialStoring, @unchecked Sendable {
    private(set) var readCount = 0

    func readAPIKey() throws -> String? {
        readCount += 1
        return "test-key"
    }

    func saveAPIKey(_ value: String) throws {}
    func deleteAPIKey() throws {}
}

private final class MockTranscriptEnhancer: TranscriptEnhancing, @unchecked Sendable {
    private(set) var callCount = 0
    private(set) var receivedTexts: [String] = []
    private let output: String?
    private let error: Error?

    init(output: String) { self.output = output; error = nil }
    init(error: Error) { output = nil; self.error = error }

    func enhance(_ request: TranscriptEnhancementRequest) async throws -> TranscriptEnhancementResult {
        callCount += 1
        receivedTexts.append(request.text)
        if let error { throw error }
        return TranscriptEnhancementResult(
            text: output ?? request.text,
            provider: "Mock",
            model: request.model
        )
    }
}

private final class EchoingLayoutMarkerEnhancer: TranscriptEnhancing, @unchecked Sendable {
    private(set) var receivedTexts: [String] = []
    private let outputPrefix: String
    private let outputSuffix: String

    init(outputPrefix: String, outputSuffix: String) {
        self.outputPrefix = outputPrefix
        self.outputSuffix = outputSuffix
    }

    func enhance(_ request: TranscriptEnhancementRequest) async throws -> TranscriptEnhancementResult {
        receivedTexts.append(request.text)
        let markerPattern = #"\[\[FLOWDICTATE_LAYOUT_BREAK_\d+\]\]"#
        let expression = try NSRegularExpression(pattern: markerPattern)
        let match = expression.firstMatch(
            in: request.text,
            range: NSRange(request.text.startIndex..., in: request.text)
        )
        let marker = match
            .flatMap { Range($0.range, in: request.text) }
            .map { String(request.text[$0]) } ?? ""
        return TranscriptEnhancementResult(
            text: "\(outputPrefix) \(marker) \(outputSuffix)",
            provider: "Mock",
            model: request.model
        )
    }
}

@MainActor
private struct MockAudioDeviceService: AudioDeviceServing {
    func inputDevices() throws -> [AudioInputDevice] { [] }
    func deviceID(forUID uid: String?) throws -> AudioDeviceID? { nil }
}

@MainActor
private final class MockRecordingOverlay: RecordingOverlayPresenting {
    private(set) var presentations: [OverlayStatus] = []
    private(set) var hideCount = 0
    private(set) var previewStates: [LivePreviewState] = []
    private(set) var meetingLevels: [(microphone: Float, systemAudio: Float)] = []
    private(set) var configurations: [(size: OverlaySize, position: OverlayPosition)] = []

    func show(status: OverlayStatus, level: Float, reposition: Bool) {
        presentations.append(status)
    }

    func updateLevel(_ level: Float) {}

    func updateMeetingLevels(microphone: Float, systemAudio: Float) {
        meetingLevels.append((microphone, systemAudio))
    }

    func updatePreview(_ state: LivePreviewState) { previewStates.append(state) }

    func configure(size: OverlaySize, position: OverlayPosition) {
        configurations.append((size, position))
    }

    func hide() {
        hideCount += 1
    }
}
