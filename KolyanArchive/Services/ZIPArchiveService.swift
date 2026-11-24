
import Foundation
import ZIPFoundation

enum ArchiveServiceError: LocalizedError {
    case onlyZIPSupported
    case archiveNotFound

    var errorDescription: String? {
        switch self {
        case .onlyZIPSupported:
            return "На этом этапе поддерживаются только ZIP-архивы."
        case .archiveNotFound:
            return "Архив не найден."
        }
    }
}

struct ZIPArchiveService {

    // MARK: - List archive contents

    func listContents(
        of archiveURL: URL,
        in directoryPath: String = ""
    ) throws -> [ArchiveEntry] {

        guard archiveURL.pathExtension.lowercased() == "zip" else {
            throw ArchiveServiceError.onlyZIPSupported
        }

        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ArchiveServiceError.archiveNotFound
        }

        let archive = try Archive(
            url: archiveURL,
            accessMode: .read
        )

        var items: [String: ArchiveEntry] = [:]

        let normalizedDirectory = directoryPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let prefix = normalizedDirectory.isEmpty
            ? ""
            : normalizedDirectory + "/"

        for entry in archive {
            let normalizedPath = entry.path.trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )

            guard normalizedPath.hasPrefix(prefix) else {
                continue
            }

            let remainder = String(
                normalizedPath.dropFirst(prefix.count)
            )

            guard !remainder.isEmpty else {
                continue
            }

            let components = remainder.split(
                separator: "/",
                omittingEmptySubsequences: true
            )

            guard let firstComponent = components.first else {
                continue
            }

            let childPath = prefix + String(firstComponent)

            // Nested directory
            if components.count > 1 {
                if items[childPath] == nil {
                    items[childPath] = ArchiveEntry(
                        id: childPath,
                        path: childPath,
                        sizeDescription: "Папка",
                        isDirectory: true
                    )
                }

                continue
            }

            // Direct child
            if entry.type == .directory {
                items[childPath] = ArchiveEntry(
                    id: childPath,
                    path: childPath,
                    sizeDescription: "Папка",
                    isDirectory: true
                )
            } else {
                items[childPath] = ArchiveEntry(
                    id: childPath,
                    path: childPath,
                    sizeDescription: ByteCountFormatter.string(
                        fromByteCount: Int64(entry.uncompressedSize),
                        countStyle: .file
                    ),
                    isDirectory: false
                )
            }
        }

        return items.values.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory
            }

            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Extract archive

    func extract(
        archiveURL: URL,
        to destinationURL: URL
    ) throws {

        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )

        try FileManager.default.unzipItem(
            at: archiveURL,
            to: destinationURL
        )
    }

    // MARK: - Create ZIP

    func createZIP(
        from sourceURL: URL,
        at destinationURL: URL
    ) throws {

        try FileManager.default.zipItem(
            at: sourceURL,
            to: destinationURL,
            shouldKeepParent: true,
            compressionMethod: .deflate
        )
    }
}
