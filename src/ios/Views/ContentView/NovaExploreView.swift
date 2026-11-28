import SwiftUI

struct NovaExploreView: View {
    @ObservedObject var tabStore: CodyNovaTabStore
    let bottomClearance: CGFloat
    let onOpenDrawer: () -> Void
    let onSelectTool: (CodyNovaPinnedTool) -> Void
    let onOpenSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    private var matchingTools: [CodyNovaPinnedTool] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return CodyNovaPinnedTool.allCases }
        return CodyNovaPinnedTool.allCases.filter { tool in
            let titles = searchTitles(for: tool)
            return titles.localized.localizedStandardContains(query)
                || titles.english.localizedStandardContains(query)
                || tool.rawValue.localizedStandardContains(query)
        }
    }

    private func searchTitles(for tool: CodyNovaPinnedTool) -> (localized: String, english: String) {
        switch tool {
        case .files: (AppLocalized("Files"), "Files")
        case .terminal: (AppLocalized("Terminal"), "Terminal")
        case .skills: (AppLocalized("Skills"), "Skills")
        case .mcp: (AppLocalized("MCP"), "MCP")
        case .browser: (AppLocalized("Browser"), "Browser")
        case .agentTools: (AppLocalized("Agent Tools"), "Agent Tools")
        case .subAgents: (AppLocalized("Sub Agents"), "Sub Agents")
        case .soul: (AppLocalized("Soul"), "Soul")
        case .memory: (AppLocalized("Memory"), "Memory")
        case .providers: (AppLocalized("Providers"), "Providers")
        case .usage: (AppLocalized("Usage"), "Usage")
        case .alarms: (AppLocalized("Alarms"), "Alarms")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                let tools = matchingTools
                if tools.isEmpty {
                    Text("No matching tools")
                        .font(CodyTypography.bodyMedium)
                        .foregroundStyle(CodyColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, CodySpacing.xl)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(tools) { tool in
                            toolCard(tool)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, CodySpacing.sm)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            footer
                .padding(.bottom, bottomClearance)
        }
        .background(CodyColors.bgCanvas)
    }

    private var header: some View {
        HStack {
            headerButton("Open sidebar", action: onOpenDrawer) {
                CodyDrawerGlyph()
            }
            Spacer()
            headerButton("Settings", action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(CodyColors.iconPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, CodySpacing.sm)
    }

    private func headerButton<Glyph: View>(
        _ title: LocalizedStringKey,
        action: @escaping () -> Void,
        @ViewBuilder glyph: () -> Glyph
    ) -> some View {
        Button {
            searchFocused = false
            action()
        } label: {
            glyph()
                .frame(width: 40, height: 40)
                .background(CodyColors.bgElevatedPrimary, in: Circle())
                .overlay {
                    Circle().strokeBorder(CodySettingsHairline.strokeColor, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .contentShape(Circle())
        }
        .buttonStyle(CodyPressableButtonStyle())
        .accessibilityLabel(Text(title))
    }

    private func toolCard(_ tool: CodyNovaPinnedTool) -> some View {
        let isPinned = tabStore.isPinned(tool)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return Button {
            searchFocused = false
            onSelectTool(tool)
        } label: {
            VStack(alignment: .leading, spacing: CodySpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: CodySpacing.xs) {
                    Text(tool.title)
                        .font(CodyTypography.titleSmall)
                        .foregroundStyle(CodyColors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if isPinned {
                        Circle()
                            .fill(tool.exploreGlyphColor)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: tool.iconName)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(tool.exploreGlyphColor)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 108, alignment: .topLeading)
            .background {
                shape.fill(CodyColors.bgElevatedPrimary)
                    .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
            }
            .overlay {
                shape.strokeBorder(CodySettingsHairline.strokeColor, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
        }
        .buttonStyle(CodyPressableButtonStyle())
        .accessibilityValue(isPinned ? Text("Pinned") : Text(""))
        .contextMenu {
            Button {
                withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                    tabStore.togglePin(tool)
                }
            } label: {
                if isPinned {
                    Label("Unpin from Tab Bar", systemImage: "pin.slash")
                } else {
                    Label("Pin to Tab Bar", systemImage: "pin")
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: CodySpacing.sm) {
            Text("Long-press an item to pin it to the tab bar")
                .font(CodyTypography.bodySmall)
                .foregroundStyle(CodyColors.textTertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: CodySpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(CodyColors.iconSecondary)
                    .frame(width: 36)
                    .accessibilityHidden(true)

                TextField("Search", text: $searchText)
                    .font(CodyTypography.bodyMedium)
                    .foregroundStyle(CodyColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit { searchFocused = false }

                if searchText.isEmpty {
                    Color.clear.frame(width: 36)
                        .accessibilityHidden(true)
                } else {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(CodyColors.iconSecondary)
                            .frame(width: 36, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CodyPressableButtonStyle())
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, CodySpacing.sm)
            .frame(height: 48)
            .background(CodyColors.bgElevatedPrimary, in: Capsule())
            .overlay {
                Capsule().strokeBorder(CodySettingsHairline.strokeColor, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, CodySpacing.sm)
    }
}
