import Models
import SwiftUI

/// Settings → Backups: the Backups section of the desktop's Data Controls — the last backup and Back Up Now, whether
/// daily backups are on (switched on the computer), and the recent backups. Export, import and delete stay there.
struct BackupSettingsPage: View {
    @Bindable var viewModel: BackupSettingsViewModel

    var body: some View {
        Form {
            switch viewModel.loadState {
            case .idle, .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case .failed(let message):
                ListLoadFailedSection(title: Text("ios:settings.backup.loadFailed"), message: message) {
                    await viewModel.load()
                }
            case .loaded:
                SettingsErrorSection(message: viewModel.refreshError)
                backupSection
                resultSection
                recentSection
            }
        }
        .refreshable { await viewModel.load() }
        .task {
            if !viewModel.isRunning { await viewModel.load() }
            #if DEBUG
            if SettingsGalleryLaunch.isEnabled, SettingsGalleryLaunch.action == "backup", viewModel.phase == .idle {
                viewModel.backUpNow()
            }
            #endif
        }
    }

    private var backupSection: some View {
        Section {
            LabeledContent {
                if let date = viewModel.status?.lastBackupDate {
                    Text(date, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                } else {
                    Text("settings:dataControls.lastBackup.none")
                }
            } label: {
                Text("settings:dataControls.lastBackup.label")
            }
            Button {
                viewModel.backUpNow()
            } label: {
                HStack {
                    if viewModel.isRunning {
                        Text("ios:settings.backup.inProgress")
                        Spacer()
                        ProgressView()
                    } else {
                        Label("settings:dataControls.backupNow.button", systemImage: "externaldrive.badge.checkmark")
                    }
                }
            }
            .disabled(viewModel.isRunning)
            LabeledContent {
                if viewModel.status?.autoBackup ?? true {
                    Text("ios:settings.backup.on")
                } else {
                    Text("ios:settings.backup.off")
                }
            } label: {
                Text("settings:dataControls.autoBackup.label")
                Text("settings:dataControls.autoBackup.description")
            }
        } footer: {
            Text("ios:settings.backup.onComputer")
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        switch viewModel.phase {
        case .succeeded:
            Section {
                Label("settings:dataControls.backupNow.successToast", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        case .failed(let message):
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings:dataControls.backupNow.errorToast").font(.headline)
                    Text(verbatim: message).foregroundStyle(.secondary)
                }
            }
        case .idle, .running:
            EmptyView()
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !viewModel.backups.isEmpty {
            Section {
                LabeledContent {
                    Text(verbatim: String(viewModel.backups.count)).monospacedDigit()
                } label: {
                    Text("ios:settings.backup.stored")
                }
                ForEach(viewModel.backups.prefix(5)) { backup in
                    LabeledContent {
                        Text(Int64(backup.size), format: .byteCount(style: .file)).monospacedDigit()
                    } label: {
                        Label {
                            Text(verbatim: backup.name).font(.body.monospaced())
                        } icon: {
                            Image(systemName: "archivebox")
                        }
                    }
                }
            } header: {
                Text("settings:dataControls.recentBackups.label")
            }
        }
    }
}
