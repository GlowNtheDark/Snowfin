//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import UIKit

class DirectionalPanGestureRecognizer: UIPanGestureRecognizer {

    var direction: Direction
    #if os(tvOS) && DEBUG
    private var didLogInitialMove = false
    #endif

    init(direction: Direction, target: AnyObject, action: Selector) {
        self.direction = direction
        super.init(target: target, action: action)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        #if os(tvOS) && DEBUG
        didLogInitialMove = false
        let touchType = touches.first.map { String(describing: $0.type) } ?? "none"
        PlaybackScrubDiagnostics.log(
            "pan-touch-began direction=\(direction) type=\(touchType) state=\(state.rawValue) attached=\(view != nil)"
        )
        #endif
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        let previousState = state
        super.touchesMoved(touches, with: event)

        #if os(tvOS) && DEBUG
        if !didLogInitialMove || previousState != state {
            didLogInitialMove = true
            let touchType = touches.first.map { String(describing: $0.type) } ?? "none"
            let delta: CGPoint
            if let touch = touches.first, let view {
                let location = touch.location(in: view)
                let previousLocation = touch.previousLocation(in: view)
                delta = CGPoint(x: location.x - previousLocation.x, y: location.y - previousLocation.y)
            } else {
                delta = .zero
            }
            PlaybackScrubDiagnostics.log(
                "pan-touch-moved direction=\(direction) type=\(touchType) delta=\(delta) state=\(state.rawValue)"
            )
        }
        #endif

        if state == .began {
            let velocity = velocity(in: view)

            let isUp = velocity.y < 0
            let isHorizontal = velocity.y.magnitude < velocity.x.magnitude
            let isVertical = velocity.x.magnitude < velocity.y.magnitude

            #if os(tvOS) && DEBUG
            PlaybackScrubDiagnostics.log(
                "directional-pan-began direction=\(direction) velocityX=\(velocity.x) velocityY=\(velocity.y)"
            )
            #endif

            switch direction {
            case .all: ()
            case .allButDown where isUp || isHorizontal: ()
            case .horizontal where isHorizontal: ()
            case .vertical where isVertical: ()
            case .up where isVertical && velocity.y < 0: ()
            case .down where isVertical && velocity.y > 0: ()
            case .left where isHorizontal && velocity.x < 0: ()
            case .right where isHorizontal && velocity.x > 0: ()
            default:
                #if os(tvOS) && DEBUG
                PlaybackScrubDiagnostics.log("directional-pan-rejected direction=\(direction)")
                #endif
                state = .cancelled
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        #if os(tvOS) && DEBUG
        PlaybackScrubDiagnostics.log("pan-touch-ended direction=\(direction) state=\(state.rawValue)")
        #endif
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        #if os(tvOS) && DEBUG
        PlaybackScrubDiagnostics.log("pan-touch-cancelled direction=\(direction) state=\(state.rawValue)")
        #endif
    }
}
