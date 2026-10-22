//
//  GhosttyTerminalGestureRouting+iOS.swift
//  VVTerm
//
//  iOS terminal gesture-recognizer routing.
//

import UIKit

// MARK: - Gesture Recognizer Delegate

extension GhosttyTerminalView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer == nativeSelectionHandlePanRecognizer {
            guard #available(iOS 17.0, *) else { return false }
            let point = touch.location(in: self)
            guard canRouteTerminalInput, !isPaused, !isShuttingDown,
                  let handle = nativeSelectionHandle(at: point),
                  let range = nativeSelectedRange else {
                nativeSelectionHandleDrag = nil
                return false
            }
            let offset = handle == .start ? range.location : nativeSelectionSnapshot.upperBound(of: range)
            let caret = nativeSelectionSnapshot.caretRect(for: offset)
            // UIKit may reset pan translation when recognition starts. Retain the
            // accepted touch position instead of reconstructing it at that point.
            nativeSelectionHandleDrag = (handle, CGPoint(x: caret.minX - point.x, y: caret.midY - point.y))
            return true
        }
        if gestureRecognizer == nativeSelectionLongPressRecognizer {
            guard canRouteTerminalInput, !isPaused, !isShuttingDown else { return false }
            return !isPointOnNativeSelectionHandleHitArea(touch.location(in: self))
        }
        if gestureRecognizer == directTouchTapRecognizer {
            guard canRouteTerminalInput, !isPaused, !isShuttingDown else { return false }
            let location = touch.location(in: self)
            return !isPointOnNativeSelectionHandleHitArea(location)
        }
        if gestureRecognizer == pinchRecognizer {
            return canReceivePinchTouch
        }
        if gestureRecognizer == scrollRecognizer {
            guard shouldAllowScrollGesture(gestureRecognizer, touchType: touch.type) else {
                return false
            }
            // Only finger touches are contested. Command + trackpad scrolling stays with
            // the scroll recognizer, since both arrow recognizers are direct-touch only.
            if touch.type == .direct,
               TerminalArrowRepeatPolicy.owner(
                   commandHeld: gestureRecognizer.modifierFlags.contains(.command),
                   touchCount: 1
               ) != .scroll {
                return false
            }
            if nativeSelectionInteractionActive || nativeSelectedRange != nil {
                return false
            }
        }
        return true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == arrowRepeatModifierRecognizer
            || gestureRecognizer == arrowRepeatTouchRecognizer {
            guard canRouteTerminalInput,
                  !isPaused,
                  !isShuttingDown,
                  !hasActiveSelectionInteraction else {
                return false
            }
            // An in-flight pinch blocks only the one-finger recognizer. The two-finger one
            // must be free to arm alongside pinch, since arming is what starts the
            // arbitration that decides between them.
            if gestureRecognizer == arrowRepeatModifierRecognizer, isPinchingTerminalZoom {
                return false
            }
            let touchCount = gestureRecognizer == arrowRepeatTouchRecognizer ? 2 : 1
            return TerminalArrowRepeatPolicy.owner(
                commandHeld: gestureRecognizer.modifierFlags.contains(.command),
                touchCount: touchCount
            ) == .arrowRepeat
        }

        if gestureRecognizer == scrollRecognizer {
            return shouldAllowScrollGesture(gestureRecognizer, touchType: .indirectPointer)
        }

        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Pinch and the two-finger arrow drag recognize together by design: they track the
        // same two touches, and `twoFingerDragOwner` decides which one acts. Locking one
        // out here would decide it by the recognition race, which cannot tell them apart.
        if (gestureRecognizer == arrowRepeatTouchRecognizer
            && otherGestureRecognizer == pinchRecognizer)
            || (gestureRecognizer == pinchRecognizer
                && otherGestureRecognizer == arrowRepeatTouchRecognizer) {
            return true
        }
        if gestureRecognizer == nativeSelectionHandlePanRecognizer
            || otherGestureRecognizer == nativeSelectionHandlePanRecognizer
            || gestureRecognizer == arrowRepeatModifierRecognizer
            || otherGestureRecognizer == arrowRepeatModifierRecognizer
            || gestureRecognizer == arrowRepeatTouchRecognizer
            || otherGestureRecognizer == arrowRepeatTouchRecognizer {
            return false
        }
        if gestureRecognizer == directTouchTapRecognizer || otherGestureRecognizer == directTouchTapRecognizer {
            return false
        }
        if nativeSelectionInteractionActive || nativeSelectedRange != nil,
           gestureRecognizer == scrollRecognizer || otherGestureRecognizer == scrollRecognizer {
            return false
        }
        if gestureRecognizer == pinchRecognizer || otherGestureRecognizer == pinchRecognizer {
            return false
        }
        // Allow the remaining compatible gestures to recognize simultaneously.
        return true
    }
}

extension GhosttyTerminalView {
    var allowsHostTextSelection: Bool {
        TerminalSelectionRoutingPolicy.shouldAllowHostSelection(
            terminalMouseCaptured: surface?.mouseCaptured == true,
            selectionInteractionActive: hasActiveSelectionInteraction
        )
    }

    var hasActiveSelectionInteraction: Bool {
        nativeSelectionInteractionActive
            || nativeSelectedRange != nil
            || prefersNativeSelectionFirstResponder
    }

    func shouldAllowScrollGesture(
        _ gestureRecognizer: UIGestureRecognizer,
        touchType: UITouch.TouchType
    ) -> Bool {
        TerminalPointerInputRoutingPolicy.shouldAllowScrollGesture(
            isIndirectPointer: touchType == .indirectPointer,
            isPointerButtonPressed: !gestureRecognizer.buttonMask.isEmpty,
            hasActiveTerminalPointerButton: activePointerButton != nil
        )
    }

    func shouldAllowActiveScrollGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        TerminalPointerInputRoutingPolicy.shouldAllowScrollGesture(
            isIndirectPointer: !gestureRecognizer.buttonMask.isEmpty || activePointerButton != nil,
            isPointerButtonPressed: !gestureRecognizer.buttonMask.isEmpty,
            hasActiveTerminalPointerButton: activePointerButton != nil
        )
    }
}

extension GhosttyTerminalView {
    // MARK: - Touch Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if handleIndirectPointerTouchesBegan(touches, event: event) {
            return
        }
        let location = touches.first?.location(in: self)
        if nativeSelectionLifecycle.interactionIsActive {
            return
        }
        if nativeSelectionLifecycle.keepsFirstResponder {
            if let location, isPointOnNativeSelectionHandleHitArea(location) {
                return
            }
            guard shouldAutoFocusKeyboard(for: touches) else { return }
            notifyDirectTouchOnTerminal(isFocusTap: true)
            return
        }
        // Tap just focuses keyboard - no mouse events (avoids accidental selection).
        notifyDirectTouchOnTerminal(isFocusTap: true)
        requestKeyboardFocus(for: .directTouch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        if handleIndirectPointerTouchesMoved(touches, event: event) {
            return
        }
        // Pan gesture handles scrolling, long press handles selection
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        _ = handleIndirectPointerTouchesEnded(touches, event: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        _ = handleIndirectPointerTouchesEnded(touches, event: event)
    }

    @objc func handleDirectTouchTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              canRouteTerminalInput,
              !isPaused,
              !isShuttingDown else {
            return
        }

        let selectionWasActive = hasActiveSelectionInteraction
        clearNativeSelectionStateForTerminalInput()
        if selectionWasActive {
            _ = requestKeyboardFocus(for: .directTouch)
        }

        guard let surface,
              TerminalPointerInputRoutingPolicy.shouldSendDirectTouchClick(
                  terminalMouseCaptured: surface.mouseCaptured,
                  terminalInputAvailable: true,
                  selectionInteractionActive: selectionWasActive
              ) else {
            return
        }

        let position = ghosttyPoint(recognizer.location(in: self))
        stopMomentumScrolling()
        surface.sendMousePos(.init(x: position.x, y: position.y, mods: []))
        surface.sendMouseButton(.init(action: .press, button: .left, mods: []))
        surface.sendMouseButton(.init(action: .release, button: .left, mods: []))
        requestRender()
    }

    func ghosttyPoint(_ location: CGPoint) -> CGPoint {
        // UIKit coordinates are top-left origin; Ghostty iOS expects the same.
        location
    }

    func firstIndirectPointerTouch(in touches: Set<UITouch>) -> UITouch? {
        touches.first { $0.type == .indirectPointer }
    }

    func pointerModifiers(from event: UIEvent?) -> Ghostty.Input.Mods {
        TerminalPointerInputRoutingPolicy.ghosttyModifiers(from: event?.modifierFlags ?? [])
    }

    func pointerButton(
        from event: UIEvent?
    ) -> TerminalPointerButton? {
        TerminalPointerInputRoutingPolicy.pointerButton(
            for: event?.buttonMask ?? [],
            modifiers: event?.modifierFlags ?? []
        )
    }

    func sendPointerPosition(_ location: CGPoint, mods: Ghostty.Input.Mods) {
        guard let surface else { return }
        let pos = ghosttyPoint(location)
        surface.sendMousePos(.init(x: pos.x, y: pos.y, mods: mods))
    }

    @discardableResult
    func handleIndirectPointerTouchesBegan(_ touches: Set<UITouch>, event: UIEvent?) -> Bool {
        guard let touch = firstIndirectPointerTouch(in: touches) else { return false }
        guard canRouteTerminalInput, let surface else { return true }

        focusForHardwareKeyboardIfNeeded()

        let location = touch.location(in: self)
        let mods = pointerModifiers(from: event)
        sendPointerPosition(location, mods: mods)

        guard let button = pointerButton(from: event) else {
            requestRender()
            return true
        }

        activePointerButton = button
        if button == .left {
            stopMomentumScrolling()
            updateSelectionAutoscroll(location: location, mods: mods)
        } else {
            stopSelectionAutoscroll()
        }
        let handled = surface.sendMouseButton(.init(action: .press, button: button.ghosttyMouseButton, mods: mods))
        requestRender()

        if TerminalPointerInputRoutingPolicy.shouldShowHostContextMenu(
            button: button,
            terminalHandledButtonPress: handled,
            terminalMouseCaptured: surface.mouseCaptured
        ) {
            showPointerContextMenu(at: location)
        }

        return true
    }

    @discardableResult
    func handleIndirectPointerTouchesMoved(_ touches: Set<UITouch>, event: UIEvent?) -> Bool {
        guard let touch = firstIndirectPointerTouch(in: touches) else { return false }
        guard canRouteTerminalInput else { return true }

        let location = touch.location(in: self)
        let mods = pointerModifiers(from: event)
        sendPointerPosition(location, mods: mods)
        if activePointerButton == .left {
            updateSelectionAutoscroll(location: location, mods: mods)
        }
        requestRender()
        return true
    }

    @discardableResult
    func handleIndirectPointerTouchesEnded(_ touches: Set<UITouch>, event: UIEvent?) -> Bool {
        guard let touch = firstIndirectPointerTouch(in: touches) else { return false }
        guard canRouteTerminalInput, let surface else {
            activePointerButton = nil
            stopSelectionAutoscroll()
            return true
        }

        let mods = pointerModifiers(from: event)
        sendPointerPosition(touch.location(in: self), mods: mods)
        if let button = activePointerButton {
            _ = surface.sendMouseButton(.init(action: .release, button: button.ghosttyMouseButton, mods: mods))
        }
        activePointerButton = nil
        stopSelectionAutoscroll()
        requestRender()
        return true
    }

    @objc func handlePointerHover(_ recognizer: UIHoverGestureRecognizer) {
        guard canRouteTerminalInput, let surface else { return }
        let mods = TerminalPointerInputRoutingPolicy.ghosttyModifiers(from: recognizer.modifierFlags)

        switch recognizer.state {
        case .began, .changed:
            sendPointerPosition(recognizer.location(in: self), mods: mods)
        case .ended, .cancelled, .failed:
            surface.sendMousePos(.init(x: -1, y: -1, mods: mods))
        default:
            return
        }

        requestRender()
    }

    @objc func handlePanGesture(_ recognizer: UIPanGestureRecognizer) {
        guard let surface = surface else { return }
        guard shouldAllowActiveScrollGesture(recognizer) else { return }
        if isPinchingTerminalZoom { return }

        let translation = recognizer.translation(in: self)
        let location = recognizer.location(in: self)

        switch recognizer.state {
        case .began:
            isScrolling = true
            stopMomentumScrolling()
        case .changed:
            // Update mouse position so TUI apps receive wheel events with coordinates.
            let pos = ghosttyPoint(location)
            surface.sendMousePos(.init(x: pos.x, y: pos.y, mods: []))
            // Send scroll delta directly with increased multiplier for snappy feel
            let scrollEvent = Ghostty.Input.MouseScrollEvent(
                x: Double(translation.x) * Self.scrollMultiplier,
                y: Double(translation.y) * Self.scrollMultiplier,
                mods: Ghostty.Input.ScrollMods(precision: true, momentum: .none)
            )
            surface.sendMouseScroll(scrollEvent)
            scrollUITestEventCount += 1
            requestRender()

            // Reset translation so we get delta on next call
            recognizer.setTranslation(.zero, in: self)
        case .ended:
            isScrolling = false
            // Get velocity for momentum scrolling
            let velocity = recognizer.velocity(in: self)
            startMomentumScrolling(velocity: velocity)
        case .cancelled, .failed:
            isScrolling = false
            stopMomentumScrolling()
        default:
            break
        }
    }

    func updateSelectionAutoscroll(location: CGPoint, mods: Ghostty.Input.Mods) {
        guard allowsHostTextSelection,
              TerminalSelectionAutoscrollPolicy.decision(
                locationY: Double(location.y - selectionAutoscrollViewport.minY),
                viewportHeight: Double(selectionAutoscrollViewport.height),
                edgeInset: Self.selectionAutoscrollEdgeInset,
                maximumScrollDelta: Self.selectionAutoscrollMaximumDelta
              ) != nil else {
            stopSelectionAutoscroll()
            return
        }

        selectionAutoscrollLocation = location
        selectionAutoscrollMods = mods
        startSelectionAutoscrollIfNeeded()
    }

    func startSelectionAutoscrollIfNeeded() {
        guard selectionAutoscrollDisplayLink == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(selectionAutoscrollTick))
        displayLink.add(to: .main, forMode: .common)
        selectionAutoscrollDisplayLink = displayLink
    }

    func stopSelectionAutoscroll() {
        selectionAutoscrollDisplayLink?.invalidate()
        selectionAutoscrollDisplayLink = nil
        selectionAutoscrollLocation = nil
        selectionAutoscrollRemainder = 0
        selectionAutoscrollMods = []
    }

    var selectionAutoscrollViewport: CGRect {
        var visible = bounds
        var ancestor = superview
        while let view = ancestor {
            if view.clipsToBounds || view is UIWindow {
                visible = visible.intersection(view.convert(view.bounds, to: self))
            }
            ancestor = view.superview
        }
        return visible.isNull ? .zero : visible
    }

    func clampedSelectionAutoscrollLocation(_ location: CGPoint) -> CGPoint {
        let viewport = selectionAutoscrollViewport
        return CGPoint(
            x: min(max(location.x, viewport.minX), viewport.maxX),
            y: min(max(location.y, viewport.minY), viewport.maxY)
        )
    }

    @objc func selectionAutoscrollTick() {
        guard let surface,
              let location = selectionAutoscrollLocation,
              allowsHostTextSelection else {
            stopSelectionAutoscroll()
            return
        }

        guard let decision = TerminalSelectionAutoscrollPolicy.decision(
            locationY: Double(location.y - selectionAutoscrollViewport.minY),
            viewportHeight: Double(selectionAutoscrollViewport.height),
            edgeInset: Self.selectionAutoscrollEdgeInset,
            maximumScrollDelta: Self.selectionAutoscrollMaximumDelta
        ) else {
            stopSelectionAutoscroll()
            return
        }

        if nativeSelectionDragAnchor != nil {
            guard nativeSelectionInteractionActive, canRouteTerminalInput, !isPaused, !isShuttingDown else {
                stopSelectionAutoscroll()
                return
            }
            // Extend from the latest viewport first. Binding actions scroll the host
            // buffer and never send wheel events to a mouse-capturing remote app.
            if nativeSelectionHandleDrag != nil {
                moveNativeSelectionHandle(to: location)
            } else {
                extendNativeSelection(to: location)
            }
            let duration = selectionAutoscrollDisplayLink.map { $0.targetTimestamp - $0.timestamp } ?? (1.0 / 60)
            selectionAutoscrollRemainder -= decision.scrollDelta * min(max(duration, 0), 0.1) * 60 / max(Double(cellSize.height), 1)
            let rows = Int(selectionAutoscrollRemainder.rounded(.towardZero))
            if rows != 0 {
                selectionAutoscrollRemainder -= Double(rows)
                if !surface.perform(action: "scroll_page_lines:\(rows)") { stopSelectionAutoscroll() }
            }
            requestRender()
            return
        }

        let clampedLocation = clampedSelectionAutoscrollLocation(location)
        let pos = ghosttyPoint(clampedLocation)
        let mousePos = Ghostty.Input.MousePosEvent(
            x: pos.x,
            y: pos.y,
            mods: selectionAutoscrollMods
        )
        surface.sendMousePos(mousePos)
        surface.sendMouseScroll(
            Ghostty.Input.MouseScrollEvent(
                x: 0,
                y: decision.scrollDelta,
                mods: Ghostty.Input.ScrollMods(precision: true, momentum: .none)
            )
        )
        surface.sendMousePos(mousePos)
        requestRender()
    }

    func startMomentumScrolling(velocity: CGPoint) {
        // Only start momentum if velocity is significant
        guard abs(velocity.y) > Self.minimumMomentumVelocity || abs(velocity.x) > Self.minimumMomentumVelocity else {
            sendMomentumEnd()
            return
        }

        // Scale velocity for momentum (divide by 60 for per-frame amount at 60fps)
        momentumVelocity = CGPoint(
            x: velocity.x / 60.0 * Self.scrollMultiplier * 0.5,
            y: velocity.y / 60.0 * Self.scrollMultiplier * 0.5
        )

        // Create display link for smooth animation
        momentumPhase = .began
        momentumDisplayLink = CADisplayLink(target: self, selector: #selector(momentumScrollTick))
        momentumDisplayLink?.add(to: .main, forMode: .common)
    }

    @objc func momentumScrollTick() {
        guard let surface = surface else {
            stopMomentumScrolling()
            return
        }

        // Apply deceleration
        momentumVelocity.x *= Self.momentumDeceleration
        momentumVelocity.y *= Self.momentumDeceleration

        // Stop if velocity is very low
        if abs(momentumVelocity.x) < 0.5 && abs(momentumVelocity.y) < 0.5 {
            stopMomentumScrolling()
            sendMomentumEnd()
            return
        }

        // Send momentum scroll event (began -> changed)
        let scrollEvent = Ghostty.Input.MouseScrollEvent(
            x: Double(momentumVelocity.x),
            y: Double(momentumVelocity.y),
            mods: Ghostty.Input.ScrollMods(
                precision: true,
                momentum: momentumPhase == .began ? .began : .changed
            )
        )
        surface.sendMouseScroll(scrollEvent)
        momentumPhase = .changed
        requestRender()
    }

    func stopMomentumScrolling() {
        momentumDisplayLink?.invalidate()
        momentumDisplayLink = nil
        momentumVelocity = .zero
        momentumPhase = .none
    }

    func sendMomentumEnd() {
        guard let surface = surface else { return }
        let endEvent = Ghostty.Input.MouseScrollEvent(
            x: 0,
            y: 0,
            mods: Ghostty.Input.ScrollMods(precision: true, momentum: .ended)
        )
        surface.sendMouseScroll(endEvent)
        momentumPhase = .none
    }

    @objc func handlePinchGesture(_ recognizer: UIPinchGestureRecognizer) {
        guard canHandlePinchZoom else {
            isPinchingTerminalZoom = false
            return
        }

        switch recognizer.state {
        case .began:
            beginPinchZoom(recognizer)
        case .changed:
            // The arbitration can resolve in pinch's favour after this gesture began, so
            // a suppressed pinch picks up here rather than staying dead for its lifetime.
            guard isPinchingTerminalZoom else {
                beginPinchZoom(recognizer)
                return
            }
            let relativeScale = recognizer.scale / pinchReferenceScale
            if relativeScale >= CGFloat(TerminalZoomPresentation.pinchZoomInThreshold) {
                if let result = onZoomAction?(.zoomIn) {
                    showZoomIndicator(fontSize: result.effectiveFontSize)
                }
                pinchReferenceScale = recognizer.scale
            } else if relativeScale <= CGFloat(TerminalZoomPresentation.pinchZoomOutThreshold) {
                if let result = onZoomAction?(.zoomOut) {
                    showZoomIndicator(fontSize: result.effectiveFontSize)
                }
                pinchReferenceScale = recognizer.scale
            }
        case .ended, .cancelled, .failed:
            isPinchingTerminalZoom = false
            pinchReferenceScale = 1
            scheduleZoomIndicatorHide(after: TerminalZoomPresentation.indicatorGestureEndHideDelay)
        default:
            break
        }
    }

    /// Re-baselines the reference scale, so travel spent deciding between an arrow drag
    /// and a pinch does not land as a font-size jump once pinch wins.
    private func beginPinchZoom(_ recognizer: UIPinchGestureRecognizer) {
        guard canHandlePinchZoom else {
            isPinchingTerminalZoom = false
            return
        }
        isPinchingTerminalZoom = true
        pinchReferenceScale = recognizer.scale
        stopMomentumScrolling()
        showZoomIndicator()
    }

    /// Whether pinch may receive touches at all. Deliberately free of the arbitration
    /// below: refusing a touch drops the recognizer for the whole gesture, so a pinch
    /// that is merely waiting on the arbitration must still be handed its touches.
    var canReceivePinchTouch: Bool {
        !nativeSelectionLifecycle.shouldRefreshSnapshot
    }

    var canHandlePinchZoom: Bool {
        guard canReceivePinchTouch else { return false }
        // Zoom stays suppressed while a two-finger drag is in flight and has not resolved
        // in pinch's favour, so one pair of touches never both zooms and sends keys.
        switch twoFingerDragOwner {
        case .inactive, .zoom:
            return true
        case .undecided, .arrowRepeat:
            return false
        }
    }
}
