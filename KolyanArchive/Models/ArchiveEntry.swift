import Foundation

struct ArchiveEntry: Identifiable {
    let id = UUID()
    let path: String
    let sizeDescription: String
    let isDirectory: Bool
}
