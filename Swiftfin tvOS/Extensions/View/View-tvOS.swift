//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI
import SwiftUIIntrospect
import UIKit

extension View {

    /// - Important: This does nothing on tvOS.
    @ViewBuilder
    func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> some View {
        self
    }

    /// - Important: This does nothing on tvOS.
    @ViewBuilder
    func navigationBarCloseButton(
        disabled: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View {
        self
    }

    /// - Important: This does nothing on tvOS.
    @ViewBuilder
    func statusBarHidden() -> some View {
        self
    }

    /// - Important: This does nothing on tvOS.
    @ViewBuilder
    func prefersStatusBarHidden(_ hidden: Bool = true) -> some View {
        self
    }

    @ViewBuilder
    func tvSearchFocusRegistration(_ coordinator: TVSearchFocusCoordinator) -> some View {
        introspect(
            .searchField,
            on: .tvOS(.v15, .v16, .v17, .v18, .v26),
            scope: .ancestor
        ) { searchBar in
            coordinator.register(searchBar)
        }
        .onAppear { coordinator.setRootVisible(true) }
        .onDisappear { coordinator.setRootVisible(false) }
    }
}

@MainActor
final class TVSearchFocusCoordinator: ObservableObject {

    @Published
    private(set) var entryRequest = 0

    fileprivate weak var host: TVSearchHostingController?
    private weak var searchBar: UISearchBar?
    fileprivate private(set) var isRootVisible = false
    fileprivate private(set) var hasPendingEntry = false
    private var updateScheduled = false

    var isFieldFocused: Bool {
        containsField(searchBar?.window?.windowScene?.focusSystem?.focusedItem as? UIView)
    }

    fileprivate var fieldTarget: UIView? {
        guard let searchBar, searchBar.window != nil,
              let host, searchBar.isDescendant(of: host.view),
              !searchBar.isHidden, searchBar.bounds.isEmpty == false
        else { return nil }

        // UISearchBar itself need not be focusable on tvOS. Target its actual
        // focusable control, using public UIView focus information.
        return firstFocusableView(in: searchBar)
    }

    private func firstFocusableView(in view: UIView) -> UIView? {
        guard !view.isHidden, view.alpha > 0 else { return nil }
        if view.canBecomeFocused {
            return view
        }
        return view.subviews.lazy.compactMap { self.firstFocusableView(in: $0) }.first
    }

    fileprivate func containsField(_ view: UIView?) -> Bool {
        guard let view, let searchBar else { return false }
        return view === searchBar || view.isDescendant(of: searchBar)
    }

    func requestEntry() {
        hasPendingEntry = true
        entryRequest &+= 1
        scheduleFocusUpdate()
    }

    func cancelEntry() {
        hasPendingEntry = false
    }

    func register(_ searchBar: UISearchBar) {
        self.searchBar = searchBar
        scheduleFocusUpdate()
    }

    func setRootVisible(_ visible: Bool) {
        isRootVisible = visible
        if visible {
            scheduleFocusUpdate()
        } else {
            cancelEntry()
            searchBar = nil
        }
    }

    fileprivate func scheduleFocusUpdate() {
        guard hasPendingEntry, !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.fulfillEntryIfReady()
        }
    }

    private func fulfillEntryIfReady() {
        // Keep the request until registration, appearance and layout all finish.
        // Their callbacks retry it; no timers or focus-state toggles are needed.
        guard hasPendingEntry, isRootVisible, fieldTarget != nil,
              let host, let system = host.view.window?.windowScene?.focusSystem
        else { return }

        if isFieldFocused {
            cancelEntry()
            return
        }
        system.requestFocusUpdate(to: host)
        system.updateFocusIfNeeded()
    }
}

/// Enclose the Search navigation stack so its native search bar and results
/// share a focus environment. Other sidebar destinations use their existing host.
struct TVSearchFocusContainer<Content: View>: UIViewControllerRepresentable {

    let content: Content
    let focus: TVSearchFocusCoordinator

    func makeUIViewController(context: Context) -> TVSearchHostingController {
        let controller = TVSearchHostingController(rootView: rootView(context), focus: focus)
        focus.host = controller
        return controller
    }

    func updateUIViewController(_ controller: TVSearchHostingController, context: Context) {
        controller.rootView = rootView(context)
        focus.scheduleFocusUpdate()
    }

    private func rootView(_ context: Context) -> AnyView {
        // Apply the inherited environment first, then inject the destination's
        // shared coordinator so replacing EnvironmentValues cannot erase it.
        AnyView(content.environmentObject(focus).environment(\.self, context.environment))
    }
}

final class TVSearchHostingController: UIHostingController<AnyView> {

    private let focus: TVSearchFocusCoordinator

    init(rootView: AnyView, focus: TVSearchFocusCoordinator) {
        self.focus = focus
        super.init(rootView: rootView)
        view.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if focus.hasPendingEntry, let target = focus.fieldTarget {
            return [target]
        }
        return super.preferredFocusEnvironments
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        focus.scheduleFocusUpdate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        focus.scheduleFocusUpdate()
    }

    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        if focus.isRootVisible,
           context.focusHeading.contains(.up),
           let previous = context.previouslyFocusedView, previous.isDescendant(of: view),
           context.nextFocusedView.map({ !$0.isDescendant(of: view) }) ?? true
        {
            return false
        }
        if focus.hasPendingEntry, let next = context.nextFocusedView,
           next.isDescendant(of: view), !focus.containsField(next)
        {
            return false
        }
        return super.shouldUpdateFocus(in: context)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        if focus.containsField(context.nextFocusedView) {
            focus.cancelEntry()
        } else if let previous = context.previouslyFocusedView, previous.isDescendant(of: view),
                  context.nextFocusedView.map({ !$0.isDescendant(of: view) }) ?? true
        {
            focus.cancelEntry()
        }
    }
}

extension EnvironmentValues {

    @Entry
    var presentationCoordinator: PresentationCoordinator = .init()
}

struct PresentationCoordinator {
    var isPresented: Bool = false
}
