
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {

    @State private var isImporterPresented = false

    @State private var archiveName = "Архив не выбран"
    @State private var archiveURL: URL?

    @State private var currentDirectoryPath = ""
    @State private var entries: [ArchiveEntry] = []

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

                        archiveContents

                        featureCards

                        Text("Личная версия Kolyan Archive")
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
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                openSelectedArchive(result)
            }
            .alert(
                "Не удалось открыть архив",
                isPresented: $showingError
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
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
        .disabled(!entry.isDirectory)
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
}
