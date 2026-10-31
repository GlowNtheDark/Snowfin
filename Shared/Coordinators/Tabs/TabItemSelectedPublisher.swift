//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension TabCoordinator {

    typealias TabItemSelectedPublisher = LegacyEventPublisher<TabCoordinator.SelectedEvent>
}

@MainActor
final class TabContentFocusHandoff: ObservableObject {

    @Published
    private(set) var pendingTabID: String?

    func begin(tabID: String?) {
        guard pendingTabID != tabID else { return }
        pendingTabID = tabID
        #if DEBUG && os(tvOS)
        LibraryFocusDiagnostics.record("handoff-began", tabID: tabID)
        #endif
    }

    func complete(tabID: String?) {
        guard let tabID, pendingTabID == tabID else { return }
        pendingTabID = nil
        #if DEBUG && os(tvOS)
        LibraryFocusDiagnostics.record("handoff-completed", tabID: tabID)
        #endif
    }
}

@propertyWrapper
struct TabItemSelected: DynamicProperty {

    @Environment(\.tabItemSelected)
    private var publisher

    var wrappedValue: TabCoordinator.TabItemSelectedPublisher {
        publisher
    }
}

extension EnvironmentValues {

    @Entry
    var tabItemSelected: TabCoordinator.TabItemSelectedPublisher = .init()

    @Entry
    var isTabContentFocusable: Bool = true
}
