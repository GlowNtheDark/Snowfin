//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct PosterButton<Item: Poster>: View {

    @Environment(\.posterConfiguration)
    private var posterConfiguration

    @Environment(\.viewContext)
    private var viewContext

    @Default(.accentColor)
    private var accentColor

    @Namespace
    private var namespace

    #if os(tvOS)
    @FocusState
    private var isFocused: Bool
    @Environment(\.launchFocusFirstPoster)
    private var launchFocusFirstPoster
    @Environment(\.initialTabCandidateReady)
    private var initialTabCandidateReady
    #endif

    @State
    private var posterSize: CGSize = .zero

    let item: Item
    let displayType: PosterDisplayType
    let size: PosterDisplayType.Size
    let action: (Namespace.ID) -> Void

    init(
        item: Item,
        displayType: PosterDisplayType,
        size: PosterDisplayType.Size = .small,
        action: @escaping (Namespace.ID) -> Void
    ) {
        self.item = item
        self.displayType = displayType
        self.size = size
        self.action = action
    }

    @ViewBuilder
    private var contextMenuPreview: some View {
        buttonLabel()
            .frame(width: posterSize.width)
            .padding(20)
            .backport
            .glassEffect(in: .rect)
    }

    @ViewBuilder
    private func posterImage(overlay: some View) -> some View {
        PosterImage(
            item: item,
            type: displayType,
            size: size
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { overlay.posterStyle(displayType) }
        .contentShape(.contextMenuPreview, Rectangle())
        .matchedTransitionSource(id: "item", in: namespace)
        .subtleShadow()
        #if os(tvOS)
            .overlay {
                Rectangle()
                    .stroke(
                        accentColor.opacity(isFocused ? 0.95 : 0),
                        lineWidth: 3
                    )
            }
            .scaleEffect(isFocused ? 1.035 : 1)
            .shadow(
                color: isFocused ? accentColor.opacity(0.28) : .clear,
                radius: isFocused ? 16 : 0
            )
            .animation(.easeOut(duration: 0.16), value: isFocused)
        #else
            .hoverEffect(.highlight)
        #endif
    }

    @ViewBuilder
    private func buttonLabel(overlay: some View = EmptyView()) -> some View {
        VStack(alignment: .leading) {
            posterImage(overlay: overlay)

            if posterConfiguration.showLabels {
                item.posterLabel
                    .allowsHitTesting(false)
            }
        }
    }

    var body: some View {
        Button {
            action(namespace)
        } label: {
            // Layout required for tvOS focused offset label behavior
            #if os(tvOS)
            VStack(alignment: .leading, spacing: 12) {
                posterImage(overlay: item.posterOverlay(for: displayType))

                if posterConfiguration.showLabels {
                    item.posterLabel
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            #else
            buttonLabel(overlay: item.posterOverlay(for: displayType))
                .trackingSize($posterSize)
            #endif
        }
        .environment(\.posterDisplayType, displayType)
        .foregroundStyle(.primary, .secondary)
        #if os(tvOS)
            .buttonStyle(SnowfinPosterButtonStyle())
            .buttonBorderShape(.roundedRectangle(radius: 0))
            .focused($isFocused)
            .focusedValue(\.focusedPoster, AnyPoster(item))
            .background {
                if launchFocusFirstPoster == AnyPoster(item) {
                    LaunchFocusCandidateProbe(
                        swiftUIFocused: isFocused,
                        onReady: initialTabCandidateReady
                    )
                    .allowsHitTesting(false)
                }
            }
        #else
            .buttonStyle(.borderless)
        #endif
            .posterContextMenu(for: item) {
                contextMenuPreview
                    .withViewContext(viewContext)
            }
    }
}

#if os(tvOS)
private struct SnowfinPosterButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif

#if os(tvOS)
extension EnvironmentValues {
    @Entry
    var launchFocusFirstPoster: AnyPoster? = nil
}

/// Signals once when the first Home tile is visible enough to accept focus.
struct LaunchFocusCandidateProbe: UIViewRepresentable {
    let swiftUIFocused: Bool
    let onReady: (() -> Void)?

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.swiftUIFocused = swiftUIFocused
        view.onReady = onReady
        view.signalIfVisible()
    }

    final class ProbeView: UIView {
        var swiftUIFocused = false
        var onReady: (() -> Void)?
        private var didSignalReadiness = false
        private var visibilityObservations: [NSKeyValueObservation] = []

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            observeVisibility()
            signalIfVisible()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observeVisibility()
            signalIfVisible()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            signalIfVisible()
        }

        private func observeVisibility() {
            visibilityObservations.removeAll()
            var ancestors: [UIView] = []
            var next: UIView? = self
            while let view = next {
                ancestors.append(view)
                next = view.superview
            }
            for view in ancestors {
                visibilityObservations.append(
                    view.observe(\.alpha, options: [.initial, .new]) { [weak self] _, _ in
                        self?.signalIfVisible()
                    }
                )
                visibilityObservations.append(
                    view.observe(\.isHidden, options: [.initial, .new]) { [weak self] _, _ in
                        self?.signalIfVisible()
                    }
                )
            }
        }

        func signalIfVisible() {
            guard !didSignalReadiness,
                  let onReady,
                  window != nil,
                  !bounds.isEmpty
            else { return }

            var effectiveAlpha: CGFloat = 1
            var next: UIView? = self
            while let view = next {
                guard !view.isHidden else { return }
                effectiveAlpha *= view.alpha
                next = view.superview
            }
            guard effectiveAlpha > 0.99 else { return }

            didSignalReadiness = true
            onReady()
        }
    }
}
#endif
