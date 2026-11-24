import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @State private var isImporterPresented = false
    @State private var archiveName = "Архив не выбран"
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

                        Button {
                            isImporterPresented = true
                        } label: {
                            Label("Открыть архив", systemImage: "folder.badge.plus")
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

                        VStack(alignment: .leading, spacing: 14) {
                            Text(archiveName)
                                .font(.headline)
                                .lineLimit(1)

                            if entries.isEmpty {
                                ContentUnavailableView(
                                    "Нет содержимого",
                                    systemImage: "doc.zipper",
                                    description: Text(message)
                                )
                                .frame(maxWidth: .infinity, minHeight: 190)
                            } else {
                                ForEach(entries) { entry in
                                    HStack(spacing: 12) {
                                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                                            .foregroundStyle(entry.isDirectory ? .cyan : .white.opacity(0.8))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(entry.path)
                                                .lineLimit(1)
                                            Text(entry.sizeDescription)
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.5))
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 5)
                                }
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))

                        HStack(spacing: 12) {
                            featureCard("ZIP", detail: "Создание и распаковка", symbol: "doc.zipper")
                            featureCard("RAR", detail: "Распаковка — следующий этап", symbol: "archivebox")
                        }

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
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                openSelectedArchive(result)
            }
            .alert("Не удалось открыть архив", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .tint(.white)
    }

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
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(.top, 18)
    }

    private func featureCard(_ title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.cyan)
            Text(title).font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
        .padding(15)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
    }

    private func openSelectedArchive(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }

            archiveName = url.lastPathComponent
            entries = try archiveService.listContents(of: url)
            message = entries.isEmpty ? "Архив пуст." : ""
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
