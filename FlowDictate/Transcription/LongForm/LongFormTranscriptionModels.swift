import Foundation

nonisolated enum LongFormSessionStatus: String, Codable, Sendable {
    case planning
    case ready
    case transcribing
    case paused
    case failed
    case merging
    case completed
}

nonisolated enum TranscriptionSegmentStatus: String, Codable, Sendable {
    case pending
    case preparing
    case ready
    case uploading
    case succeeded
    case silent
    case failed
    case interrupted
}

nonisolated enum LongFormReason: String, Codable, Sendable, Equatable {
    case duration
    case estimatedUploadSize
    case actualUploadSize
    case uncertainPreparation
    case resumedSession
}

nonisolated enum TranscriptionPreparationMode: Sendable, Equatable {
    case singleFile
    case longForm(reason: LongFormReason)
}

nonisolated struct LongFormConfiguration: Sendable, Equatable {
    var targetDurationMilliseconds: Int64 = 15 * 60 * 1_000
    var minimumDurationMilliseconds: Int64 = 12 * 60 * 1_000
    var maximumDurationMilliseconds: Int64 = 17 * 60 * 1_000
    var boundarySearchRadiusMilliseconds: Int64 = 60 * 1_000
    var fallbackOverlapMilliseconds: Int64 = 1_500
    var softUploadByteLimit: Int64 = 20_000_000
    var hardUploadByteLimit: Int64 = 24_500_000
    var workingStorageReserveBytes: Int64 = 250_000_000
    var promptCharacterLimit: Int = 400

    static let `default` = LongFormConfiguration()
}

nonisolated struct AudioAssetInspection: Sendable, Equatable {
    var byteCount: Int64
    var durationMilliseconds: Int64
    var sampleRate: Double
    var channelCount: Int
    var estimatedCompactByteCount: Int64
    var isCompactM4A: Bool
}

nonisolated struct TranscriptionSourceFingerprint: Codable, Sendable, Equatable {
    var audioRelativePath: String
    var byteCount: Int64
    var durationMilliseconds: Int64
    var modificationDate: Date?
}

nonisolated struct TranscriptionSegment: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var index: Int
    var startMilliseconds: Int64
    var endMilliseconds: Int64
    var overlapBeforeMilliseconds: Int64
    var status: TranscriptionSegmentStatus
    var preparedRelativePath: String?
    var preparedByteCount: Int64?
    var transcript: String?
    /// Provider timing relative to this segment's exported audio. Optional so
    /// interrupted sessions written by older builds remain readable.
    var timedUnits: [TranscriptionTimedUnit]? = nil
    var attemptCount: Int
    var lastAttemptAt: Date?
    var errorCategory: DictationErrorCategory?
    var errorMessage: String?

    var durationMilliseconds: Int64 { endMilliseconds - startMilliseconds }
}

nonisolated struct TranscriptionSessionManifest: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1
    static let currentMergeAlgorithmVersion = 1

    var schemaVersion: Int
    var id: UUID
    var recordID: UUID
    var source: TranscriptionSourceFingerprint
    var providerID: String
    var modelID: String
    var language: String?
    var status: LongFormSessionStatus
    var segments: [TranscriptionSegment]
    var mergedTranscript: String?
    var mergeAlgorithmVersion: Int
    var createdAt: Date
    var updatedAt: Date
    var lastErrorCategory: DictationErrorCategory?
    var lastErrorMessage: String?

    var completedSegmentCount: Int {
        segments.prefix(while: { [.succeeded, .silent].contains($0.status) }).count
    }

    var partialTranscript: String? {
        let values = segments
            .prefix(while: { [.succeeded, .silent].contains($0.status) })
            .compactMap(\.transcript)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: "\n")
    }

    mutating func normalizeInterruptedWork(now: Date = Date()) {
        for index in segments.indices {
            switch segments[index].status {
            case .preparing, .uploading:
                segments[index].status = .interrupted
                segments[index].errorCategory = .interrupted
                segments[index].errorMessage = "Segment processing was interrupted when NativeDictate stopped."
            default:
                break
            }
        }
        if [.planning, .transcribing, .merging].contains(status) {
            status = .paused
            lastErrorCategory = .interrupted
            lastErrorMessage = "Long-form transcription was interrupted when NativeDictate stopped."
        }
        updatedAt = now
    }

    func validated() throws -> Self {
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw LongFormTranscriptionError.unsupportedSessionSchema(schemaVersion)
        }
        guard !segments.isEmpty else { throw LongFormTranscriptionError.invalidSegmentPlan }
        let sorted = segments.sorted { $0.index < $1.index }
        guard sorted == segments else { throw LongFormTranscriptionError.invalidSegmentPlan }
        for (offset, segment) in segments.enumerated() {
            guard segment.index == offset,
                  segment.startMilliseconds >= 0,
                  segment.endMilliseconds > segment.startMilliseconds,
                  segment.overlapBeforeMilliseconds >= 0 else {
                throw LongFormTranscriptionError.invalidSegmentPlan
            }
            if offset > 0 {
                let previous = segments[offset - 1]
                guard segment.startMilliseconds <= previous.endMilliseconds,
                      previous.endMilliseconds - segment.startMilliseconds
                        == segment.overlapBeforeMilliseconds else {
                    throw LongFormTranscriptionError.invalidSegmentPlan
                }
            }
            if segment.status == .succeeded {
                guard segment.transcript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    throw LongFormTranscriptionError.invalidSessionState
                }
            } else if segment.status == .silent {
                guard segment.transcript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
                    throw LongFormTranscriptionError.invalidSessionState
                }
            }
        }
        guard segments[0].startMilliseconds == 0,
              segments.last?.endMilliseconds == source.durationMilliseconds else {
            throw LongFormTranscriptionError.invalidSegmentPlan
        }
        if status == .completed {
            guard segments.allSatisfy({ [.succeeded, .silent].contains($0.status) }),
                  let mergedTranscript,
                  !mergedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || segments.allSatisfy({ $0.status == .silent }) else {
                throw LongFormTranscriptionError.invalidSessionState
            }
        }
        return self
    }
}

nonisolated enum LongFormProgress: Sendable, Equatable {
    case inspecting
    case planning
    case preparing(segment: Int, total: Int)
    case transcribing(segment: Int, total: Int, attempt: Int)
    case merging(total: Int)
    case paused(completed: Int, total: Int)

    var statusText: String {
        switch self {
        case .inspecting:
            "Inspecting recording…"
        case .planning:
            "Preparing long recording…"
        case let .preparing(segment, total):
            "Preparing segment \(segment + 1) of \(total)…"
        case let .transcribing(segment, total, attempt):
            attempt > 1
                ? "Retrying segment \(segment + 1) of \(total)…"
                : "Transcribing segment \(segment + 1) of \(total)…"
        case let .merging(total):
            "Merging \(total) segments…"
        case let .paused(completed, total):
            "Paused after \(completed) of \(total) segments"
        }
    }
}

nonisolated enum LongFormTranscriptionError: LocalizedError, Equatable {
    case sourceUnavailable
    case sourceContainsNoSamples
    case insufficientWorkingStorage(requiredBytes: Int64, availableBytes: Int64)
    case invalidSegmentPlan
    case segmentExportFailed(Int)
    case segmentTooLarge(index: Int, actualBytes: Int64, maximumBytes: Int64)
    case invalidSessionState
    case unsupportedSessionSchema(Int)
    case sourceChanged
    case sessionNotFound
    case transcriptMergeFailed

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            "The saved recording could not be opened. The original file was not changed."
        case .sourceContainsNoSamples:
            "The saved recording contains no usable audio samples."
        case let .insufficientWorkingStorage(requiredBytes, availableBytes):
            "Long-form transcription needs approximately \(Self.mb(requiredBytes)) MB of free space, but only \(Self.mb(availableBytes)) MB is available."
        case .invalidSegmentPlan:
            "NativeDictate could not create a safe, complete audio segment plan."
        case let .segmentExportFailed(index):
            "Audio segment \(index + 1) could not be prepared. The original recording was kept."
        case let .segmentTooLarge(index, actualBytes, maximumBytes):
            "Audio segment \(index + 1) is too large (\(Self.mb(actualBytes)) MB; maximum \(Self.mb(maximumBytes)) MB)."
        case .invalidSessionState:
            "The saved long-form transcription state is inconsistent. The original recording and existing text were kept."
        case let .unsupportedSessionSchema(version):
            "This transcription session uses unsupported schema version \(version)."
        case .sourceChanged:
            "The original recording changed after segmentation. Start a new transcription session to continue safely."
        case .sessionNotFound:
            "The resumable transcription session could not be found."
        case .transcriptMergeFailed:
            "The segment transcripts could not be merged safely. All partial transcripts were kept."
        }
    }

    private static func mb(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1_000_000)
    }
}
