//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import SwiftUI

enum SidebarClockTimeFormat: String, CaseIterable, Defaults.Serializable {
    case system
    case twelveHour
    case twentyFourHour

    var title: String {
        switch self {
        case .system: L10n.systemDefault
        case .twelveHour: L10n.twelveHour
        case .twentyFourHour: L10n.twentyFourHour
        }
    }
}

enum SidebarClockSize: String, CaseIterable, Defaults.Serializable {
    case small
    case medium
    case large

    var fontSize: CGFloat {
        switch self {
        case .small: 16
        case .medium: 22
        case .large: 28
        }
    }

    var title: String {
        switch self {
        case .small: L10n.small
        case .medium: L10n.medium
        case .large: L10n.large
        }
    }
}

struct SidebarClock: View {

    @Default(.sidebarClockTimeFormat)
    private var timeFormat

    @Default(.sidebarClockSize)
    private var size

    @Environment(\.screenTheme)
    private var screenTheme

    var body: some View {
        TimelineView(.periodic(from: nextMinute, by: 60)) { context in
            Text(formattedTime(context.date))
                .font(.system(size: size.fontSize, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(screenTheme.foregrounds.secondary.swiftUIColor)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var nextMinute: Date {
        Calendar.current.dateInterval(of: .minute, for: .now)?.end ?? .now
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .none

        switch timeFormat {
        case .system:
            formatter.timeStyle = .short
        case .twelveHour:
            formatter.dateFormat = "h:mm a"
        case .twentyFourHour:
            formatter.dateFormat = "HH:mm"
        }

        return formatter.string(from: date)
    }
}
