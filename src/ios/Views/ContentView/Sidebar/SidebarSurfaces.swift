//
//  SidebarSurfaces.swift
//  Cody - home screen (session list, navigation, settings entry)
//
//  View modifiers and backgrounds of the sidebar: selection opt-out, folder
//  header visibility probe, folder card / member-row surfaces (one source of
//  truth for the folder look), and the search bar / FAB glass styling.
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI

struct SidebarListCanvas: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(CodyColors.bgCanvas)
    }
}

struct SidebarSectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(CodyTypography.sectionHeader)
            .foregroundStyle(CodyColors.textSecondary)
            .textCase(nil)
            .padding(.horizontal, CodyMetrics.Sidebar.rowPaddingH)
            .frame(maxWidth: .infinity, minHeight: CodyMetrics.Sidebar.sectionHeaderHeight, alignment: .leading)
            .listRowInsets(EdgeInsets())
    }
}

/// List-selection opt-out with an availability floor. The folder card row
/// must never become the List(selection:)'s selected value — its "tap" is
/// collapse/expand, not navigation — but .selectionDisabled is iOS 17+ and
/// the app floors at 16 (where the plain Button row doesn't self-select).
struct SelectionDisabledIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.selectionDisabled()
        } else {
            content
        }
    }
}

/// Tracks whether an expanded folder's header card has scrolled out above
/// the list's visible top, reporting only on TRANSITIONS (Bool onChange) so
/// scroll frames don't churn ContentView state. Lives in the header row's
/// background — geometry is read in .global and compared against the
/// threshold the mini-bar overlay measured, which sidesteps the known-flaky
/// preference propagation across List cell hosting boundaries entirely.
///
/// `lastMaxY` exists for the CULLING edge: when the List recycles the header
/// cell far offscreen, onDisappear is the only signal left, and it alone
/// can't tell "culled above" from "culled below". The last observed frame
/// disambiguates. onDisappear also fires on collapse and on entering select
/// mode (the header row unmounts) — those reports are harmless because the
/// mini-bar's display guard independently requires an expanded folder
/// outside select mode.
struct FolderHeaderVisibilityProbe: View {
    let folderId: String
    let thresholdY: CGFloat
    let onVisibilityChange: (String, Bool) -> Void

    @State private var lastMaxY: CGFloat = .infinity

    var body: some View {
        GeometryReader { geo in
            let maxY = geo.frame(in: .global).maxY
            let hidden = maxY < thresholdY
            Color.clear
                .onAppear {
                    lastMaxY = maxY
                    onVisibilityChange(folderId, hidden)
                }
                .onChange(of: maxY) { newValue in
                    lastMaxY = newValue
                }
                .onChange(of: hidden) { newValue in
                    onVisibilityChange(folderId, newValue)
                }
                .onDisappear {
                    onVisibilityChange(folderId, lastMaxY < thresholdY)
                }
        }
    }
}

/// One row's share of the expanded container's OUTER border. The top kind
/// draws the top arc + upper side walls, middle draws side walls only, and
/// bottom draws the lower walls + bottom arc — tiled across the group's rows
/// they form one continuous rounded-rect highlight, with no horizontal lines
/// at the row boundaries (which a per-segment full stroke would create).
private struct FolderSegmentBorder: Shape {
    enum Kind { case top, middle, bottom }
    let kind: Kind
    var radius: CGFloat = CodyRadius.surface

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch kind {
        case .top:
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            p.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                     radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            p.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            p.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                     radius: radius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .middle:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottom:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
            p.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                     radius: radius, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            p.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
            p.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                     radius: radius, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        return p
    }
}

/// Expanded search uses one capsule surface around the field and controls.
struct SearchBarSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if reduceTransparency {
                content
                    .background(CodyColors.bgElevatedPrimary, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(CodyColors.borderDefault, lineWidth: CodySpacing.px)
                            .allowsHitTesting(false)
                    }
            } else {
                content.glassEffect(.regular, in: .capsule)
            }
        } else {
            content
                .background(CodyColors.bgSecondary, in: Capsule())
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
        }
    }
}

/// Tags the search FAB and the expanded search bar with ONE shared
/// `glassEffectID`.
///
/// Currently INERT: `glassEffectID` only does anything inside a
/// `GlassEffectContainer`, and the FAB row no longer has one — that container
/// suppressed the new-chat FAB's context menu, see the note on `fabRow`. The
/// modifier is kept (harmless, and it costs nothing) so that if the container
/// is ever reinstated with the menu problem solved, the morph works again
/// without re-deriving the id plumbing. The row's scale+opacity transition is
/// what actually animates the swap today.
struct FABGlassMorphID: ViewModifier {
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffectID("fabSearch", in: namespace)
        } else {
            content
        }
    }
}

/// A stable fill and hairline across collapsed and expanded folder rows.
private struct FolderSurface: ViewModifier {
    enum Kind { case lone, top, middle, bottom }
    let kind: Kind
    @Environment(\.colorScheme) private var colorScheme

    private var shape: AnyShape {
        let radius = CodyRadius.surface
        switch kind {
        case .lone:
            return AnyShape(RoundedRectangle(cornerRadius: radius, style: .circular))
        case .top:
            return AnyShape(UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .circular))
        case .middle:
            return AnyShape(Rectangle())
        case .bottom:
            return AnyShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .circular))
        }
    }

    private var border: AnyShape {
        switch kind {
        case .lone:
            return AnyShape(RoundedRectangle(cornerRadius: CodyRadius.surface, style: .circular))
        case .top:
            return AnyShape(FolderSegmentBorder(kind: .top))
        case .middle:
            return AnyShape(FolderSegmentBorder(kind: .middle))
        case .bottom:
            return AnyShape(FolderSegmentBorder(kind: .bottom))
        }
    }

    func body(content: Content) -> some View {
        content
            .background(shape.fill(colorScheme == .dark ? CodyColors.bgPrimary : CodyColors.bgElevatedPrimary))
            .overlay {
                border.stroke(CodyColors.borderLight, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
    }
}

struct FolderCardBackground: ViewModifier {
    let isDropTarget: Bool
    let isExpanded: Bool

    private var dropShape: AnyShape {
        isExpanded
            ? AnyShape(UnevenRoundedRectangle(
                topLeadingRadius: CodyRadius.surface, topTrailingRadius: CodyRadius.surface, style: .circular))
            : AnyShape(RoundedRectangle(cornerRadius: CodyRadius.surface, style: .circular))
    }

    func body(content: Content) -> some View {
        content
            .modifier(FolderSurface(kind: isExpanded ? .top : .lone))
            .overlay {
                if isDropTarget {
                    ZStack {
                        dropShape.fill(CodyColors.textAccent.opacity(0.15))
                        dropShape.stroke(CodyColors.textAccent, lineWidth: 1.5)
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

/// Middle/bottom rows of an expanded group: the SAME FolderSurface as the
/// collapsed card, with the corner segmentation and border tiling that
/// multi-row composition needs.
struct FolderMemberRowBackground: View {
    let isLast: Bool

    var body: some View {
        Color.clear
            .modifier(FolderSurface(kind: isLast ? .bottom : .middle))
            .padding(.horizontal, CodySpacing.xsPlus)
            .padding(.bottom, isLast ? CodySpacing.xs : 0)
    }
}
