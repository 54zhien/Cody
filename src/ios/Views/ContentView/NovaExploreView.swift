import SwiftUI

struct NovaExploreView: View {
    let bottomClearance: CGFloat
    let onOpenBrowser: () -> Void
    let onOpenTerminal: () -> Void
    let onOpenSettings: () -> Void

    @AppStorage("novaExplorePinnedIds") private var storedPins = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchText = ""
    @State private var presentedTool: Tool?
    @FocusState private var searchFocused: Bool

    private var pinnedTools: [Tool] {
        storedPins.split(separator: ",").compactMap { Tool(rawValue: String($0)) }
    }

    private var matchingTools: [Tool] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Tool.allCases.filter { tool in
            tool.isAvailable && (query.isEmpty
                || AppLocalized(String.LocalizationValue(tool.title)).localizedStandardContains(query)
                || AppLocalized(String.LocalizationValue(tool.category.rawValue)).localizedStandardContains(query))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CodySpacing.xxl) {
                searchBar
                let matches = matchingTools
                let pinned = pinnedTools.filter(matches.contains)
                if !pinned.isEmpty { section("Pinned", tools: pinned) }
                ForEach(Category.allCases, id: \.self) { category in
                    let tools = matches.filter { $0.category == category && !pinned.contains($0) }
                    if !tools.isEmpty { section(LocalizedStringKey(category.rawValue), tools: tools) }
                }
                if matches.isEmpty {
                    Text("No matching tools")
                        .font(CodyTypography.bodyMedium)
                        .foregroundStyle(CodyColors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, CodySpacing.lg)
            .padding(.top, CodySpacing.md)
            .padding(.bottom, bottomClearance + CodySpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CodyColors.bgCanvas)
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $presentedTool) { tool in
            if tool == .alarms {
                if #available(iOS 26.0, *), alarmkit_is_usable() {
                    AlarmListView()
                }
            } else {
                NavigationStack {
                    toolDestination(tool)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { presentedTool = nil }
                            }
                        }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: CodySpacing.sm) {
            Image(systemName: "magnifyingglass")
                .accessibilityHidden(true)
            TextField("Search tools & capabilities", text: $searchText)
                .font(CodyTypography.bodyMedium)
                .foregroundStyle(CodyColors.textPrimary)
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Label("Clear search", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: CodyControlHeight.standard, minHeight: CodyControlHeight.standard)
                }
                .buttonStyle(CodyPressableButtonStyle())
            }
        }
        .foregroundStyle(CodyColors.iconSecondary)
        .padding(.leading, CodySpacing.lg)
        .padding(.trailing, searchText.isEmpty ? CodySpacing.lg : 0)
        .frame(minHeight: CodyControlHeight.standard)
        .background(CodyColors.interactiveSecondaryBg, in: Capsule())
    }

    private func section(_ title: LocalizedStringKey, tools: [Tool]) -> some View {
        VStack(alignment: .leading, spacing: CodySpacing.md) {
            Text(title)
                .font(CodyTypography.titleSmall)
                .foregroundStyle(CodyColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: CodySpacing.md, alignment: .top),
                               count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                spacing: CodySpacing.md
            ) {
                ForEach(tools) { tool in toolCard(tool) }
            }
        }
    }

    private func toolCard(_ tool: Tool) -> some View {
        let color = tool.tint.color
        let isPinned = pinnedTools.contains(tool)
        let shape = RoundedRectangle(cornerRadius: CodyRadius.surface, style: .continuous)
        return Button {
            searchFocused = false
            switch tool {
            case .browser: onOpenBrowser()
            case .terminal: onOpenTerminal()
            case .settings: onOpenSettings()
            default: presentedTool = tool
            }
        } label: {
            VStack(alignment: .leading, spacing: CodySpacing.md) {
                HStack {
                    CodyListIconBadge(systemImage: tool.icon, tint: tool.tint)
                    Spacer(minLength: 0)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(color)
                            .accessibilityHidden(true)
                    }
                }
                Text(LocalizedStringKey(tool.title))
                    .font(CodyTypography.labelLarge)
                    .foregroundStyle(CodyColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(CodySpacing.lg)
            .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
            .background {
                shape.fill(CodyColors.bgElevatedPrimary)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
            }
            .overlay { shape.strokeBorder(CodyColors.borderLight, lineWidth: 1).allowsHitTesting(false) }
            .contentShape(shape)
        }
        .buttonStyle(CodyPressableButtonStyle())
        .accessibilityValue(isPinned ? Text("Pinned") : Text(""))
        .contextMenu {
            Button {
                withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                    let pins = isPinned ? pinnedTools.filter { $0 != tool } : pinnedTools + [tool]
                    storedPins = pins.map(\.rawValue).joined(separator: ",")
                }
            } label: {
                Label(isPinned ? "Unpin" : "Pin to Top", systemImage: isPinned ? "pin.slash" : "pin")
            }
        }
    }

    @ViewBuilder
    private func toolDestination(_ tool: Tool) -> some View {
        switch tool {
        case .skills: SkillsManagementView()
        case .mcp: MCPIntegrationsView()
        case .agentTools: ToolsSettingsView()
        case .subAgents: HelperSettingsView()
        case .soul: SoulSettingsView()
        case .memory: MemoryManagementView()
        case .providers: ProviderInstancesView()
        case .usage: UsageStatsView()
        case .browser, .terminal, .alarms, .settings: EmptyView()
        }
    }

    private enum Category: String, CaseIterable {
        case capabilities = "Capabilities"
        case workspace = "Workspace"
        case configuration = "Configuration"
    }

    private enum Tool: String, CaseIterable, Identifiable {
        case skills, mcp, agentTools, subAgents, soul, memory
        case browser, terminal, providers, usage, alarms, settings

        var id: String { rawValue }

        var category: Category {
            switch self {
            case .skills, .mcp, .agentTools, .subAgents, .soul, .memory: .capabilities
            case .browser, .terminal, .alarms: .workspace
            case .providers, .usage, .settings: .configuration
            }
        }

        var isAvailable: Bool {
            guard self == .alarms else { return true }
            if #available(iOS 26.0, *) { return alarmkit_is_usable() }
            return false
        }

        var title: String {
            switch self {
            case .skills: "Skills"
            case .mcp: "MCP Integrations"
            case .agentTools: "Agent Tools"
            case .subAgents: "Sub Agents"
            case .soul: "Soul & Persona"
            case .memory: "Memory"
            case .browser: "Web Browser"
            case .terminal: "Linux Terminal"
            case .providers: "Providers & Models"
            case .usage: "Token Usage"
            case .alarms: "Alarms"
            case .settings: "Settings"
            }
        }

        var icon: String {
            switch self {
            case .skills: "puzzlepiece.extension"
            case .mcp: "square.stack.3d.up"
            case .agentTools: "wrench.and.screwdriver.fill"
            case .subAgents: "sparkles.rectangle.stack"
            case .soul: "sparkles"
            case .memory: "brain.head.profile"
            case .browser: "safari"
            case .terminal: "terminal"
            case .providers: "cpu"
            case .usage: "chart.line.uptrend.xyaxis"
            case .alarms: "alarm"
            case .settings: "gearshape.fill"
            }
        }

        var tint: CodyCategoryTint {
            switch self {
            case .skills, .browser, .providers: .blue
            case .mcp, .terminal, .usage: .green
            case .agentTools, .subAgents, .soul, .memory: .purple
            case .alarms: .orange
            case .settings: .neutral
            }
        }
    }
}
