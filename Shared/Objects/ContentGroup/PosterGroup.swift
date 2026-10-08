//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct PosterGroup<Library: PagingLibrary>: ContentGroup,
    HomeCollectionInvalidatableContentGroup,
    SearchCollectionInvalidatableContentGroup
    where Library.Element: LibraryElement, Library.Element: Poster
{

    struct Environment: WithDefaultValue, WithViewContext {

        var isHeaderButtonEnabled: Bool = true
        var viewContext: ViewContext = .init()

        static var `default`: Self {
            .init()
        }
    }

    let displayTitle: String
    let environment: Environment
    let id: String
    let library: Library
    let posterDisplayType: PosterDisplayType
    let posterSize: PosterDisplayType.Size
    let viewModel: PagingLibraryViewModel<Library>

    var _shouldBeResolved: Bool {
        viewModel.elements.isNotEmpty
    }

    func shouldRefreshHomeCollection(after update: ItemUpdate) -> Bool {
        viewModel.refreshesForItemStateChanges && viewModel.shouldRefreshCollection(after: update)
    }

    func shouldRefreshHomeCollection(afterDeletingItemID itemID: String) -> Bool {
        viewModel.refreshesForItemStateChanges && viewModel.shouldRefreshCollection(afterDeletingItemID: itemID)
    }

    func refreshHomeCollection() async {
        await viewModel.refreshCollectionForHomeChange()
    }

    func invalidateSearchCollection(after update: ItemUpdate) -> Bool {
        viewModel.invalidateSearchCollection(after: update)
    }

    func refreshSearchCollection() async {
        await viewModel.refreshCollectionForSearchChange()
    }

    init(
        id: String = UUID().uuidString,
        library: Library,
        posterDisplayType: PosterDisplayType = .portrait,
        posterSize: PosterDisplayType.Size = .small,
        environment: Environment,
        refreshesForItemStateChanges: Bool = false
    ) {
        self.displayTitle = library.parent.displayTitle
        self.environment = environment
        self.id = id
        self.library = library
        self.posterDisplayType = posterDisplayType
        self.posterSize = posterSize
        self.viewModel = .init(
            library: library,
            pageSize: 20,
            refreshesForItemStateChanges: refreshesForItemStateChanges
        )
    }

    init(
        id: String = UUID().uuidString,
        library: Library,
        posterDisplayType: PosterDisplayType = .portrait,
        posterSize: PosterDisplayType.Size = .small,
        _viewContext: ViewContext? = nil,
        refreshesForItemStateChanges: Bool = false
    ) {
        self.init(
            id: id,
            library: library,
            posterDisplayType: posterDisplayType,
            posterSize: posterSize,
            environment: .init(viewContext: _viewContext ?? .init()),
            refreshesForItemStateChanges: refreshesForItemStateChanges
        )
    }

    @ViewBuilder
    func body(with viewModel: PagingLibraryViewModel<Library>) -> some View {
        PosterHStackLibrarySection(
            viewModel: viewModel,
            group: self
        )
        .withViewContext(environment.viewContext)
    }
}
