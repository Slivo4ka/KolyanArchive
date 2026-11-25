
import Foundation
import ZIPFoundation

enum ZIPConflictResolution: Equatable {
    case replace
    case rename
}

struct ZIPExtractionPlan {
    fileprivate let archive: Archive
    fileprivate let items: [ZIPPlannedItem]
    let conflicts: [String]
}

fileprivate struct ZIPPlannedItem {
    let entry: Entry
    let path: String
    let isDirectory: Bool
}
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
// MARK: - Safe extraction with conflict handling

extension ZIPArchiveService {

    func prepareFullExtraction(
        archiveURL: URL,
        to destinationURL: URL
    ) throws -> ZIPExtractionPlan {

        return try makeExtractionPlan(
            archiveURL: archiveURL,
            destinationURL: destinationURL,
            selectedPaths: nil
        )
    }

    func prepareSelectedExtraction(
        archiveURL: URL,
        selectedPaths: Set<String>,
        to destinationURL: URL
    ) throws -> ZIPExtractionPlan {

        guard !selectedPaths.isEmpty else {
            return ZIPExtractionPlan(
                archive: try Archive(url: archiveURL, accessMode: .read),
                items: [],
                conflicts: []
            )
        }

        return try makeExtractionPlan(
            archiveURL: archiveURL,
            destinationURL: destinationURL,
            selectedPaths: selectedPaths
        )
    }

    func performExtraction(
        plan: ZIPExtractionPlan,
        to destinationURL: URL,
        resolution: ZIPConflictResolution
    ) throws {

        let fileManager = FileManager.default
        let destination = destinationURL.standardizedFileURL

        try fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        var reservedPaths = Set<String>()

        for item in plan.items {

            var relativePath = item.path
            var targetURL = try safeTargetURL(
                relativePath,
                in: destination
            )

            if item.isDirectory {

                var isDirectory: ObjCBool = false

                if fileManager.fileExists(
                    atPath: targetURL.path,
                    isDirectory: &isDirectory
                ) {
                    guard isDirectory.boolValue else {
                        throw ArchiveServiceError.destinationFileExists(
                            relativePath
                        )
                    }
                } else {
                    try fileManager.createDirectory(
                        at: targetURL,
                        withIntermediateDirectories: true
                    )
                }

                continue
            }

            // Проверяем, не занято ли имя уже существующим
            // файлом или ранее обработанной записью архива.
            let pathIsReserved = reservedPaths.contains(
                relativePath.lowercased()
            )

            var isDirectory: ObjCBool = false
            var exists = fileManager.fileExists(
                atPath: targetURL.path,
                isDirectory: &isDirectory
            )

            if exists && isDirectory.boolValue {
                throw ArchiveServiceError.destinationFileExists(
                    relativePath
                )
            }

            if (exists || pathIsReserved) && resolution == .rename {

                relativePath = try uniqueFileName(
                    for: relativePath,
                    in: destination,
                    reservedPaths: reservedPaths
                )

                targetURL = try safeTargetURL(
                    relativePath,
                    in: destination
                )

                exists = fileManager.fileExists(
                    atPath: targetURL.path,
                    isDirectory: &isDirectory
                )
            }

            if exists {

                guard !isDirectory.boolValue else {
                    throw ArchiveServiceError.destinationFileExists(
                        relativePath
                    )
                }

                guard resolution == .replace else {
                    throw ArchiveServiceError.destinationFileExists(
                        relativePath
                    )
                }

                try fileManager.removeItem(at: targetURL)
            }

            try fileManager.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            try plan.archive.extract(
                item.entry,
                to: targetURL
            )

            reservedPaths.insert(relativePath.lowercased())
        }
    }

    private func makeExtractionPlan(
        archiveURL: URL,
        destinationURL: URL,
        selectedPaths: Set<String>?
    ) throws -> ZIPExtractionPlan {

        guard archiveURL.pathExtension.lowercased() == "zip" else {
            throw ArchiveServiceError.onlyZIPSupported
        }

        guard FileManager.default.fileExists(
            atPath: archiveURL.path
        ) else {
            throw ArchiveServiceError.archiveNotFound
        }

        let fileManager = FileManager.default
        let destination = destinationURL.standardizedFileURL

        let archive = try Archive(
            url: archiveURL,
            accessMode: .read
        )

        func normalize(_ rawPath: String) throws -> String {

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
                      !$0.isEmpty &&
                      $0 != "." &&
                      $0 != ".."
                  }),
                  let first = components.first,
                  !first.contains(":") else {
                throw ArchiveServiceError.unsafeArchivePath(rawPath)
            }

            return path
        }

        let normalizedSelections = try Set(
            (selectedPaths ?? []).map { try normalize($0) }
        )

        var archiveEntries: [(entry: Entry, path: String)] = []

        for entry in archive {

            let path = try normalize(entry.path)

            guard entry.type != .symlink else {
                throw ArchiveServiceError.symbolicLinkNotAllowed
            }

            archiveEntries.append((entry, path))
        }

        // Определяем, какие выбранные элементы являются папками.
        var selectedFolders = Set<String>()

        for selected in normalizedSelections {

            let isFolder = archiveEntries.contains {
                $0.path == selected &&
                $0.entry.type == .directory
            } || archiveEntries.contains {
                $0.path.hasPrefix(selected + "/")
            }

            if isFolder {
                selectedFolders.insert(selected)
            }
        }

        var plannedItems: [ZIPPlannedItem] = []

        for item in archiveEntries {

            var targetPath = item.path

            if let _ = selectedPaths {

                // Ищем выбранную папку, которой принадлежит запись.
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

                    targetPath = suffix.isEmpty
                        ? folderName
                        : folderName + "/" + suffix

                } else if normalizedSelections.contains(item.path) {

                    // Отдельно выбранный файл извлекается в корень.
                    guard item.entry.type != .directory else {
                        continue
                    }

                    targetPath = URL(
                        fileURLWithPath: item.path
                    ).lastPathComponent

                } else {
                    continue
                }
            }

            plannedItems.append(
                ZIPPlannedItem(
                    entry: item.entry,
                    path: targetPath,
                    isDirectory: item.entry.type == .directory
                )
            )
        }

        // Проверяем безопасность назначения и существующие конфликты.
        var conflicts = Set<String>()

        var plannedFilePaths = Set<String>()

        for item in plannedItems {

            let targetURL = try safeTargetURL(
                item.path,
                in: destination
            )

            var isDirectory: ObjCBool = false

            let exists = fileManager.fileExists(
                atPath: targetURL.path,
                isDirectory: &isDirectory
            )

            if exists {

                if item.isDirectory {

                    guard isDirectory.boolValue else {
                        throw ArchiveServiceError.destinationFileExists(
                            item.path
                        )
                    }

                } else {

                    guard !isDirectory.boolValue else {
                        throw ArchiveServiceError.destinationFileExists(
                            item.path
                        )
                    }

                    conflicts.insert(item.path)
                }
            }

            if !item.isDirectory {

                let key = item.path.lowercased()

                if plannedFilePaths.contains(key) {
                    conflicts.insert(item.path)
                }

                plannedFilePaths.insert(key)
            }
        }

        return ZIPExtractionPlan(
            archive: archive,
            items: plannedItems,
            conflicts: conflicts.sorted()
        )
    }

    private func safeTargetURL(
        _ path: String,
        in destination: URL
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

    private func uniqueFileName(
        for path: String,
        in destination: URL,
        reservedPaths: Set<String>
    ) throws -> String {

        let fileURL = URL(fileURLWithPath: path)

        let directory = fileURL.deletingLastPathComponent().path
        let fileName = fileURL.lastPathComponent

        let fileExtension = fileURL.pathExtension
        let name = fileExtension.isEmpty
            ? fileName
            : fileURL.deletingPathExtension().lastPathComponent

        var index = 1

        while true {

            let newName = fileExtension.isEmpty
                ? "\(name) (\(index))"
                : "\(name) (\(index)).\(fileExtension)"

            let newPath = directory == "."
                ? newName
                : directory + "/" + newName

            let targetURL = try safeTargetURL(
                newPath,
                in: destination
            )

            let exists = FileManager.default.fileExists(
                atPath: targetURL.path
            )

            if !exists &&
                !reservedPaths.contains(newPath.lowercased()) {
                return newPath
            }

            index += 1
        }
    }
}
