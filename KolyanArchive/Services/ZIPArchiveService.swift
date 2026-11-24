import Foundation
import ZIPFoundation

enum ArchiveServiceError: LocalizedError {
    case onlyZIPSupported

    var errorDescription: String? {
        switch self {
        case .onlyZIPSupported:
            return "На этом этапе поддерживаются ZIP-архивы. Поддержку RAR подключим отдельным этапом."
        }
    }
}

struct ZIPArchiveService {
    func listContents(of archiveURL: URL) throws -> [ArchiveEntry] {
        guard archiveURL.pathExtension.lowercased() == "zip" else {
            throw ArchiveServiceError.onlyZIPSupported
        }

        let archive = try Archive(url: archiveURL, accessMode: .read)
        return archive.map { entry in
            ArchiveEntry(
                path: entry.path,
                sizeDescription: ByteCountFormatter.string(
                    fromByteCount: Int64(entry.uncompressedSize),
                    countStyle: .file
                ),
                isDirectory: entry.type == .directory
            )
        }
    }

    func extract(archiveURL: URL, to destinationURL: URL) throws {
        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.unzipItem(at: archiveURL, to: destinationURL)
    }

    func createZIP(from sourceURL: URL, at destinationURL: URL) throws {
        try FileManager.default.zipItem(
            at: sourceURL,
            to: destinationURL,
            shouldKeepParent: true,
            compressionMethod: .deflate
        )
    }
}
