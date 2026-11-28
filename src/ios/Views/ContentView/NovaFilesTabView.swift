import SwiftUI

struct NovaFilesTabView: View {
    let bottomClearance: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedRoot: Root = .shared

    var body: some View {
        VStack(spacing: 0) {
            rootSelector
            FileBrowserView(rootPath: selectedRoot.url, rootLabel: selectedRoot.linuxPath)
                .id(selectedRoot)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: bottomClearance)
        }
        .background(CodyColors.bgCanvas)
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var rootSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CodySpacing.sm) {
                ForEach(Root.allCases, id: \.self) { root in
                    let selected = root == selectedRoot
                    Button {
                        withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                            selectedRoot = root
                        }
                    } label: {
                        Text(LocalizedStringKey(root.rawValue))
                            .font(CodyTypography.labelLarge)
                            .foregroundStyle(selected ? CodyColors.textPrimary : CodyColors.textSecondary)
                            .padding(.horizontal, CodySpacing.lg)
                            .frame(minHeight: CodyControlHeight.standard)
                            .background(selected ? CodyColors.interactiveSecondaryBg : .clear,
                                        in: RoundedRectangle(cornerRadius: CodyRadius.pill))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(CodyPressableButtonStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, CodySpacing.lg)
            .padding(.vertical, CodySpacing.sm)
        }
    }

    private enum Root: String, CaseIterable {
        case shared = "Shared"
        case skills = "Skills"
        case memory = "Memory"
        case linux = "Linux Root"

        var url: URL {
            switch self {
            case .shared: AIChatViewModel.codySharedPersistentDir
            case .skills: AIChatViewModel.codySkillsPersistentDir
            case .memory: AIChatViewModel.codyMemoryPersistentDir
            case .linux: RootfsManager.shared.dataPath
            }
        }

        var linuxPath: String {
            switch self {
            case .shared: AIChatViewModel.codySharedLinuxDir
            case .skills: AIChatViewModel.codySkillsLinuxDir
            case .memory: AIChatViewModel.codyMemoryLinuxDir
            case .linux: "/"
            }
        }
    }
}
