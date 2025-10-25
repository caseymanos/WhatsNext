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
    @State private var isConnectingGoogle = false
    @State private var showCalendarPicker = false
    @State private var availableGoogleCalendars: [GoogleCalendar] = []
    @State private var showCategoryPicker = false
    @State private var selectedCategory: String?

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
            .sheet(isPresented: $showCalendarPicker) {
                if let credentials = settings.flatMap({ s in
                    guard let token = s.googleAccessToken,
                          let refresh = s.googleRefreshToken,
                          let expiry = s.googleTokenExpiry else { return nil }
                    return GoogleOAuthCredentials(
                        accessToken: token,
                        refreshToken: refresh,
                        expiresAt: expiry,
                        scope: "https://www.googleapis.com/auth/calendar"
                    )
                }) {
                    GoogleCalendarPickerView(calendars: availableGoogleCalendars) { calendarId in
                        Task {
                            await saveGoogleCredentials(credentials: credentials, calendarId: calendarId)
                        }
                    }
                }
            }
            .sheet(isPresented: $showCategoryPicker) {
                if let category = selectedCategory {
                    CategoryCalendarPickerView(
                        category: category,
                        currentMapping: settings?.categoryCalendarMapping[category],
                        onSelect: { calendarName in
                            updateCategoryMapping(category: category, calendarName: calendarName)
                        }
                    )
                }
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
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)

                            if let calendarId = settings.googleCalendarId {
                                Text("Calendar: \(calendarId)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Button("Change Calendar") {
                                showCalendarPicker = true
                            }
                            .font(.caption)

                            Button("Disconnect", role: .destructive) {
                                disconnectGoogleCalendar()
                            }
                            .font(.caption)
                        }
                    } else {
                        Button {
                            Task {
                                await connectGoogleCalendar()
                            }
                        } label: {
                            if isConnectingGoogle {
                                HStack {
                                    ProgressView()
                                    Text("Connecting...")
                                }
                            } else {
                                Label("Connect Google Calendar", systemImage: "link")
                            }
                        }
                        .disabled(isConnectingGoogle)
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
            selectedCategory = category
            showCategoryPicker = true
            selectedCategory = category
            showCategoryPicker = true
            selectedCategory = category
            showCategoryPicker = true
            selectedCategory = category
            showCategoryPicker = true
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
        let isAuthorized = await permissionService.isCalendarAuthorized
        guard !isAuthorized else {
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
        let isAuthorized = await permissionService.isRemindersAuthorized
        guard !isAuthorized else {
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

    // MARK: - Google Calendar Connection

    private func connectGoogleCalendar() async {
        isConnectingGoogle = true
        defer { isConnectingGoogle = false }
        errorMessage = nil

        do {
            let googleAuthService = GoogleAuthService()

            // Request Calendar OAuth
            let credentials = try await googleAuthService.authorizeGoogleCalendar()

            // Fetch available calendars
            availableGoogleCalendars = try await googleAuthService.listGoogleCalendars(credentials: credentials)

            // If only one writable calendar, use it automatically
            let writableCalendars = availableGoogleCalendars.filter { $0.canWrite }
            if let primaryCalendar = writableCalendars.first(where: { $0.primary }) ?? writableCalendars.first {
                await saveGoogleCredentials(credentials: credentials, calendarId: primaryCalendar.id)
            } else {
                // Show picker if multiple calendars
                showCalendarPicker = true
            }
        } catch {
            errorMessage = "Failed to connect Google Calendar: \(error.localizedDescription)"
        }
    }

    private func saveGoogleCredentials(credentials: GoogleOAuthCredentials, calendarId: String) async {
        guard var currentSettings = settings else { return }

        currentSettings.googleCalendarId = calendarId
        currentSettings.googleAccessToken = credentials.accessToken
        currentSettings.googleRefreshToken = credentials.refreshToken
        currentSettings.googleTokenExpiry = credentials.expiresAt

        settings = currentSettings

        do {
            try await viewModel.updateSyncSettings(currentSettings)
        } catch {
            errorMessage = "Failed to save Google Calendar settings: \(error.localizedDescription)"
        }
    }

    private func disconnectGoogleCalendar() {
        guard var currentSettings = settings else { return }

        currentSettings.googleCalendarId = nil
        currentSettings.googleAccessToken = nil
        currentSettings.googleRefreshToken = nil
        currentSettings.googleTokenExpiry = nil

        settings = currentSettings

        Task {
            do {
                try await viewModel.updateSyncSettings(currentSettings)
            } catch {
                errorMessage = "Failed to disconnect: \(error.localizedDescription)"
            }
        }
    }

    private func updateCategoryMapping(category: String, calendarName: String?) {
        guard var currentSettings = settings else { return }

        if let calendarName = calendarName {
            currentSettings.categoryCalendarMapping[category] = calendarName
        } else {
            currentSettings.categoryCalendarMapping.removeValue(forKey: category)
        }

        settings = currentSettings

        Task {
            do {
                try await viewModel.updateSyncSettings(currentSettings)
            } catch {
                errorMessage = "Failed to update category mapping: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Category Calendar Picker

struct CategoryCalendarPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let category: String
    let currentMapping: String?
    let onSelect: (String?) -> Void

    @State private var availableCalendars: [String] = []
    @State private var availableLists: [String] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading calendars...")
                } else {
                    List {
                        Section {
                            Button {
                                onSelect(nil)
                                dismiss()
                            } label: {
                                HStack {
                                    Text("Default")
                                    Spacer()
                                    if currentMapping == nil {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }

                        if !availableCalendars.isEmpty {
                            Section("Apple Calendar") {
                                ForEach(availableCalendars, id: \.self) { calendar in
                                    Button {
                                        onSelect(calendar)
                                        dismiss()
                                    } label: {
                                        HStack {
                                            Text(calendar)
                                            Spacer()
                                            if currentMapping == calendar {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if !availableLists.isEmpty {
                            Section("Apple Reminders") {
                                ForEach(availableLists, id: \.self) { list in
                                    Button {
                                        onSelect(list)
                                        dismiss()
                                    } label: {
                                        HStack {
                                            Text(list)
                                            Spacer()
                                            if currentMapping == list {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(category.capitalized) Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadCalendarsAndLists()
            }
        }
    }

    private func loadCalendarsAndLists() async {
        isLoading = true
        defer { isLoading = false }

        let eventKitService = EventKitService()

        // Load Apple Calendars
        do {
            let calendars = try await eventKitService.getAvailableCalendars()
            availableCalendars = calendars.map { $0.title }
        } catch {
            // Permission not granted or error
        }

        // Load Apple Reminder Lists
        do {
            let lists = try await eventKitService.getAvailableReminderLists()
            availableLists = lists.map { $0.title }
        } catch {
            // Permission not granted or error
        }
    }
}

// MARK: - Google Calendar Picker

struct GoogleCalendarPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let calendars: [GoogleCalendar]
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List(calendars) { calendar in
                Button {
                    onSelect(calendar.id)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(calendar.summary)
                            .font(.body)
                        if let description = calendar.description {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            if calendar.primary {
                                Text("Primary")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundStyle(.blue)
                                    .cornerRadius(4)
                            }
                            if calendar.canWrite {
                                Text("Writable")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundStyle(.green)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .disabled(!calendar.canWrite)
            }
            .navigationTitle("Select Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#endif
