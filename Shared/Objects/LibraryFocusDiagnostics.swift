//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if DEBUG && os(tvOS)
import Foundation
import OSLog

enum LibraryFocusDiagnostics {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.snowfin.tvos",
        category: "LibraryFocusDiagnostics"
    )

    static func record(_ event: String, tabID: String? = nil, detail: String = "") {
        let uptime = ProcessInfo.processInfo.systemUptime
        logger.debug(
            "uptime=\(uptime, privacy: .public) event=\(event, privacy: .public) tab=\(tabID ?? "-", privacy: .public) detail=\(detail, privacy: .public)"
        )
    }
}
#endif
