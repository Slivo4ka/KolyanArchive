
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ZIPFoundation

struct HomeView: View {

    @State private var isImporterPresented = false
    @State private var isChoosingDestination = false

    @AppStorage("isEnglish") private var isEnglish = false

    @State private var archiveName = "Архив не выбран"
    @State private var archiveURL: URL?

    @State private var currentDirectoryPath = ""
    @State private var entries: [ArchiveEntry] = []
    @State private var searchText = ""
    @State private var searchResults: [ArchiveEntry] = []
    @State private var activeGallery: GalleryPresentation?

    @State private var message = "Выбери ZIP-архив через кнопку выше."

    @State private var errorMessage = ""
    @State private var showingError = false

    private let archiveService = ZIPArchiveService()
    private func tr(_ ru: String, _ en: String) -> String {
        isEnglish ? en : ru
    }
    private var isSearching: Bool {
        !searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    private var displayedEntries: [ArchiveEntry] {
        isSearching ? searchResults : entries
    }

    
var body: some View {
    NavigationStack {
        ZStack {
            Color(red: 0.035, green: 0.043, blue: 0.075)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    openArchiveButton

                    if archiveURL != nil {
                        extractArchiveButton
                    }

                    archiveContents
                    featureCards

                    Text("Kolyan Tech. LTD")
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
            tr("Не удалось открыть архив", "Unable to open archive"),
            isPresented: $showingError
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(item: $activeGallery) { gallery in
            ImageGalleryView(
                archiveURL: gallery.archiveURL,
                items: gallery.items,
                initialIndex: gallery.initialIndex,
                isEnglish: isEnglish
            )
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

            Button {
                isEnglish.toggle()

                if archiveURL == nil {
                    archiveName = tr("Архив не выбран", "No archive selected")
                    message = tr(
                        "Выбери ZIP-архив через кнопку выше.",
                        "Choose a ZIP archive using the button above."
                    )
                }
            } label: {
                HStack(spacing: 7) {
                    Text(isEnglish ? "🇬🇧" : "🇷🇺")
                        .font(.system(size: 22))

                    Text(isEnglish ? "EN" : "RU")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(15)
                .background(
                    Color.white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 16)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 18)
    }


    // MARK: - Open archive button

    private var openArchiveButton: some View {
        Button {
            isImporterPresented = true
        } label: {
            Label(
                tr("Открыть архив", "Open archive"),
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
        Label(
            tr("Распаковать архив", "Extract archive"),
            systemImage: "archivebox"
        )
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

            HStack {
                Text(archiveName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if archiveURL != nil {
                    Button {
                        closeArchive()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            }
            if archiveURL != nil {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.cyan)

                    TextField(
                        tr("Поиск по архиву...", "Search archive..."),
                        text: $searchText
                    )
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: searchText) { _, newValue in
                        performSearch(newValue)
                    }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(13)
                .background(
                    Color.white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 13)
                )
            }            
            if displayedEntries.isEmpty {
                ContentUnavailableView(
                    tr(
                        isSearching ? "Ничего не найдено" : "Нет содержимого",
                        isSearching ? "No results found" : "No contents"
                    ),
                    systemImage: isSearching ? "magnifyingglass" : "doc.zipper",
                    description: Text(
                        isSearching
                            ? tr("Попробуй другое название или путь.", "Try another name or path.")
                            : message
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 190)

            } else {

                ForEach(displayedEntries) { entry in
                    archiveEntryRow(entry)

                    if entry.id != displayedEntries.last?.id {
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

    // MARK: - Search

    private func performSearch(_ query: String) {
        guard let archiveURL else {
            searchResults = []
            return
        }

        let trimmedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedQuery.isEmpty else {
            searchResults = []
            return
        }

        do {
            searchResults = try archiveService.searchContents(
                of: archiveURL,
                matching: trimmedQuery
            )
        } catch {
            showError(error)
        }
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
    guard let archiveURL else { return }

    let supportedFormats = ["jpg", "jpeg", "png", "gif", "heic", "webp"]

    let images = displayedEntries
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

    activeGallery = GalleryPresentation(
        archiveURL: archiveURL,
        items: images,
        initialIndex: selectedIndex
    )
}
    // MARK: - Directory navigation

    private func openDirectory(_ entry: ArchiveEntry) {
        guard let archiveURL else { return }
        searchText = ""
        searchResults = []

        do {
            currentDirectoryPath = entry.path

            entries = try archiveService.listContents(
                of: archiveURL,
                in: currentDirectoryPath
            )

            message = entries.isEmpty
                ? tr("Эта папка пуста.", "This folder is empty.")
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

            message = entries.isEmpty ? tr("Эта папка пуста.", "This folder is empty.") : ""

        } catch {
            showError(error)
        }
    }

    // MARK: - Feature cards

    private var featureCards: some View {
        HStack(spacing: 12) {
            featureCard(
                "ZIP",
                detail: tr(
                    "Создание и распаковка",
                    "Create and extract archives"
                ),
                symbol: "doc.zipper"
            )

            featureCard(
                "RAR",
                detail: tr(
                    "Распаковка — следующий этап",
                    "Extraction — coming next"
                ),
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


            searchText = ""
            searchResults = []

            activeGallery = nil
            archiveURL = copiedURL
            archiveName = sourceURL.lastPathComponent
            currentDirectoryPath = ""
            entries = newEntries

            message = newEntries.isEmpty
                ? tr("Архив пуст.", "Archive is empty.")
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

        message = tr(
            "Архив успешно распакован!",
            "Archive extracted successfully!"
        )

    } catch {
        showError(error)
    }
}
private func closeArchive() {
    searchText = ""
    searchResults = []

    archiveURL = nil
    archiveName = tr("Архив не выбран", "No archive selected")
    currentDirectoryPath = ""
    entries = []
    activeGallery = nil
    message = tr(
        "Выбери ZIP-архив через кнопку выше.",
        "Choose a ZIP archive using the button above."
    )
}
}
struct GalleryPresentation: Identifiable {
    let id = UUID()
    let archiveURL: URL
    let items: [ArchiveImage]
    let initialIndex: Int
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
    let isEnglish: Bool

    @State private var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(
        archiveURL: URL,
        items: [ArchiveImage],
        initialIndex: Int,
        isEnglish: Bool
    ) {
        self.archiveURL = archiveURL
        self.items = items
        self.isEnglish = isEnglish
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
                    : (isEnglish ? "Photo" : "Фото")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEnglish ? "Done" : "Готово") {
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
            image = nil
            scale = 1
            lastScale = 1
            loadImage()
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

            try archive.extract(
                archiveEntry,
                to: previewURL
            )

            defer {
                try? FileManager.default.removeItem(at: previewURL)
            }

            let imageData = try Data(contentsOf: previewURL)

            guard let loadedImage = UIImage(data: imageData) else {
                return
            }

            image = loadedImage

        } catch {
            print("Ошибка загрузки изображения: \(error)")
        }
    }  
}