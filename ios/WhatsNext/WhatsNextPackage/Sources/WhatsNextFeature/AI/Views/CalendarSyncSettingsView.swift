import SwiftUI
#if AI_FEATURES

struct CalendarSyncSettingsView: View {
    @ObservedObject var viewModel: AIViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings: CalendarSyncSettings?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showPermissionAlert = false
    @State private var permissionType: PermissionType = .calendar

    enum PermissionType {
        case calendar, reminders
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading settings...")
                } else if let settings = settings {
                    settingsForm(settings)
                } else {
                    errorView
                }
            }
            .navigationTitle("Calendar Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadSettings()
            }
            .alert("Permission Required", isPresented: $showPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Please enable \(permissionType == .calendar ? "Calendar" : "Reminders") access in Settings to sync \(permissionType == .calendar ? "events" : "tasks").")
            }
        }
    }

    private func settingsForm(_ settings: CalendarSyncSettings) -> some View {
        Form {
            // Sync toggles section
            Section {
                Toggle("Auto-sync", isOn: Binding(
                    get: { settings.autoSyncEnabled },
                    set: { updateSetting(\.autoSyncEnabled, value: $0) }
                ))
                .onChange(of: settings.autoSyncEnabled) { _, newValue in
                    if newValue {
                        // Trigger sync when enabled
                        Task {
                            await viewModel.syncAllPending()
                        }
                    }
                }

                Toggle("Sync to all participants", isOn: Binding(
                    get: { settings.syncToAllParticipants },
                    set: { updateSetting(\.syncToAllParticipants, value: $0) }
                ))
            } header: {
                Text("General")
            } footer: {
                if settings.autoSyncEnabled {
                    Text("Events and deadlines will sync automatically when detected")
                }
            }

            // Apple Calendar section
            Section {
                Toggle("Enable Apple Calendar", isOn: Binding(
                    get: { settings.appleCalendarEnabled },
                    set: { newValue in
                        if newValue {
                            Task {
                                await requestCalendarPermission {
                                    updateSetting(\.appleCalendarEnabled, value: true)
                                }
                            }
                        } else {
                            updateSetting(\.appleCalendarEnabled, value: false)
                        }
                    }
                ))

                if settings.appleCalendarEnabled {
                    Label("Syncing events to Apple Calendar", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } header: {
                Label("Apple Calendar", systemImage: "calendar")
            }

            // Apple Reminders section
            Section {
                Toggle("Enable Apple Reminders", isOn: Binding(
                    get: { settings.appleRemindersEnabled },
                    set: { newValue in
                        if newValue {
                            Task {
                                await requestRemindersPermission {
                                    updateSetting(\.appleRemindersEnabled, value: true)
                                }
                            }
                        } else {
                            updateSetting(\.appleRemindersEnabled, value: false)
                        }
                    }
                ))

                if settings.appleRemindersEnabled {
                    Label("Syncing deadlines to Apple Reminders", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } header: {
                Label("Apple Reminders", systemImage: "checklist")
            }

            // Google Calendar section
            Section {
                Toggle("Enable Google Calendar", isOn: Binding(
                    get: { settings.googleCalendarEnabled },
                    set: { updateSetting(\.googleCalendarEnabled, value: $0) }
                ))

                if settings.googleCalendarEnabled {
                    if settings.isGoogleCalendarConfigured {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            // TODO: Implement Google OAuth
                            errorMessage = "Google Calendar setup coming soon"
                        } label: {
                            Label("Connect Google Calendar", systemImage: "link")
                        }
                    }
                }
            } header: {
                Label("Google Calendar", systemImage: "calendar.badge.clock")
            } footer: {
                if settings.googleCalendarEnabled && !settings.isGoogleCalendarConfigured {
                    Text("Connect your Google account to sync events")
                }
            }

            // Category mapping section
            if settings.appleCalendarEnabled || settings.googleCalendarEnabled || settings.appleRemindersEnabled {
                Section {
                    categoryMappingList
                } header: {
                    Text("Calendar Mapping")
                } footer: {
                    Text("Choose which calendar or list to use for each category")
                }
            }

            // Sync actions section
            if settings.hasAnySyncEnabled {
                Section {
                    Button {
                        Task {
                            await viewModel.syncAllPending()
                        }
                    } label: {
                        Label("Sync All Pending", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(viewModel.isSyncing)

                    Button {
                        Task {
                            await viewModel.processRetryQueue()
                        }
                    } label: {
                        Label("Retry Failed Items", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isSyncing)

                    Button {
                        Task {
                            await viewModel.detectExternalChanges()
                        }
                    } label: {
                        Label("Check for External Changes", systemImage: "arrow.down.circle")
                    }
                    .disabled(viewModel.isSyncing)
                } header: {
                    Text("Sync Actions")
                }

                if viewModel.isSyncing {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Syncing...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = viewModel.syncErrorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } header: {
                        Text("Error")
                    }
                }
            }
        }
    }

    private var categoryMappingList: some View {
        Group {
            categoryMappingRow(category: "school", displayName: "School")
            categoryMappingRow(category: "bills", displayName: "Bills")
            categoryMappingRow(category: "chores", displayName: "Chores")
            categoryMappingRow(category: "forms", displayName: "Forms")
            categoryMappingRow(category: "medical", displayName: "Medical")
            categoryMappingRow(category: "work", displayName: "Work")
            categoryMappingRow(category: "other", displayName: "Other")
        }
    }

    private func categoryMappingRow(category: String, displayName: String) -> some View {
        HStack {
            Text(displayName)
                .font(.body)

            Spacer()

            if let calendarName = settings?.categoryCalendarMapping[category] {
                Text(calendarName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Default")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // TODO: Navigate to calendar picker
            errorMessage = "Calendar picker coming soon"
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(errorMessage ?? "Failed to load settings")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("Try Again") {
                Task {
                    await loadSettings()
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadSettings() async {
        isLoading = true
        defer { isLoading = false }

        await viewModel.loadSyncSettings()
        settings = viewModel.syncSettings

        if settings == nil {
            errorMessage = "Failed to load sync settings"
        }
    }

    private func updateSetting<T>(_ keyPath: WritableKeyPath<CalendarSyncSettings, T>, value: T) {
        guard var currentSettings = settings else { return }
        currentSettings[keyPath: keyPath] = value
        settings = currentSettings

        Task {
            do {
                try await viewModel.updateSyncSettings(currentSettings)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func requestCalendarPermission(onSuccess: @escaping () -> Void) async {
        let permissionService = CalendarPermissionService.shared
        guard !await permissionService.isCalendarAuthorized else {
            onSuccess()
            return
        }

        do {
            try await permissionService.requestCalendarAuthorization()
            if await permissionService.isCalendarAuthorized {
                onSuccess()
            } else {
                permissionType = .calendar
                showPermissionAlert = true
            }
        } catch {
            permissionType = .calendar
            showPermissionAlert = true
        }
    }

    private func requestRemindersPermission(onSuccess: @escaping () -> Void) async {
        let permissionService = CalendarPermissionService.shared
        guard !await permissionService.isRemindersAuthorized else {
            onSuccess()
            return
        }

        do {
            try await permissionService.requestRemindersAuthorization()
            if await permissionService.isRemindersAuthorized {
                onSuccess()
            } else {
                permissionType = .reminders
                showPermissionAlert = true
            }
        } catch {
            permissionType = .reminders
            showPermissionAlert = true
        }
    }
}

#endif
