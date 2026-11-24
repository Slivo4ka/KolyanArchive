
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ZIPFoundation

struct HomeView: View {

    @State private var isImporterPresented = false
    @State private var isChoosingDestination = false

    @State private var archiveName = "Архив не выбран"
    @State private var archiveURL: URL?

    @State private var currentDirectoryPath = ""
    @State private var entries: [ArchiveEntry] = []
    @State private var previewImages: [ArchiveImage] = []
    @State private var previewStartIndex = 0
    @State private var isImagePreviewPresented = false

    @State private var message = "Выбери ZIP-архив через кнопку выше."

    @State private var errorMessage = ""
    @State private var showingError = false

    private let archiveService = ZIPArchiveService()

    
var body: some View {
    NavigationStack {
        ZStack {
            Color(red: 0.035, green: 0.043, blue: 0.075)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    openArchiveButton

                    if archiveURL != nil {
                        extractArchiveButton
                    }

                    archiveContents
                    featureCards

                    Text("Kolyan Technologies")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: isChoosingDestination ? [.folder] : [.zip],
            allowsMultipleSelection: false
        ) { result in
            if isChoosingDestination {
                extractToSelectedFolder(result)
            } else {
                openSelectedArchive(result)
            }
        }
        .alert(
            "Не удалось открыть архив",
            isPresented: $showingError
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $isImagePreviewPresented) {
            if let archiveURL {
                ImageGalleryView(
                    archiveURL: archiveURL,
                    items: previewImages,
                    initialIndex: previewStartIndex
                )
            }
        }
    }
    .tint(.white)
}


    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("KOLYAN")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .tracking(2.5)

                Text("ARCHIVE")
                    .font(.caption.weight(.semibold))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            Image(systemName: "shippingbox.fill")
                .font(.system(size: 27))
                .foregroundStyle(.cyan)
                .padding(15)
                .background(
                    Color.white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 16)
                )
        }
        .padding(.top, 18)
    }

    // MARK: - Open archive button

    private var openArchiveButton: some View {
        Button {
            isImporterPresented = true
        } label: {
            Label(
                "Открыть архив",
                systemImage: "folder.badge.plus"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                LinearGradient(
                    colors: [.indigo, .blue],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Extract archive button

private var extractArchiveButton: some View {
    Button {
        isChoosingDestination = true
        isImporterPresented = true
    } label: {
        Label("Распаковать архив", systemImage: "archivebox")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                Color.green.opacity(0.8),
                in: RoundedRectangle(cornerRadius: 16)
            )
    }
    .buttonStyle(.plain)
    }

    // MARK: - Archive contents

    private var archiveContents: some View {
        VStack(alignment: .leading, spacing: 14) {

            Text(archiveName)
                .font(.headline)
                .lineLimit(1)

            if archiveURL != nil && !currentDirectoryPath.isEmpty {
                Button {
                    goBack()
                } label: {
                    Label("Назад", systemImage: "arrow.left")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)

                Text(currentDirectoryPath)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(2)
            }

            if entries.isEmpty {
                ContentUnavailableView(
                    "Нет содержимого",
                    systemImage: "doc.zipper",
                    description: Text(message)
                )
                .frame(maxWidth: .infinity, minHeight: 190)

            } else {

                ForEach(entries) { entry in
                    archiveEntryRow(entry)

                    if entry.id != entries.last?.id {
                        Divider()
                            .overlay(Color.white.opacity(0.06))
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }

    // MARK: - Entry row

    private func archiveEntryRow(_ entry: ArchiveEntry) -> some View {
        Button {
            if entry.isDirectory {
                openDirectory(entry)
            } else if ["jpg", "jpeg", "png", "gif", "heic", "webp"].contains(entry.fileExtension) {
                openImage(entry)
            }
        } label: {
            HStack(spacing: 12) {

                Image(systemName: entry.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(
                        entry.isDirectory ? .cyan : .white.opacity(0.8)
                    )
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(entry.sizeDescription)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(
            !entry.isDirectory &&
            !["jpg", "jpeg", "png", "gif", "heic", "webp"].contains(entry.fileExtension)
        )
    }
    // MARK: - Image preview

private func openImage(_ entry: ArchiveEntry) {
    let supportedFormats = ["jpg", "jpeg", "png", "gif", "heic", "webp"]

    let images = entries
        .filter {
            !$0.isDirectory &&
            supportedFormats.contains($0.fileExtension)
        }
        .map {
            ArchiveImage(
                path: $0.path,
                name: $0.name,
                fileExtension: $0.fileExtension
            )
        }

    guard let selectedIndex = images.firstIndex(where: {
        $0.path == entry.path
    }) else {
        return
    }

    previewImages = images
    previewStartIndex = selectedIndex
    isImagePreviewPresented = true
}
    // MARK: - Directory navigation

    private func openDirectory(_ entry: ArchiveEntry) {
        guard let archiveURL else { return }

        do {
            currentDirectoryPath = entry.path

            entries = try archiveService.listContents(
                of: archiveURL,
                in: currentDirectoryPath
            )

            message = entries.isEmpty
                ? "Эта папка пуста."
                : ""

        } catch {
            showError(error)
        }
    }

    private func goBack() {
        let components = currentDirectoryPath.split(separator: "/")

        currentDirectoryPath = components
            .dropLast()
            .joined(separator: "/")

        guard let archiveURL else { return }

        do {
            entries = try archiveService.listContents(
                of: archiveURL,
                in: currentDirectoryPath
            )

            message = entries.isEmpty ? "Эта папка пуста." : ""

        } catch {
            showError(error)
        }
    }

    // MARK: - Feature cards

    private var featureCards: some View {
        HStack(spacing: 12) {
            featureCard(
                "ZIP",
                detail: "Создание и распаковка",
                symbol: "doc.zipper"
            )

            featureCard(
                "RAR",
                detail: "Распаковка — следующий этап",
                symbol: "archivebox"
            )
        }
    }

    private func featureCard(
        _ title: String,
        detail: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.cyan)

            Text(title)
                .font(.headline)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
        .padding(15)
        .background(
            Color.white.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 17)
        )
    }

    // MARK: - Import archive

    private func openSelectedArchive(
        _ result: Result<[URL], Error>
    ) {
        do {
            guard let sourceURL = try result.get().first else {
                return
            }

            let hasAccess = sourceURL.startAccessingSecurityScopedResource()

            defer {
                if hasAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let fileManager = FileManager.default

            let storageDirectory = fileManager.temporaryDirectory
                .appendingPathComponent(
                    "KolyanArchive",
                    isDirectory: true
                )

            try fileManager.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true
            )

            let copiedURL = storageDirectory
                .appendingPathComponent(
                    UUID().uuidString + "-" + sourceURL.lastPathComponent
                )

            try fileManager.copyItem(
                at: sourceURL,
                to: copiedURL
            )

            let newEntries = try archiveService.listContents(
                of: copiedURL
            )

            archiveURL = copiedURL
            archiveName = sourceURL.lastPathComponent
            currentDirectoryPath = ""
            entries = newEntries

            message = newEntries.isEmpty
                ? "Архив пуст."
                : ""

        } catch {
            showError(error)
        }
    }

    // MARK: - Error handling

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
// MARK: - Extract archive

private func extractToSelectedFolder(
    _ result: Result<[URL], Error>
) {
    defer {
        isChoosingDestination = false
    }

    do {
        guard let destinationURL = try result.get().first else {
            return
        }

        guard let archiveURL else {
            return
        }

        let hasAccess = destinationURL.startAccessingSecurityScopedResource()

        defer {
            if hasAccess {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }

        try archiveService.extract(
            archiveURL: archiveURL,
            to: destinationURL
        )

        message = "Архив успешно распакован!"

    } catch {
        showError(error)
    }
}
}
struct ArchiveImage: Identifiable {
    let path: String
    let name: String
    let fileExtension: String

    var id: String { path }
}
struct ImageGalleryView: View {

    let archiveURL: URL
    let items: [ArchiveImage]

    @State private var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(
        archiveURL: URL,
        items: [ArchiveImage],
        initialIndex: Int
    ) {
        self.archiveURL = archiveURL
        self.items = items
        _selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedIndex) {
                ForEach(items.indices, id: \.self) { index in
                    ArchiveImagePage(
                        archiveURL: archiveURL,
                        item: items[index]
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(Color.black)
            .navigationTitle(
                items.indices.contains(selectedIndex)
                    ? items[selectedIndex].name
                    : "Фото"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ArchiveImagePage: View {

    let archiveURL: URL
    let item: ArchiveImage


    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .scaleEffect(scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = min(
                                        max(lastScale * value, 1),
                                        5
                                    )
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                if scale > 1 {
                                    scale = 1
                                    lastScale = 1
                                } else {
                                    scale = 2.5
                                    lastScale = 2.5
                                }
                            }
                        }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .clipped()
        }
        .task(id: item.id) {
            loadImage()
        }
        .onChange(of: item.id) { _, _ in
            scale = 1
            lastScale = 1
            image = nil
        }
    }

    private func loadImage() {
        do {
            let archive = try Archive(
                url: archiveURL,
                accessMode: .read
            )

            guard let archiveEntry = archive.first(where: {
                $0.path == item.path
            }), archiveEntry.type == .file else {
                return
            }

            let previewURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(item.fileExtension)

            defer {
                try? FileManager.default.removeItem(at: previewURL)
            }

            try archive.extract(
                archiveEntry,
                to: previewURL
            )

            let imageData = try Data(contentsOf: previewURL)
            image = UIImage(data: imageData)

        } catch {
            print("Ошибка загрузки изображения: \(error)")
        }
    }
}