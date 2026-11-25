
import Foundation
import LibArchive

struct RARArchiveService {

    private let reader = ArchiveReader()

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
                isDirectory: isDirectory
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
}
