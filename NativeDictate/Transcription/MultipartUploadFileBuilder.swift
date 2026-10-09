import Foundation

nonisolated struct MultipartUploadFile: Sendable {
    let url: URL
    let byteCount: Int64

    func cleanup(fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: url)
    }
}

nonisolated struct MultipartUploadFileBuilder {
    let boundary: String
    let fileManager: FileManager
    let chunkSize: Int

    init(
        boundary: String,
        fileManager: FileManager = .default,
        chunkSize: Int = 64 * 1_024
    ) {
        self.boundary = boundary
        self.fileManager = fileManager
        self.chunkSize = chunkSize
    }

    func build(
        fields: [(name: String, value: String?)],
        fileFieldName: String,
        filename: String,
        mimeType: String,
        sourceURL: URL
    ) throws -> MultipartUploadFile {
        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent("FlowDictate-Multipart-\(UUID().uuidString).body")
        guard fileManager.createFile(atPath: outputURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }

            for field in fields {
                guard let value = field.value, !value.isEmpty else { continue }
                try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
                try output.write(contentsOf: Data(
                    "Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n".utf8
                ))
                try output.write(contentsOf: Data("\(value)\r\n".utf8))
            }

            try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
            try output.write(contentsOf: Data(
                "Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(filename)\"\r\n".utf8
            ))
            try output.write(contentsOf: Data("Content-Type: \(mimeType)\r\n\r\n".utf8))

            let input = try FileHandle(forReadingFrom: sourceURL)
            defer { try? input.close() }
            while true {
                try Task.checkCancellation()
                guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else { break }
                try output.write(contentsOf: chunk)
            }

            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            try output.synchronize()
            let values = try outputURL.resourceValues(forKeys: [.fileSizeKey])
            return MultipartUploadFile(url: outputURL, byteCount: Int64(values.fileSize ?? 0))
        } catch {
            try? fileManager.removeItem(at: outputURL)
            throw error
        }
    }
}
