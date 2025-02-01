//
//  PWin_Input.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-19.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

/// Mouse, Trackpad, Keyboard event handling.
/// For scroll wheel, see `PWin_ScrollWheel`.
extension PlayerWindowController {

  // MARK: - Keyboard event handling

  func handleKeyDown(event: NSEvent, normalizedMpvKey: String) -> Bool {
    let wasHandled = PluginInputManager.handle(
      input: normalizedMpvKey, event: .keyDown, player: player, arguments: keyEventArgs(event), handler: { [self] in
        if let keyBinding = player.keyBindingContext.matchActiveKeyBinding(endingWith: normalizedMpvKey) {
          if keyBinding.isIgnored {
            // if "ignore", just swallow the event. Do not forward; do not beep
            log.verbose("Binding is ignored for key: \(normalizedMpvKey.quoted)")
            return true
          } else {
            return handleKeyBinding(keyBinding)
          }
        }
        return false
      })

    return wasHandled
  }

  func keyEventArgs(_ event: NSEvent) -> [[String: Any]] {
    return [[
      "x": event.locationInWindow.x,
      "y": event.locationInWindow.y,
      "isRepeat": event.isARepeat
    ] as [String : Any]]
  }

  /// Returns true if handled
  @discardableResult
  func handleKeyBinding(_ keyBinding: KeyMapping) -> Bool {
    assert(DispatchQueue.isExecutingIn(.main))

    if let menuItem = keyBinding.menuItem, let action = menuItem.action {
      log.verbose{"Key binding is attached to menu item: \(menuItem.title.quoted) but was not handled by MenuController. Calling it manually"}
      // Send to nil to allow for greatest search scope
      NSApp.sendAction(action, to: nil, from: menuItem)
      return true
    }

    guard let rawAction = keyBinding.rawAction, let action = keyBinding.action else {
      log.error{"Expected key binding to have an mpv action, aborting: \(keyBinding)"}
      return false
    }

    // Some script bindings will draw to the video area. We don't know which will, but
    // if the DisplayLink is not active the updates will not be displayed.
    // So start the DisplayLink temporily if not already running:
    forceDraw()

    if keyBinding.isIINACommand {
      // - IINA command
      if let iinaCommand = IINACommand(rawValue: rawAction) {
        executeIINACommand(iinaCommand)
        return true
      } else {
        log.error{"Unrecognized IINA command: \(rawAction.quoted)"}
        return false
      }
    }

    // - mpv command
    var returnValue: Int32
    // execute the command
    switch action.first! {

    case MPVCommand.abLoop.rawValue:
      player.abLoop()
      returnValue = 0

    case MPVCommand.quit.rawValue:
      // Initiate application termination. AppKit requires this be done from the main thread,
      // however the main dispatch queue must not be used to avoid blocking the queue as per
      // instructions from Apple. IINA must support quitting being initiated by mpv as the user
      // could use mpv's IPC interface to send the quit command directly to mpv. However the
      // shutdown sequence is cleaner when initiated by IINA, so we do not send the quit command
      // to mpv and instead trigger the normal app termination sequence.
      RunLoop.main.perform(inModes: [.common]) {
        if !AppDelegate.shared.isTerminating {
          NSApp.terminate(nil)
        }
      }
      returnValue = 0

    case MPVCommand.screenshot.rawValue,
      MPVCommand.screenshotRaw.rawValue:
      player.mpv.queue.async { [self] in
        player.screenshot(fromKeyBinding: keyBinding)
      }
      return true

    default:
      let dispatchGroup = DispatchGroup()
      dispatchGroup.enter()

      returnValue = 0
      player.mpv.queue.async { [self] in
        returnValue = player.mpv.command(rawString: rawAction)
        dispatchGroup.leave()
      }
      let waitResult = dispatchGroup.wait(timeout: .now() + Constants.TimeInterval.keyDownHandlingTimeout)
      if waitResult == .timedOut {
        log.debug{"Command timed out: \(rawAction.quoted)"}
        return false
      }
    }

    guard returnValue == 0 else {
      log.error{"Return value \(returnValue) when executing key command \(rawAction.quoted)"}
      return false
    }
    return true
  }

  private func executeIINACommand(_ cmd: IINACommand) {
    assert(DispatchQueue.isExecutingIn(.main))

    switch cmd {
    case .openFile:
      AppDelegate.shared.showOpenFileWindow(isAlternativeAction: false)
    case .openURL:
      AppDelegate.shared.openURL(self)
    case .flip:
      menuToggleFlip(.dummy)
    case .mirror:
      menuToggleMirror(.dummy)
    case .saveCurrentPlaylist:
      menuSavePlaylist(.dummy)
    case .deleteCurrentFile:
      menuDeleteCurrentFile(.dummy)
    case .findOnlineSubs:
      menuFindOnlineSub(.dummy)
    case .saveDownloadedSub:
      saveDownloadedSub(.dummy)
    default:
      break
    }
  }

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

  /// Returns the first view found in `views` for which the given mouse event's point location lands inside its bounds.
  func viewForMouseEvent(_ event: NSEvent, in views: [NSView?]) -> NSView? {
    for view in views {
      guard let view else { continue }
      let localPoint = view.convert(event.locationInWindow, from: nil)
      if view.isMousePoint(localPoint, in: view.bounds) {
        return view
      }
    }
    return nil
  }

  /// Being called to perform single click action after timeout.
  ///
  /// - SeeAlso: mouseUp(with:)
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
    if let clickedButton = viewForMouseEvent(event, in: symButtons) {
      // Allow these controls to handle the event
      clickedButton.pressureChange(with: event)
      return
    }
    log.trace{"PressureChange: stage=\(event.stage) stageTransition=\(event.stageTransition)"}
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
    log.verbose{"PWin MouseDown @ \(event.locationInWindow)"}

    wasKeyWindowAtMouseDown = lastKeyWindowStatus

    if isMouseEvent(event, inAnyOf: [controlBarFloating]) {
      log.error("PWin MouseDown: ignoring; should be handled by controlBarFloating")
      return
    }
    if let cbView = cropSettingsView?.cropBoxView, !cbView.isHidden && isMouseEvent(event, inAnyOf: [cbView]) {
      log.error("PWin MouseDown: ignoring; should be handled by CropBoxView")
      return
    }

    // Start resize if applicable
    if startResizingSidebar(with: event) {
      return
    }

    // Else: could be dragging window.
    mouseDownLocationInWindow = event.locationInWindow
    restartHideCursorTimer()

    PluginInputManager.handle(
      input: PluginInputManager.Input.mouse, event: .mouseDown,
      player: player, arguments: mouseEventArgs(event)
    )
    // we don't call super here because before adding the plugin system,
    // PlayerWindowController didn't call super at all
  }
  
  override func mouseDragged(with event: NSEvent) {
    log.trace{"PWin MouseDragged @ \(event.locationInWindow)"}

    hideCursorTimer?.invalidate()
    if let currentDragObject {
      currentDragObject.mouseDragged(with: event)
      return
    }
    let didResizeSidebar = resizeSidebar(with: event)
    if didResizeSidebar {
      return
    }

    if !isFullScreen, let mouseDownLocationInWindow {
      if !isDragging {
        /// Require that the user must drag the cursor at least a small distance for it to start a "drag" (`isDragging==true`)
        /// The user's action will only be counted as a click if `isDragging==false` when `mouseUp` is called.
        /// (Apple's trackpad in particular is very sensitive and tends to call `mouseDragged()` if there is even the slightest
        /// roll of the finger during a click, and the distance of the "drag" may be less than `minimumInitialDragDistance`)
        let dragDistance = mouseDownLocationInWindow.distance(to: event.locationInWindow)
        guard dragDistance > Constants.Distance.windowControllerMinInitialDragThreshold else { return }
        log.verbose{"PWin MouseDrag: minimum dragging distance was met"}
        isDragging = true
      }
      window?.performDrag(with: event)
      informPluginMouseDragged(with: event)
    }
  }

  override func mouseUp(with event: NSEvent) {
    guard event.eventNumber != lastMouseUpEventID else { return }
    lastMouseUpEventID = event.eventNumber
    log.verbose{"PWin MouseUp @ \(event.locationInWindow), dragging=\(isDragging.yn), clickCount=\(event.clickCount) eventNum=\(event.eventNumber)"}

    if let currentDragObject {
      defer {
        self.currentDragObject = nil
      }
      log.verbose("PWin MouseUp: finished drag of object")
      currentDragObject.mouseUp(with: event)
      return
    }

    restartHideCursorTimer()
    mouseDownLocationInWindow = nil

    if isDragging {
      // if it's a mouseup after dragging window
      log.verbose("PWin MouseUp: finished drag of window")
      isDragging = false
      // In case WindowDidChangeScreen already timed out
      denyWindowResizeIntervalStartTime = Date()
      return
    }

    if finishResizingSidebar(with: event) {
      log.verbose("PWin MouseUp: finished resizing sidebar")
      return
    }

    // Else: if it's a mouseup after clicking
    let isSingleClick = event.clickCount == 1
    let isDoubleClick = event.clickCount == 2

    /// Single click. Note that `event.clickCount` will be 0 if there is at least one call to `mouseDragged()`,
    /// but we will only count it as a drag if `isDragging==true`
    if isSingleClick && !isMouseEvent(event, inAnyOf: [leadingSidebarView, trailingSidebarView, subPopoverView,
                                                       topBarView, bottomBarView]) {
      if hideSidebarsOnClick() {
        log.verbose("PWin MouseUp: hiding sidebars")
        return
      }
    }
    let titleBarMinY = window!.frame.height - Constants.Distance.standardTitleBarHeight
    if isDoubleClick {
      if !isFullScreen && (event.locationInWindow.y >= titleBarMinY) {
        if let userDefault = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
          log.verbose{"Double-click occurred in title bar. Executing \(userDefault.quoted)"}
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
        log.verbose{"Double-click did not occur inside title bar (minY: \(titleBarMinY)) or is full screen (\(isFullScreen))"}
      }
    }

    guard !isMouseEvent(event, inAnyOf: mouseActionDisabledViews) else {
      log.verbose{"PWin MouseUp: click occurred in a disabled view; ignoring"}
      super.mouseUp(with: event)
      return
    }
    PluginInputManager.handle(
      input: PluginInputManager.Input.mouse, event: .mouseUp, player: player,
      arguments: mouseEventArgs(event), defaultHandler: { [self] in
        let doubleClickAction: Preference.MouseClickAction = Preference.enum(for: .doubleClickAction)
        // default handler
        if isSingleClick {
          let singleClickAction: Preference.MouseClickAction = Preference.enum(for: .singleClickAction)
          if singleClickAction == .hideOSC && !wasKeyWindowAtMouseDown {
            // Don't hide OSC
            log.verbose{"Window was not key at mouseDown; skipping mouseAction: \(singleClickAction)"}
            return false
          }
          if doubleClickAction == .none {
            performMouseAction(singleClickAction)
          } else {
            singleClickTimer = Timer.scheduledTimer(timeInterval: NSEvent.doubleClickInterval, target: self, selector: #selector(performMouseActionLater), userInfo: singleClickAction, repeats: false)
            mouseExitEnterCount = 0
          }
        } else if isDoubleClick {
          if let timer = singleClickTimer {
            timer.invalidate()
            singleClickTimer = nil
          }
          performMouseAction(doubleClickAction)
        }
        return true
      })
  }

  override func otherMouseDown(with event: NSEvent) {
    restartHideCursorTimer()
    super.otherMouseDown(with: event)
  }

  override func otherMouseUp(with event: NSEvent) {
    log.verbose("PWin.otherMouseUp!")
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
        return true
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
    log.verbose("PWin.rightMouseDown!")

    defer {
      /// Apple note (https://developer.apple.com/documentation/appkit/nsview):
      /// NSView changes the default behavior of rightMouseDown(with:) so that it calls menu(for:) and, if non nil, presents the contextual menu. In macOS 10.7 and later, if the event is not handled, NSView passes the event up the responder chain. Because of these behaviorial changes, call super when implementing rightMouseDown(with:) in your custom NSView subclasses.
      super.rightMouseDown(with: event)
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
    log.verbose("PWin.rightMouseUp!")
    restartHideCursorTimer()
    guard !isMouseEvent(event, inAnyOf: mouseActionDisabledViews) else { return }

    PluginInputManager.handle(
      input: PluginInputManager.Input.rightMouse, event: .mouseUp, player: player,
      arguments: mouseEventArgs(event), defaultHandler: {
        self.performMouseAction(Preference.enum(for: .rightClickAction))
        return true
      })
  }

  func performMouseAction(_ action: Preference.MouseClickAction) {
    log.verbose{"Performing mouseAction: \(action)"}
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
    case .customTitleBar:
      customTitleBar?.leadingStackView.mouseEntered(with: event)
    default:
      break
    }
  }

  override func mouseExited(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    guard let area = event.trackingArea?.userInfo?[TrackingArea.key] as? TrackingArea else {
      log.warn("MouseExited: no data for tracking area!")
      return
    }
    mouseExitEnterCount += 1

    switch area {
    case .playerWindow:
      isMouseInWindow = false
      if currentDragObject != nil { return }
      if !isAnimating && Preference.bool(for: .hideFadeableViewsWhenOutsideWindow) {
        hideFadeableViews()
      } else {
        // Closes loophole in case cursor hovered over OSC before exiting (in which case timer was destroyed)
        fadeableViews.hideTimer.restart()
      }
    case .customTitleBar:
      customTitleBar?.leadingStackView.mouseExited(with: event)
    default:
      break
    }
  }

  override func mouseMoved(with event: NSEvent) {
    guard !isScrollingOrDraggingPlaySlider, !isScrollingOrDraggingVolumeSlider else { return }
    
    if isInInteractiveMode {
      let disableWindowDragging = isMouseEvent(event, inAnyOf: [viewportView])
      updateIsMoveableByWindowBackground(disableWindowDrag: disableWindowDragging)
      return
    }

    // Do not use `event.locationInWindow`: it can be stale
    let pointInWindow = mouseLocationInWindow

    /// Set or unset the cursor to `resizeLeftRight` if able to resize the sidebar
    if isMousePosWithinLeadingSidebarResizeRect(mousePositionInWindow: pointInWindow) ||
        isMousePosWithinTrailingSidebarResizeRect(mousePositionInWindow: pointInWindow) {
      if sidebarResizeCursor == nil {
        let newCursor = NSCursor.resizeLeftRight
        newCursor.push()
        sidebarResizeCursor = newCursor
      }
      // Kludge to prevent window drag if trying to drag sidebar. Do not drag the window!
      updateIsMoveableByWindowBackground(disableWindowDrag: true)
    } else {
      if let currentCursor = sidebarResizeCursor {
        currentCursor.pop()
        sidebarResizeCursor = nil
      }

      // Kludge to prevent window drag if trying to drag floating OSC.
      let disableWindowDragging = isMouseEvent(event, inAnyOf: [controlBarFloating])
      updateIsMoveableByWindowBackground(disableWindowDrag: disableWindowDragging)
    }

    refreshSeekPreviewAsync(forPointInWindow: pointInWindow)
    volumeSliderCell.refreshVolumeSliderHoverEffect()

    let isTopBarHoverEnabled = Preference.isAdvancedEnabled && Preference.enum(for: .showTopBarTrigger) == Preference.ShowTopBarTrigger.topBarHover
    let forceShowTopBar = isTopBarHoverEnabled && isMouseInTopBarArea(pointInWindow) && fadeableViews.topBarAnimationState == .hidden
    // Check whether mouse is in OSC
    let shouldRestartFadeTimer = !isPoint(pointInWindow, inAnyOf: [currentControlBar, titleBarView])
    showFadeableViews(thenRestartFadeTimer: shouldRestartFadeTimer, duration: 0, forceShowTopBar: forceShowTopBar)

    // Always hide after timeout even if OSD fade time is longer
    restartHideCursorTimer()
  }

  func isMouseActuallyInside(view: NSView) -> Bool {
    return window!.isKeyWindow && isPoint(mouseLocationInWindow, inAnyOf: [view])
  }

  // assumes mouse is in window
  private func isMouseInTopBarArea(_ mouseLocInWindow: NSPoint) -> Bool {
    if !currentLayout.topBarView.isShowable {
      // e.g. music mode
      return false
    }
    guard let window = window, let contentView = window.contentView else { return false }
    let heightThreshold = contentView.frame.height - currentLayout.topBarHeight
    return mouseLocInWindow.y >= heightThreshold
  }

  @objc func handleMagnifyGesture(recognizer: NSMagnificationGestureRecognizer) {
    magnificationHandler.handleMagnifyGesture(recognizer: recognizer)
  }

  @objc func handleRotationGesture(recognizer: NSRotationGestureRecognizer) {
    rotationHandler.handleRotationGesture(recognizer: recognizer)
  }

  func updateIsMoveableByWindowBackground(disableWindowDrag: Bool = false) {
    if disableWindowDrag || currentLayout.isFullScreen {
      window?.isMovableByWindowBackground = false
    } else {
      // Enable this so that user can drag from title bar with first mouse
      window?.isMovableByWindowBackground = true
    }

  }
}
