//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension PrimitiveButtonStyle where Self == SupplementActionButtonStyle {

    static var supplementAction: SupplementActionButtonStyle {
        SupplementActionButtonStyle()
    }
}

struct SupplementActionButtonStyle: PrimitiveButtonStyle {

    private func baseLabel(_ configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func legacyButton(_ configuration: Configuration) -> some View {
        Button {
            configuration.trigger()
        } label: {
            baseLabel(configuration)
                .background {
                    #if os(tvOS)
                    Rectangle()
                        .fill(.white)
                    #else
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.white)
                    #endif
                }
            #if os(tvOS)
                .clipShape(Rectangle())
            #else
                .clipShape(RoundedRectangle(cornerRadius: 7))
            #endif
        }
        .buttonStyle(.card)
    }

    @available(iOS 26.0, tvOS 26.0, *)
    private func glassButton(_ configuration: Configuration) -> some View {
        Button {
            configuration.trigger()
        } label: {
            #if os(tvOS)
            baseLabel(configuration)
                .glassEffect(
                    .regular
                        .tint(.white)
                        .interactive(),
                    in: Rectangle()
                )
            #else
            baseLabel(configuration)
                .glassEffect(
                    .regular
                        .tint(.white)
                        .interactive(),
                    in: Capsule()
                )
            #endif
        }
        #if os(tvOS)
        .buttonBorderShape(.roundedRectangle(radius: 0))
        #else
        .buttonBorderShape(.capsule)
        #endif
        #if os(tvOS)
        .buttonStyle(.card)
        #endif
    }

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *), UIDevice.supportsLiquidGlass {
            glassButton(configuration)
        } else {
            legacyButton(configuration)
        }
    }
}
