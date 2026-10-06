//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

struct LatestInLibrary: BaseItemKindLibrary {

    let libraryItemTypes: [BaseItemKind]
    let parent: TitledLibraryParent

    init(library: BaseItemDto) {
        self.parent = .init(
            displayTitle: L10n.latestWithString(library.displayTitle),
            id: library.id
        )
        self.libraryItemTypes = library.supportedItemTypes
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        let latestPremiereDate = Date.now
        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.includeItemTypes = libraryItemTypes
        parameters.isRecursive = true
        parameters.limit = pageState.pageSize
        parameters.maxPremiereDate = latestPremiereDate
        parameters.parentID = parent.id
        parameters.sortBy = [.premiereDate, .dateCreated, .sortName]
        parameters.sortOrder = [.descending, .descending, .ascending]
        parameters.startIndex = pageState.pageOffset
        parameters.userID = pageState.userSession.user.id

        let request = Paths.getItems(parameters: parameters)
        let response = try await pageState.userSession.client.send(request)

        return (response.value.items ?? []).filter { item in
            guard let premiereDate = item.premiereDate else { return false }
            return premiereDate <= latestPremiereDate
        }
    }
}
