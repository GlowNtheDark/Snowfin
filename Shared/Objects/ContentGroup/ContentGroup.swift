//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// TODO: Relax `WithRefresh` requirement?

typealias ContentGroupBuilder = ArrayBuilder<any ContentGroup>

@MainActor
protocol ContentGroup<ViewModel>: Identifiable {

    associatedtype Body: View
    associatedtype ViewModel: WithRefresh

    var id: String { get }
    var viewModel: ViewModel { get }
    var _shouldBeResolved: Bool { get }

    @ViewBuilder
    func body(with viewModel: ViewModel) -> Body
}

extension ContentGroup {
    var _shouldBeResolved: Bool {
        true
    }
}

@MainActor
protocol HomeCollectionInvalidatableContentGroup {

    var id: String { get }

    func shouldRefreshHomeCollection(after update: ItemUpdate) -> Bool
    func shouldRefreshHomeCollection(afterDeletingItemID itemID: String) -> Bool
    func refreshHomeCollection() async
}

@MainActor
protocol SearchCollectionInvalidatableContentGroup {

    var id: String { get }

    func invalidateSearchCollection(after update: ItemUpdate) -> Bool
    func refreshSearchCollection() async
}

extension ContentGroup where ViewModel == Empty {
    var viewModel: Empty {
        .init()
    }
}
