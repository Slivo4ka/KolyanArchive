
import Foundation
import LibArchive

struct ISOArchiveService {

    private let reader = ArchiveReader()

    // MARK: - List ISO contents

    func listContents(
        of archiveURL: URL,
        in directoryPath: String = ""
    ) throws -> [ArchiveEntry] {

        try validateArchive(archiveURL)

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

    // MARK: - Search ISO contents

    func searchContents(
        of archiveURL: URL,
        matching query: String
    ) throws -> [ArchiveEntry] {

        try validateArchive(archiveURL)

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
        folderName: String
    ) throws -> URL {

        try validateArchive(archiveURL)

        let outputFolder = try createUniqueArchiveFolder(
            folderName: folderName,
            inside: destinationURL
        )

        do {
            try extractEntriesSafely(
                from: archiveURL,
                to: outputFolder
            )

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

        let entries = try reader.entries(at: archiveURL)

        for entry in entries {
            let path = try normalizedPath(entry.path)
            if path.isEmpty {
                continue
            }

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
        }

        let normalizedSelections = try Set(
            selectedPaths.map { try normalizedPath($0) }
        )

        let archivePaths = try entries.compactMap { entry -> String? in
            let path = try normalizedPath(entry.path)
            return path.isEmpty ? nil : path
        }

        var selectedFolders = Set<String>()

        for selected in normalizedSelections {
            let isFolder = archivePaths.contains {
                $0.hasPrefix(selected + "/")
            }

            if isFolder {
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

                let selectedFolderName = URL(
                    fileURLWithPath: selected
                ).lastPathComponent

                plannedItems.append((
                    source: selected,
                    target: selectedFolderName
                ))

            } else if archivePaths.contains(selected) {

                let fileName = URL(
                    fileURLWithPath: selected
                ).lastPathComponent

                plannedItems.append((
                    source: selected,
                    target: fileName
                ))
            }
        }

        guard !plannedItems.isEmpty else {
            throw ArchiveServiceError.noSelectedEntries
        }

        let outputFolder = try createUniqueArchiveFolder(
            folderName: folderName,
            inside: destinationURL
        )

        let temporaryFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: temporaryFolder,
                withIntermediateDirectories: true
            )

            defer {
                try? FileManager.default.removeItem(at: temporaryFolder)
            }

            try extractEntriesSafely(
                from: archiveURL,
                to: temporaryFolder
            )

            var extractedPaths = Set<String>()

            for item in plannedItems {

                let sourcePath = try normalizedPath(item.source)
                let targetPath = try normalizedPath(item.target)

                guard extractedPaths.insert(
                    targetPath.lowercased()
                ).inserted else {
                    throw ArchiveServiceError.destinationFileExists(
                        targetPath
                    )
                }

                let sourceURL = temporaryFolder
                    .appendingPathComponent(sourcePath)
                    .standardizedFileURL

                guard FileManager.default.fileExists(
                    atPath: sourceURL.path
                ) else {
                    throw ArchiveServiceError.noSelectedEntries
                }

                let targetURL = try safeTargetURL(
                    targetPath,
                    inside: outputFolder
                )

                try FileManager.default.createDirectory(
                    at: targetURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                guard !FileManager.default.fileExists(
                    atPath: targetURL.path
                ) else {
                    throw ArchiveServiceError.destinationFileExists(
                        targetPath
                    )
                }

                try FileManager.default.copyItem(
                    at: sourceURL,
                    to: targetURL
                )
            }

            return outputFolder

        } catch {
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

        guard let matchingEntry = entries.first(where: { entry in
            guard let entryPath = try? normalizedPath(entry.path),
                  !entryPath.isEmpty else {
                return false
            }

            let type = String(describing: entry.fileType).lowercased()

            return entryPath == normalizedPreviewPath &&
                   type.contains("regular")
        }) else {
            throw ArchiveServiceError.noSelectedEntries
        }

        let fileExtension = URL(
            fileURLWithPath: normalizedPreviewPath
        ).pathExtension

        let previewURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        do {
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

    
    // MARK: - Safe ISO extraction

    private func extractEntriesSafely(
        from archiveURL: URL,
        to destinationURL: URL
    ) throws {

        let entries = try reader.entries(at: archiveURL)

        for entry in entries {

            if entry.symlinkTarget != nil ||
                entry.hardlinkTarget != nil {
                throw ArchiveServiceError.symbolicLinkNotAllowed
            }

            let path = try normalizedPath(entry.path)

            // Skip ISO root directory entries: "." and "./"
            guard !path.isEmpty else {
                continue
            }

            let type = String(describing: entry.fileType).lowercased()

            let isDirectory = type.contains("directory")
            let isRegularFile = type.contains("regular")

            guard isDirectory || isRegularFile else {
                throw ArchiveServiceError.unsafeArchivePath(path)
            }

            let targetURL = try safeTargetURL(
                path,
                inside: destinationURL
            )

            if isDirectory {
                try FileManager.default.createDirectory(
                    at: targetURL,
                    withIntermediateDirectories: true
                )
            } else {
                try FileManager.default.createDirectory(
                    at: targetURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                guard !FileManager.default.fileExists(
                    atPath: targetURL.path
                ) else {
                    throw ArchiveServiceError.destinationFileExists(path)
                }

                let data = try reader.data(
                    forEntryPath: entry.path,
                    in: archiveURL
                )

                try data.write(
                    to: targetURL,
                    options: .atomic
                )
            }
        }
    }

    
    // MARK: - Validation

    private func validateArchive(_ url: URL) throws {

        guard url.pathExtension.lowercased() == "iso" else {
            throw ArchiveServiceError.onlyISOSupported
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

        // Remove harmless leading "./" components.
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }

        // Remove trailing slashes.
        while path.hasSuffix("/") {
            path.removeLast()
        }

        // ISO root directory.
        if path.isEmpty || path == "." {
            return ""
        }

        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )

        guard components.allSatisfy({
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
