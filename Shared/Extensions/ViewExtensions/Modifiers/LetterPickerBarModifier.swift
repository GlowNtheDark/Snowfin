//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct LetterPickerBarModifier: ViewModifier {

    @Default(.Customization.Library.letterPickerOrientation)
    private var letterPickerOrientation

    let viewModel: FilterViewModel?
    let preferredLetter: ItemLetter?
    let onLetterFocused: ((ItemLetter) -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let edge = letterPickerOrientation.edge,
           let viewModel
        {
            content
                .focusSection()
                .ignoresSafeArea(.all, edges: edge == .leading ? .trailing : .leading)
                .safeAreaInset(edge: edge, alignment: .center, spacing: 0) {
                    LetterPickerBar(
                        viewModel: viewModel,
                        preferredLetter: preferredLetter,
                        onLetterFocused: onLetterFocused
                    )
                }
                .overlayPreferenceValue(LetterPickerActiveLetterKey.self) { letter in
                    #if os(iOS)
                    ZStack {
                        if let letter {
                            LetterPickerBar.LetterPickerCallout(letter: letter)
                                .font(.system(size: 64, design: .rounded).weight(.bold))
                        }
                    }
                    #endif
                }
        } else {
            content
                .ignoresSafeArea(.all, edges: .horizontal)
        }
    }
}
