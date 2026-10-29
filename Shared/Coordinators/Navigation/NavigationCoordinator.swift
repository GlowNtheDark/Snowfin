//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

@MainActor
final class NavigationCoordinator: ObservableObject {

    #if DEBUG
    let debugDiagnosticID = String(UUID().uuidString.prefix(8))
    #endif

    struct PresentedRoute: Identifiable {

        private final class DismissalState {
            var didNotify = false
        }

        let route: NavigationRoute
        let coordinator: NavigationCoordinator
        private let dismissalState = DismissalState()

        var id: String {
            route.id
        }

        func notifyWillDismiss() {
            guard !dismissalState.didNotify else { return }
            dismissalState.didNotify = true
            route.onWillDismiss?()
        }
    }

    @Published
    var path: [NavigationRoute] = []

    @Published
    var presentedSheet: PresentedRoute?
    @Published
    var presentedFullScreen: PresentedRoute?

    private var dismissedFullScreenPresentations: [PresentedRoute] = []

    func fullScreenPresentationDidDisappear(_ presentation: PresentedRoute) {
        guard presentedFullScreen?.coordinator === presentation.coordinator else { return }
        presentation.notifyWillDismiss()
        dismissedFullScreenPresentations.append(presentation)
        #if DEBUG
        EpisodePlaybackDiagnostics.log(
            presentation.route.playbackDiagnosticID,
            event: "full-screen-presentation-disappeared coordinator=\(debugDiagnosticID) destinationCoordinator=\(presentation.coordinator.debugDiagnosticID) route=\(presentation.route.id)"
        )
        #endif
    }

    func fullScreenPresentationDidDismiss() {
        guard !dismissedFullScreenPresentations.isEmpty else { return }
        let dismissedPresentation = dismissedFullScreenPresentations.removeFirst()
        guard presentedFullScreen?.coordinator === dismissedPresentation.coordinator else {
            #if DEBUG
            EpisodePlaybackDiagnostics.log(
                dismissedPresentation.route.playbackDiagnosticID,
                event: "full-screen-presentation-cleanup-skipped coordinator=\(debugDiagnosticID) dismissedDestinationCoordinator=\(dismissedPresentation.coordinator.debugDiagnosticID) currentDestinationCoordinator=\(presentedFullScreen?.coordinator.debugDiagnosticID ?? "none")"
            )
            #endif
            return
        }

        dismissedPresentation.notifyWillDismiss()
        presentedFullScreen = nil
        #if DEBUG
        EpisodePlaybackDiagnostics.log(
            dismissedPresentation.route.playbackDiagnosticID,
            event: "presentation-binding-cleanup coordinator=\(debugDiagnosticID) destinationCoordinator=\(dismissedPresentation.coordinator.debugDiagnosticID) route=\(dismissedPresentation.route.id) source=full-screen-onDismiss"
        )
        #endif
    }

    func push(
        _ route: NavigationRoute
    ) {
        #if os(tvOS)
        if let presentedCoordinator = presentedFullScreen?.coordinator ?? presentedSheet?.coordinator {
            #if DEBUG
            if let diagnosticID = route.playbackDiagnosticID {
                let currentRoute = presentedFullScreen?.route ?? presentedSheet?.route
                EpisodePlaybackDiagnostics.log(
                    diagnosticID,
                    event: "route-forward parentCoordinator=\(debugDiagnosticID) destinationCoordinator=\(presentedCoordinator.debugDiagnosticID) existingPresentation=true existingRoute=\(currentRoute?.id ?? "unknown") route=\(route.id)"
                )
            }
            #endif
            presentedCoordinator.push(route)
            return
        }

        switch route.transitionStyle {
        case .push, .sheet:
            let destinationCoordinator = NavigationCoordinator()
            presentedSheet = .init(
                route: route,
                coordinator: destinationCoordinator
            )
            #if DEBUG
            EpisodePlaybackDiagnostics.log(
                route.playbackDiagnosticID,
                event: "route-dispatch parentCoordinator=\(debugDiagnosticID) destinationCoordinator=\(destinationCoordinator.debugDiagnosticID) existingPresentation=false presentation=sheet route=\(route.id)"
            )
            #endif
        case .fullscreen:
            let destinationCoordinator = NavigationCoordinator()
            presentedFullScreen = .init(
                route: route,
                coordinator: destinationCoordinator
            )
            #if DEBUG
            EpisodePlaybackDiagnostics.log(
                route.playbackDiagnosticID,
                event: "route-dispatch parentCoordinator=\(debugDiagnosticID) destinationCoordinator=\(destinationCoordinator.debugDiagnosticID) existingPresentation=false presentation=fullscreen route=\(route.id)"
            )
            #endif
        }
        #else
        switch route.transitionStyle {
        case .push:
            path.append(route)
        case .sheet:
            presentedSheet = .init(
                route: route,
                coordinator: .init()
            )
        case .fullscreen:
            withAnimation {
                presentedFullScreen = .init(
                    route: route,
                    coordinator: .init()
                )
            }
        }
        #endif
    }
}
