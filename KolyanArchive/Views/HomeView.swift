
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ZIPFoundation
import LibArchive
import WebKit
import PDFKit
import QuickLook

private enum ArchiveSortOption: Equatable {
    case nameAscending
    case nameDescending
    case sizeDescending
    case sizeAscending
}

struct HomeView: View {

    private struct ArchiveNavigationState {
        let archiveURL: URL
        let archiveName: String
        let currentDirectoryPath: String
        let entries: [ArchiveEntry]
        let searchText: String
        let searchResults: [ArchiveEntry]
        let selectedPaths: Set<String>
        let isSelectionMode: Bool
        let isSelectionConfirmed: Bool

    }

    @State private var archiveNavigationStack: [ArchiveNavigationState] = []

    @Environment(\.scenePhase) private var scenePhase

    @State private var isImporterPresented = false
    @State private var selectedArchiveFormat = "zip"
    @State private var isChoosingDestination = false
    @State private var isSelectionMode = false
    @State private var isSelectionConfirmed = false
    @State private var selectedPaths: Set<String> = []
    @State private var isExtractingSelection = false
    @State private var archiveInfo: ArchiveInfo?
    @State private var selectedEntryInfo: EntryInfo?
    @State private var sortOption: ArchiveSortOption = .nameAscending

    @AppStorage("isEnglish") private var isEnglish = false
    init() {
        let english = UserDefaults.standard.bool(forKey: "isEnglish")

        _archiveName = State(
            initialValue: english ? "No archive selected" : "Архив не выбран"
        )

        _message = State(
            initialValue: english
                ? "Choose a ZIP archive using the button above."
                : "Выбери ZIP-архив через кнопку выше."
        )
    }

    @State private var archiveName = ""
    @State private var archiveURL: URL?
    
    @State private var isArchiveOperationInProgress = false
    @State private var archiveOperationProgress = 0.0
    @State private var archiveOperationTitle = ""
    @State private var archiveOperationSuccessMessage: String? = nil
    @State private var archiveOperationSuccessID = UUID()
    @StateObject private var progressTracker = ArchiveProgressTracker()

    @State private var backgroundEnteredAt: Date? = nil

    @State private var isNamingExtractionFolder = false
    @State private var extractionFolderName = ""
    @State private var extractionNameFocusRequest = UUID()
    @State private var pendingExtractionIsSelection = false
    @State private var shouldChooseDestinationAfterNaming = false

    @State private var currentDirectoryPath = ""
    @State private var entries: [ArchiveEntry] = []
    @State private var searchText = ""
    @State private var searchResults: [ArchiveEntry] = []
    @State private var activeGallery: GalleryPresentation?

    @State private var message = ""

    @State private var errorMessage = ""
    @State private var showingError = false
    
    // Создание ZIP-архива
    
    @State private var isCreatingZIPPreview = false
    @State private var isZIPFilesImporterPresented = false
    @State private var isZIPFolderImporterPresented = false
    @State private var isZIPDestinationImporterPresented = false
    @State private var selectedZIPFiles: [URL] = []
    @State private var isNamingZIP = false
    @State private var zipArchiveName = ""
    @State private var zipNameFocusRequest = UUID()


    private let archiveService = ZIPArchiveService()
    private let rarArchiveService = RARArchiveService()
    private let isoArchiveService = ISOArchiveService()

    private var isRARArchive: Bool {
        archiveURL?.pathExtension.lowercased() == "rar"
    }
    private var isISOArchive: Bool {
    archiveURL?.pathExtension.lowercased() == "iso"
    }

    private var selectedArchiveContentTypes: [UTType] {
        switch selectedArchiveFormat {
        case "rar":
            return [UTType(filenameExtension: "rar") ?? .data]
        case "iso":
            return [UTType(filenameExtension: "iso") ?? .data]
        default:
            return [.zip]
        }
    }
    
    private func tr(_ ru: String, _ en: String) -> String {
        isEnglish ? en : ru
    }
    private var isSearching: Bool {
        !searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    private var displayedEntries: [ArchiveEntry] {
        let source = isSearching ? searchResults : entries

        return source.sorted { first, second in

            // Папки всегда выше файлов
            if first.isDirectory != second.isDirectory {
                return first.isDirectory
            }

            // Папки всегда сортируются по имени
            if first.isDirectory && second.isDirectory {
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            }

            // Сортировка файлов
            switch sortOption {

            case .nameAscending:
                return first.name.localizedStandardCompare(second.name) == .orderedAscending

            case .nameDescending:
                return first.name.localizedStandardCompare(second.name) == .orderedDescending

            case .sizeDescending:
                if first.sizeInBytes == second.sizeInBytes {
                    return first.name.localizedStandardCompare(second.name) == .orderedAscending
                }
                return first.sizeInBytes > second.sizeInBytes

            case .sizeAscending:
                if first.sizeInBytes == second.sizeInBytes {
                    return first.name.localizedStandardCompare(second.name) == .orderedAscending
                }
                return first.sizeInBytes < second.sizeInBytes
            }
        }
    }
 
var body: some View {
    NavigationStack {
        AnyView(
            ZStack {
            Color(red: 0.035, green: 0.043, blue: 0.075)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if archiveURL == nil {
                        openArchiveButtons
                    }

                    if archiveURL != nil {
                        extractArchiveButton

                        if isSelectionConfirmed && !selectedPaths.isEmpty {
                            selectedExtractButton
                        }
                    }

                    if isArchiveOperationInProgress ||
                        archiveOperationSuccessMessage != nil {
                        archiveProgressView
                    }

                    archiveContents
                    featureCards

                    Text("Kolyan Tech. LTD")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
                .animation(.easeInOut(duration: 0.25), value: archiveURL)
            }
            
        zipCreationPreview
        }
        )
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: isChoosingDestination ? [.folder] : selectedArchiveContentTypes,
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

        .fileImporter(
            isPresented: $isZIPFilesImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    if !selectedZIPFiles.contains(where: {
                        $0.standardizedFileURL.path == url.standardizedFileURL.path
                    }) {
                        selectedZIPFiles.append(url)
                    }
                }
            case .failure(let error):
                showError(error)
            }
        }
        .fileImporter(
            isPresented: $isZIPFolderImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let folderURL = urls.first else { return }

                if !selectedZIPFiles.contains(where: {
                    $0.standardizedFileURL.path ==
                    folderURL.standardizedFileURL.path
                }) {
                    selectedZIPFiles.append(folderURL)
                }

            case .failure(let error):
                showError(error)
            }
        }

        .fileImporter(
            isPresented: $isZIPDestinationImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let destinationURL = urls.first else { return }
                createZIPArchive(at: destinationURL)

            case .failure(let error):
                showError(error)
            }
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
                entryInfo: nil,
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
        .sheet(isPresented: $isNamingZIP) {
            zipNameSheet
                .presentationDetents([.height(290)])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        }
    .tint(.white)
    .onChange(of: progressTracker.progressValue) { _, newValue in
        withAnimation(.easeInOut(duration: 0.2)) {
            archiveOperationProgress = newValue
        }
    }
    
    .onChange(of: scenePhase) { _, newPhase in

        if newPhase == .inactive {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }

        if newPhase == .background {
            backgroundEnteredAt = Date()

            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }

        if newPhase == .active,
        let backgroundDate = backgroundEnteredAt {

            let elapsedTime = Date().timeIntervalSince(backgroundDate)

            backgroundEnteredAt = nil

            if elapsedTime >= 30 {
                closeArchive()
                // Здесь подключим запуск существующей заставки.
            }
        }
    }
}

@ViewBuilder
private var zipCreationPreview: some View {
    if isCreatingZIPPreview {
        Color.black.opacity(0.75)
            .ignoresSafeArea()

        VStack(spacing: 18) {
            HStack {
                Text(tr("Создание ZIP", "Create ZIP"))
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    isCreatingZIPPreview = false
                    selectedZIPFiles = []
                    zipArchiveName = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 27))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if selectedZIPFiles.isEmpty {
                Text(
                    tr(
                        "Добавь файлы или папки для архива",
                        "Add files or folders to the archive"
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(selectedZIPFiles, id: \.path) { url in
                            zipSourceRow(url)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    isZIPFilesImporterPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus")
                        Text(tr("Добавить файлы", "Add files"))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        .white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    isZIPFolderImporterPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                        Text(tr("Добавить папку", "Add folder"))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        .white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                guard !selectedZIPFiles.isEmpty else { return }
                isNamingZIP = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.zipper")
                    Text(tr(
                        "Продолжить создание ZIP",
                        "Continue creating ZIP"
                    ))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    selectedZIPFiles.isEmpty
                        ? Color.white.opacity(0.05)
                        : Color.blue.opacity(0.75),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedZIPFiles.isEmpty)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: 520)
        .background(
            Color(red: 0.07, green: 0.08, blue: 0.13),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .padding(20)
        .transition(.scale.combined(with: .opacity))
        .zIndex(10)
    }
}

private func zipSourceRow(_ url: URL) -> some View {
    let isDirectory = (
        try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
    ) ?? false

    return HStack(spacing: 12) {
        Image(systemName: isDirectory ? "folder.fill" : "doc.fill")
            .font(.system(size: 22))
            .foregroundStyle(.white.opacity(0.8))

        Text(url.lastPathComponent)
            .font(.subheadline)
            .foregroundStyle(.white)
            .lineLimit(1)

        Spacer()

        Button {
            selectedZIPFiles.removeAll {
                $0.standardizedFileURL.path ==
                url.standardizedFileURL.path
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.45))
        }
        .buttonStyle(.plain)
    }
    .padding(12)
    .background(
        .white.opacity(0.05),
        in: RoundedRectangle(cornerRadius: 12)
    )
}

    private var archiveFolderDefaultName: String {
        guard archiveURL != nil else { return "" }

        return URL(fileURLWithPath: archiveName)
            .deletingPathExtension()
            .lastPathComponent
    }
    
    private var archiveProgressView: some View {

        Group {

            if let successMessage = archiveOperationSuccessMessage {

                HStack(spacing: 12) {

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            Color(red: 0.30, green: 0.85, blue: 0.58)
                        )

                    Text(successMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .transition(.opacity.combined(with: .move(edge: .top)))

            } else {

                VStack(alignment: .leading, spacing: 12) {

                    HStack {
                        Text(archiveOperationTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))

                        Spacer()

                        Text("\(Int(max(0, min(1, archiveOperationProgress)) * 100))%")
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.10))

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.35, green: 0.65, blue: 1.0),
                                            Color(red: 0.45, green: 0.45, blue: 1.0)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: geometry.size.width
                                        * max(0, min(1, archiveOperationProgress))
                                )
                        }
                    }
                    .frame(height: 7)
                }
                .padding(16)
                .background(.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: archiveOperationProgress)
        .animation(.easeInOut(duration: 0.25), value: archiveOperationSuccessMessage)
    }
    
    private func showArchiveOperationSuccess(_ message: String) {

        let notificationID = UUID()

        archiveOperationSuccessID = notificationID

        withAnimation(.easeInOut(duration: 0.25)) {
            archiveOperationSuccessMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {

            guard archiveOperationSuccessID == notificationID else {
                return
            }

            withAnimation(.easeInOut(duration: 0.25)) {
                archiveOperationSuccessMessage = nil
            }
        }
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

    private var openArchiveButtons: some View {
        VStack(spacing: 10) {
            archiveOpenButton(
                title: "ZIP",
                subtitle: tr("Открыть ZIP-архив", "Open ZIP archive"),
                icon: "doc.zipper",
                format: "zip",
                colors: [.indigo, .blue]
            )

            archiveOpenButton(
                title: "RAR",
                subtitle: tr("Открыть RAR-архив", "Open RAR archive"),
                icon: "archivebox",
                format: "rar",
                colors: [.orange, .red]
            )

            archiveOpenButton(
                title: "ISO",
                subtitle: tr("Открыть ISO-образ", "Open ISO image"),
                icon: "opticaldisc",
                format: "iso",
                colors: [.cyan, .blue]
            )
        }
    }

    private func archiveOpenButton(
        title: String,
        subtitle: String,
        icon: String,
        format: String,
        colors: [Color]
    ) -> some View {
        Button {
            selectedArchiveFormat = format
            isImporterPresented = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)

                    Text(subtitle)
                        .font(.caption)
                        .opacity(0.8)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: colors,
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
            extractionNameFocusRequest = UUID()
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
        .disabled(isArchiveOperationInProgress)
        .buttonStyle(.plain)
    }

    private var selectedExtractButton: some View {
        Button {
            isExtractingSelection = true
            pendingExtractionIsSelection = true

            extractionFolderName = archiveFolderDefaultName
            extractionNameFocusRequest = UUID()
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
        .disabled(isArchiveOperationInProgress)
        .buttonStyle(.plain)
    }

    // MARK: - Archive contents

    private var archiveContents: some View {
        VStack(alignment: .leading, spacing: 14) {

            
            VStack(spacing: 10) {

                // Первая строка: навигация и значки
                HStack(spacing: 8) {

                    if !currentDirectoryPath.isEmpty || !archiveNavigationStack.isEmpty {
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

                    if isSelectionMode {
                        HStack(spacing: 9) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.cyan)

                            Text(tr("Выбор файлов", "Select files"))
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    } else {
                        Text(archiveName)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Spacer(minLength: 4)

                    if archiveURL != nil {

                        if !isSelectionMode {
                            Button {
                                isSelectionConfirmed = false
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

                // Вторая строка: кнопки режима выбора

                if archiveURL != nil && isSelectionMode {
                    HStack(spacing: 16) {

                        if !isSearching {
                            Button {
                                let pathsToSelect = displayedEntries
                                    .filter {
                                        !isInsideSelectedFolder($0.path)
                                    }
                                    .map { $0.path }

                                selectedPaths.formUnion(pathsToSelect)

                            } label: {
                                Text(tr("Выбрать всё", "Select all"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Color.white.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            }
                        }

                        Button {
                            selectedPaths.subtract(
                                displayedEntries.map { $0.path }
                            )
                        } label: {
                            Text(tr("Снять всё", "Clear all"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Color.white.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        }

                        Button {
                            isSelectionMode = false
                            isSelectionConfirmed = true
                        } label: {
                            Text(tr("Готово", "Done"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.cyan)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Color.white.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            if archiveURL != nil {
                HStack(spacing: 8) {
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

                    
                    Menu {
                        Button {
                            sortOption = .nameAscending
                        } label: {
                            HStack {
                                Text(tr("Имя: А–Я", "Name: A–Z"))                            

                                Spacer()

                                if sortOption == .nameAscending {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.cyan)
                                }
                            }
                        }

                        Button {
                            sortOption = .nameDescending
                        } label: {
                            HStack {
                                Text(tr("Имя: Я–А", "Name: Z–A"))                                

                                Spacer()

                                if sortOption == .nameDescending {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.cyan)
                                }
                            }
                        }

                        Button {
                            sortOption = .sizeDescending
                        } label: {
                            HStack {
                                Text(tr("Размер: сначала большие", "Size: largest first"))
                                
                                Spacer()

                                if sortOption == .sizeDescending {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.cyan)
                                }
                            }
                        }

                        Button {
                            sortOption = .sizeAscending
                        } label: {
                            HStack {
                                Text(tr("Размер: сначала маленькие", "Size: smallest first"))

                                Spacer()

                                if sortOption == .sizeAscending {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.cyan)
                                }
                            }
                        }

                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.cyan)
                            .frame(width: 46, height: 46)
                            .background(
                                Color.white.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 13)
                            )
                    }
                }
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

    // MARK: - Archive reading

    private func listArchiveContents(
        of url: URL,
        in directoryPath: String = ""
    ) throws -> [ArchiveEntry] {

        let fileExtension = url.pathExtension.lowercased()

        if fileExtension == "rar" {
            return try rarArchiveService.listContents(
                of: url,
                in: directoryPath
            )
        }

        if fileExtension == "iso" {
            return try isoArchiveService.listContents(
                of: url,
                in: directoryPath
            )
        }

        return try archiveService.listContents(
            of: url,
            in: directoryPath
        )
    }

    private func searchArchiveContents(
        of url: URL,
        matching query: String
    ) throws -> [ArchiveEntry] {

        let fileExtension = url.pathExtension.lowercased()

        if fileExtension == "rar" {
            return try rarArchiveService.searchContents(
                of: url,
                matching: query
            )
        }

        if fileExtension == "iso" {
            return try isoArchiveService.searchContents(
                of: url,
                matching: query
            )
        }

        return try archiveService.searchContents(
            of: url,
            matching: query
        )
    }

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
            searchResults = try searchArchiveContents(
                of: archiveURL,
                matching: trimmedQuery
            )
        } catch {
            showError(error)
        }
    }

    // MARK: - Entry row

private func isInsideSelectedFolder(_ path: String) -> Bool {
    selectedPaths.contains { selectedPath in
        path.hasPrefix(selectedPath + "/")
    }
}
private func archiveEntryRow(_ entry: ArchiveEntry) -> some View {

    let isCovered = isInsideSelectedFolder(entry.path)
    let isSelected = selectedPaths.contains(entry.path) || isCovered

    let previewableFormats = [
        "jpg", "jpeg", "png", "gif",
        "heic", "webp", "pdf", "txt",
        "rtf", "html", "htm",
        "docx", "xlsx", "pptx"
    ]

    let isPreviewable = previewableFormats.contains(entry.fileExtension)
    let isNestedArchive = ["zip", "rar", "iso"].contains(
        entry.fileExtension.lowercased()
    )

    return HStack(spacing: 12) {

        Button {
            if entry.isDirectory {
                openDirectory(entry)

            } else if isSelectionMode {
                guard !isCovered else { return }

                if selectedPaths.contains(entry.path) {
                    selectedPaths.remove(entry.path)
                } else {
                    selectedPaths.insert(entry.path)
                }

            } else if isNestedArchive {
                openNestedArchive(entry)

            } else if isPreviewable {
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

                    Text(
                        entry.isDirectory
                            ? tr("Папка", "Folder")
                            : entry.sizeDescription
                    )
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.35))

                } else if isSelectionMode {

                    Image(
                        systemName: isSelected
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        isCovered
                            ? .cyan.opacity(0.4)
                            : isSelected
                                ? .cyan
                                : .white.opacity(0.35)
                    )

                    if isCovered {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(
            !entry.isDirectory &&
            (
                isSelectionMode
                    ? isCovered
                    : !(isPreviewable || isNestedArchive)
            )
        )

        // Отдельная галочка для выбора целой папки
        if entry.isDirectory && isSelectionMode {

            Button {
                if selectedPaths.contains(entry.path) {
                    selectedPaths.remove(entry.path)
                } else if !isCovered {
                    selectedPaths.insert(entry.path)
                }

            } label: {

                HStack(spacing: 5) {

                    Image(
                        systemName: isSelected
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        isCovered
                            ? .cyan.opacity(0.4)
                            : isSelected
                                ? .cyan
                                : .white.opacity(0.35)
                    )

                    if isCovered {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .frame(minWidth: 30, minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCovered)
        }

        // Кнопка информации о файле или папке

        Button {
            showEntryInfo(entry)
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 19))
                .foregroundStyle(.cyan.opacity(0.85))
                .frame(width: 36, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(item: $selectedEntryInfo) { info in
            ArchiveInfoView(
                info: nil,
                entryInfo: info,
                isEnglish: isEnglish
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
    }
    .padding(.vertical, 2)
}

    // MARK: - Image preview

private func openImage(_ entry: ArchiveEntry) {
    guard let archiveURL else { return }

    let supportedFormats = ["jpg", "jpeg", "png", "gif", "heic", "webp", "pdf", "txt", "rtf", "html", "htm", "docx", "xlsx", "pptx"]

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

    private func openNestedArchive(_ entry: ArchiveEntry) {

        guard let parentURL = archiveURL else { return }

        let fileExtension = entry.fileExtension.lowercased()

        guard ["zip", "rar", "iso"].contains(fileExtension) else {
            return
        }

        guard archiveNavigationStack.count < 10 else {
            errorMessage = tr(
                "Превышена максимальная глубина вложенности архивов.",
                "Maximum nested archive depth reached."
            )
            showingError = true
            return
        }

        do {
            let nestedURL: URL

            switch parentURL.pathExtension.lowercased() {

            case "zip":
                nestedURL = try archiveService.extractPreviewFile(
                    archiveURL: parentURL,
                    path: entry.path
                )

            case "rar":
                nestedURL = try rarArchiveService.extractPreviewFile(
                    archiveURL: parentURL,
                    path: entry.path
                )

            case "iso":
                nestedURL = try isoArchiveService.extractPreviewFile(
                    archiveURL: parentURL,
                    path: entry.path
                )

            default:
                return
            }

            let nestedEntries = try listArchiveContents(
                of: nestedURL,
                in: ""
            )

            archiveNavigationStack.append(
                ArchiveNavigationState(
                    archiveURL: parentURL,
                    archiveName: archiveName,
                    currentDirectoryPath: currentDirectoryPath,
                    entries: entries,
                    searchText: searchText,
                    searchResults: searchResults,
                    selectedPaths: selectedPaths,
                    isSelectionMode: isSelectionMode,
                    isSelectionConfirmed: isSelectionConfirmed
                )
            )

            archiveURL = nestedURL
            archiveName = entry.name
            currentDirectoryPath = ""
            entries = nestedEntries
            searchText = ""
            searchResults = []
            selectedPaths = []
            isSelectionMode = false
            isSelectionConfirmed = false

        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func openDirectory(_ entry: ArchiveEntry) {
        guard let archiveURL else { return }
        searchText = ""
        searchResults = []

        do {
            currentDirectoryPath = entry.path

            entries = try listArchiveContents(
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

        // Если мы находимся внутри папки — возвращаемся на уровень выше.
        if !currentDirectoryPath.isEmpty {

            searchText = ""
            searchResults = []

            let components = currentDirectoryPath.split(separator: "/")

            currentDirectoryPath = components
                .dropLast()
                .joined(separator: "/")

            guard let archiveURL else { return }

            do {
                entries = try listArchiveContents(
                    of: archiveURL,
                    in: currentDirectoryPath
                )

                message = entries.isEmpty
                    ? tr("Эта папка пуста.", "This folder is empty.")
                    : ""

            } catch {
                showError(error)
            }

            return
        }

        // Если мы в корне вложенного архива — возвращаемся к родительскому.
        guard let previous = archiveNavigationStack.popLast() else {
            return
        }

        archiveURL = previous.archiveURL
        archiveName = previous.archiveName
        currentDirectoryPath = previous.currentDirectoryPath
        entries = previous.entries
        searchText = previous.searchText
        searchResults = previous.searchResults
        selectedPaths = previous.selectedPaths
        isSelectionMode = previous.isSelectionMode
        isSelectionConfirmed = previous.isSelectionConfirmed

        message = ""
    }

    // MARK: - Feature cards

    private var featureCards: some View {
        HStack(spacing: 12) {
            featureCard(
                tr("Создать ZIP", "Create ZIP"),
                detail: tr(
                    "Создание ZIP-архивов",
                    "Create ZIP archives"
                ),
                symbol: "doc.zipper"
            ) {
                selectedZIPFiles = []
                zipArchiveName = ""
                isCreatingZIPPreview = true
            }

            featureCard(
                tr("Создать ISO", "Create ISO"),
                detail: tr(
                    "Создание ISO-образов",
                    "Create ISO images"
                ),
                symbol: "opticaldisc"
            ) {
                showError(
                    NSError(
                        domain: "KolyanArchive",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: tr(
                                "Создание ISO появится в следующем обновлении.",
                                "ISO creation will be available in a future update."
                            )
                        ]
                    )
                )
            }
        }
    }

    private func featureCard(
        _ title: String,
        detail: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        .disabled(isArchiveOperationInProgress)
        .buttonStyle(.plain)
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

            let newEntries = try listArchiveContents(
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

            var fileCount = 0
            var folders = Set<String>()
            var totalUncompressedSize: UInt64 = 0

            if isRARArchive || isISOArchive {

                // Получаем информацию из RAR через LibArchive
                let reader = ArchiveReader()
                let allEntries = try reader.entries(at: archiveURL)

                for entry in allEntries {

                    let path = entry.path.trimmingCharacters(
                        in: CharacterSet(charactersIn: "/")
                    )

                    guard !path.isEmpty else { continue }

                    let components = path.split(separator: "/")

                    let isDirectory =
                        String(describing: entry.fileType)
                            .lowercased()
                            .contains("directory")

                    // Учитываем вложенные папки
                    if components.count > 1 {
                        for index in 1..<components.count {
                            let folderPath = components
                                .prefix(index)
                                .joined(separator: "/")

                            folders.insert(folderPath)
                        }
                    }

                    if isDirectory {
                        folders.insert(path)
                    } else {
                        fileCount += 1
                        totalUncompressedSize += UInt64(entry.size)
                    }
                }

            } else {

                // Существующая логика ZIP через ZIPFoundation
                let archive = try Archive(
                    url: archiveURL,
                    accessMode: .read
                )

                let allEntries = Array(archive)

                let files = allEntries.filter {
                    $0.type == .file
                }

                fileCount = files.count

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

                totalUncompressedSize = files.reduce(UInt64(0)) {
                    $0 + UInt64($1.uncompressedSize)
                }
            }

            // Общий размер самого файла архива
            let attributes = try FileManager.default.attributesOfItem(
                atPath: archiveURL.path
            )

            let archiveSize = (attributes[.size] as? NSNumber)?
                .uint64Value ?? 0

            archiveInfo = ArchiveInfo(
                archiveSize: archiveSize,
                fileCount: fileCount,
                folderCount: folders.count,
                uncompressedSize: totalUncompressedSize
            )

        } catch {
            showError(error)
        }
    }

    private func showEntryInfo(_ selectedEntry: ArchiveEntry) {
        guard let archiveURL else { return }

        do {
            var archiveItems: [
                (path: String, isDirectory: Bool, size: UInt64)
            ] = []

            if isRARArchive || isISOArchive {

                let reader = ArchiveReader()
                let allEntries = try reader.entries(at: archiveURL)

                for item in allEntries {
                    let path = item.path
                        .replacingOccurrences(of: "\\", with: "/")
                        .trimmingCharacters(
                            in: CharacterSet(charactersIn: "/")
                        )

                    guard !path.isEmpty else { continue }

                    let isDirectory =
                        String(describing: item.fileType)
                            .lowercased()
                            .contains("directory")

                    archiveItems.append((
                        path: path,
                        isDirectory: isDirectory,
                        size: isDirectory ? 0 : UInt64(item.size)
                    ))
                }

            } else {

                let archive = try Archive(
                    url: archiveURL,
                    accessMode: .read
                )

                for item in archive {
                    let path = item.path
                        .replacingOccurrences(of: "\\", with: "/")
                        .trimmingCharacters(
                            in: CharacterSet(charactersIn: "/")
                        )

                    guard !path.isEmpty else { continue }

                    let isDirectory = item.type == .directory

                    archiveItems.append((
                        path: path,
                        isDirectory: isDirectory,
                        size: isDirectory ? 0 : item.uncompressedSize
                    ))
                }
            }

            let selectedPath = selectedEntry.path
                .replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(
                    in: CharacterSet(charactersIn: "/")
                )

            if selectedEntry.isDirectory {

                let prefix = selectedPath + "/"

                let descendants = archiveItems.filter {
                    $0.path.hasPrefix(prefix)
                }

                var folders = Set<String>()
                var fileCount = 0
                var totalSize: UInt64 = 0

                for item in descendants {

                    let relativePath = String(
                        item.path.dropFirst(prefix.count)
                    )

                    let components = relativePath.split(separator: "/")

                    if item.isDirectory {
                        folders.insert(item.path)
                    }

                    if components.count > 1 {
                        for index in 1..<components.count {
                            let folderPath = prefix +
                                components.prefix(index).joined(separator: "/")

                            folders.insert(folderPath)
                        }
                    }

                    if !item.isDirectory {
                        fileCount += 1
                        totalSize += item.size
                    }
                }

                selectedEntryInfo = EntryInfo(
                    name: selectedEntry.name,
                    path: selectedEntry.path,
                    fileType: tr("Папка", "Folder"),
                    isDirectory: true,
                    sizeInBytes: totalSize,
                    fileCount: fileCount,
                    folderCount: folders.count
                )

            } else {

                let matchingItem = archiveItems.first {
                    $0.path == selectedPath
                }

                let size = matchingItem?.size
                    ?? UInt64(max(0, selectedEntry.sizeInBytes))

                let fileType = selectedEntry.fileExtension.isEmpty
                    ? tr("Файл", "File")
                    : selectedEntry.fileExtension.uppercased()

                selectedEntryInfo = EntryInfo(
                    name: selectedEntry.name,
                    path: selectedEntry.path,
                    fileType: fileType,
                    isDirectory: false,
                    sizeInBytes: size,
                    fileCount: 0,
                    folderCount: 0
                )
            }

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
    guard !isArchiveOperationInProgress else { return }

    let hasAccess =
        destinationURL.startAccessingSecurityScopedResource()

    let selectedPathsSnapshot = selectedPaths
    let folderName = extractionFolderName

    let operationProgress = Progress(totalUnitCount: 1)

    if isSelection {
        archiveOperationTitle = isISOArchive
            ? tr("Извлечение выбранных файлов…", "Extracting selected files…")
            : tr("Распаковка выбранных файлов…", "Extracting selected files…")
    } else if isISOArchive {
        archiveOperationTitle = tr(
            "Извлечение образа…",
            "Extracting ISO image…"
        )
    } else {
        archiveOperationTitle = tr(
            "Распаковка архива…",
            "Extracting archive…"
        )
    }

    archiveOperationProgress = 0
    isArchiveOperationInProgress = true

    progressTracker.observe(operationProgress)

    let isRAR = isRARArchive
    let isISO = isISOArchive

    let zipService = archiveService
    let rarService = rarArchiveService
    let isoService = isoArchiveService

    DispatchQueue.global(qos: .userInitiated).async {

        let result: Result<URL, Error>

        do {
            let extractionFolder: URL

            if isRAR {

                if isSelection {
                    extractionFolder = try rarService.extractSelected(
                        archiveURL: archiveURL,
                        selectedPaths: selectedPathsSnapshot,
                        to: destinationURL,
                        folderName: folderName,
                        progress: operationProgress
                    )
                } else {
                    extractionFolder = try rarService.extract(
                        archiveURL: archiveURL,
                        to: destinationURL,
                        folderName: folderName,
                        progress: operationProgress
                    )
                }

            } else if isISO {

                if isSelection {
                    extractionFolder = try isoService.extractSelected(
                        archiveURL: archiveURL,
                        selectedPaths: selectedPathsSnapshot,
                        to: destinationURL,
                        folderName: folderName,
                        progress: operationProgress
                    )
                } else {
                    extractionFolder = try isoService.extract(
                        archiveURL: archiveURL,
                        to: destinationURL,
                        folderName: folderName,
                        progress: operationProgress
                    )
                }

            } else {

                if isSelection {
                    extractionFolder = try zipService.extractSelected(
                        archiveURL: archiveURL,
                        selectedPaths: selectedPathsSnapshot,
                        to: destinationURL,
                        folderName: folderName,
                        progress: operationProgress
                    )
                } else {
                    extractionFolder = try zipService.extract(
                        archiveURL: archiveURL,
                        to: destinationURL,
                        folderName: folderName,
                        progress: operationProgress
                    )
                }
            }

            result = .success(extractionFolder)

        } catch {
            result = .failure(error)
        }

        if hasAccess {
            destinationURL.stopAccessingSecurityScopedResource()
        }

        DispatchQueue.main.async {

            isArchiveOperationInProgress = false
            progressTracker.stop()
            archiveOperationProgress = 0

            switch result {

            case .success(let extractionFolder):

                let extractedFolderName =
                    extractionFolder.lastPathComponent
                    showArchiveOperationSuccess(
                        tr(
                            isSelection
                                ? "Выбранные файлы из \(archiveName) распакованы успешно!"
                                : "\(archiveName) распакован успешно!",
                            isSelection
                                ? "Selected files from \(archiveName) extracted successfully!"
                                : "\(archiveName) extracted successfully!"
                        )
                    )

                if isSelection {
                    selectedPaths.removeAll()
                    isSelectionConfirmed = false
                    isSelectionMode = false

                    message = tr(
                        "Выбранные элементы распакованы в папку \(extractedFolderName).",
                        "Selected items extracted into \(extractedFolderName)."
                    )

                } else {

                    message = tr(
                        "Архив распакован в папку \(extractedFolderName).",
                        "Archive extracted into \(extractedFolderName)."
                    )
                    
                    closeArchive()
                }

            case .failure(let error):
                showError(error)
            }
        }
    }
}

private func closeArchive() {
    isChoosingDestination = false
    searchText = ""
    searchResults = []

    archiveNavigationStack.removeAll()

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

private func createZIPArchive(at destinationFolderURL: URL) {

    guard !isArchiveOperationInProgress else { return }

    let cleanName = zipArchiveName
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !cleanName.isEmpty,
          cleanName != ".",
          cleanName != "..",
          !cleanName.contains("/"),
          !cleanName.contains("\\"),
          !cleanName.contains(":"),
          !cleanName.contains("\0") else {
        showError(
            ArchiveServiceError.unsafeArchivePath(cleanName)
        )
        return
    }

    let fileName = cleanName.lowercased().hasSuffix(".zip")
        ? cleanName
        : cleanName + ".zip"

    let outputURL = destinationFolderURL
        .appendingPathComponent(fileName)

    let sourceFiles = selectedZIPFiles
    let zipService = archiveService

    let hasAccess = destinationFolderURL
        .startAccessingSecurityScopedResource()

    let operationProgress = Progress(totalUnitCount: 1)

    archiveOperationTitle = tr(
        "Создание ZIP-архива…",
        "Creating ZIP archive…"
    )

    archiveOperationProgress = 0
    isArchiveOperationInProgress = true

    progressTracker.observe(operationProgress)

    DispatchQueue.global(qos: .userInitiated).async {

        let result: Result<URL, Error>

        do {
            let createdArchiveURL = try zipService.createZIP(
                from: sourceFiles,
                at: outputURL,
                progress: operationProgress
            )

            result = .success(createdArchiveURL)

        } catch {
            result = .failure(error)
        }

        if hasAccess {
            destinationFolderURL.stopAccessingSecurityScopedResource()
        }

        DispatchQueue.main.async {

            isArchiveOperationInProgress = false
            progressTracker.stop()
            archiveOperationProgress = 0

            switch result {

            case .success(let createdArchiveURL):

                let actualFileName =
                    createdArchiveURL.lastPathComponent
                showArchiveOperationSuccess(
                    tr(
                        "ZIP-архив \(actualFileName) успешно создан!",
                        "ZIP archive \(actualFileName) created successfully!"
                    )
                )

                selectedZIPFiles = []
                zipArchiveName = ""
                isCreatingZIPPreview = false
                isNamingZIP = false

                message = ""

            case .failure(let error):
                showError(error)
            }
        }
    }
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

            ExtractionNameTextField(
                text: $extractionFolderName,
                placeholder: tr("Название папки", "Folder name"),
                focusRequest: extractionNameFocusRequest
            )
            .frame(height: 22)
            .padding(15)
            .background(
                Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 13)
            )

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

private var zipNameSheet: some View {
    ZStack {
        Color(red: 0.035, green: 0.043, blue: 0.075)
            .ignoresSafeArea()

        VStack(alignment: .leading, spacing: 20) {
            Text(tr("Создание ZIP-архива", "Create ZIP archive"))
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(
                tr(
                    "Введи название будущего архива.",
                    "Enter a name for the new archive."
                )
            )
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.6))

            ExtractionNameTextField(
                text: $zipArchiveName,
                placeholder: tr("Название архива", "Archive name"),
                focusRequest: zipNameFocusRequest
            )
            .frame(height: 22)
            .padding(15)
            .background(
                Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 13)
            )

            HStack(spacing: 12) {
                Button {
                    isNamingZIP = false
                    isCreatingZIPPreview = true
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
                    let cleanedName = zipArchiveName
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !cleanedName.isEmpty else { return }

                    zipArchiveName = cleanedName
                    isNamingZIP = false
                    isZIPDestinationImporterPresented = true
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
                    } else if items[selectedIndex].fileExtension == "rtf" {
                        ArchiveRTFView(
                            archiveURL: archiveURL,
                            item: items[selectedIndex],
                            isEnglish: isEnglish
                        )
                    } else if ["html", "htm"].contains(items[selectedIndex].fileExtension) {
    ArchiveHTMLView(
        archiveURL: archiveURL,
        item: items[selectedIndex],
        isEnglish: isEnglish
    )
                    } else if ["docx", "xlsx", "pptx"].contains(items[selectedIndex].fileExtension) {
                        ArchiveOfficeView(
                            archiveURL: archiveURL,
                            item: items[selectedIndex],
                            isEnglish: isEnglish
                        )
                    } else {
                        ArchiveImagePage(
    archiveURL: archiveURL,
    isEnglish: isEnglish,
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
    let isEnglish: Bool
    let item: ArchiveImage
    @Binding var isZoomed: Bool

    @State private var image: UIImage?
    @State private var loadingError: String?

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

                } else if let loadingError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)

                        Text(
                            isEnglish
                                ? "Unable to open image"
                                : "Не удалось открыть изображение"
                        )
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(loadingError)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
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
            loadingError = nil
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero

            await loadImage()
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

    private func loadImage() async {
        let currentArchiveURL = archiveURL
        let currentPath = item.path
        let currentExtension = item.fileExtension
        let english = isEnglish

        do {
            let imageData = try await Task.detached(
                priority: .userInitiated
            ) {
                if currentArchiveURL.pathExtension.lowercased() == "rar" {

                    let previewURL = try RARArchiveService().extractPreviewFile(
                        archiveURL: currentArchiveURL,
                        path: currentPath
                    )

                    defer {
                        try? FileManager.default.removeItem(at: previewURL)
                    }

                    return try Data(contentsOf: previewURL)

                } else if currentArchiveURL.pathExtension.lowercased() == "iso" {

                    let previewURL = try ISOArchiveService().extractPreviewFile(
                        archiveURL: currentArchiveURL,
                        path: currentPath
                    )

                    defer {
                        try? FileManager.default.removeItem(at: previewURL)
                    }

                    return try Data(contentsOf: previewURL)

                } else {

                    let archive = try Archive(
                        url: currentArchiveURL,
                        accessMode: .read
                    )

                    guard let archiveEntry = archive.first(where: {
                        $0.path == currentPath
                    }), archiveEntry.type == .file else {
                        throw NSError(
                            domain: "KolyanArchive",
                            code: 1,
                            userInfo: [
                                NSLocalizedDescriptionKey: english
    ? "File not found in archive"
    : "Файл не найден в архиве"
                            ]
                        )
                    }

                    let previewURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(currentExtension)

                    defer {
                        try? FileManager.default.removeItem(at: previewURL)
                    }

                    try archive.extract(
                        archiveEntry,
                        to: previewURL
                    )

                    return try Data(contentsOf: previewURL)
                }
            }.value

            guard let loadedImage = UIImage(data: imageData) else {
                loadingError = isEnglish
                    ? "The file was extracted, but iOS couldn't recognize the image."
                    : "Файл извлечён, но iOS не смогла распознать изображение."
                return
            }

            image = loadedImage

        } catch {
            loadingError = error.localizedDescription
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
            let data: Data

            if archiveURL.pathExtension.lowercased() == "rar" {

                let temporaryURL = try RARArchiveService().extractPreviewFile(
                    archiveURL: archiveURL,
                    path: item.path
                )

                defer {
                    try? FileManager.default.removeItem(at: temporaryURL)
                }

                data = try Data(contentsOf: temporaryURL)

            } else if archiveURL.pathExtension.lowercased() == "iso" {

                let temporaryURL = try ISOArchiveService().extractPreviewFile(
                    archiveURL: archiveURL,
                    path: item.path
                )

                defer {
                    try? FileManager.default.removeItem(at: temporaryURL)
                }

                data = try Data(contentsOf: temporaryURL)

            } else {

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

                defer {
                    try? FileManager.default.removeItem(at: temporaryURL)
                }

                try archive.extract(entry, to: temporaryURL)

                data = try Data(contentsOf: temporaryURL)
            }

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

        do {
            let data: Data

            if archiveURL.pathExtension.lowercased() == "rar" {

                let temporaryURL = try RARArchiveService().extractPreviewFile(
                    archiveURL: archiveURL,
                    path: item.path
                )

                defer {
                    try? FileManager.default.removeItem(at: temporaryURL)
                }

                data = try Data(contentsOf: temporaryURL)

            } else if archiveURL.pathExtension.lowercased() == "iso" {

                let temporaryURL = try ISOArchiveService().extractPreviewFile(
                    archiveURL: archiveURL,
                    path: item.path
                )

                defer {
                    try? FileManager.default.removeItem(at: temporaryURL)
                }

                data = try Data(contentsOf: temporaryURL)

            } else {

                let archive = try Archive(
                    url: archiveURL,
                    accessMode: .read
                )

                guard let entry = archive.first(where: {
                    $0.path == item.path
                }), entry.type == .file else {
                    throw NSError(
                        domain: "KolyanArchive",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "PDF-файл не найден в архиве"
                        ]
                    )
                }

                let temporaryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("pdf")

                defer {
                    try? FileManager.default.removeItem(at: temporaryURL)
                }

                try archive.extract(entry, to: temporaryURL)

                data = try Data(contentsOf: temporaryURL)
            }

            guard let document = PDFDocument(data: data) else {
                throw NSError(
                    domain: "KolyanArchive",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Не удалось открыть PDF-файл"
                    ]
                )
            }

            pdfView.document = document
            pdfView.goToFirstPage(nil)

            context.coordinator.loadedPath = item.path

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
            let data: Data

            let fileExtension = archiveURL.pathExtension.lowercased()

            if fileExtension == "rar" {

                let temporaryURL = try RARArchiveService().extractPreviewFile(
                    archiveURL: archiveURL,
                    path: item.path
                )

                defer {
                    try? FileManager.default.removeItem(at: temporaryURL)
                }

                data = try Data(contentsOf: temporaryURL)

            } else if fileExtension == "iso" {

                let temporaryURL = try ISOArchiveService().extractPreviewFile(
                    archiveURL: archiveURL,
                    path: item.path
                )

                defer {
                    try? FileManager.default.removeItem(at: temporaryURL)
                }

                data = try Data(contentsOf: temporaryURL)

            } else {

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

                defer {
                    try? FileManager.default.removeItem(at: temporaryURL)
                }

                try archive.extract(entry, to: temporaryURL)

                data = try Data(contentsOf: temporaryURL)
            }

            if let decodedText =
                String(data: data, encoding: .utf8) ??
                String(data: data, encoding: .utf16) ??
                String(data: data, encoding: .windowsCP1251) {

                text = decodedText
                    .replacingOccurrences(of: "\u{FEFF}", with: "")
                loadFailed = false

            } else {
                loadFailed = true
            }

        } catch {
            loadFailed = true
            print("TXT loading error: \(error)")
        }
    }
}

// MARK: - RTF Preview

private struct ArchiveRTFView: UIViewRepresentable {

    let archiveURL: URL
    let item: ArchiveImage
    let isEnglish: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()

        textView.backgroundColor = .white
        textView.textColor = .black
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.font = .systemFont(ofSize: 16)
        textView.textContainerInset = UIEdgeInsets(
            top: 75,
            left: 20,
            bottom: 85,
            right: 20
        )

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard context.coordinator.loadedPath != item.path else {
            return
        }

        context.coordinator.loadedPath = item.path

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data: Data

                let fileExtension = archiveURL.pathExtension.lowercased()

                if fileExtension == "zip" {
                    let temporaryURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)

                    defer {
                        try? FileManager.default.removeItem(at: temporaryURL)
                    }

                    let archive = try Archive(url: archiveURL, accessMode: .read)

                    guard let entry = archive[item.path] else {
                        throw NSError(
                            domain: "ArchiveRTF",
                            code: 1
                        )
                    }

                    _ = try archive.extract(entry, to: temporaryURL)
                    data = try Data(contentsOf: temporaryURL)

                } else if fileExtension == "iso" {

                    let temporaryURL = try ISOArchiveService().extractPreviewFile(
                        archiveURL: archiveURL,
                        path: item.path
                    )

                    defer {
                        try? FileManager.default.removeItem(at: temporaryURL)
                    }

                    data = try Data(contentsOf: temporaryURL)

                } else {

                    let temporaryURL = try RARArchiveService().extractPreviewFile(
                        archiveURL: archiveURL,
                        path: item.path
                    )

                    defer {
                        try? FileManager.default.removeItem(at: temporaryURL)
                    }

                    data = try Data(contentsOf: temporaryURL)
                }

                let attributedText = try NSAttributedString(
                    data: data,
                    options: [
                        .documentType: NSAttributedString.DocumentType.rtf
                    ],
                    documentAttributes: nil
                )

                DispatchQueue.main.async {
                    textView.attributedText = attributedText
                }

            } catch {
                DispatchQueue.main.async {
                    context.coordinator.loadedPath = nil
                    textView.text = isEnglish
                        ? "Unable to open RTF document."
                        : "Не удалось открыть RTF-документ."
                    textView.textColor = .white
                }
            }
        }
    }

    final class Coordinator {
        var loadedPath: String?
    }
}


// MARK: - HTML Preview

private struct ArchiveHTMLView: UIViewRepresentable {

    let archiveURL: URL
    let item: ArchiveImage
    let isEnglish: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.isOpaque = false
        webView.backgroundColor = UIColor(
            red: 0.035,
            green: 0.043,
            blue: 0.075,
            alpha: 1
        )
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedPath != item.path else {
            return
        }

        context.coordinator.loadedPath = item.path

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data: Data

                let fileExtension = archiveURL.pathExtension.lowercased()

                if fileExtension == "zip" {
                    let temporaryURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)

                    defer {
                        try? FileManager.default.removeItem(at: temporaryURL)
                    }

                    let archive = try Archive(url: archiveURL, accessMode: .read)

                    guard let entry = archive[item.path] else {
                        throw NSError(
                            domain: "ArchiveHTML",
                            code: 1
                        )
                    }

                    _ = try archive.extract(entry, to: temporaryURL)
                    data = try Data(contentsOf: temporaryURL)

                } else if fileExtension == "iso" {

                    let temporaryURL = try ISOArchiveService().extractPreviewFile(
                        archiveURL: archiveURL,
                        path: item.path
                    )

                    defer {
                        try? FileManager.default.removeItem(at: temporaryURL)
                    }

                    data = try Data(contentsOf: temporaryURL)

                } else {

                    let temporaryURL = try RARArchiveService().extractPreviewFile(
                        archiveURL: archiveURL,
                        path: item.path
                    )

                    defer {
                        try? FileManager.default.removeItem(at: temporaryURL)
                    }

                    data = try Data(contentsOf: temporaryURL)
                }

                
                let html =
                    String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .utf16)
                    ?? String(data: data, encoding: .windowsCP1252)

                guard let html else {
                    throw NSError(
                        domain: "ArchiveHTML",
                        code: 2
                    )
                }

                let darkTheme = """
                <style>
                html, body {
                    background-color: #090b13 !important;
                    color: #f1f3f8 !important;
                }

                body, body *:not(svg):not(svg *) {
                    color: #f1f3f8 !important;
                }

                a, a * {
                    color: #42dce8 !important;
                }

                input, textarea, select {
                    background-color: #171d2d !important;
                    color: #f1f3f8 !important;
                }

                table, th, td {
                    border-color: #343b50;
                }
                </style>
                """

                let styledHTML: String

                if let headRange = html.range(
                    of: "</head>",
                    options: .caseInsensitive
                ) {
                    var modifiedHTML = html
                    modifiedHTML.insert(
                        contentsOf: darkTheme,
                        at: headRange.lowerBound
                    )
                    styledHTML = modifiedHTML
                } else {
                    styledHTML = """
                    <html>
                    <head>
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    \(darkTheme)
                    </head>
                    <body>
                    \(html)
                    </body>
                    </html>
                    """
                }

                DispatchQueue.main.async {
                    webView.loadHTMLString(styledHTML, baseURL: nil)
                }

            } catch {
                DispatchQueue.main.async {
                    context.coordinator.loadedPath = nil

                    let message = isEnglish
                        ? "Unable to open HTML document."
                        : "Не удалось открыть HTML-документ."

                    webView.loadHTMLString(
                        "<html><body style='background:#090b13;color:white;font-family:-apple-system;padding:24px;'>\(message)</body></html>",
                        baseURL: nil
                    )
                }
            }
        }
    }

    final class Coordinator {
        var loadedPath: String?
    }
}

struct EntryInfo: Identifiable {
    let id = UUID()

    let name: String
    let path: String
    let fileType: String
    let isDirectory: Bool

    let sizeInBytes: UInt64
    let fileCount: Int
    let folderCount: Int
}

private struct ArchiveInfo: Identifiable {
    let id = UUID()

    let archiveSize: UInt64
    let fileCount: Int
    let folderCount: Int
    let uncompressedSize: UInt64
}


private struct ArchiveInfoView: View {

    let info: ArchiveInfo?
    let entryInfo: EntryInfo?
    let isEnglish: Bool

    @Environment(\.dismiss) private var dismiss

    private func tr(_ ru: String, _ en: String) -> String {
        isEnglish ? en : ru
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(clamping: bytes),
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
                        entryInfo != nil
                            ? tr("Информация об элементе", "Item information")
                            : tr("Информация об архиве", "Archive information"),
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

                    if let entryInfo {

                        infoRow(
                            tr("Название", "Name"),
                            value: entryInfo.name,
                            icon: entryInfo.isDirectory ? "folder" : "doc"
                        )

                        infoRow(
                            tr("Путь в архиве", "Archive path"),
                            value: entryInfo.path,
                            icon: "folder.badge.gearshape"
                        )

                        infoRow(
                            tr("Тип", "Type"),
                            value: entryInfo.fileType,
                            icon: "doc.text"
                        )

                        if entryInfo.isDirectory {

                            infoRow(
                                tr("Файлов", "Files"),
                                value: "\(entryInfo.fileCount)",
                                icon: "doc"
                            )

                            infoRow(
                                tr("Вложенных папок", "Subfolders"),
                                value: "\(entryInfo.folderCount)",
                                icon: "folder"
                            )

                            infoRow(
                                tr("Общий размер", "Total size"),
                                value: formatSize(entryInfo.sizeInBytes),
                                icon: "externaldrive"
                            )

                        } else {

                            infoRow(
                                tr("Размер файла", "File size"),
                                value: formatSize(entryInfo.sizeInBytes),
                                icon: "externaldrive"
                            )
                        }

                    } else if let info {

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
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

struct ExtractionNameTextField: UIViewRepresentable {

    @Binding var text: String

    let placeholder: String
    let focusRequest: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()

        textField.delegate = context.coordinator
        textField.text = text
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.textColor = .white
        textField.tintColor = .white
        textField.font = UIFont.systemFont(
            ofSize: 16,
            weight: UIFont.Weight.medium
        )

        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: UIColor.white.withAlphaComponent(0.45)
            ]
        )

        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )

        return textField
    }

    func updateUIView(
        _ textField: UITextField,
        context: Context
    ) {
        if textField.text != text {
            textField.text = text
        }

        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest

            DispatchQueue.main.async {
                textField.becomeFirstResponder()

                DispatchQueue.main.async {
                    guard let range = textField.textRange(
                        from: textField.beginningOfDocument,
                        to: textField.endOfDocument
                    ) else {
                        return
                    }

                    textField.selectedTextRange = range
                }
            }
        }
    }

    class Coordinator: NSObject, UITextFieldDelegate {

        var parent: ExtractionNameTextField
        var lastFocusRequest: UUID?

        init(_ parent: ExtractionNameTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
    }
}

// MARK: - Office Preview

private struct ArchiveOfficeView: UIViewControllerRepresentable {

    let archiveURL: URL
    let item: ArchiveImage
    let isEnglish: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(
        context: Context
    ) -> QLPreviewController {

        let controller = QLPreviewController()
        let coordinator = context.coordinator
        controller.overrideUserInterfaceStyle = .dark
        controller.view.backgroundColor = .black
        controller.view.isOpaque = true
        controller.view.tintColor = .white

        do {
            let fileURL: URL

            let fileExtension = archiveURL.pathExtension.lowercased()

            if fileExtension == "zip" {

                let directoryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "KolyanOffice-\(UUID().uuidString)",
                        isDirectory: true
                    )

                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )

                let destinationURL = directoryURL.appendingPathComponent(
                    URL(fileURLWithPath: item.path).lastPathComponent
                )

                let archive = try Archive(
                    url: archiveURL,
                    accessMode: .read
                )

                guard let entry = archive[item.path] else {
                    throw NSError(
                        domain: "ArchiveOffice",
                        code: 1
                    )
                }

                _ = try archive.extract(
                    entry,
                    to: destinationURL
                )

                fileURL = destinationURL
                coordinator.cleanupURLs.append(directoryURL)

            } else if fileExtension == "iso" {

                fileURL = try ISOArchiveService().extractPreviewFile(
                    archiveURL: archiveURL,
                    path: item.path
                )

                coordinator.cleanupURLs.append(fileURL)

            } else {

                fileURL = try RARArchiveService().extractPreviewFile(
                    archiveURL: archiveURL,
                    path: item.path
                )

                coordinator.cleanupURLs.append(fileURL)
            }

            coordinator.previewURL = fileURL

        } catch {

            let directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "KolyanOfficeError-\(UUID().uuidString)",
                    isDirectory: true
                )

            do {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )

                let errorURL = directoryURL.appendingPathComponent(
                    "Preview-Error.txt"
                )

                let message = isEnglish
                    ? "Unable to open this Office document."
                    : "Не удалось открыть документ Office."

                try message.write(
                    to: errorURL,
                    atomically: true,
                    encoding: .utf8
                )

                coordinator.previewURL = errorURL
                coordinator.cleanupURLs.append(directoryURL)

            } catch {
                coordinator.previewURL = nil
            }
        }

        controller.dataSource = coordinator
        controller.reloadData()

        return controller
    }

    func updateUIViewController(
        _ controller: QLPreviewController,
        context: Context
    ) {
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {

        var previewURL: URL?
        var cleanupURLs: [URL] = []

        func numberOfPreviewItems(
            in controller: QLPreviewController
        ) -> Int {
            return previewURL == nil ? 0 : 1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            return previewURL! as NSURL
        }

        deinit {
            for url in cleanupURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

@MainActor
private final class ArchiveProgressTracker: ObservableObject {

    @Published var progressValue = 0.0

    private var observation: NSKeyValueObservation?

    func observe(_ progress: Progress) {

        observation?.invalidate()

        observation = progress.observe(
            \.fractionCompleted,
            options: [.initial, .new]
        ) { [weak self] progress, _ in

            let value = progress.fractionCompleted

            DispatchQueue.main.async {
                self?.progressValue = value
            }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        progressValue = 0
    }
}
