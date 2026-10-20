import CryptoKit
import Foundation

/// Only public model artifacts are requested here. Project text and audio never enter this service.
struct ModelDownloader: Sendable {
    static let manifestName = "workspace-model.json"

    static func directory(for modelID: String, root: URL) -> URL {
        root.appending(path: modelID.replacingOccurrences(of: "/", with: "--"), directoryHint: .isDirectory)
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") &&
            !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty })
    }

    static func installation(at directory: URL) -> InstalledModel? {
        guard let data = try? Data(contentsOf: directory.appending(path: manifestName)),
              let installation = try? JSONDecoder().decode(InstalledModel.self, from: data),
              !installation.files.isEmpty,
              installation.files.contains(where: { $0.path.hasSuffix(".safetensors") }),
              installation.files.contains(where: { $0.path == "config.json" }),
              installation.files.contains(where: { $0.path == "tokenizer.json" }),
              installation.files.contains(where: { $0.path == "tokenizer_config.json" }),
              installation.files.allSatisfy({ file in
                  guard isSafeRelativePath(file.path),
                        let size = try? directory.appending(path: file.path).resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
                  return Int64(size) == file.size
              }) else { return nil }
        return installation
    }

    func download(_ model: CatalogModel, root: URL, progress: @escaping @Sendable (Double, String) -> Void) async throws -> InstalledModel {
        guard model.nativeMLX, let revision = model.revision else {
            throw ModelLibraryError.message("Für dieses Modell ist kein integrierter MLX-Download verfügbar.")
        }
        // A snapshot revision is fixed in the catalog, preventing a branch change during a download.
        let metadataURL = URL(string: "https://huggingface.co/api/models/\(model.id)/revision/\(revision)?blobs=true")!
        let (data, response) = try await URLSession.shared.data(from: metadataURL)
        try validate(response)
        let metadata = try JSONDecoder().decode(HubMetadata.self, from: data)
        guard metadata.sha == revision else { throw ModelLibraryError.message("Die Modellversion stimmt nicht mit dem Katalog überein.") }
        let files = metadata.siblings.filter { item in
            Self.isSafeRelativePath(item.rfilename) &&
            (["json", "safetensors", "model", "tiktoken", "jinja"].contains(URL(fileURLWithPath: item.rfilename).pathExtension) ||
             ["merges.txt", "README.md", "LICENSE", "LICENSE.txt"].contains(item.rfilename))
        }.map { ModelFile(path: $0.rfilename, size: $0.size, sha256: $0.lfs?.sha256, gitBlobID: $0.blobId) }
        guard files.contains(where: { $0.path == "config.json" }),
              files.contains(where: { $0.path == "tokenizer.json" }),
              files.contains(where: { $0.path == "tokenizer_config.json" }),
              files.contains(where: { $0.path.hasSuffix(".safetensors") }) else {
            throw ModelLibraryError.message("Der Modell-Snapshot enthält nicht alle benötigten Dateien.")
        }
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        let available = (try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? Int64.max
        guard total > 0, available > total + 500_000_000 else {
            throw ModelLibraryError.message("Es ist nicht genug freier Speicher für diesen Download vorhanden.")
        }
        let staging = root.appending(path: ".download-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: staging) } }
        var downloaded: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            progress(Double(downloaded) / Double(total), file.path)
            let url = URL(string: "https://huggingface.co/\(model.id)/resolve/\(revision)/\(file.path)")!
            let offset = downloaded
            let observer = DownloadProgressObserver { received in
                progress(min(0.99, Double(offset + received) / Double(total)), file.path)
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 180
            let (temporary, response) = try await URLSession.shared.download(for: request, delegate: observer)
            try validate(response)
            let destination = staging.appending(path: file.path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: temporary, to: destination)
            try verify(file: file, at: destination)
            downloaded += file.size
        }
        try Task.checkCancellation()
        let installation = InstalledModel(id: model.id, revision: revision, downloadedAt: Date(), files: files)
        try JSONEncoder().encode(installation).write(to: staging.appending(path: Self.manifestName), options: .atomic)
        let destination = Self.directory(for: model.id, root: root)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ModelLibraryError.message("Das Modell ist bereits vorhanden. Entferne es vor einem erneuten Download.")
        }
        try FileManager.default.moveItem(at: staging, to: destination)
        committed = true
        progress(1, "Vollständig geprüft und gespeichert")
        return installation
    }

    func verify(file: ModelFile, at url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard Int64(size ?? -1) == file.size else { throw ModelLibraryError.message("Unvollständiger Download: \(file.path)") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var sha256 = SHA256()
        var gitHash = Insecure.SHA1()
        gitHash.update(data: Data("blob \(file.size)\0".utf8))
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            if file.sha256 != nil { sha256.update(data: chunk) }
            else { gitHash.update(data: chunk) }
        }
        let actual: String
        let expected: String
        if let value = file.sha256 {
            actual = sha256.finalize().map { String(format: "%02x", $0) }.joined()
            expected = value
        } else if let value = file.gitBlobID {
            actual = gitHash.finalize().map { String(format: "%02x", $0) }.joined()
            expected = value
        } else { throw ModelLibraryError.message("Prüfsumme fehlt für \(file.path).") }
        guard actual == expected else { throw ModelLibraryError.message("Die Prüfsumme von \(file.path) stimmt nicht. Der Download wurde verworfen.") }
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ModelLibraryError.message("Modelldownload fehlgeschlagen (HTTP \(code)).")
        }
    }
}

private struct HubMetadata: Decodable {
    struct Sibling: Decodable {
        struct LFS: Decodable { var sha256: String }
        var rfilename: String
        var size: Int64
        var blobId: String?
        var lfs: LFS?
    }
    var sha: String
    var siblings: [Sibling]
}

private final class DownloadProgressObserver: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let report: @Sendable (Int64) -> Void
    init(report: @escaping @Sendable (Int64) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) { }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        report(totalBytesWritten)
    }
}
