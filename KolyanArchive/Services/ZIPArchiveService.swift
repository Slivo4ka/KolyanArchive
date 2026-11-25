
import Foundation
import ZIPFoundation

enum ArchiveServiceError: LocalizedError {
    case onlyZIPSupported
    case archiveNotFound
    case unsafeArchivePath(String)
    case symbolicLinkNotAllowed
    case destinationFileExists(String)
    case symbolicLinkInDestination
    case noSelectedEntries

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
                ? "Destination contains a symbolic link."
                : "Папка назначения содержит символическую ссылку."
        case .noSelectedEntries:
            return isEnglish
                ? "No selected files were found."
                : "Выбранные файлы не найдены."
        }
    }
}

struct ZIPArchiveService {

    // MARK: - List archive contents

    func listContents(
        of archiveURL: URL,
        in directoryPath: String = ""
    ) throws -> [ArchiveEntry] {

        try validateArchive(archiveURL)

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
            let path = entry.path.trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )

            guard path.hasPrefix(prefix) else { continue }

            let remainder = String(path.dropFirst(prefix.count))
            guard !remainder.isEmpty else { continue }

            let components = remainder.split(separator: "/")
            guard let first = components.first else { continue }

            let childPath = prefix + String(first)

            if components.count > 1 || entry.type == .directory {
                if items[childPath] == nil {
                    items[childPath] = ArchiveEntry(
                        id: childPath,
                        path: childPath,
                        sizeDescription: "Папка",
                        isDirectory: true
                    )
                }
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
            return $0.name.localizedStandardCompare($1.name)
                == .orderedAscending
        }
    }

    // MARK: - Search archive contents

    func searchContents(
        of archiveURL: URL,
        matching query: String
    ) throws -> [ArchiveEntry] {

        try validateArchive(archiveURL)

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

            let components = path.split(separator: "/")

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

    // MARK: - Full extraction

    func extract(
        archiveURL: URL,
        to destinationURL: URL,
        folderName: String
    ) throws -> URL {

        try validateArchive(archiveURL)

        let archive = try Archive(
            url: archiveURL,
            accessMode: .read
        )

        let outputFolder = try createUniqueArchiveFolder(
            folderName: folderName,
            inside: destinationURL
        )

        do {
            for entry in archive {
                let path = try normalizedPath(entry.path)

                guard entry.type != .symlink else {
                    throw ArchiveServiceError.symbolicLinkNotAllowed
                }

                let target = try safeTargetURL(
                    path,
                    inside: outputFolder
                )

                if entry.type == .directory {
                    try FileManager.default.createDirectory(
                        at: target,
                        withIntermediateDirectories: true
                    )
                } else {
                    try FileManager.default.createDirectory(
                        at: target.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )

                    guard !FileManager.default.fileExists(
                        atPath: target.path
                    ) else {
                        throw ArchiveServiceError.destinationFileExists(path)
                    }

                    try archive.extract(entry, to: target)
                }
            }

            return outputFolder

        } catch {
            try? FileManager.default.removeItem(at: outputFolder)
            throw error
        }
    }

    // MARK: - Selected extraction

    func extractSelected(
        archiveURL: URL,
        selectedPaths: Set<String>,
        to destinationURL: URL,
        folderName: String
    ) throws -> URL {

        try validateArchive(archiveURL)

        guard !selectedPaths.isEmpty else {
            throw ArchiveServiceError.noSelectedEntries
        }

        let archive = try Archive(
            url: archiveURL,
            accessMode: .read
        )

        let selections = try Set(
            selectedPaths.map { try normalizedPath($0) }
        )

        var archiveEntries: [(entry: Entry, path: String)] = []

        for entry in archive {
            let path = try normalizedPath(entry.path)

            guard entry.type != .symlink else {
                throw ArchiveServiceError.symbolicLinkNotAllowed
            }

            archiveEntries.append((entry, path))
        }

        var selectedFolders = Set<String>()

        for selected in selections {
            let isFolder = archiveEntries.contains {
                $0.path == selected && $0.entry.type == .directory
            } || archiveEntries.contains {
                $0.path.hasPrefix(selected + "/")
            }

            if isFolder {
                selectedFolders.insert(selected)
            }
        }

        // Убираем вложенные выборы, если их родительская папка
        // уже выбрана целиком.
        let effectiveSelections = selections.filter { selected in
            !selectedFolders.contains { folder in
                folder != selected &&
                selected.hasPrefix(folder + "/")
            }
        }

        selectedFolders = selectedFolders.intersection(effectiveSelections)

        var plannedEntries: [(entry: Entry, path: String)] = []

        for item in archiveEntries {
            let matchingFolder = selectedFolders
                .filter {
                    item.path == $0 ||
                    item.path.hasPrefix($0 + "/")
                }
                .max {
                    $0.count < $1.count
                }

            if let folder = matchingFolder {
                let folderName = URL(
                    fileURLWithPath: folder
                ).lastPathComponent

                let suffix = item.path == folder
                    ? ""
                    : String(item.path.dropFirst(folder.count + 1))

                let targetPath = suffix.isEmpty
                    ? folderName
                    : folderName + "/" + suffix

                plannedEntries.append((item.entry, targetPath))

            } else if effectiveSelections.contains(item.path),
                      item.entry.type != .directory {

                plannedEntries.append((
                    item.entry,
                    URL(fileURLWithPath: item.path).lastPathComponent
                ))
            }
        }

        guard !plannedEntries.isEmpty else {
            throw ArchiveServiceError.noSelectedEntries
        }

        let outputFolder = try createUniqueArchiveFolder(
            folderName: folderName,
            inside: destinationURL
        )

        do {
            var extractedPaths = Set<String>()

            for item in plannedEntries {
                let path = try normalizedPath(item.path)

                guard extractedPaths.insert(path.lowercased()).inserted else {
                    throw ArchiveServiceError.destinationFileExists(path)
                }

                let target = try safeTargetURL(
                    path,
                    inside: outputFolder
                )

                if item.entry.type == .directory {
                    try FileManager.default.createDirectory(
                        at: target,
                        withIntermediateDirectories: true
                    )
                } else {
                    try FileManager.default.createDirectory(
                        at: target.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )

                    guard !FileManager.default.fileExists(
                        atPath: target.path
                    ) else {
                        throw ArchiveServiceError.destinationFileExists(path)
                    }

                    try archive.extract(item.entry, to: target)
                }
            }

            return outputFolder

        } catch {
            try? FileManager.default.removeItem(at: outputFolder)
            throw error
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

    // MARK: - Validation

    private func validateArchive(_ url: URL) throws {
        guard url.pathExtension.lowercased() == "zip" else {
            throw ArchiveServiceError.onlyZIPSupported
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ArchiveServiceError.archiveNotFound
        }
    }

    private func normalizedPath(_ rawPath: String) throws -> String {
        guard !rawPath.isEmpty,
              !rawPath.hasPrefix("/"),
              !rawPath.contains("\\"),
              !rawPath.contains("\0") else {
            throw ArchiveServiceError.unsafeArchivePath(rawPath)
        }

        var path = rawPath

        while path.hasSuffix("/") {
            path.removeLast()
        }

        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )

        guard !path.isEmpty,
              components.allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              }),
              let first = components.first,
              !first.contains(":") else {
            throw ArchiveServiceError.unsafeArchivePath(rawPath)
        }

        return path
    }

    // MARK: - Create unique output folder

    private func createUniqueArchiveFolder(
        folderName: String,
        inside destinationURL: URL
    ) throws -> URL {

        let fileManager = FileManager.default

        let cleanName = folderName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanName.isEmpty,
            cleanName != ".",
            cleanName != "..",
            !cleanName.contains("/"),
            !cleanName.contains("\\"),
            !cleanName.contains(":"),
            !cleanName.contains("\0") else {
            throw ArchiveServiceError.unsafeArchivePath(folderName)
        }

        let destination = destinationURL.standardizedFileURL

        try fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        var index = 0

        while true {
            let name = index == 0
                ? cleanName
                : "\(cleanName) (\(index))"

            let candidate = destination.appendingPathComponent(
                name,
                isDirectory: true
            )

            if !fileManager.fileExists(atPath: candidate.path) {
                try fileManager.createDirectory(
                    at: candidate,
                    withIntermediateDirectories: false
                )
                return candidate
            }

            index += 1
        }
    }

    // MARK: - Safe destination path

    private func safeTargetURL(
        _ path: String,
        inside destination: URL
    ) throws -> URL {

        let fileManager = FileManager.default

        let target = destination
            .appendingPathComponent(path)
            .standardizedFileURL

        let rootPath = destination.path.hasSuffix("/")
            ? destination.path
            : destination.path + "/"

        guard target.path.hasPrefix(rootPath) else {
            throw ArchiveServiceError.unsafeArchivePath(path)
        }

        func rejectSymlink(_ url: URL) throws {
            guard let attributes = try? fileManager.attributesOfItem(
                atPath: url.path
            ),
            let type = attributes[.type] as? FileAttributeType,
            type == .typeSymbolicLink else {
                return
            }

            throw ArchiveServiceError.symbolicLinkInDestination
        }

        try rejectSymlink(destination)

        var current = destination

        for component in path.split(separator: "/") {
            current.appendPathComponent(String(component))
            try rejectSymlink(current)
        }

        return target
    }
}
