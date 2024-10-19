//
//  PWin_Mouse.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-19.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

extension PlayerWindowController {
  // MARK: - Mouse / Trackpad event handling

  /// This method is provided soly for invoking plugin input handlers.
  func informPluginMouseDragged(with event: NSEvent) {
    PluginInputManager.handle(
      input: PluginInputManager.Input.mouse, event: .mouseDrag, player: player,
      arguments: mouseEventArgs(event)
    )
  }

  fileprivate func mouseEventArgs(_ event: NSEvent) -> [[String: Any]] {
    return [[
      "x": event.locationInWindow.x,
      "y": event.locationInWindow.y,
      "clickCount": event.clickCount,
      "pressure": event.pressure
    ] as [String : Any]]
  }

  func isMouseEvent(_ event: NSEvent, inAnyOf views: [NSView?]) -> Bool {
    return isPoint(event.locationInWindow, inAnyOf: views)
  }

  func isPoint(_ pointInWindow: NSPoint, inAnyOf views: [NSView?]) -> Bool {
    return views.filter { $0 != nil }.reduce(false, { (result, view) in
      return result || view!.isMousePoint(view!.convert(pointInWindow, from: nil), in: view!.bounds)
    })
  }

  /**
   Being called to perform single click action after timeout.

   - SeeAlso:
   mouseUp(with:)
   */
  @objc internal func performMouseActionLater(_ timer: Timer) {
    guard let action = timer.userInfo as? Preference.MouseClickAction else { return }
    if mouseExitEnterCount >= 2 && action == .hideOSC {
      /// the counter being greater than or equal to 2 means that the mouse re-entered the window
      /// `showFadeableViews()` must be called due to the movement in the window, thus `hideOSC` action should be cancelled
      return
    }
    performMouseAction(action)
  }

  override func pressureChange(with event: NSEvent) {
    if isCurrentPressInSecondStage == false && event.stage == 2 {
      performMouseAction(Preference.enum(for: .forceTouchAction))
      isCurrentPressInSecondStage = true
    } else if event.stage == 1 {
      isCurrentPressInSecondStage = false
    }
  }

  override func mouseDown(with event: NSEvent) {
    guard event.eventNumber != lastMouseDownEventID else { return }
    lastMouseDownEventID = event.eventNumber
    if Logger.enabled && Logger.Level.preferred >= .verbose {
      log.verbose("PlayerWindow mouseDown @ \(event.locationInWindow)")
    }
    if let controlBarFloating = controlBarFloating, !controlBarFloating.isHidden, isMouseEvent(event, inAnyOf: [controlBarFloating]) {
      controlBarFloating.mouseDown(with: event)
      return
    }
    if let cropSettingsView, !cropSettingsView.cropBoxView.isHidden, isMouseEvent(event, inAnyOf: [cropSettingsView.cropBoxView]) {
      log.verbose("PlayerWindow: mouseDown should have been handled by CropBoxView")
      return
    }
    // record current mouse pos
    mousePosRelatedToWindow = event.locationInWindow
    // Start resize if applicable
    let wasHandled = startResizingSidebar(with: event)
    guard !wasHandled else { return }

    restartHideCursorTimer()

    PluginInputManager.handle(
      input: PluginInputManager.Input.mouse, event: .mouseDown,
      player: player, arguments: mouseEventArgs(event)
    )
    // we don't call super here because before adding the plugin system,
    // PlayerWindowController didn't call super at all
  }

  override func mouseDragged(with event: NSEvent) {
    hideCursorTimer?.invalidate()
    if let controlBarFloating = controlBarFloating, !controlBarFloating.isHidden, controlBarFloating.isDragging {
      controlBarFloating.mouseDragged(with: event)
      return
    }
    if let cropSettingsView, cropSettingsView.cropBoxView.isDraggingToResize || cropSettingsView.cropBoxView.isDraggingNew {
      cropSettingsView.cropBoxView.mouseDragged(with: event)
      return
    }
    let didResizeSidebar = resizeSidebar(with: event)
    guard !didResizeSidebar else {
      return
    }

    if !isFullScreen && !controlBarFloating.isDragging {
      if let mousePosRelatedToWindow = mousePosRelatedToWindow {
        if !isDragging {
          /// Require that the user must drag the cursor at least a small distance for it to start a "drag" (`isDragging==true`)
          /// The user's action will only be counted as a click if `isDragging==false` when `mouseUp` is called.
          /// (Apple's trackpad in particular is very sensitive and tends to call `mouseDragged()` if there is even the slightest
          /// roll of the finger during a click, and the distance of the "drag" may be less than `minimumInitialDragDistance`)
          if mousePosRelatedToWindow.distance(to: event.locationInWindow) <= Constants.Distance.windowControllerMinInitialDragThreshold {
            return
          }
          if Logger.enabled && Logger.Level.preferred >= .verbose {
            log.verbose("PlayerWindow mouseDrag: minimum dragging distance was met")
          }
          isDragging = true
        }
        window?.performDrag(with: event)
        informPluginMouseDragged(with: event)
      }
    }
  }

  override func mouseUp(with event: NSEvent) {
    guard event.eventNumber != lastMouseUpEventID else { return }
    lastMouseUpEventID = event.eventNumber
    if Logger.enabled && Logger.Level.preferred >= .verbose {
      log.verbose("PlayerWindow mouseUp @ \(event.locationInWindow), dragging: \(isDragging.yn), clickCount: \(event.clickCount): eventNum: \(event.eventNumber)")
    }

    restartHideCursorTimer()
    mousePosRelatedToWindow = nil

    if let cropSettingsView, cropSettingsView.cropBoxView.isDraggingToResize || cropSettingsView.cropBoxView.isDraggingNew {
      log.verbose("PlayerWindow mouseUp: finishing cropBoxView selection drag")
      cropSettingsView.cropBoxView.mouseUp(with: event)
    } else if let controlBarFloating = controlBarFloating, !controlBarFloating.isHidden,
              controlBarFloating.isDragging || isMouseEvent(event, inAnyOf: [controlBarFloating]) {
      log.verbose("PlayerWindow mouseUp: finished drag of floating OSC")
      controlBarFloating.mouseUp(with: event)
    } else if isDragging {
      // if it's a mouseup after dragging window
      log.verbose("PlayerWindow mouseUp: finished drag of window")
      isDragging = false
    } else if finishResizingSidebar(with: event) {
      log.verbose("PlayerWindow mouseUp: finished resizing sidebar")
    } else {
      // if it's a mouseup after clicking

      /// Single click. Note that `event.clickCount` will be 0 if there is at least one call to `mouseDragged()`,
      /// but we will only count it as a drag if `isDragging==true`
      if event.clickCount <= 1 && !isMouseEvent(event, inAnyOf: [leadingSidebarView, trailingSidebarView, subPopoverView,
                                                                 topBarView, bottomBarView]) {
        if hideSidebarsOnClick() {
          log.verbose("PlayerWindow mouseUp: hiding sidebars")
          return
        }
      }
      let titleBarMinY = window!.frame.height - PlayerWindowController.standardTitleBarHeight
      if event.clickCount == 2 {
        if !isFullScreen && (event.locationInWindow.y >= titleBarMinY) {
          if let userDefault = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            log.verbose("Double-click occurred in title bar. Executing \(userDefault.quoted)")
            if userDefault == "Minimize" {
              window?.performMiniaturize(nil)
            } else if userDefault == "Maximize" {
              window?.performZoom(nil)
            }
            return
          } else {
            log.verbose("Double-click occurred in title bar, but no action for AppleActionOnDoubleClick")
          }
        } else {
          log.verbose("Double-click did not occur inside title bar (minY: \(titleBarMinY)) or is full screen (\(isFullScreen))")
        }
      }

      guard !isMouseEvent(event, inAnyOf: mouseActionDisabledViews) else {
        player.log.verbose("MouseUp: click occurred in a disabled view; ignoring")
        super.mouseUp(with: event)
        return
      }
      PluginInputManager.handle(
        input: PluginInputManager.Input.mouse, event: .mouseUp, player: player,
        arguments: mouseEventArgs(event), defaultHandler: { [self] in
          // default handler
          if event.clickCount == 1 {
            if doubleClickAction == .none {
              performMouseAction(singleClickAction)
            } else {
              singleClickTimer = Timer.scheduledTimer(timeInterval: NSEvent.doubleClickInterval, target: self, selector: #selector(performMouseActionLater), userInfo: singleClickAction, repeats: false)
              mouseExitEnterCount = 0
            }
          } else if event.clickCount == 2 {
            if let timer = singleClickTimer {
              timer.invalidate()
              singleClickTimer = nil
            }
            performMouseAction(doubleClickAction)
          }
        })
    }
  }

  override func otherMouseDown(with event: NSEvent) {
    restartHideCursorTimer()
    super.otherMouseDown(with: event)
  }

  override func otherMouseUp(with event: NSEvent) {
    log.verbose("PlayerWindow otherMouseUp!")
    restartHideCursorTimer()
    guard !isMouseEvent(event, inAnyOf: mouseActionDisabledViews) else { return }

    PluginInputManager.handle(
      input: PluginInputManager.Input.otherMouse, event: .mouseUp, player: player,
      arguments: mouseEventArgs(event), defaultHandler: {
        if event.type == .otherMouseUp {
          self.performMouseAction(Preference.enum(for: .middleClickAction))
        } else {
          super.otherMouseUp(with: event)
        }
      })
  }

  /// Workaround for issue #4183, Cursor remains visible after resuming playback with the touchpad using secondary click
  ///
  /// AppKit contains special handling for [rightMouseDown](https://developer.apple.com/documentation/appkit/nsview/event_handling/1806802-rightmousedown) having to do with contextual menus.
  /// Even though the documentation indicates the event will be passed up the responder chain, the event is not being received by the
  /// window controller. We are having to catch the event in the view. Because of that we do not call the super method and instead
  /// return to the view.`
  override func rightMouseDown(with event: NSEvent) {
    guard event.eventNumber != lastRightMouseDownEventID else { return }
    lastRightMouseDownEventID = event.eventNumber
    log.verbose("PlayerWindow rightMouseDown!")

    if let controlBarFloating = controlBarFloating, !controlBarFloating.isHidden, isMouseEvent(event, inAnyOf: [controlBarFloating]) {
      controlBarFloating.rightMouseDown(with: event)
      return
    }
    restartHideCursorTimer()
    PluginInputManager.handle(
      input: PluginInputManager.Input.rightMouse, event: .mouseDown,
      player: player, arguments: mouseEventArgs(event)
    )
  }

  override func rightMouseUp(with event: NSEvent) {
    guard event.eventNumber != lastRightMouseUpEventID else { return }
    lastRightMouseUpEventID = event.eventNumber
    log.verbose("PlayerWindow rightMouseUp!")
    restartHideCursorTimer()
    guard !isMouseEvent(event, inAnyOf: mouseActionDisabledViews) else { return }

    PluginInputManager.handle(
      input: PluginInputManager.Input.rightMouse, event: .mouseUp, player: player,
      arguments: mouseEventArgs(event), defaultHandler: {
        self.performMouseAction(Preference.enum(for: .rightClickAction))
      })
  }

  func performMouseAction(_ action: Preference.MouseClickAction) {
    log.verbose("Performing mouseAction: \(action)")
    switch action {
    case .pause:
      player.togglePause()
    case .fullscreen:
      toggleWindowFullScreen()
    case .hideOSC:
      hideFadeableViewsAndCursor()
    case .togglePIP:
      menuTogglePIP(.dummy)
    case .contextMenu:
      showContextMenu()
    default:
      break
    }
  }

  private func showContextMenu() {
    // TODO
  }

  override func scrollWheel(with event: NSEvent) {
    guard !isInInteractiveMode else { return }

    guard !isMouseEvent(event, inAnyOf: [currentControlBar, leadingSidebarView, trailingSidebarView,
                                         titleBarView, subPopoverView]) else { return }

    let isMouse = event.phase.isEmpty
    let isTrackpadBegan = event.phase.contains(.began)
    let isTrackpadEnd = event.phase.contains(.ended)

    // determine direction

    if isMouse || isTrackpadBegan {
      if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
        scrollDirection = .horizontal
      } else {
        scrollDirection = .vertical
      }
    }

    let scrollAction: Preference.ScrollAction = scrollDirection == .horizontal ? horizontalScrollAction : verticalScrollAction
    switch scrollAction {
    case .seek:
      // PlaySlider contains logic for scroll wheel seek.
      // Also see:
      playSlider.scrollWheel(with: event)

    case .volume:
      // show volume popover when volume seek begins and hide on end
      if isInMiniPlayer {
        player.windowController.miniPlayer.handleVolumePopover(isTrackpadBegan, isTrackpadEnd, isMouse)
      }

      volumeSlider.scrollWheel(with: event)
    default:
      break
    }

    if isTrackpadEnd {
      scrollDirection = nil
    }
  }

  override func mouseEntered(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    guard let area = event.trackingArea?.userInfo?[TrackingArea.key] as? TrackingArea else {
      log.warn("No data for tracking area")
      return
    }
    mouseExitEnterCount += 1

    switch area {
    case .playerWindow:
      isMouseInWindow = true
      showFadeableViews(duration: 0)
    case .playSlider:
      if controlBarFloating.isDragging { return }

      refreshSeekTimeAndThumbnailAsync(forPointInWindow: event.locationInWindow)
    case .customTitleBar:
      customTitleBar?.leadingTitleBarView.mouseEntered(with: event)
    }
  }

  override func mouseExited(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    guard let area = event.trackingArea?.userInfo?[TrackingArea.key] as? TrackingArea else {
      log.warn("No data for tracking area")
      return
    }
    mouseExitEnterCount += 1

    switch area {
    case .playerWindow:
      isMouseInWindow = false
      if controlBarFloating.isDragging { return }
      if !isAnimating && Preference.bool(for: .hideFadeableViewsWhenOutsideWindow) {
        hideFadeableViews()
      } else {
        // Closes loophole in case cursor hovered over OSC before exiting (in which case timer was destroyed)
        resetFadeTimer()
      }
    case .playSlider:
      hideSeekTimeAndThumbnail()
    case .customTitleBar:
      customTitleBar?.leadingTitleBarView.mouseExited(with: event)
    }
  }

  override func mouseMoved(with event: NSEvent) {
    guard !isInInteractiveMode else { return }

    /// Set or unset the cursor to `resizeLeftRight` if able to resize the sidebar
    if isMousePosWithinLeadingSidebarResizeRect(mousePositionInWindow: event.locationInWindow) ||
        isMousePosWithinTrailingSidebarResizeRect(mousePositionInWindow: event.locationInWindow) {
      if sidebarResizeCursor == nil {
        let newCursor = NSCursor.resizeLeftRight
        newCursor.push()
        sidebarResizeCursor = newCursor
      }
    } else {
      if let currentCursor = sidebarResizeCursor {
        currentCursor.pop()
        sidebarResizeCursor = nil
      }
    }

    if isPoint(event.locationInWindow, inAnyOf: [playSlider]) {
      refreshSeekTimeAndThumbnailAsync(forPointInWindow: event.locationInWindow)
    } else {
      hideSeekTimeAndThumbnail(animated: false)
    }

    let isTopBarHoverEnabled = Preference.isAdvancedEnabled && Preference.enum(for: .showTopBarTrigger) == Preference.ShowTopBarTrigger.topBarHover
    let forceShowTopBar = isTopBarHoverEnabled && isMouseInTopBarArea(event) && fadeableTopBarAnimationState == .hidden
    // Check whether mouse is in OSC
    let shouldRestartFadeTimer = !isMouseEvent(event, inAnyOf: [currentControlBar, titleBarView])
    showFadeableViews(thenRestartFadeTimer: shouldRestartFadeTimer, duration: 0, forceShowTopBar: forceShowTopBar)

    // Always hide after timeout even if OSD fade time is longer
    restartHideCursorTimer()
  }

  // assumes mouse is in window
  private func isMouseInTopBarArea(_ event: NSEvent) -> Bool {
    if !currentLayout.topBarView.isShowable {
      // e.g. music mode
      return false
    }
    guard let window = window, let contentView = window.contentView else { return false }
    let heightThreshold = contentView.frame.height - currentLayout.topBarHeight
    return event.locationInWindow.y >= heightThreshold
  }

  @objc func handleMagnifyGesture(recognizer: NSMagnificationGestureRecognizer) {
    magnificationHandler.handleMagnifyGesture(recognizer: recognizer)
  }

  @objc func handleRotationGesture(recognizer: NSRotationGestureRecognizer) {
    rotationHandler.handleRotationGesture(recognizer: recognizer)
  }

}
