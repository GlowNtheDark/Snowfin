//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

/// Movies with the highest server play count, with rating used to keep ties stable.
struct PopularMoviesLibrary: BaseItemKindLibrary {

    let libraryItemTypes: [BaseItemKind] = [.movie]
    let parent: TitledLibraryParent = .init(
        displayTitle: String(localized: "popularMovies", defaultValue: "Popular Movies"),
        id: "popular-movies"
    )

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.includeItemTypes = [.movie]
        parameters.isRecursive = true
        parameters.limit = pageState.pageSize
        parameters.sortBy = [.playCount, .communityRating]
        parameters.sortOrder = [.descending]
        parameters.startIndex = pageState.pageOffset
        parameters.userID = pageState.userSession.user.id

        let request = Paths.getItems(parameters: parameters)
        let response = try await pageState.userSession.client.send(request)

        return response.value.items ?? []
    }
}
