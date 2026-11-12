import AppKit
import SwiftUI

struct MemoryView: View {
    static let panelSize = NSSize(width: 432, height: 570)

    let snapshot: MemorySnapshot?
    let refresh: () -> Void
    let quit: () -> Void

    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @State private var search = ""
    @State private var expandedGroups: Set<String> = []

    private func t(_ key: String.LocalizationValue) -> String {
        language.localized(key)
    }

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var groups: [AppMemoryGroup] {
        guard let snapshot else { return [] }
        guard !query.isEmpty else { return snapshot.groups }

        return snapshot.groups.filter { group in
            group.name.localizedStandardContains(query) ||
            group.bundlePath.map {
                URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.localizedStandardContains(query)
            } == true ||
            group.processes.contains { process in
                process.name.localizedStandardContains(query) || String(process.id) == query
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let snapshot {
                systemUsage(snapshot)
            }
            searchField
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            if let snapshot {
                let displayedGroups = groups
                if displayedGroups.isEmpty {
                    emptyState
                } else {
                    let largestGroup = snapshot.groups.first?.bytes ?? 0
                    columnHeaders
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(displayedGroups) { group in
                                groupRow(group, largestGroup: largestGroup)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                    }
                    .accessibilityIdentifier("application-memory-list")
                }
            } else {
                ProgressView(t("Reading memory usage…"))
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            footer
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        // Dates and numbers follow the chosen language too, not only the strings.
        .environment(\.locale, language.locale)
        .accessibilityIdentifier("application-memory")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "memorychip")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            Text(t("App Memory"))
                .font(.system(size: 21, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            languageMenu
            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 27, height: 24)
            }
            .buttonStyle(.borderless)
            .help(t("Refresh Now"))
            .accessibilityLabel(t("Refresh Now"))
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var languageMenu: some View {
        Menu {
            Picker(selection: $language) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.title(in: language)).tag(option)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 14, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(t("Language"))
        .accessibilityLabel(t("Language"))
        .accessibilityIdentifier("language-menu")
    }

    private func systemUsage(_ snapshot: MemorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t("Memory Used"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(formatBytes(snapshot.usedBytes)) / \(formatBytes(snapshot.totalBytes))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(snapshot.usedBytes), total: Double(snapshot.totalBytes))
                .progressViewStyle(.linear)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("system-memory-usage")
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(t("Search apps or processes"), text: $search)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("application-memory-search")
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(t("Clear Search"))
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 9)
        .frame(height: 29)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
    }

    private var columnHeaders: some View {
        HStack {
            Text(t("App"))
            Spacer()
            Image(systemName: "arrow.down")
                .font(.system(size: 9, weight: .semibold))
            Text(t("Memory"))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.leading, 25)
        .padding(.trailing, 42)
        .padding(.top, 5)
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }

    private func groupRow(_ group: AppMemoryGroup, largestGroup: UInt64) -> some View {
        let expanded = expandedGroups.contains(group.id)
        let fraction = largestGroup > 0 ? min(1, Double(group.bytes) / Double(largestGroup)) : 0

        return VStack(spacing: 0) {
            Button {
                if expanded {
                    expandedGroups.remove(group.id)
                } else {
                    expandedGroups.insert(group.id)
                }
            } label: {
                HStack(spacing: 8) {
                    AppIcon(path: group.bundlePath)
                    Text(group.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(group.processes.count, format: .number)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .fixedSize()
                    Spacer(minLength: 8)
                    Text(formatBytes(group.bytes))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .fixedSize()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                .padding(.horizontal, 11)
                .frame(height: 38)
                .contentShape(Rectangle())
                .background {
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: geometry.size.width * fraction)
                    }
                    .accessibilityHidden(true)
                }
            }
            .buttonStyle(AppRowButtonStyle())
            .accessibilityLabel(group.name)
            .accessibilityValue([
                formatBytes(group.bytes),
                t("\(group.processes.count) processes"),
                expanded ? t("Expanded") : t("Collapsed"),
            ].joined(separator: ", "))
            .accessibilityIdentifier("memory-group-\(group.id)")

            if expanded {
                VStack(spacing: 1) {
                    ForEach(group.processes) { process in
                        processRow(process)
                    }
                }
                .padding(.vertical, 5)
            }
        }
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 7))
    }

    private func processRow(_ process: ProcessMemory) -> some View {
        HStack(spacing: 8) {
            Text(process.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
            // verbatim: a PID is an identifier, so no thousands separator ("PID 95760", not "PID 95,760")
            Text(verbatim: "PID \(process.id)")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 5)
            Text(formatBytes(process.bytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .font(.system(size: 11))
        .padding(.leading, 43)
        .padding(.trailing, 31)
        .frame(height: 23)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: query.isEmpty ? "memorychip" : "magnifyingglass")
                .font(.system(size: 23))
                .accessibilityHidden(true)
            Text(query.isEmpty ? t("No memory data") : t("No matching apps or processes"))
                .font(.system(size: 13))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                if let snapshot {
                    Text(t("\(snapshot.groups.count) apps"))
                    Text(verbatim: "·")
                        .accessibilityHidden(true)
                    Text(t("Updated"))
                    Text(snapshot.timestamp, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                }
                Spacer()
                Button(t("Quit"), action: quit)
                    .buttonStyle(.borderless)
                    .accessibilityLabel(t("Quit RAMScope"))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(height: 33)
        }
    }

    // Memory style (1 GB = 1024³ bytes) matches Activity Monitor and shows 16 GB of RAM as "16 GB".
    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
}

private struct AppIcon: View {
    private static let icons = NSCache<NSString, NSImage>()
    let path: String?

    var body: some View {
        Group {
            if let path {
                Image(nsImage: Self.icon(for: path))
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 23, height: 23)
        .accessibilityHidden(true)
    }

    private static func icon(for path: String) -> NSImage {
        if let cached = icons.object(forKey: path as NSString) {
            return cached
        }
        let image = NSWorkspace.shared.icon(forFile: path)
        icons.setObject(image, forKey: path as NSString)
        return image
    }
}

private struct AppRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                .primary.opacity(configuration.isPressed ? 0.12 : 0),
                in: RoundedRectangle(cornerRadius: 7)
            )
    }
}
