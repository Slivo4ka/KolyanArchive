
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ZIPFoundation
import WebKit
import PDFKit

struct HomeView: View {

    @State private var isImporterPresented = false
    @State private var isChoosingDestination = false
    @State private var isSelectionMode = false
    @State private var selectedPaths: Set<String> = []
    @State private var isExtractingSelection = false
    @State private var archiveInfo: ArchiveInfo?

    @AppStorage("isEnglish") private var isEnglish = false

    @State private var archiveName = "Архив не выбран"
    @State private var archiveURL: URL?

    @State private var isNamingExtractionFolder = false
    @State private var extractionFolderName = ""
    @State private var extractionFolderNameSelection: TextSelection?
    @State private var pendingExtractionIsSelection = false
    @State private var shouldChooseDestinationAfterNaming = false

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

                        if isSelectionMode && !selectedPaths.isEmpty {
                            selectedExtractButton
                        }
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
                if isExtractingSelection {
                    extractSelectedToFolder(result)
                } else {
                    extractToSelectedFolder(result)
                }
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
        
        .fullScreenCover(item: $activeGallery) { gallery in
            ImageGalleryView(
                archiveURL: gallery.archiveURL,
                items: gallery.items,
                initialIndex: gallery.initialIndex,
                isEnglish: isEnglish
            )
        }
        .sheet(item: $archiveInfo) { info in
            ArchiveInfoView(
                info: info,
                isEnglish: isEnglish
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .sheet(
            isPresented: $isNamingExtractionFolder,
            onDismiss: {
                if shouldChooseDestinationAfterNaming {
                    shouldChooseDestinationAfterNaming = false
                    isChoosingDestination = true
                    isImporterPresented = true
                }
            }
        ) {
            extractionNameSheet
                .presentationDetents([.height(290)])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
    }
    .tint(.white)
}

    private var archiveFolderDefaultName: String {
        guard let archiveURL else { return "" }

        let name = archiveURL.deletingPathExtension().lastPathComponent
        return name
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
            isExtractingSelection = false
            pendingExtractionIsSelection = false
            extractionFolderName = archiveFolderDefaultName
            extractionFolderNameSelection = nil
            isNamingExtractionFolder = true
        } label: {
            Label(
                tr("Распаковать весь архив", "Extract entire archive"),
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

    private var selectedExtractButton: some View {
        Button {
            isExtractingSelection = true
            pendingExtractionIsSelection = true
            extractionFolderName = archiveFolderDefaultName
            extractionFolderNameSelection = nil
            isNamingExtractionFolder = true
        } label: {
            Label(
                tr(
                    "Распаковать выбранное (\(selectedPaths.count))",
                    "Extract selected (\(selectedPaths.count))"
                ),
                systemImage: "archivebox"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                Color.cyan.opacity(0.8),
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Archive contents

    private var archiveContents: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack(spacing: 12) {

                if !currentDirectoryPath.isEmpty {
                    Button {
                        goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.cyan)
                            .frame(width: 36, height: 36)
                            .background(
                                Color.white.opacity(0.08),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Назад", "Back"))
                }

                Text(archiveName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if archiveURL != nil {

                    if isSelectionMode {

                        if !isSearching {
                            Button {
                                selectedPaths = Set(displayedEntries
                                    .filter { !$0.isDirectory }
                                    .map { $0.path })
                            } label: {
                                Text(tr("Выбрать всё", "Select all"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.cyan)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            selectedPaths.removeAll()
                        } label: {
                            Text(tr("Снять всё", "Clear all"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)

                        Button {
                            isSelectionMode = false
                        } label: {
                            Text(tr("Готово", "Done"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)

                    } else {

                        Button {
                            isSelectionMode = true
                        } label: {
                            Image(systemName: "checkmark.circle")
                                .font(.title2)
                                .foregroundStyle(.cyan)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            tr("Выбрать файлы", "Select files")
                        )
                    }

                    Button {
                        showArchiveInfo()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .foregroundStyle(.cyan)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        tr("Информация об архиве", "Archive information")
                    )

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
                if isSearching {
                    VStack(spacing: 14) {
                        ZStack(alignment: .bottomTrailing) {
                            Image(systemName: "doc.zipper")
                                .font(.system(size: 58, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.cyan, .blue, .indigo],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .cyan.opacity(0.35), radius: 12)

                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 23, weight: .semibold))
                                .foregroundStyle(.cyan)
                                .padding(8)
                                .background(
                                    Color(red: 0.035, green: 0.043, blue: 0.075),
                                    in: Circle()
                                )
                                .overlay {
                                    Circle()
                                        .stroke(.cyan.opacity(0.7), lineWidth: 1.5)
                                }
                                .offset(x: 10, y: 7)
                        }
                        .frame(height: 90)

                        Text(tr("Ничего не найдено", "No results found"))
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(
                            tr(
                                "Попробуй другое название или путь.",
                                "Try another name or path."
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 190)
                    .padding(.vertical, 8)
                } else {
                    ContentUnavailableView(
                        tr("Нет содержимого", "No contents"),
                        systemImage: "doc.zipper",
                        description: Text(message)
                    )
                    .frame(maxWidth: .infinity, minHeight: 190)
                }
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
            if isSelectionMode {
                if selectedPaths.contains(entry.path) {
                    selectedPaths.remove(entry.path)
                } else {
                    selectedPaths.insert(entry.path)
                }
            } else {
                if entry.isDirectory {
                    openDirectory(entry)
                } else if ["jpg", "jpeg", "png", "gif", "heic", "webp", "pdf", "txt"].contains(entry.fileExtension) {
                    openImage(entry)
                }
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

                if isSelectionMode {
                    Image(
                        systemName: selectedPaths.contains(entry.path)
                        ? "checkmark.circle.fill"
                        : "circle"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        selectedPaths.contains(entry.path)
                        ? .cyan
                        : .white.opacity(0.35)
                    )
                } else if entry.isDirectory {
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
            !isSelectionMode &&
            !entry.isDirectory &&
            !["jpg", "jpeg", "png", "gif", "heic", "webp", "pdf", "txt"].contains(entry.fileExtension)
        )
    }
    // MARK: - Image preview

private func openImage(_ entry: ArchiveEntry) {
    guard let archiveURL else { return }

    let supportedFormats = ["jpg", "jpeg", "png", "gif", "heic", "webp", "pdf", "txt"]

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
        searchText = ""
        searchResults = []

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

            let uniqueStorageDirectory = storageDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)

            try fileManager.createDirectory(
                at: uniqueStorageDirectory,
                withIntermediateDirectories: true
            )

            let copiedURL = uniqueStorageDirectory
                .appendingPathComponent(sourceURL.lastPathComponent)

            try fileManager.copyItem(
                at: sourceURL,
                to: copiedURL
            )

            let newEntries = try archiveService.listContents(
                of: copiedURL
            )


            searchText = ""
            searchResults = []
            isSelectionMode = false
            selectedPaths.removeAll()

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
// MARK: - Archive information

    private func showArchiveInfo() {
        guard let archiveURL else { return }

        do {
            let archive = try Archive(
                url: archiveURL,
                accessMode: .read
            )

            let allEntries = Array(archive)

            let files = allEntries.filter {
                $0.type == .file
            }

            var folders = Set<String>()

            for entry in allEntries {
                let components = entry.path.split(separator: "/")
                var currentPath = ""

                for (index, component) in components.enumerated() {
                    currentPath += (currentPath.isEmpty ? "" : "/")
                        + String(component)

                    if index < components.count - 1 ||
                        entry.type == .directory {
                        folders.insert(currentPath)
                    }
                }
            }

            let attributes = try FileManager.default.attributesOfItem(
                atPath: archiveURL.path
            )

            let archiveSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0

            let totalUncompressedSize = files.reduce(UInt64(0)) {
                $0 + UInt64($1.uncompressedSize)
            }

            archiveInfo = ArchiveInfo(
                archiveSize: archiveSize,
                fileCount: files.count,
                folderCount: folders.count,
                uncompressedSize: totalUncompressedSize
            )


        } catch {
            showError(error)
        }
    }
    // MARK: - Error handling

    private func showError(_ error: Error) {
    if let archiveError = error as? ArchiveServiceError {
        errorMessage = archiveError.description(isEnglish: isEnglish)
    } else {
        errorMessage = error.localizedDescription
    }

    showingError = true
}

// MARK: - Extract archive

private func extractToSelectedFolder(
    _ result: Result<[URL], Error>
) {
    isChoosingDestination = false

    do {
        guard let destinationURL = try result.get().first else {
            return
        }

        beginExtraction(
            to: destinationURL,
            isSelection: false
        )

    } catch {
        showError(error)
    }
}

// MARK: - Extract selected entries

private func extractSelectedToFolder(
    _ result: Result<[URL], Error>
) {
    isChoosingDestination = false
    isExtractingSelection = false

    do {
        guard let destinationURL = try result.get().first else {
            return
        }

        guard !selectedPaths.isEmpty else {
            return
        }

        beginExtraction(
            to: destinationURL,
            isSelection: true
        )

    } catch {
        showError(error)
    }
}

// MARK: - Unified extraction

private func beginExtraction(
    to destinationURL: URL,
    isSelection: Bool
) {

    guard let archiveURL else { return }

    let hasAccess =
        destinationURL.startAccessingSecurityScopedResource()

    defer {
        if hasAccess {
            destinationURL.stopAccessingSecurityScopedResource()
        }
    }

    do {

        let extractionFolder: URL

        if isSelection {

            extractionFolder = try archiveService.extractSelected(
                archiveURL: archiveURL,
                selectedPaths: selectedPaths,
                to: destinationURL,
                folderName: extractionFolderName
            )

        } else {

            extractionFolder = try archiveService.extract(
                archiveURL: archiveURL,
                to: destinationURL,
                folderName: extractionFolderName
            )
        }

        let folderName = extractionFolder.lastPathComponent

        if isSelection {
            selectedPaths.removeAll()
            isSelectionMode = false

            message = tr(
                "Выбранные элементы распакованы в папку \(folderName).",
                "Selected items extracted into \(folderName)."
            )

        } else {

            message = tr(
                "Архив распакован в папку \(folderName).",
                "Archive extracted into \(folderName)."
            )
        }

    } catch {
        showError(error)
    }
}

private func closeArchive() {
    isChoosingDestination = false
    searchText = ""
    searchResults = []

    isSelectionMode = false
    selectedPaths.removeAll()
    isExtractingSelection = false

    archiveURL = nil
    archiveName = tr("Архив не выбран", "No archive selected")
    currentDirectoryPath = ""
    entries = []
    activeGallery = nil
    archiveInfo = nil
    message = tr(
        "Выбери ZIP-архив через кнопку выше.",
        "Choose a ZIP archive using the button above."
    )
}

private var extractionNameSheet: some View {
    ZStack {
        Color(red: 0.035, green: 0.043, blue: 0.075)
            .ignoresSafeArea()

        VStack(alignment: .leading, spacing: 20) {
            Text(tr("Название папки", "Folder name"))
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(
                tr(
                    "Выбери имя папки, в которую будет распакован архив.",
                    "Choose the folder name for the extracted archive."
                )
            )
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.6))

            TextField(
                tr("Название папки", "Folder name"),
                text: $extractionFolderName,
                selection: $extractionFolderNameSelection
            )
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .padding(15)
            .background(
                Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .onAppear {
                extractionFolderNameSelection = .selection(
                    range: extractionFolderName.startIndex..<extractionFolderName.endIndex
                )
            }

            HStack(spacing: 12) {
                Button {
                    shouldChooseDestinationAfterNaming = false
                    isNamingExtractionFolder = false
                } label: {
                    Text(tr("Отмена", "Cancel"))
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 13)
                        )
                }

                Button {
                    let cleanedName = extractionFolderName
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !cleanedName.isEmpty else { return }

                    extractionFolderName = cleanedName
                    shouldChooseDestinationAfterNaming = true
                    isNamingExtractionFolder = false
                } label: {
                    Text(tr("Продолжить", "Continue"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            LinearGradient(
                                colors: [.indigo, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 13)
                        )
                }
            }
        }
        .padding(24)
    }
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
    @State private var isZoomed = false

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
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                Group {
                    if items[selectedIndex].fileExtension == "gif" {
                        ArchiveGIFView(
                            archiveURL: archiveURL,
                            item: items[selectedIndex]
                        )
                    } else if items[selectedIndex].fileExtension == "pdf" {
                        ArchivePDFView(
                            archiveURL: archiveURL,
                            item: items[selectedIndex]
                        )
                    } else if items[selectedIndex].fileExtension == "txt" {
                        ArchiveTextView(
                            archiveURL: archiveURL,
                            item: items[selectedIndex],
                            isEnglish: isEnglish
                        )
                    } else {
                        ArchiveImagePage(
                            archiveURL: archiveURL,
                            item: items[selectedIndex],
                            isZoomed: $isZoomed
                        )
                    }
                }

                .id(selectedIndex)
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            // Увеличено фото — перелистывание запрещено
                            guard !isZoomed else { return }

                            let horizontal = value.translation.width
                            let vertical = value.translation.height

                            // Реагируем только на горизонтальный свайп
                            guard abs(horizontal) > 50,
                                abs(horizontal) > abs(vertical) else {
                                return
                            }

                            withAnimation(.easeInOut(duration: 0.2)) {
                                if horizontal < 0,
                                selectedIndex < items.count - 1 {
                                    selectedIndex += 1
                                } else if horizontal > 0,
                                        selectedIndex > 0 {
                                    selectedIndex -= 1
                                }
                            }
                        }
                )
                .onChange(of: selectedIndex) { _, _ in
                    isZoomed = false
                }

                VStack {
                    HStack {
                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text(
                        "\(selectedIndex + 1) / \(items.count)"
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, geometry.safeAreaInsets.top + 8)
                .padding(.bottom, geometry.safeAreaInsets.bottom + 12)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }
}




private struct ArchiveImagePage: View {

    let archiveURL: URL
    let item: ArchiveImage
    @Binding var isZoomed: Bool

    @State private var image: UIImage?

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let image {
                    let fittedSize = fittedImageSize(
                        image: image.size,
                        container: geometry.size
                    )

                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .scaleEffect(scale)
                        .offset(offset)
                        .contentShape(Rectangle())

                        // Увеличение двумя пальцами
                        .simultaneousGesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    let newScale = min(
                                        max(
                                            lastScale * value.magnification,
                                            1
                                        ),
                                        5
                                    )

                                    let anchor = CGPoint(
                                        x: value.startAnchor.x * geometry.size.width,
                                        y: value.startAnchor.y * geometry.size.height
                                    )

                                    let center = CGPoint(
                                        x: geometry.size.width / 2,
                                        y: geometry.size.height / 2
                                    )

                                    let ratio = newScale / lastScale

                                    let newOffset = CGSize(
                                        width: (anchor.x - center.x)
                                            - ((anchor.x - center.x - lastOffset.width) * ratio),
                                        height: (anchor.y - center.y)
                                            - ((anchor.y - center.y - lastOffset.height) * ratio)
                                    )

                                    scale = newScale
                                    isZoomed = newScale > 1

                                    if newScale <= 1 {
                                        offset = .zero
                                    } else {
                                        offset = limitedOffset(
                                            newOffset,
                                            scale: newScale,
                                            imageSize: fittedSize,
                                            containerSize: geometry.size
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    lastOffset = offset
                                }
                        )

                        // Перемещение увеличенного изображения
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { value in
                                    guard scale > 1 else { return }

                                    let newOffset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )

                                    offset = limitedOffset(
                                        newOffset,
                                        scale: scale,
                                        imageSize: fittedSize,
                                        containerSize: geometry.size
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )

                        // Двойное нажатие по выбранной области
                        .onTapGesture(count: 2) { location in
                            withAnimation(.spring(response: 0.3)) {
                                if scale > 1 {
                                    scale = 1
                                    lastScale = 1
                                    offset = .zero
                                    lastOffset = .zero
                                    isZoomed = false
                                } else {
                                    let newScale: CGFloat = 2.5

                                    let center = CGPoint(
                                        x: geometry.size.width / 2,
                                        y: geometry.size.height / 2
                                    )

                                    let newOffset = CGSize(
                                        width: -(location.x - center.x) * (newScale - 1),
                                        height: -(location.y - center.y) * (newScale - 1)
                                    )

                                    scale = newScale
                                    lastScale = newScale
                                    isZoomed = true

                                    offset = limitedOffset(
                                        newOffset,
                                        scale: newScale,
                                        imageSize: fittedSize,
                                        containerSize: geometry.size
                                    )

                                    lastOffset = offset
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
            offset = .zero
            lastOffset = .zero
            loadImage()
        }
    }

    private func fittedImageSize(
        image: CGSize,
        container: CGSize
    ) -> CGSize {
        guard image.width > 0, image.height > 0 else {
            return container
        }

        let ratio = min(
            container.width / image.width,
            container.height / image.height
        )

        return CGSize(
            width: image.width * ratio,
            height: image.height * ratio
        )
    }

    private func limitedOffset(
        _ proposed: CGSize,
        scale: CGFloat,
        imageSize: CGSize,
        containerSize: CGSize
    ) -> CGSize {
        let maxX = max(
            0,
            (imageSize.width * scale - containerSize.width) / 2
        )

        let maxY = max(
            0,
            (imageSize.height * scale - containerSize.height) / 2
        )

        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
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
            print("Image loading error: \(error)")
        }
    }
}

private struct ArchiveGIFView: UIViewRepresentable {

    let archiveURL: URL
    let item: ArchiveImage

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedPath != item.path else {
            return
        }

        context.coordinator.loadedPath = item.path

        do {
            let archive = try Archive(
                url: archiveURL,
                accessMode: .read
            )

            guard let entry = archive.first(where: {
                $0.path == item.path
            }), entry.type == .file else {
                return
            }

            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("gif")

            try archive.extract(entry, to: temporaryURL)

            let data = try Data(contentsOf: temporaryURL)
            try? FileManager.default.removeItem(at: temporaryURL)

            let base64 = data.base64EncodedString()

            let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport"
                content="width=device-width, initial-scale=1.0,
                maximum-scale=1.0, user-scalable=no">
                <style>
                    html, body {
                        margin: 0;
                        padding: 0;
                        width: 100%;
                        height: 100%;
                        background: black;
                        overflow: hidden;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                    }

                    img {
                        max-width: 100%;
                        max-height: 100%;
                        object-fit: contain;
                    }
                </style>
            </head>
            <body>
                <img src="data:image/gif;base64,\(base64)">
            </body>
            </html>
            """

            webView.loadHTMLString(html, baseURL: nil)

        } catch {
            context.coordinator.loadedPath = nil
            print("GIF loading error: \(error)")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var loadedPath: String?
    }
}

private struct ArchivePDFView: UIViewRepresentable {

    let archiveURL: URL
    let item: ArchiveImage

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()

        pdfView.backgroundColor = .black
        pdfView.documentView?.backgroundColor = .black

        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.usePageViewController(false)

        pdfView.minScaleFactor = 0.5
        pdfView.maxScaleFactor = 5.0

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        guard context.coordinator.loadedPath != item.path else {
            return
        }

        context.coordinator.loadedPath = item.path

        do {
            let archive = try Archive(
                url: archiveURL,
                accessMode: .read
            )

            guard let entry = archive.first(where: {
                $0.path == item.path
            }), entry.type == .file else {
                return
            }

            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("pdf")

            try archive.extract(entry, to: temporaryURL)

            defer {
                try? FileManager.default.removeItem(at: temporaryURL)
            }

            let data = try Data(contentsOf: temporaryURL)

            guard let document = PDFDocument(data: data) else {
                return
            }

            pdfView.document = document
            pdfView.goToFirstPage(nil)

        } catch {
            context.coordinator.loadedPath = nil
            print("PDF loading error: \(error)")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var loadedPath: String?
    }
}

private struct ArchiveTextView: View {

    let archiveURL: URL
    let item: ArchiveImage
    let isEnglish: Bool

    @State private var text = ""
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if loadFailed {
                Text(
                    isEnglish
                    ? "Unable to read this file."
                    : "Не удалось прочитать этот файл."
                )
                .foregroundStyle(.white.opacity(0.7))
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 75)
                        .padding(.bottom, 85)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task(id: item.id) {
            loadText()
        }
    }

    private func loadText() {
        do {
            let archive = try Archive(
                url: archiveURL,
                accessMode: .read
            )

            guard let entry = archive.first(where: {
                $0.path == item.path
            }), entry.type == .file else {
                loadFailed = true
                return
            }

            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("txt")

            try archive.extract(entry, to: temporaryURL)

            defer {
                try? FileManager.default.removeItem(at: temporaryURL)
            }

            let data = try Data(contentsOf: temporaryURL)

            if let decodedText =
                String(data: data, encoding: .utf8) ??
                String(data: data, encoding: .utf16) ??
                String(data: data, encoding: .windowsCP1251) {

                text = decodedText
                    .replacingOccurrences(of: "\u{FEFF}", with: "")
            } else {
                loadFailed = true
            }

        } catch {
            loadFailed = true
            print("TXT loading error: \(error)")
        }
    }
}

private struct ArchiveInfo: Identifiable {
    let id = UUID()

    let archiveSize: UInt64
    let fileCount: Int
    let folderCount: Int
    let uncompressedSize: UInt64
}

private struct ArchiveInfoView: View {

    let info: ArchiveInfo
    let isEnglish: Bool

    @Environment(\.dismiss) private var dismiss

    private func tr(_ ru: String, _ en: String) -> String {
        isEnglish ? en : ru
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(bytes),
            countStyle: .file
        )
    }

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.043, blue: 0.075)
                .ignoresSafeArea()

            VStack(spacing: 22) {

                HStack {
                    Label(
                        tr("Информация об архиве", "Archive information"),
                        systemImage: "info.circle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.white)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 18) {

                    infoRow(
                        tr("Размер архива", "Archive size"),
                        value: formatSize(info.archiveSize),
                        icon: "doc.zipper"
                    )

                    infoRow(
                        tr("Всего файлов", "Total files"),
                        value: "\(info.fileCount)",
                        icon: "doc"
                    )

                    infoRow(
                        tr("Количество папок", "Total folders"),
                        value: "\(info.folderCount)",
                        icon: "folder"
                    )

                    infoRow(
                        tr("Размер содержимого", "Uncompressed size"),
                        value: formatSize(info.uncompressedSize),
                        icon: "externaldrive"
                    )
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private func infoRow(
        _ title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(.cyan)
                .frame(width: 28)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }
}

