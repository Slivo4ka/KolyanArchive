
import Foundation
import ZIPFoundation

enum ArchiveServiceError: LocalizedError {
    case onlyZIPSupported
    case archiveNotFound
    case unsafeArchivePath(String)
    case symbolicLinkNotAllowed
    case destinationFileExists(String)

    var errorDescription: String? {
        switch self {
        case .onlyZIPSupported:
            return "На этом этапе поддерживаются только ZIP-архивы."
        case .archiveNotFound:
            return "Архив не найден."
        case .unsafeArchivePath(let path):
            return "Архив содержит небезопасный путь: \(path)"
        case .symbolicLinkNotAllowed:
            return "Архив содержит символическую ссылку. Распаковка отменена."
        case .destinationFileExists(let path):
            return "Файл уже существует: \(path)"
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

    // MARK: - Search archive contents

    func searchContents(
        of archiveURL: URL,
        matching query: String
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

        for entry in archive {
            let path = entry.path.trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )

            guard !path.isEmpty else { continue }

            let components = path.split(
                separator: "/",
                omittingEmptySubsequences: true
            )

            // Добавляем все вложенные папки
            if components.count > 1 {
                for index in 1..<components.count {
                    let directoryPath = components
                        .prefix(index)
                        .joined(separator: "/")

                    if items[directoryPath] == nil {
                        items[directoryPath] = ArchiveEntry(
                            id: directoryPath,
                            path: directoryPath,
                            sizeDescription: "Папка",
                            isDirectory: true
                        )
                    }
                }
            }

            // Добавляем сам файл или папку
            if entry.type == .directory {
                items[path] = ArchiveEntry(
                    id: path,
                    path: path,
                    sizeDescription: "Папка",
                    isDirectory: true
                )
            } else {
                items[path] = ArchiveEntry(
                    id: path,
                    path: path,
                    sizeDescription: ByteCountFormatter.string(
                        fromByteCount: Int64(entry.uncompressedSize),
                        countStyle: .file
                    ),
                    isDirectory: false
                )
            }
        }

        let searchQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !searchQuery.isEmpty else { return [] }

        return items.values
            .filter {
                $0.name.localizedCaseInsensitiveContains(searchQuery) ||
                $0.path.localizedCaseInsensitiveContains(searchQuery)
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory
                }

                return $0.path.localizedStandardCompare($1.path)
                    == .orderedAscending
            }
    }

    // MARK: - Extract archive

    func extract(
    archiveURL: URL,
    to destinationURL: URL
) throws {

    guard archiveURL.pathExtension.lowercased() == "zip" else {
        throw ArchiveServiceError.onlyZIPSupported
    }

    guard FileManager.default.fileExists(atPath: archiveURL.path) else {
        throw ArchiveServiceError.archiveNotFound
    }

    try FileManager.default.createDirectory(
        at: destinationURL,
        withIntermediateDirectories: true
    )

    try FileManager.default.unzipItem(
        at: archiveURL,
        to: destinationURL,
        symlinksValidWithin: destinationURL
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
