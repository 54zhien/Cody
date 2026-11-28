//
//  ContentView+Navigation.swift
//  Cody - home screen (session list, navigation, settings entry)
//
//  ContentView, navigation: row highlight, alarm lookup, and moving between
//  chats - new-chat requests (notification / Quick Action), pop-to-home,
//  opening or switching sessions, and committing a navigation path that was
//  deferred while the app was in the background.
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI

private let shareLog = AppLogger(category: "Share")
private let draftLog = AppLogger(category: "DraftSession")

// MARK: - [T-nav-stack-diag] Navigation diagnostics

/// [T-nav-stack-diag] Evidence for "starting a new chat while another session is
/// running pulled that session onto the navigation stack" (the bug 5d912c58f
/// targeted; its mechanism was inferred from a log, never reproduced). Nothing
/// here changes navigation - it only records:
///   - every path write the app makes (`write`): who called (file:line), the
///     path before and after, animated or not, deferred or not;
///   - every observed path change (`observe`): the path, the sessions running
///     an agent loop at that moment, whether one of them is on the stack
///     without being the requested target, and whether the observed path
///     differs from the last path the app wrote - i.e. something other than the
///     app's own navigation code changed it.
/// All lines carry `[NavDiag]`; anomalies are warnings with `⚠️`.
// BEGIN NavDiag
@MainActor
enum NavDiag {
    private static let log = AppLogger(category: "NavDiag")
    /// The last path the app wrote (or deferred) - its ids bottom to top - and
    /// where from.
    private static var lastWrite: (ids: [String], caller: String, at: Date)?

    /// The path's elements, bottom to top (session / draft ids). nil when the
    /// path is not codable. `NavigationPath.codable` encodes as
    /// `[type, json-value, type, json-value, ...]`, TOP first.
    static func ids(_ path: NavigationPath) -> [String]? {
        guard let codable = path.codable, let data = try? JSONEncoder().encode(codable),
              let flat = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        var out: [String] = []
        var i = 1
        while i < flat.count {
            let value = (try? JSONDecoder().decode(String.self, from: Data(flat[i].utf8))) ?? flat[i]
            out.append(value)
            i += 2
        }
        return out.reversed()
    }

    static func describe(_ path: NavigationPath) -> String {
        guard let ids = ids(path) else { return "<\(path.count) non-codable>" }
        return "[" + ids.joined(separator: ",") + "]"
    }

    /// Sessions running an agent loop right now (streaming / reasoning / tools).
    static func runningSessions() -> [String] {
        SessionActivityTracker.shared.activeSessions.sorted()
    }

    private static func short(_ ids: [String]) -> String {
        "[" + ids.map { String($0.prefix(8)) }.joined(separator: ",") + "]"
    }

    /// Running sessions on the stack that are not `target`.
    private static func strayRunning(_ ids: [String], target: String?) -> [String] {
        runningSessions().filter { $0 != target && ids.contains($0) }
    }

    /// A path write by the app. `outcome`: committed / deferred-background /
    /// flushed / discarded.
    static func write(event: String, target: String?, before: NavigationPath, after: NavigationPath,
                      animated: Bool, outcome: String, caller: String) {
        let afterIds = ids(after) ?? []
        if outcome != "discarded" { lastWrite = (afterIds, caller, Date()) }
        let stray = strayRunning(afterIds, target: target)
        let line = "[NavDiag] write event=\(event) caller=\(caller) target=\(target?.prefix(8) ?? "-") "
            + "animated=\(animated) outcome=\(outcome) before=\(describe(before)) after=\(describe(after)) "
            + "running=\(short(runningSessions()))"
        if stray.isEmpty {
            log.info(line)
        } else {
            log.warning("⚠️ " + line + " RUNNING-SESSION-NOT-TARGET-IN-STACK=\(short(stray))")
        }
    }

    /// Any change of the compact navigation path, whoever made it.
    static func observe(_ path: NavigationPath, currentTarget: String?) {
        let current = ids(path) ?? []
        let stray = strayRunning(current, target: currentTarget)
        let lastLabel = lastWrite.map { "\($0.caller)@\(String(format: "%.2f", Date().timeIntervalSince($0.at)))s" } ?? "-"
        let base = "[NavDiag] path-changed depth=\(path.count) path=\(describe(path)) target=\(currentTarget?.prefix(8) ?? "-") "
            + "running=\(short(runningSessions())) lastWrite=\(lastLabel)"
        var flags: [String] = []
        if !stray.isEmpty { flags.append("RUNNING-SESSION-NOT-TARGET-IN-STACK=\(short(stray))") }
        // Explained: the path the app last wrote, or a pop of it (swipe back /
        // Back drops from the top without an app write). Anything else - a
        // longer path, or different ids - was not written by the app.
        if let last = lastWrite {
            let isLastWrite = current == last.ids
            let isPop = current.count < last.ids.count && Array(last.ids.prefix(current.count)) == current
            if !isLastWrite && !isPop {
                flags.append("NOT-WRITTEN-BY-APP lastWritten=[\(last.ids.joined(separator: ","))]")
            }
        } else if !current.isEmpty {
            flags.append("NOT-WRITTEN-BY-APP lastWritten=none")
        }
        if flags.isEmpty {
            log.info(base)
        } else {
            log.warning("⚠️ " + base + " " + flags.joined(separator: " "))
        }
    }
}
// END NavDiag

extension ContentView {
    // MARK: - Selection Helpers

    /// Whether a session row should be highlighted as selected.
    func isSessionHighlighted(_ sessionId: String) -> Bool {
        if selectedSessionId == sessionId { return true }
        // Highlight the real session when a draft is selected and it has been persisted
        if let selId = selectedSessionId, Self.isNewSessionId(selId), sessionId == newSessionRealId { return true }
        return false
    }

    func fetchAlarmsIfNeeded() {
        // AlarmOffloadBridge references AlarmKit types (AlarmMetadata).
        // On OS versions where AlarmKit doesn't exist (e.g. macOS 14),
        // merely referencing the class triggers Swift runtime type resolution
        // that crashes in swift_getTypeByMangledNameInContextImpl.
        // Use a helper that isolates the reference behind @available.
        //
        // [T-visionos-alarmkit-launch] @available alone is the condition the
        // 1.14(11) xrOS crash passed: visionOS reports a mapped iOS version
        // >= 26, so the check succeeds and the app enters AlarmKit-typed
        // Swift with no AlarmKit present. a52085dc2 added the class probe but
        // only wired it into the apple-alarm shell command; this call runs
        // on every launch, session change and foreground, so it is the more
        // likely origin of the report. Same probe, same order: OS version
        // first, then "does the framework actually exist".
        guard #available(iOS 26.0, *), alarmkit_is_usable() else { return }
        _fetchAlarmsImpl()
    }

    @available(iOS 26.0, *)
    private func _fetchAlarmsImpl() {
        AlarmOffloadBridge.listAlarms { arr, _ in
            DispatchQueue.main.async {
                hasAlarms = (arr?.count ?? 0) > 0
            }
        }
    }

    // MARK: - Navigation Helper

    /// Open a fresh draft, or let the shortcut workflow first unwind any
    /// pushed destination before dispatching to its own draft.
    func handleNewChatRequest() {
        let newId = Self.makeNewSessionId()
        // Clear any stale flags left over from a prior quick-action
        // request that didn't run to completion (user backgrounded the
        // app, the pop-then-push dance got interrupted, etc).
        pendingNewChatAfterPop = false
        pendingNewChatTargetId = nil
        // If a workflow is mid-flight in ensuringHome, ContentView's
        // observers (`onChange(navigationPath)` / `onChange(selectedSessionId)`)
        // drive the home-then-open sequence. Otherwise this call came
        // from a non-quick-action source (in-app menu "New Chat") and
        // we just open directly.
        let workflowEnsuringHome: Bool = {
            if case .ensuringHome = QuickActionWorkflow.shared.state { return true }
            return false
        }()
        if workflowEnsuringHome {
            popToHomeForQuickAction()
            return
        }
        if isWideLayout {
            openSession(newId)
        } else {
            commitNavigationPath(NavigationPath([newId]))
        }
    }

    /// Drive the quick-action workflow's `ensuringHome → pendingDispatch
    /// → waitingForChatMount` sequence. Pops whatever session is on top
    /// without animation; observers (see below) call `markHome` once
    /// the unwind is observable, and a separate observer for
    /// `pendingDispatch` opens the new session.
    private func popToHomeForQuickAction() {
        // [T-ios-bg-nav-push-watchdog] A pop supersedes any push still held
        // back from the background — flushing it later would resurrect a
        // session the workflow just asked us to leave. Dropped before the
        // `alreadyHome` check so the early return can't strand it either.
        //
        // Popping itself is NOT deferred: it tears a screen down rather than
        // laying a new one out (so it doesn't carry the cost this gate exists
        // to keep out of the watchdog window), and the quick-action state
        // machine advances from the `onChange(of: navigationPath)` observer
        // this write triggers — holding it back would stall `markHome`.
        pendingBackgroundNavigation = nil
        let alreadyHome = isWideLayout ? (selectedSessionId == nil) : navigationPath.isEmpty
        if alreadyHome {
            // Same-runloop advance — no SwiftUI commit needed.
            QuickActionWorkflow.shared.markHome()
            return
        }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            if isWideLayout {
                selectedSessionId = nil
            } else {
                navigationPath = NavigationPath()
            }
        }
        // `onChange(navigationPath)` / `onChange(selectedSessionId)`
        // will fire next runloop with the empty state and call
        // `markHome` from there.
    }

    /// React to workflow state advancing past ensuringHome. When the
    /// workflow says it's ready for a session, mint a fresh draft id
    /// and open it; attach to the workflow so AIChatView's modifier
    /// can match.
    func openSessionForPendingQuickAction() {
        guard case .pendingDispatch = QuickActionWorkflow.shared.state else { return }
        let newId = Self.makeNewSessionId()
        if isWideLayout {
            openSession(newId)
        } else {
            commitNavigationPath(NavigationPath([newId]))
        }
        QuickActionWorkflow.shared.attachTargetSession(newId)
    }

    /// [T-ios-bg-nav-push-watchdog] Coalesce compact route requests during
    /// background execution and apply the newest request once visible.
    private func commitNavigationPath(_ newPath: NavigationPath, animated: Bool = false,
                                      target: String? = nil,
                                      file: String = #fileID, line: Int = #line) {
        let caller = "\((file as NSString).lastPathComponent):\(line)"
        // [T-share-first-tap-no-response] `.inactive` is NOT the state this
        // gate was built for. The watchdog kills it prevents come from a push
        // running AIChatView's whole first layout while the app is genuinely
        // BACKGROUNDED (T-ios-bg-nav-push-watchdog); `.inactive` means the app
        // is on its way to the foreground — the system is about to give it a
        // full frame budget — and iOS delivers `openURL` in exactly that state.
        //
        // Device log 2026-08-18 23:55:31: the share URL arrived at .478 with
        // the app `.inactive`, the navigation was deferred, and `.active` only
        // landed 31ms later. The user saw the app open on the home screen with
        // nothing happening and tapped Share a second time — the reported
        // "first tap does nothing". Deferring here bought no safety: the flush
        // performs the identical push moments later, just after the user has
        // already given up on it.
        let appState = UIApplication.shared.applicationState
        if appState == .background {
            // Coalesce: only the newest requested destination matters. An
            // earlier pending push that never became visible has nothing to
            // preserve. Overwriting also restarts the TTL, which is correct —
            // the newest request is the one whose freshness we care about.
            pendingBackgroundNavigation = (newPath, Date())
            shareLog.info("🔄SESSION deferring nav commit — app backgrounded (count=\(newPath.count))")
            NavDiag.write(event: "commit", target: target, before: navigationPath, after: newPath,
                          animated: animated, outcome: "deferred-background", caller: caller)
            return
        }
        pendingBackgroundNavigation = nil
        // The last string in a compact route request selects the Nova root.
        // Only destinations pushed inside that root occupy the live stack.
        let target = target ?? NavDiag.ids(newPath)?.last
        let newPath = target == nil ? newPath : NavigationPath()
        NavDiag.write(event: "commit", target: target, before: navigationPath, after: newPath,
                      animated: animated, outcome: "committed", caller: caller)
        if target != nil { closeNovaDrawer() }
        if animated {
            navigationPath = newPath
            if let target { activateNovaSession(target) }
            return
        }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            navigationPath = newPath
            if let target { activateNovaSession(target) }
        }
    }

    // BEGIN NavPushAnimationRule
    /// [T-nav-row-push-animation] Whether a `switchToSession` may animate.
    ///
    /// 5d912c58f moved list-row taps off the row's hidden NavigationLink onto
    /// `commitNavigationPath`, which always disables animations - so opening any
    /// chat from the list lost its push animation. The disabled transaction is
    /// there for REPLACING a page that is already on screen (move-to /
    /// notification opens): an animated pop-then-push there lets SwiftUI drop
    /// the push (T-ios-moveto-transfer-race). A row tap from the home list is
    /// not that case - the stack is empty, so `[] -> [id]` is an ordinary push
    /// with nothing to pop. Animate only then:
    ///   - the caller asked for it (row taps only; the FAB / folder / empty-state
    ///     new chat, move-to and notification opens never animated and still
    ///     don't);
    ///   - the stack is empty (nothing is replaced, so no pop-then-push);
    ///   - no background-deferred navigation is pending (it is the newer truth
    ///     and is flushed without animation);
    ///   - the app is active (an `.inactive` launch / openURL transition is not
    ///     the moment for a push animation).
    static func shouldAnimateSessionPush(requested: Bool, pathIsEmpty: Bool,
                                         hasPendingBackgroundNavigation: Bool,
                                         appIsActive: Bool) -> Bool {
        requested && pathIsEmpty && !hasPendingBackgroundNavigation && appIsActive
    }
    // END NavPushAnimationRule

    /// Apply a navigation change that was held back while backgrounded.
    /// Called from the `scenePhase == .active` observer.
    func flushPendingBackgroundNavigation() {
        guard let pending = pendingBackgroundNavigation else { return }
        // Re-check rather than trust the caller: the `.onAppear` backstop can
        // run while still backgrounded, and committing there would reinstate
        // exactly the synchronous background push this gate exists to prevent.
        // Keep it pending — a later flush will take it.
        // [T-share-first-tap-no-response] Mirrors commitNavigationPath: only a
        // genuinely BACKGROUNDED app must hold the push back. Blocking on
        // `.inactive` here too would re-deny the flush during the very
        // foreground transition that is supposed to release it.
        guard UIApplication.shared.applicationState != .background else { return }
        // Consume before the staleness check, not after: an expired request is
        // dropped for good. Leaving it parked would let a later foreground —
        // which is even further from the original intent — try again.
        pendingBackgroundNavigation = nil
        let age = Date().timeIntervalSince(pending.deferredAt)
        guard age <= Self.pendingBackgroundNavigationTTL else {
            shareLog.info("🔄SESSION discarding deferred nav commit — stale (age=\(Int(age))s > \(Int(Self.pendingBackgroundNavigationTTL))s, count=\(pending.path.count))")
            NavDiag.write(event: "flush", target: nil, before: navigationPath, after: pending.path,
                          animated: false, outcome: "discarded", caller: "flushPendingBackgroundNavigation")
            return
        }
        shareLog.info("🔄SESSION flushing deferred nav commit (count=\(pending.path.count) age=\(Int(age))s)")
        let target = NavDiag.ids(pending.path)?.last
        let path = target == nil ? pending.path : NavigationPath()
        NavDiag.write(event: "flush", target: target, before: navigationPath, after: path,
                      animated: false, outcome: "flushed", caller: "flushPendingBackgroundNavigation")
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            if isWideLayout, let target {
                openSession(target)
            } else {
                navigationPath = path
                if let target { activateNovaSession(target) }
            }
        }
        closeNovaDrawer()
    }

    /// Replace the displayed conversation in one transaction for a sidebar
    /// tap, move-to transfer, or external route.
    func switchToSession(_ id: String, animated: Bool = false,
                         file: String = #fileID, line: Int = #line) {
        if isWideLayout {
            openSession(id)
            return
        }
        searchFocused = false
        let animate = Self.shouldAnimateSessionPush(
            requested: animated,
            pathIsEmpty: navigationPath.isEmpty,
            hasPendingBackgroundNavigation: pendingBackgroundNavigation != nil,
            appIsActive: UIApplication.shared.applicationState == .active)
        commitNavigationPath(NavigationPath([id]), animated: animate, target: id, file: file, line: line)
    }

    func openNovaDrawer() {
        dismissNovaKeyboard()
        withAnimation(CodyMotion.resolved(CodyMotion.drawer, reduceMotion: reduceMotion)) {
            isNovaDrawerOpen = true
        }
    }

    func closeNovaDrawer() {
        searchFocused = false
        withAnimation(CodyMotion.resolved(CodyMotion.drawer, reduceMotion: reduceMotion)) {
            isNovaDrawerOpen = false
        }
    }

    func dismissNovaKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func startNewNovaChat() {
        handleNewChatRequest()
    }

    func selectNovaDestination(_ destination: CodyNovaDestination) {
        dismissSearchIfEmptyOnNavigate()
        closeNovaDrawer()
        switch destination {
        case .tool(.terminal):
            showTerminal = true
        case .tool(.browser):
            activeToolSheet = .browser
        case .tool(.alarms):
            if #available(iOS 26.0, *), alarmkit_is_usable() {
                showAlarmList = true
            } else {
                novaDestination = destination
            }
        default:
            withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                novaDestination = destination
            }
        }
    }

    func novaDestinationChanged(_ destination: CodyNovaDestination) {
        if destination != .home {
            let leaving = isWideLayout ? selectedSessionId : currentStackSessionId
            suspendNovaSessionForTransition(leaving.flatMap { persistedSessionId(for: $0) })
            AIChatViewModel.activeSessionId = nil
            AlwaysOnController.shared.chatSelectionChanged(to: nil)
        }
    }

    func updateNovaLayout(wide: Bool) {
        if wide {
            closeNovaDrawer()
            if !searchText.isEmpty { showSearchBar = true }
            selectedSessionId = navigationPath.isEmpty ? novaActiveSessionId : currentStackSessionId
            if selectedSessionId != activeDraftId { clearDraftTracking() }
        } else {
            novaActiveSessionId = selectedSessionId ?? Self.makeNewSessionId()
            currentStackSessionId = novaActiveSessionId
            selectedSessionId = novaActiveSessionId
        }
        navigationPath = NavigationPath()
        previousStackSessionId = nil
        isWideLayout = wide
    }

    var splitSessionSelection: Binding<String?> {
        Binding(get: { novaDestination == .home ? selectedSessionId : nil }, set: { id in
            if let id { openSession(id) }
            else { selectedSessionId = nil }
        })
    }

    private func activateNovaSession(_ id: String) {
        let route = draftRoute(for: id)
        if route != novaActiveSessionId {
            let outgoing = persistedSessionId(for: novaActiveSessionId)
            suspendNovaSessionForTransition(outgoing)
            if outgoing != nil { scheduleOutgoingPreviewRefresh() }
            clearDraftTracking()
            novaActiveSessionId = route
        }
        currentStackSessionId = route
        selectedSessionId = route
        novaDestination = .home
        clearNovaUnread(route)
    }

    private func draftRoute(for id: String) -> String {
        if id == newSessionRealId, let activeDraftId { return activeDraftId }
        return id
    }

    private func clearDraftTracking() {
        newSessionRealId = nil
        activeDraftId = nil
    }

    func persistedSessionId(for route: String) -> String? {
        if let remote = Self.remoteSessionRoute(route) { return remote.sessionId }
        if Self.isNewSessionId(route) { return route == activeDraftId ? newSessionRealId : nil }
        return route
    }

    func handlePersistedDraft(_ sessionId: String, draftId: String?) {
        let route = isWideLayout ? selectedSessionId : novaActiveSessionId
        if let draftId, Self.isNewSessionId(draftId), draftId == route {
            newSessionRealId = sessionId
            activeDraftId = draftId
            if novaDestination == .home, isWideLayout || navigationPath.isEmpty {
                SessionBadgeStore.shared.remove(.unread, for: sessionId)
            }
            draftLog.info("🔑DRAFT sessionDidCreate ACCEPTED newSessionRealId=\(sessionId) activeDraftId=\(draftId)")
        }
        refreshSessionList()
    }

    func novaChatAppeared(_ id: String, isPushed: Bool = false) {
        guard !isWideLayout, novaDestination == .home, isPushed || navigationPath.isEmpty else { return }
        currentStackSessionId = id
        selectedSessionId = id
        clearNovaUnread(id)
        let localId = Self.remoteSessionRoute(id) == nil ? persistedSessionId(for: id) : nil
        AIChatViewModel.activeSessionId = localId
        AlwaysOnController.shared.chatSelectionChanged(to: id)
    }

    func suspendNovaSessionForTransition(_ id: String?) {
        guard let id, let vm = ViewModelCache.shared.get(for: id) else { return }
        vm.setSuspendedForTransition(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak vm] in
            vm?.setSuspendedForTransition(false)
        }
    }

    private func clearNovaUnread(_ id: String) {
        SessionBadgeStore.shared.remove(.unread, for: persistedSessionId(for: id) ?? id)
    }

    static func remoteSessionRoute(_ id: String) -> (deviceId: String, sessionId: String)? {
        guard id.hasPrefix("remote:") else { return nil }
        let parts = id.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
        return (String(parts[1]), String(parts[2]))
    }

    /// Opens a session in the appropriate layout mode.
    func openSession(_ id: String, file: String = #fileID, line: Int = #line) {
        draftLog.info("🔑DRAFT openSession id=\(id) isWide=\(isWideLayout) prevSel=\(selectedSessionId ?? "nil") prevReal=\(newSessionRealId ?? "nil") prevDraft=\(activeDraftId ?? "nil")")
        // Dismiss keyboard when navigating to a session
        searchFocused = false
        if isWideLayout {
            let route = draftRoute(for: id)
            if route != selectedSessionId { clearDraftTracking() }
            novaDestination = .home
            selectedSessionId = route
            draftLog.info("🔑DRAFT openSession DONE selectedSessionId=\(id)")
        } else {
            // Preserve the latest route even if another request is deferred.
            var next = pendingBackgroundNavigation?.path ?? navigationPath
            next.append(id)
            commitNavigationPath(next, target: id, file: file, line: line)
        }
    }
}
