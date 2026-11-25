
import Foundation
import ZIPFoundation

enum ArchiveServiceError: LocalizedError {
    case onlyZIPSupported
    case archiveNotFound
    case unsafeArchivePath(String)
    case symbolicLinkNotAllowed
    case destinationFileExists(String)
    case symbolicLinkInDestination

    var errorDescription: String? {
        description(isEnglish: false)
    }

    func description(isEnglish: Bool) -> String {
        switch self {
        case .onlyZIPSupported:
            return isEnglish
                ? "Only ZIP archives are supported."
                : "На этом этапе поддерживаются только ZIP-архивы."

        case .archiveNotFound:
            return isEnglish
                ? "Archive not found."
                : "Архив не найден."

        case .unsafeArchivePath(let path):
            return isEnglish
                ? "Archive contains an unsafe path: \(path)"
                : "Архив содержит небезопасный путь: \(path)"

        case .symbolicLinkNotAllowed:
            return isEnglish
                ? "Archive contains a symbolic link. Extraction cancelled."
                : "Архив содержит символическую ссылку. Распаковка отменена."

        case .destinationFileExists(let path):
            return isEnglish
                ? "File already exists: \(path)"
                : "Файл уже существует: \(path)"

        case .symbolicLinkInDestination:
            return isEnglish
                ? "Destination folder contains a symbolic link. Extraction cancelled."
                : "Папка назначения содержит символическую ссылку. Распаковка отменена."
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
    
    // MARK: - Extract selected entries

    func extractSelected(
        archiveURL: URL,
        selectedPaths: Set<String>,
        to destinationURL: URL
    ) throws {

        guard archiveURL.pathExtension.lowercased() == "zip" else {
            throw ArchiveServiceError.onlyZIPSupported
        }

        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ArchiveServiceError.archiveNotFound
        }

        guard !selectedPaths.isEmpty else {
            return
        }

        let fileManager = FileManager.default
        let destination = destinationURL.standardizedFileURL

        func normalizePath(_ rawPath: String) throws -> String {
            guard !rawPath.isEmpty,
                  !rawPath.hasPrefix("/"),
                  !rawPath.contains("\\"),
                  !rawPath.contains("\0") else {
                throw ArchiveServiceError.unsafeArchivePath(rawPath)
            }

            var path = rawPath

            // Убираем завершающие слеши у папок
            while path.hasSuffix("/") {
                path.removeLast()
            }

            guard !path.isEmpty else {
                throw ArchiveServiceError.unsafeArchivePath(rawPath)
            }

            let components = path.split(
                separator: "/",
                omittingEmptySubsequences: false
            )

            guard components.allSatisfy({
                !$0.isEmpty &&
                $0 != "." &&
                $0 != ".."
            }) else {
                throw ArchiveServiceError.unsafeArchivePath(rawPath)
            }

            // Защита от Windows-путей вида C:/...
            guard let firstComponent = components.first,
                  !firstComponent.contains(":") else {
                throw ArchiveServiceError.unsafeArchivePath(rawPath)
            }

            return path
        }

        func rejectSymbolicLink(at url: URL) throws {
            guard let attributes = try? fileManager.attributesOfItem(
                atPath: url.path
            ),
            let type = attributes[.type] as? FileAttributeType,
            type == .typeSymbolicLink else {
                return
            }

            throw ArchiveServiceError.symbolicLinkInDestination
        }

        func destinationForEntry(_ path: String) throws -> URL {
            let target = destination
                .appendingPathComponent(path)
                .standardizedFileURL

            let rootPath = destination.path.hasSuffix("/")
                ? destination.path
                : destination.path + "/"

            guard target.path.hasPrefix(rootPath) else {
                throw ArchiveServiceError.unsafeArchivePath(path)
            }

            // Проверяем саму папку назначения
            try rejectSymbolicLink(at: destination)

            // Проверяем все компоненты пути
            var current = destination

            for component in path.split(separator: "/") {
                current.appendPathComponent(String(component))
                try rejectSymbolicLink(at: current)
            }

            return target
        }

        let normalizedSelections = Set(
            try selectedPaths.map { try normalizePath($0) }
        )

        let archive = try Archive(
            url: archiveURL,
            accessMode: .read
        )

        var selectedEntries: [(entry: Entry, path: String)] = []

        // Сначала проверяем все записи архива
        for entry in archive {
            let path = try normalizePath(entry.path)

            let shouldExtract = normalizedSelections.contains { selected in
                path == selected || path.hasPrefix(selected + "/")
            }

            guard shouldExtract else {
                continue
            }

            guard entry.type != .symlink else {
                throw ArchiveServiceError.symbolicLinkNotAllowed
            }

            selectedEntries.append((entry, path))
        }

        // Если ничего не найдено, ничего не распаковываем
        guard !selectedEntries.isEmpty else {
            return
        }

        // Проверяем конфликты до начала распаковки
        for item in selectedEntries {
            let targetURL = try destinationForEntry(item.path)

            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(
                atPath: targetURL.path,
                isDirectory: &isDirectory
            )

            if exists {
                if item.entry.type == .directory {
                    guard isDirectory.boolValue else {
                        throw ArchiveServiceError.destinationFileExists(
                            item.path
                        )
                    }
                } else {
                    throw ArchiveServiceError.destinationFileExists(
                        item.path
                    )
                }
            }
        }

        // Создаём папку назначения
        try fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        // Извлекаем только выбранные элементы
        for item in selectedEntries {
            let targetURL = try destinationForEntry(item.path)

            if item.entry.type == .directory {
                try fileManager.createDirectory(
                    at: targetURL,
                    withIntermediateDirectories: true
                )
            } else {
                try fileManager.createDirectory(
                    at: targetURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                try archive.extract(
                    item.entry,
                    to: targetURL
                )
            }
        }
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
