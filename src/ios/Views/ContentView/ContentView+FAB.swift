//
//  ContentView+FAB.swift
//  Cody - home screen (session list, navigation, settings entry)
//
//  ContentView, floating buttons: the draggable new-chat and search FABs and
//  the search bar they expand into (Liquid Glass on iOS 26+). Their drag /
//  focus state and glass namespace are stored in ContentView.swift.
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI

extension ContentView {
    // MARK: - FAB Row (New Chat + Search)

    /// A full-size target keeps the clear glyph easy to tap inside the capsule.
    private var searchClearButton: some View {
        Button { dismissSearch() } label: {
            Group {
                if #available(iOS 26.0, *) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            .foregroundStyle(CodyColors.textSecondary)
            // [T-ios-search-bar-glass-hit-hole] Include the area around the glyph.
            .frame(width: CodyControlHeight.standard, height: CodyControlHeight.standard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Cancel"))
    }

    /// [T-ios-crash-objectdestroy-fab-uaf] `static`, deliberately.
    ///
    /// This is a pure function of its parameters — it reads no instance state.
    /// But as an INSTANCE method, calling it from inside `DraggableFAB`'s
    /// stored `label` closure captured `self`, which drags an entire
    /// ContentView struct copy into that closure's heap context. When SwiftUI
    /// tears the graph down it releases the closure, destroying the stale copy
    /// field by field — and its `@State` boxes are already gone. That is the
    /// `objectdestroy.90Tm` crash (owner: ContentView), still arriving on
    /// 1.14(21) after `e3579b381` fixed only the `onTap` half.
    ///
    /// Making it static removes the last `self` capture from `label`: every
    /// other reference in there is `Self.`-qualified, a singleton, or the
    /// `fabActions` channel, and `Namespace.ID` is a value type that copies.
    ///
    /// Keep it static. Adding an instance reference here silently reintroduces
    /// the capture and the crash.
    private static func fabCircleSurface<Icon: View>(
        isPrimary: Bool,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        icon().modifier(FABCircleSurface(isPrimary: isPrimary))
    }

    @ViewBuilder
    var fabRow: some View {
        // [T-fab-glass-contextmenu-regression] NO GlassEffectContainer here.
        //
        // The row was briefly wrapped in `GlassEffectContainer(spacing: 10)` so the
        // search FAB and the expanded search bar (which share a `glassEffectID`)
        // would morph into one another like the system Dock. That container is what
        // broke the new-chat FAB's long-press "New Chat with Group" menu.
        //
        // Verified on device by A/B-ing the view tree with the debug inspector, same
        // screen both times, looking for views owning a `UIContextMenuInteraction`:
        //   with the container:  [WKContentView, UpdateCoalescingCollectionView]
        //   without it:          [WKContentView, HostingView, UpdateCoalescingCollectionView]
        // The `HostingView` that hosts this row only gets its context-menu
        // interaction when the container is absent — inside it, SwiftUI never
        // materialises one, so no long press can ever raise the menu no matter how
        // the hit region is shaped. (That is why the earlier `.contentShape(.circle)`
        // fix did not help: it widened a hit region for an interaction that was
        // never created.)
        //
        // Dropping the container costs only the FAB→search-bar morph animation,
        // which falls back to the scale+opacity transition the row already declares.
        // Search still uses the standalone glass material.
        fabRowContent
    }

    var sidebarFABInset: some View {
        fabRow.background(alignment: .bottom) {
            VStack(spacing: 0) {
                CodyEdgeFadeBar(
                    direction: .bottom,
                    height: CodyMetrics.Conversation.bottomFadeHeight,
                    color: CodyColors.bgCanvas
                )
                CodyColors.bgCanvas.frame(height: CodySpacing.s40)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var fabRowContent: some View {
        let searchGlassNamespace = fabGlassNamespace
        let searchAnchor: UnitPoint = fabOnLeft ? .leading : .trailing
        ZStack {
            // New chat FAB (draggable)
            DraggableFAB(
                fabOnLeft: $fabOnLeft,
                dragOffset: $fabDragOffset,
                didDrag: $fabDidDrag
            ) { [fabActions] in
                // [T-ios-crash-objectdestroy-fab-uaf] Capture ONLY the channel,
                // never self. The drag guard moved to the receiver, which reads
                // the live @State rather than a captured copy.
                fabActions.send(.newChat)
            } label: {
                Self.fabCircleSurface(isPrimary: true) {
                    Image(systemName: {
                        if #available(iOS 17.0, *) { return "bubble.left.and.text.bubble.right" }
                        return "plus.message.fill"
                    }())
                    .font(.system(size: 22, weight: .semibold))
                }
                    .accessibilityLabel(Text("New Chat"))
                    .contextMenu {
                        let groups = Array(ProviderConfigStore.shared.config.modelGroups.prefix(10))
                        if !groups.isEmpty {
                            Section(AppLocalized("New Chat with Group")) {
                                ForEach(groups) { group in
                                    Button { [fabActions] in
                                        fabActions.send(.newChatInGroup(group.id))
                                    } label: {
                                        Label(group.name, systemImage: "square.stack.3d.up")
                                    }
                                }
                            }
                        }
                    }
            }

            // Search FAB or inline search bar (hidden when no sessions)
            if !sessions.isEmpty {
                if showSearchBar {
                    // Inline search bar — fills space between edges, leaving room for New Chat
                    GeometryReader { geo in
                        let fabSize = CodySpacing.s56
                        let edgePad = CodySpacing.lg
                        let gap = CodySpacing.smPlus
                        let barX: CGFloat = fabOnLeft
                            ? edgePad + fabSize + gap
                            : edgePad
                        let barWidth: CGFloat = geo.size.width - edgePad * 2 - fabSize - gap

                        HStack(spacing: CodySpacing.sm) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(CodyColors.textSecondary)
                                .accessibilityHidden(true)
                            TextField("Search chats...", text: $searchText)
                                .textFieldStyle(.plain)
                                .foregroundStyle(CodyColors.textPrimary)
                                .autocorrectionDisabled()
                                .focused($searchFocused)
                                .onChange(of: searchText) { _ in scheduleSearch() }
                            searchClearButton
                        }
                        .padding(.leading, CodyMetrics.Sidebar.rowPaddingH)
                        .padding(.trailing, CodyMetrics.Sidebar.badgeTrailingPadding)
                        .frame(width: barWidth, height: fabSize)
                        .modifier(SearchBarSurface())
                        // [T-ios-search-bar-glass-hit-hole] `glassEffect(in:)`
                        // RENDERS a capsule but contributes no hit region of
                        // its own, and this row sits in a `safeAreaInset` over
                        // the session List — an inset does not swallow touches
                        // where it has nothing hit-testable. So every point of
                        // the bar not covered by a real control (icon,
                        // TextField, X button) passed the touch straight
                        // through to the cell scrolling underneath and opened
                        // whatever session or folder was there.
                        //
                        // Declaring the capsule's shape restores the hit region
                        // to match what is drawn. NOTE this is necessary but
                        // not sufficient on its own: verified on device that
                        // the capsule still cannot fully consume taps (the
                        // a11y tree exposes no element for it, only its
                        // children), so the durable part of this fix is the
                        // enlarged, explicitly-shaped X target in
                        // `searchClearButton` — that is what the user actually
                        // aims at, and it now hits at all four corners.
                        .contentShape(.capsule)
                        .modifier(FABGlassMorphID(namespace: searchGlassNamespace))
                        .position(x: barX + barWidth / 2, y: fabSize / 2)
                    }
                    .modifier(FABSearchTransition(anchor: searchAnchor))
                    .onAppear { searchFocused = true }
                } else {
                    // Search FAB (draggable, inverted side)
                    DraggableFAB(
                        fabOnLeft: $fabOnLeft,
                        dragOffset: $searchDragOffset,
                        didDrag: $searchDidDrag,
                        inverted: true
                    ) { [fabActions] in
                        fabActions.send(.openSearch)
                    } label: {
                        Self.fabCircleSurface(isPrimary: false) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 22, weight: .semibold))
                        }
                            .accessibilityLabel(Text("Search chats..."))
                            .modifier(FABGlassMorphID(namespace: searchGlassNamespace))
                    }
                    .modifier(FABSearchTransition(anchor: searchAnchor))
                }
            }
        }
        .modifier(FABSearchAnimation(showSearchBar: showSearchBar))
        .frame(height: CodySpacing.s56)
        .padding(.bottom, CodySpacing.xl)
    }
}

private struct FABCircleSurface: ViewModifier {
    let isPrimary: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let icon = content
            .foregroundStyle(isPrimary ? CodyColors.interactivePrimaryLabel : CodyColors.textPrimary)
            .frame(width: CodySpacing.s56, height: CodySpacing.s56)

        Group {
            if isPrimary {
                icon
                    .background(CodyColors.interactivePrimaryBg, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: CodySpacing.sm, y: CodySpacing.xs)
            } else if #available(iOS 26.0, *), !reduceTransparency {
                icon.glassEffect(.regular.interactive(), in: .circle)
            } else {
                icon
                    .background(CodyColors.bgSecondary, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(CodyColors.borderDefault, lineWidth: CodySpacing.px)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: .black.opacity(0.15), radius: CodySpacing.sm, y: CodySpacing.xs)
            }
        }
        // The interaction and menu preview both use the full circular surface.
        .contentShape(Circle())
        .contentShape(.contextMenuPreview, Circle())
    }
}

private struct FABSearchTransition: ViewModifier {
    let anchor: UnitPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .identity : .scale(scale: 0.85, anchor: anchor).combined(with: .opacity))
    }
}

private struct FABSearchAnimation: ViewModifier {
    let showSearchBar: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: showSearchBar)
    }
}
