//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct ProgressIndicator: View {

    @Default(.accentColor)
    private var accentColor

    let title: String?
    let progress: Double
    let posterDisplayType: PosterDisplayType
    let isCompleted: Bool

    private var progressColor: Color {
        #if os(tvOS)
        isCompleted ? Color(red: 0.25, green: 0.95, blue: 0.62) : accentColor
        #else
        accentColor
        #endif
    }

    private var progressHeight: CGFloat {
        #if os(tvOS)
        isCompleted ? 9 : 6
        #else
        6
        #endif
    }

    @ViewBuilder
    private var compactView: some View {
        Rectangle()
            .fill(progressColor)
            .scaleEffect(x: progress, y: 1, anchor: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: progressHeight)
            .shadow(color: isCompleted ? progressColor.opacity(0.6) : .clear, radius: 5)
    }

    @ViewBuilder
    private var regularView: some View {
        VStack(alignment: .leading, spacing: 5) {

            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.medium)
            }

            ProgressView(value: progress)
                .progressViewStyle(.playback)
                .foregroundStyle(progressColor)
                .frame(height: progressHeight)
                .shadow(color: isCompleted ? progressColor.opacity(0.6) : .clear, radius: 5)
        }
        .padding(.bottom, 5)
        .padding(.horizontal, 5)
        .background(extendedBy: .init(top: 5, leading: 0, bottom: 0, trailing: 0)) {
            Rectangle()
                .fill(Color.black)
                .mask(gradient: .linear) {
                    (location: 0, opacity: 0)
                    (location: 0.5, opacity: 0.7)
                    (location: 1, opacity: 1)
                }
        }
        .colorScheme(.dark)
    }

    var body: some View {
        if posterDisplayType != .landscape {
            compactView
        } else {
            regularView
        }
    }
}
