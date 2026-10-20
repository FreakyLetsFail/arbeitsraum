import Darwin
import Foundation

enum InferenceRuntime: String, Codable, CaseIterable, Identifiable {
    case mlx, localServer
    var id: String { rawValue }
    var title: String { self == .mlx ? "MLX · in der App" : "Lokaler Server" }
}

struct CatalogModel: Decodable, Identifiable, Sendable {
    enum Support: String, Decodable { case mlx, server, unavailable }
    let id: String
    let title: String
    let family: String
    let summary: String
    let revision: String?
    let downloadBytes: Int64
    let recommendedRAMGB: Int
    let support: Support
    let license: String
    let source: String
    let architecture: String
    let quantization: String
    let totalParameters: String
    let activeParameters: String?
    let tested: Bool
    let rank: Int
    let contextWindow: Int?
    var nativeMLX: Bool { support == .mlx }
    var fitsThisMac: Bool { ProcessInfo.processInfo.physicalMemory >= UInt64(recommendedRAMGB) * 1_073_741_824 }
    var diskSize: String { ByteCountFormatter.string(fromByteCount: downloadBytes, countStyle: .file) }
    var sourceURL: URL { URL(string: source)! }

    static let all: [CatalogModel] = {
        guard let url = Bundle.main.url(forResource: "ModelCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let models = try? JSONDecoder().decode([CatalogModel].self, from: data) else { return [] }
        return models
    }()
    static func model(id: String) -> CatalogModel? { all.first { $0.id == id } }
}

struct MacSpecifications {
    let chip: String
    let memoryGB: Double
    let cores: Int
    let appleSilicon: Bool
    var freeDiskBytes: Int64?
    static func current(storage: URL) -> MacSpecifications {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0)
        #if arch(arm64)
        let silicon = true
        #else
        let silicon = false
        #endif
        return .init(chip: String(cString: bytes), memoryGB: Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
                     cores: ProcessInfo.processInfo.processorCount, appleSilicon: silicon,
                     freeDiskBytes: try? storage.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage)
    }
}

struct ModelAssessment {
    enum Fit { case good, limited, tooLarge, unsupported }
    let fit: Fit
    let title: String
    let reason: String
    let score: Int
    let estimatedTotalGB: Double
    static func assess(_ model: CatalogModel, on mac: MacSpecifications) -> ModelAssessment {
        let weights = Double(model.downloadBytes) / 1_073_741_824
        // A conservative planning estimate for this app's bounded 8K cache, plus the OS.
        // This is not measured peak memory and does not predict generation speed.
        let estimate = weights + max(2.5, weights * 0.3) + 4
        if model.support == .unavailable || (model.nativeMLX && !mac.appleSilicon) {
            return .init(fit: .unsupported, title: "Nicht unterstützt", reason: "Konfiguration passt nicht zur eingebauten MLX-Swift-Laufzeit.", score: -200, estimatedTotalGB: estimate)
        }
        if mac.memoryGB < Double(model.recommendedRAMGB) || estimate > mac.memoryGB {
            return .init(fit: .tooLarge, title: "Mehr Speicher nötig", reason: "Mindestens \(model.recommendedRAMGB) GB empfohlen; Gewichte, Kontext und macOS benötigen zusammen mehr Reserve.", score: -100, estimatedTotalGB: estimate)
        }
        let target = max(0.5, mac.memoryGB * 0.2)
        let sizeBalance = min(weights / target, target / max(0.1, weights))
        let priority = model.rank + Int(sizeBalance * 40) + (model.tested ? 10 : 0)
        if mac.memoryGB - estimate < 3 || Double(model.recommendedRAMGB) >= mac.memoryGB {
            return .init(fit: .limited, title: "Wenig Reserve", reason: "Könnte passen. Andere Apps, größere Texte und Denkmodus können zusätzlichen Speicher belegen.", score: priority - 30, estimatedTotalGB: estimate)
        }
        return .init(fit: .good, title: "Passende Größe", reason: "Für den begrenzten Kontext dieser App ist voraussichtlich genügend Speicher vorhanden.", score: priority, estimatedTotalGB: estimate)
    }
}

struct InstalledModel: Codable, Identifiable, Sendable {
    var id: String
    var revision: String
    var downloadedAt: Date
    var files: [ModelFile]
    var byteCount: Int64 { files.reduce(0) { $0 + $1.size } }
}
struct ModelFile: Codable, Sendable {
    var path: String
    var size: Int64
    var sha256: String?
    var gitBlobID: String?
}
enum ModelLibraryError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
