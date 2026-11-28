import SwiftUI
import UIKit

// MARK: - View Model

class LogManagementViewModel: ObservableObject {
    struct LogFile: Identifiable {
        let id: String
        let name: String
        let url: URL
        let date: Date
        let size: Int64
        let type: String  // "running" | "crash" | "other"
    }

    @Published var logFiles: [LogFile] = []
    @Published var totalSize: Int64 = 0

    /// Running + other logs (non-crash). Shown in the "Log Files" section.
    var runningFiles: [LogFile] { logFiles.filter { $0.type != "crash" } }
    /// Crash reports (crash-*.log). Shown in a separate section only if non-empty.
    var crashFiles: [LogFile] { logFiles.filter { $0.type == "crash" } }

    private let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        f.countStyle = .file
        return f
    }()

    func format(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }

    func load() {
        let files = LoggingManager.shared.logFiles()
        logFiles = files.map {
            LogFile(id: $0.name, name: $0.name, url: $0.url, date: $0.date, size: $0.size, type: $0.type)
        }
        totalSize = LoggingManager.shared.totalLogSize()
    }
}

// MARK: - Log Management View

struct LogManagementView: View {
    @StateObject private var vm = LogManagementViewModel()
    @ObservedObject private var loggingManager = LoggingManager.shared
    @State private var showDeleteAllConfirm = false
    @State private var showShareSheet = false

    /// Selected top-level tab. Bound to a deep-link query string so
    /// `cody://settings/logs?tab=config-audit` lands users straight on
    /// the audit list. Stored as a String so the Picker can drive it.
    @State var initialTab: String = "logs"
    @State private var tab: String = "logs"

    var body: some View {
        VStack(spacing: 0) {
            CodySettingsNovaSection {
                Picker("Tab", selection: $tab) {
                    Text("Logs").tag("logs")
                    Text("Config Changes").tag("config-audit")
                }
                .pickerStyle(.segmented)
                .settingsNovaControlRow()
            }
            .padding(.horizontal, CodySpacing.lg)
            .padding(.top, CodySpacing.sm)

            if tab == "config-audit" {
                ConfigAuditView()
            } else {
                logsBody
            }
        }
        .background(CodyColors.bgCanvas.ignoresSafeArea())
        .navigationTitle("Diagnostic Logs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // "crashes" is no longer a tab — crash reports now live in a
            // section of the Logs body. Fall back to "logs" for stale deep links.
            tab = (initialTab == "crashes") ? "logs" : initialTab
            vm.load()
        }
    }

    @ViewBuilder
    private var logsBody: some View {
        CodySettingsScrollPage {
            loggingSection
            fileSection("Log Files", files: vm.runningFiles)
            if !vm.crashFiles.isEmpty {
                fileSection("Crash Reports", files: vm.crashFiles)
            }

            CodySettingsNovaSection {
                CodySettingsNovaNavRow("Crash Diagnostics", systemImage: nil) {
                    CrashDiagnosticsView()
                }
                if #available(iOS 17.0, *) {
                    CodySettingsNovaDivider(leadingInset: 18)
                    CodySettingsNovaNavRow("iCloud Sync Logs", systemImage: nil) {
                        Text(SyncLogStore.shared.entries.count, format: .number)
                            .font(CodyTypography.bodySmall.monospacedDigit())
                            .foregroundStyle(CodyColors.textSecondary)
                    } destination: {
                        SyncLogView()
                    }
                }
            }

            if !vm.logFiles.isEmpty {
                CodySettingsNovaSection(footer: "Total log storage: \(vm.format(vm.totalSize))") {
                    CodySettingsNovaActionRow("Delete All Logs", systemImage: nil, isDestructive: true, action: {
                        showDeleteAllConfirm = true
                    }) {
                        Text(vm.format(vm.totalSize))
                            .font(CodyTypography.bodySmall.monospacedDigit())
                            .foregroundStyle(CodyColors.textSecondary)
                    }
                }
            }
        }
        .toolbar {
            if !vm.logFiles.isEmpty && tab == "logs" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .accessibilityLabel(Text("Share Logs"))
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            LogShareSheet(urls: vm.logFiles.map(\.url))
        }
        .alert("Delete All Logs?", isPresented: $showDeleteAllConfirm) {
            Button("Delete All", role: .destructive) {
                LoggingManager.shared.deleteAllLogs()
                vm.load()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete \(vm.format(vm.totalSize)) of log files. This action cannot be undone.")
        }
    }

    private var loggingSection: some View {
        CodySettingsNovaSection(
            footer: loggingManager.isEnabled && loggingManager.level == .verbose
                ? "Verbose adds high-frequency traces (filesystem, rendering, context). Useful when reproducing a specific problem — logs grow very quickly, so switch back to Info afterwards."
                : "When enabled, all console output is captured to daily log files."
        ) {
            Toggle("Enable Logging", isOn: $loggingManager.isEnabled)
                .tint(.green)
                .settingsNovaControlRow()
            if loggingManager.isEnabled {
                CodySettingsNovaDivider(leadingInset: 18)
                Menu {
                    Picker("Detail Level", selection: $loggingManager.level) {
                        Text("Info").tag(AppLogger.Level.info)
                        Text("Verbose").tag(AppLogger.Level.verbose)
                    }
                } label: {
                    SettingsNovaPickerLabel(
                        title: "Detail Level",
                        value: Text(loggingManager.level == .verbose ? "Verbose" : "Info")
                    )
                }
                .buttonStyle(CodyPressableButtonStyle())
            }
        }
    }

    private func fileSection(_ title: LocalizedStringKey, files: [LogManagementViewModel.LogFile]) -> some View {
        CodySettingsNovaSection(title) {
            if files.isEmpty {
                Text("No log files")
                    .foregroundStyle(CodyColors.textSecondary)
                    .settingsNovaControlRow()
            } else {
                ForEach(files) { file in
                    if file.id != files.first?.id {
                        CodySettingsNovaDivider(leadingInset: 18)
                    }
                    HStack(spacing: 0) {
                        CodySettingsNovaNavRow(
                            "\(file.name)",
                            subtitle: "\(vm.format(file.size))",
                            systemImage: nil
                        ) {
                            LogDetailView(url: file.url, name: file.name)
                        }
                        SettingsNovaRowMenu(title: "Actions for \(file.name)") {
                            Button("Delete", role: .destructive) {
                                LoggingManager.shared.deleteLog(at: file.url)
                                vm.load()
                            }
                        }
                        .padding(.trailing, CodySpacing.sm)
                    }
                }
            }
        }
    }
}

// MARK: - Log Detail View

struct LogDetailView: View {
    let url: URL
    let name: String
    @State private var content: String = ""
    @State private var isLoading = true

    var body: some View {
        CodySettingsNovaSection {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LogTextView(text: content)
            }
        }
        .padding(.horizontal, CodySpacing.lg)
        .padding(.vertical, CodySpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CodyColors.bgCanvas.ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: url)
            }
        }
        .task {
            let fileURL = url
            let loaded = await Task.detached(priority: .userInitiated) {
                LoggingManager.shared.readLog(at: fileURL)
            }.value
            content = loaded
            isLoading = false
        }
    }
}

// MARK: - UITextView wrapper (TextKit 2 lazy layout)

private struct LogTextView: UIViewRepresentable {
    let text: String
    @ScaledMetric(relativeTo: .caption) private var fontSize: CGFloat = 11

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.dataDetectorTypes = []
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.font?.pointSize != fontSize {
            textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        if textView.text != text {
            textView.text = text
        }
    }
}

// MARK: - Share Sheet

private struct LogShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        // [T-share-sheet-uti] See CodyShareSheet.sanitizedShareURL.
        let safe = urls.map { CodyShareSheet.sanitizedShareURL($0) ?? $0 }
        return UIActivityViewController(activityItems: safe, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
