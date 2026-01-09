import SwiftUI

struct AdvancedSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    @Binding var isPickingIndexPlist: Bool

    var body: some View {
        Form {
            Section {
                Text("These options are for troubleshooting and custom setups. Most users should leave them at the defaults.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Downloads") {
                let timeoutMinutesBinding = Binding<Int>(
                    get: { max(1, Int(appState.settings.downloadTimeout) / 60) },
                    set: { appState.settings.downloadTimeout = TimeInterval(max(60, $0 * 60)) }
                )

                LabeledContent("Download timeout") {
                    Stepper(value: timeoutMinutesBinding, in: 1...120, step: 1) {
                        Text("\(timeoutMinutesBinding.wrappedValue) min")
                            .frame(minWidth: 72, alignment: .trailing)
                    }
                }
                .help("How long AerialFlow will wait for a download to complete before failing.")
            }

            Section("Wallpaper store") {
                LabeledContent("Index.plist") {
                    Text(appState.settings.indexPlistURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                .help("The Index.plist file AerialFlow edits to apply the next Aerial. The default is the system wallpaper store.")

                LabeledContent("Location") {
                    HStack(spacing: 8) {
                        Button("Choose…") {
                            isPickingIndexPlist = true
                        }
                        Button("Reset") {
                            appState.settings.indexPlistURL = WallpaperStoreEditor.defaultIndexPlistURL
                        }
                    }
                }

                Text("Changing this can prevent AerialFlow from updating your wallpaper if it points to the wrong store.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Backups") {
                let backupRetentionBinding = Binding<Int>(
                    get: { appState.settings.backupRetentionCount },
                    set: { appState.settings.backupRetentionCount = $0 }
                )

                LabeledContent("Backups to keep") {
                    Stepper(value: backupRetentionBinding, in: 1...Constants.maximumBackupRetentionCount, step: 1) {
                        Text("\(backupRetentionBinding.wrappedValue)")
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }
                .help("How many Index.plist backups AerialFlow keeps next to the original. Older backups are pruned automatically.")
            }
        }
        .formStyle(.grouped)
    }
}

