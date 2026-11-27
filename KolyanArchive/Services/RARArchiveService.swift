
import Foundation
import LibArchive

struct RARArchiveService {

    private let reader = ArchiveReader()

    // MARK: - List archive contents

    func listContents(
        of archiveURL: URL,
        in directoryPath: String = ""
    ) throws -> [ArchiveEntry] {

        let archiveEntries = try reader.entries(at: archiveURL)

        let normalizedDirectory = directoryPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let prefix = normalizedDirectory.isEmpty
            ? ""
            : normalizedDirectory + "/"

        var items: [String: ArchiveEntry] = [:]

        for item in archiveEntries {
            let path = item.path.trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )

            guard !path.isEmpty,
                  path.hasPrefix(prefix) else {
                continue
            }

            let remainder = String(path.dropFirst(prefix.count))
            guard !remainder.isEmpty else { continue }

            let components = remainder.split(separator: "/")
            guard let first = components.first else { continue }

            let childPath = prefix + String(first)

            let isDirectory =
                components.count > 1 ||
                String(describing: item.fileType).lowercased()
                    .contains("directory")

            if isDirectory {
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
                        fromByteCount: Int64(item.size),
                        countStyle: .file
                    ),
                    isDirectory: false,
                    sizeInBytes: Int64(item.size)
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

        let allEntries = try reader.entries(at: archiveURL)

        let searchQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !searchQuery.isEmpty else { return [] }

        var items: [String: ArchiveEntry] = [:]

        for item in allEntries {
            let path = item.path.trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )

            guard !path.isEmpty else { continue }

            let components = path.split(separator: "/")

            if components.count > 1 {
                for index in 1..<components.count {
                    let folderPath = components
                        .prefix(index)
                        .joined(separator: "/")

                    if items[folderPath] == nil {
                        items[folderPath] = ArchiveEntry(
                            id: folderPath,
                            path: folderPath,
                            sizeDescription: "Папка",
                            isDirectory: true
                        )
                    }
                }
            }

            let isDirectory =
                String(describing: item.fileType).lowercased()
                    .contains("directory")

            items[path] = ArchiveEntry(
                id: path,
                path: path,
                sizeDescription: isDirectory
                    ? "Папка"
                    : ByteCountFormatter.string(
                        fromByteCount: Int64(item.size),
                        countStyle: .file
                    ),
                isDirectory: isDirectory,
                sizeInBytes: isDirectory ? 0 : Int64(item.size)
            )
        }

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
        folderName: String,
        progress: Progress? = nil
    ) throws -> URL {

        try validateArchive(archiveURL)

        let entries = try reader.entries(at: archiveURL)

        var totalSize: Int64 = 0

        for entry in entries {
            let path = try normalizedPath(entry.path)

            if entry.symlinkTarget != nil ||
                entry.hardlinkTarget != nil {
                throw ArchiveServiceError.symbolicLinkNotAllowed
            }

            let type = String(describing: entry.fileType).lowercased()

            let isDirectory = type.contains("directory")
            let isRegularFile = type.contains("regular")

            guard isDirectory || isRegularFile else {
                throw ArchiveServiceError.unsafeArchivePath(path)
            }

            if isRegularFile {
                totalSize += max(0, entry.size)
            }
        }

        progress?.totalUnitCount = max(1, totalSize)
        progress?.completedUnitCount = 0

        let outputFolder = try createUniqueArchiveFolder(
            folderName: folderName,
            inside: destinationURL
        )

        var fileHandles: [String: FileHandle] = [:]

        do {
            try reader.readDataBlocks(
                in: archiveURL,
                selecting: { entry in

                    let path = try normalizedPath(entry.path)
                    let type = String(describing: entry.fileType).lowercased()

                    let targetURL = try safeTargetURL(
                        path,
                        inside: outputFolder
                    )

                    if type.contains("directory") {
                        try FileManager.default.createDirectory(
                            at: targetURL,
                            withIntermediateDirectories: true
                        )

                        return .skip
                    }

                    let parentURL = targetURL.deletingLastPathComponent()

                    try FileManager.default.createDirectory(
                        at: parentURL,
                        withIntermediateDirectories: true
                    )

                    guard !FileManager.default.fileExists(
                        atPath: targetURL.path
                    ) else {
                        throw ArchiveServiceError.destinationFileExists(path)
                    }

                    guard FileManager.default.createFile(
                        atPath: targetURL.path,
                        contents: nil
                    ) else {
                        throw ArchiveServiceError.destinationFileExists(path)
                    }

                    fileHandles[path] = try FileHandle(
                        forWritingTo: targetURL
                    )

                    return .read
                },
                didFinishEntry: { entry, _ in

                    let path = try normalizedPath(entry.path)

                    if let handle = fileHandles.removeValue(forKey: path) {
                        try handle.close()
                    }
                },
                { entry, block in

                    let path = try normalizedPath(entry.path)

                    guard let handle = fileHandles[path] else {
                        throw ArchiveServiceError.noSelectedEntries
                    }

                    guard block.offset >= 0 else {
                        throw ArchiveServiceError.unsafeArchivePath(path)
                    }

                    try handle.seek(toOffset: UInt64(block.offset))
                    try handle.write(contentsOf: block.data)

                    progress?.completedUnitCount += Int64(block.data.count)

                    return .continueReading
                }
            )

            if totalSize == 0 {
                progress?.completedUnitCount = 1
            } else {
                progress?.completedUnitCount = totalSize
            }

            return outputFolder

        } catch {
            for handle in fileHandles.values {
                try? handle.close()
            }

            try? FileManager.default.removeItem(at: outputFolder)
            throw error
        }
    }

    // MARK: - Selected extraction
    
    func extractSelected(
        archiveURL: URL,
        selectedPaths: Set<String>,
        to destinationURL: URL,
        folderName: String,
        progress: Progress? = nil
    ) throws -> URL {

        try validateArchive(archiveURL)

        guard !selectedPaths.isEmpty else {
            throw ArchiveServiceError.noSelectedEntries
        }

        let entries = try reader.entries(at: archiveURL)

        var archivePaths: [String] = []

        for entry in entries {
            let path = try normalizedPath(entry.path)

            if entry.symlinkTarget != nil ||
                entry.hardlinkTarget != nil {
                throw ArchiveServiceError.symbolicLinkNotAllowed
            }

            let type = String(describing: entry.fileType).lowercased()

            let isDirectory = type.contains("directory")
            let isRegularFile = type.contains("regular")

            guard isDirectory || isRegularFile else {
                throw ArchiveServiceError.unsafeArchivePath(path)
            }

            archivePaths.append(path)
        }

        let normalizedSelections = try Set(
            selectedPaths.map { try normalizedPath($0) }
        )

        var selectedFolders = Set<String>()

        for selected in normalizedSelections {
            if archivePaths.contains(where: {
                $0.hasPrefix(selected + "/")
            }) {
                selectedFolders.insert(selected)
            }
        }

        let effectiveSelections = normalizedSelections.filter { selected in
            !selectedFolders.contains { folder in
                folder != selected &&
                selected.hasPrefix(folder + "/")
            }
        }

        selectedFolders = selectedFolders.intersection(
            effectiveSelections
        )

        var plannedItems: [(source: String, target: String)] = []

        for selected in effectiveSelections {

            if selectedFolders.contains(selected) {

                let name = URL(
                    fileURLWithPath: selected
                ).lastPathComponent

                plannedItems.append((
                    source: selected,
                    target: name
                ))

            } else if archivePaths.contains(selected) {

                let name = URL(
                    fileURLWithPath: selected
                ).lastPathComponent

                plannedItems.append((
                    source: selected,
                    target: name
                ))
            }
        }

        guard !plannedItems.isEmpty else {
            throw ArchiveServiceError.noSelectedEntries
        }

        var targetPaths: [String: String] = [:]

        for path in archivePaths {

            for item in plannedItems {

                if path == item.source {
                    targetPaths[path] = item.target
                    break
                }

                if selectedFolders.contains(item.source),
                   path.hasPrefix(item.source + "/") {

                    let suffix = String(
                        path.dropFirst(item.source.count + 1)
                    )

                    targetPaths[path] = item.target + "/" + suffix
                    break
                }
            }
        }

        let totalSize = entries.reduce(Int64(0)) { total, entry in
            guard let path = try? normalizedPath(entry.path),
                  targetPaths[path] != nil,
                  String(describing: entry.fileType)
                    .lowercased()
                    .contains("regular") else {
                return total
            }

            return total + max(0, entry.size)
        }

        progress?.totalUnitCount = max(1, totalSize)
        progress?.completedUnitCount = 0

        let outputFolder = try createUniqueArchiveFolder(
            folderName: folderName,
            inside: destinationURL
        )

        var fileHandles: [String: FileHandle] = [:]

        do {
            try reader.readDataBlocks(
                in: archiveURL,
                selecting: { entry in

                    let sourcePath = try normalizedPath(entry.path)

                    guard let targetPath = targetPaths[sourcePath] else {
                        return .skip
                    }

                    let type = String(
                        describing: entry.fileType
                    ).lowercased()

                    let targetURL = try safeTargetURL(
                        targetPath,
                        inside: outputFolder
                    )

                    if type.contains("directory") {

                        try FileManager.default.createDirectory(
                            at: targetURL,
                            withIntermediateDirectories: true
                        )

                        return .skip
                    }

                    let parentURL = targetURL.deletingLastPathComponent()

                    try FileManager.default.createDirectory(
                        at: parentURL,
                        withIntermediateDirectories: true
                    )

                    guard !FileManager.default.fileExists(
                        atPath: targetURL.path
                    ) else {
                        throw ArchiveServiceError.destinationFileExists(
                            targetPath
                        )
                    }

                    guard FileManager.default.createFile(
                        atPath: targetURL.path,
                        contents: nil
                    ) else {
                        throw ArchiveServiceError.destinationFileExists(
                            targetPath
                        )
                    }

                    fileHandles[sourcePath] = try FileHandle(
                        forWritingTo: targetURL
                    )

                    return .read
                },
                didFinishEntry: { entry, _ in

                    let sourcePath = try normalizedPath(entry.path)

                    if let handle = fileHandles.removeValue(
                        forKey: sourcePath
                    ) {
                        try handle.close()
                    }
                },
                { entry, block in

                    let sourcePath = try normalizedPath(entry.path)

                    guard let handle = fileHandles[sourcePath] else {
                        throw ArchiveServiceError.noSelectedEntries
                    }

                    guard block.offset >= 0 else {
                        throw ArchiveServiceError.unsafeArchivePath(
                            sourcePath
                        )
                    }

                    try handle.seek(toOffset: UInt64(block.offset))
                    try handle.write(contentsOf: block.data)

                    progress?.completedUnitCount +=
                        Int64(block.data.count)

                    return .continueReading
                }
            )

            if totalSize == 0 {
                progress?.completedUnitCount = 1
            } else {
                progress?.completedUnitCount = totalSize
            }

            return outputFolder

        } catch {

            for handle in fileHandles.values {
                try? handle.close()
            }

            try? FileManager.default.removeItem(at: outputFolder)

            throw error
        }
    }

    // MARK: - Extract single file for preview

    func extractPreviewFile(
        archiveURL: URL,
        path: String
    ) throws -> URL {

        try validateArchive(archiveURL)

        let normalizedPreviewPath = try normalizedPath(path)
        let entries = try reader.entries(at: archiveURL)

        // Проверяем безопасность элементов архива
        for entry in entries {

            let entryPath = try normalizedPath(entry.path)

            if entry.symlinkTarget != nil ||
                entry.hardlinkTarget != nil {
                throw ArchiveServiceError.symbolicLinkNotAllowed
            }

            let type = String(describing: entry.fileType).lowercased()

            let isDirectory = type.contains("directory")
            let isRegularFile = type.contains("regular")

            guard isDirectory || isRegularFile else {
                throw ArchiveServiceError.unsafeArchivePath(entryPath)
            }
        }

        // Находим нужный файл
        guard let matchingEntry = entries.first(where: {
            (try? normalizedPath($0.path)) == normalizedPreviewPath &&
            $0.fileType == .regular
        }) else {
            throw ArchiveServiceError.noSelectedEntries
        }

        let previewURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(
                URL(fileURLWithPath: normalizedPreviewPath).pathExtension
            )

        do {
            // Читаем непосредственно содержимое выбранного файла
            let data = try reader.data(
                forEntryPath: matchingEntry.path,
                in: archiveURL
            )

            try data.write(to: previewURL, options: .atomic)

            return previewURL

        } catch {
            try? FileManager.default.removeItem(at: previewURL)
            throw error
        }
    }


    // MARK: - Validation

    private func validateArchive(_ url: URL) throws {
        guard url.pathExtension.lowercased() == "rar" else {
            throw ArchiveServiceError.onlyZIPSupported
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ArchiveServiceError.archiveNotFound
        }
    }

    private func normalizedPath(
        _ rawPath: String
    ) throws -> String {

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

        var current = destination

        for component in path.split(separator: "/") {
            current.appendPathComponent(String(component))

            if let attributes = try? fileManager.attributesOfItem(
                atPath: current.path
            ),
            let type = attributes[.type] as? FileAttributeType,
            type == .typeSymbolicLink {
                throw ArchiveServiceError.symbolicLinkInDestination
            }
        }

        return target
    }
}
