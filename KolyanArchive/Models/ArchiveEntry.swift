
import Foundation

struct ArchiveEntry: Identifiable, Hashable {
    let id: String
    let path: String
    let sizeDescription: String
    let isDirectory: Bool

    var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var fileExtension: String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    var icon: String {
        if isDirectory {
            return "folder.fill"
        }

        switch fileExtension {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return "photo"
        case "mp4", "mov", "mkv", "avi":
            return "video"
        case "mp3", "wav", "m4a", "flac":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "zip", "rar", "7z":
            return "doc.zipper"
        case "txt", "rtf":
            return "doc.text"
        case "doc", "docx":
            return "doc"
        case "xls", "xlsx":
            return "tablecells"
        default:
            return "doc"
        }
    }
}
