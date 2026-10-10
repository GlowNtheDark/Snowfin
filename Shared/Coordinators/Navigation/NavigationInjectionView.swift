//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import PreferencesView
import SwiftUI
import Transmission

// TODO: have full screen zoom presentation zoom from/to center
//       - probably need to make mock view with matching ids

struct PresentationControllerShouldDismissPreferenceKey: PreferenceKey {

    static var defaultValue: Bool = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

struct NavigationInjectionView: View {

    @Environment(\.isTabContentActive)
    private var tabContentActivity

    private var isTabContentActive: Bool {
        tabContentActivity.wrappedValue
    }

    @StateObject
    private var coordinator: NavigationCoordinator

    @State
    private var isPresentationInteractive: Bool = true

    private let content: AnyView

    init(
        coordinator: @autoclosure @escaping () -> NavigationCoordinator,
        @ViewBuilder content: @escaping () -> some View
    ) {
        _coordinator = StateObject(wrappedValue: coordinator())
        self.content = AnyView(content())
    }

    // Hiding a retained tab must dismiss its UI without discarding its routes.
    private func activePresentation(
        _ presentation: Binding<NavigationCoordinator.PresentedRoute?>,
        canDismiss: Bool = true
    ) -> Binding<NavigationCoordinator.PresentedRoute?> {
        Binding(
            get: { isTabContentActive ? presentation.wrappedValue : nil },
            set: { value in
                guard isTabContentActive else { return }
                guard value != nil || canDismiss else { return }
                if value == nil {
                    presentation.wrappedValue?.route.onWillDismiss?()
                }
                presentation.wrappedValue = value
            }
        )
    }

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            content
                .navigationDestination(for: NavigationRoute.self) { route in
                    route.destination
                }
        }
        .trackingFrame(for: .navigationStack)
        .environment(
            \.router,
            .init(
                navigationCoordinator: coordinator
            )
        )
        .environmentObject(coordinator)
        #if os(tvOS)
            .fullScreenCover(
                item: activePresentation($coordinator.presentedSheet)
            ) {
                guard isTabContentActive else { return }
                coordinator.presentedSheet = nil
            } content: { presentedRoute in
                NavigationInjectionView(coordinator: presentedRoute.coordinator) {
                    presentedRoute.route.destination
                }
                .background(.regularMaterial)
            }
            .fullScreenCover(
                item: activePresentation(
                    $coordinator.presentedFullScreen,
                    canDismiss: isPresentationInteractive
                )
            ) { presentedRoute in
                NavigationInjectionView(coordinator: presentedRoute.coordinator) {
                    presentedRoute.route.destination
                        .environment(\.isCurrentPresentationDismissible, $isPresentationInteractive)
                }
            }
            .interactiveDismissDisabled(!isPresentationInteractive)
        #else
            .sheet(
                item: $coordinator.presentedSheet
            ) {
                coordinator.presentedSheet = nil
            } content: { presentedRoute in
                NavigationInjectionView(coordinator: presentedRoute.coordinator) {
                    presentedRoute.route.destination
                }
            }
            .presentation(
                $coordinator.presentedFullScreen,
                transition: .zoomIfAvailable(
                    .init(
                        dimmingVisualEffect: .systemThickMaterialDark,
                        prefersScalePresentingView: false
                    ),
                    options: .init(
                        isInteractive: isPresentationInteractive,
                        preferredPresentationSafeAreaInsets: .zero,
                    ),
                    otherwise: .slide(.init(edge: .bottom), options: .init(isInteractive: isPresentationInteractive))
                )
            ) { presentedRouteBinding, _ in
                let vc = UIPreferencesHostingController {
                    NavigationInjectionView(coordinator: presentedRouteBinding.wrappedValue.coordinator) {
                        presentedRouteBinding.wrappedValue.route.destination
                            .onPreferenceChange(PresentationControllerShouldDismissPreferenceKey.self) { newValue in
                                isPresentationInteractive = newValue
                            }
                    }
                }

                vc.view.backgroundColor = .black

                return vc
            }
        #endif
    }
}

// Ordinary navigation hosts remain active unless a retained tab opts out.
extension EnvironmentValues {
    @Entry
    var isTabContentActive: Binding<Bool> = .constant(true)

    @Entry
    var isCurrentPresentationDismissible: Binding<Bool> = .constant(true)
}
