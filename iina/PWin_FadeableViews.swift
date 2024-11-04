//
//  PWin_FadeableViews.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-19.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

/// Encapsulates logic to:
/// Show/hide fadeable views
/// Show/hide seek time & thumbnail
/// Hide mouse cursor
/// Show/hide default album art
extension PlayerWindowController {

  // MARK: - Visibility utility functions

  func apply(visibility: VisibilityMode, to view: NSView) {
    switch visibility {
    case .hidden:
      view.alphaValue = 0
      view.isHidden = true
      fadeableViews.remove(view)
      fadeableViewsInTopBar.remove(view)
    case .showAlways:
      view.alphaValue = 1
      view.isHidden = false
      fadeableViews.remove(view)
      fadeableViewsInTopBar.remove(view)
    case .showFadeableTopBar:
      view.alphaValue = 1
      view.isHidden = false
      fadeableViewsInTopBar.insert(view)
    case .showFadeableNonTopBar:
      view.alphaValue = 1
      view.isHidden = false
      fadeableViews.insert(view)
    }
  }

  func apply(visibility: VisibilityMode, _ views: NSView?...) {
    for view in views {
      if let view = view {
        apply(visibility: visibility, to: view)
      }
    }
  }

  func applyHiddenOnly(visibility: VisibilityMode, to view: NSView, isTopBar: Bool = true) {
    guard visibility == .hidden else { return }
    apply(visibility: visibility, view)
  }

  func applyShowableOnly(visibility: VisibilityMode, to view: NSView, isTopBar: Bool = true) {
    guard visibility != .hidden else { return }
    apply(visibility: visibility, view)
  }

  // MARK: - UI: Show / Hide Fadeable Views

  // Shows fadeableViews and titlebar via fade
  func showFadeableViews(thenRestartFadeTimer restartFadeTimer: Bool = true,
                         duration: CGFloat = IINAAnimation.DefaultDuration,
                         forceShowTopBar: Bool = false) {
    guard !player.disableUI && !isInInteractiveMode else { return }
    let tasks: [IINAAnimation.Task] = buildAnimationToShowFadeableViews(restartFadeTimer: restartFadeTimer,
                                                                        duration: duration,
                                                                        forceShowTopBar: forceShowTopBar)
    animationPipeline.submit(tasks)
  }

  func buildAnimationToShowFadeableViews(restartFadeTimer: Bool = true,
                                         duration: CGFloat = IINAAnimation.DefaultDuration,
                                         forceShowTopBar: Bool = false) -> [IINAAnimation.Task] {
    var tasks: [IINAAnimation.Task] = []

    /// Default `showTopBarTrigger` setting to `.windowHover` if advanced settings not enabled
    let wantsTopBarVisible = forceShowTopBar || (!Preference.isAdvancedEnabled || Preference.enum(for: .showTopBarTrigger) == Preference.ShowTopBarTrigger.windowHover)

    guard !player.disableUI && !isInInteractiveMode else {
      return tasks
    }

    guard wantsTopBarVisible || fadeableViewsAnimationState == .hidden else {
      if restartFadeTimer {
        resetFadeTimer()
      } else {
        hideFadeableViewsTimer?.invalidate()
      }
      return tasks
    }

    let currentLayout = self.currentLayout

    tasks.append(IINAAnimation.Task(duration: duration, { [self] in
      guard fadeableViewsAnimationState == .hidden || fadeableViewsAnimationState == .shown else { return }
      fadeableViewsAnimationState = .willShow
      player.refreshSyncUITimer(logMsg: "Showing fadeable views ")
      hideFadeableViewsTimer?.invalidate()

      for v in fadeableViews {
        v.animator().alphaValue = 1
      }

      if wantsTopBarVisible {  // start top bar
        fadeableTopBarAnimationState = .willShow
        for v in fadeableViewsInTopBar {
          v.animator().alphaValue = 1
        }

        if currentLayout.titleBar == .showFadeableTopBar {
          if currentLayout.spec.isLegacyStyle {
            customTitleBar?.view.animator().alphaValue = 1
          } else {
            for button in trafficLightButtons {
              button.alphaValue = 1
            }
            titleTextField?.alphaValue = 1
            documentIconButton?.alphaValue = 1
          }
        }
      }  // end top bar
    }))

    // Not animated, but needs to wait until after fade is done
    tasks.append(.instantTask { [self] in
      // if no interrupt then hide animation
      if fadeableViewsAnimationState == .willShow {
        fadeableViewsAnimationState = .shown
        for v in fadeableViews {
          v.isHidden = false
        }

        if restartFadeTimer {
          resetFadeTimer()
        }
      }

      if wantsTopBarVisible && fadeableTopBarAnimationState == .willShow {
        fadeableTopBarAnimationState = .shown
        for v in fadeableViewsInTopBar {
          v.isHidden = false
        }

        if currentLayout.titleBar == .showFadeableTopBar {
          if currentLayout.spec.isLegacyStyle {
            customTitleBar?.view.isHidden = false
          } else {
            for button in trafficLightButtons {
              button.isHidden = false
            }
            titleTextField?.isHidden = false
            documentIconButton?.isHidden = false
          }
        }
      }  // end top bar
    })
    return tasks
  }

  @discardableResult
  func hideFadeableViews() -> Bool {
    guard pipStatus == .notInPIP, (!(window?.isMiniaturized ?? false)), fadeableViewsAnimationState == .shown else {
      return false
    }

    // Don't hide UI when auto hide control bar is disabled
    guard Preference.bool(for: .enableControlBarAutoHide) || Preference.bool(for: .hideFadeableViewsWhenOutsideWindow) else { return false }

    var tasks: [IINAAnimation.Task] = []

    // Seek time & thumbnail can only be shown if the OSC is visible.
    // Need to hide them because the OSC is being hidden:
    let mustHideSeekTimeAndThumbnail = !currentLayout.hasPermanentControlBar

    if mustHideSeekTimeAndThumbnail {
      // Cancel timer now. Hide thumbnail with other views (below)
      hideSeekTimeAndThumbnailTimer?.invalidate()
    }

    tasks.append(IINAAnimation.Task(duration: IINAAnimation.DefaultDuration) { [self] in
      // Don't hide overlays when in PIP or when they are not actually shown
      destroyFadeTimer()
      fadeableViewsAnimationState = .willHide
      fadeableTopBarAnimationState = .willHide
      player.refreshSyncUITimer(logMsg: "Hiding fadeable views ")

      for v in fadeableViews {
        v.animator().alphaValue = 0
      }
      for v in fadeableViewsInTopBar {
        v.animator().alphaValue = 0
      }
      /// Quirk 1: special handling for `trafficLightButtons`
      if currentLayout.titleBar == .showFadeableTopBar {
        if currentLayout.spec.isLegacyStyle {
          customTitleBar?.view.alphaValue = 0
        } else {
          documentIconButton?.alphaValue = 0
          titleTextField?.alphaValue = 0
          for button in trafficLightButtons {
            button.alphaValue = 0
          }
        }
      }

      if mustHideSeekTimeAndThumbnail {
        seekTimeAndThumbnailAnimationState = .willHide
        thumbnailPeekView.animator().alphaValue = 0
        timePositionHoverLabel.isHidden = true
      }
    })

    tasks.append(IINAAnimation.Task(duration: IINAAnimation.DefaultDuration) { [self] in
      // if no interrupt then hide animation
      guard fadeableViewsAnimationState == .willHide else { return }

      fadeableViewsAnimationState = .hidden
      fadeableTopBarAnimationState = .hidden
      for v in fadeableViews {
        v.isHidden = true
      }
      for v in fadeableViewsInTopBar {
        v.isHidden = true
      }
      /// Quirk 1: need to set `alphaValue` back to `1` so that each button's corresponding menu items still work
      if currentLayout.titleBar == .showFadeableTopBar {
        if currentLayout.spec.isLegacyStyle {
          customTitleBar?.view.isHidden = true
        } else {
          hideBuiltInTitleBarViews(setAlpha: false)
        }
      }

      if mustHideSeekTimeAndThumbnail, seekTimeAndThumbnailAnimationState == .willHide {
        seekTimeAndThumbnailAnimationState = .hidden
        thumbnailPeekView.isHidden = true
        timePositionHoverLabel.isHidden = true
      }
    })

    animationPipeline.submit(tasks)
    return true
  }

  /// Executed when `hideFadeableViewsTimer` fires
  @objc func hideFadeableViewsAndCursor() {
    // don't hide UI when dragging control bar
    if controlBarFloating.isDragging { return }
    if hideFadeableViews() {
      hideCursor()
    }
  }

  // MARK: - Fadeable Views Timer

  func resetFadeTimer() {
    // If timer exists, destroy first
    hideFadeableViewsTimer?.invalidate()

    // The fade timer is only used if auto-hide is enabled
    guard Preference.bool(for: .enableControlBarAutoHide) else { return }

    // Create new timer.
    // Timer and animation APIs require Double, but we must support legacy prefs, which store as Float
    var timeout = Double(Preference.float(for: .controlBarAutoHideTimeout))
    if timeout < IINAAnimation.DefaultDuration {
      timeout = IINAAnimation.DefaultDuration
    }
    let timer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideFadeableViewsAndCursor), userInfo: nil, repeats: false)
    timer.tolerance = 0.05
    hideFadeableViewsTimer = timer
  }

  func destroyFadeTimer() {
    hideFadeableViewsTimer?.invalidate()
  }

  // MARK: - Cursor visibility

  func restartHideCursorTimer() {
    hideCursorTimer?.invalidate()
    hideCursorTimer = Timer.scheduledTimer(timeInterval: max(0, Preference.double(for: .cursorAutoHideTimeout)), target: self, selector: #selector(hideCursor), userInfo: nil, repeats: false)
  }

  /// Only hides cursor if in full screen or windowed (non-interactive) modes, and only if mouse is within
  /// bounds of the window's real estate.
  @objc func hideCursor() {
    hideCursorTimer?.invalidate()
    hideCursorTimer = nil
    guard let window else { return }

    switch currentLayout.mode {
    case .windowed:
      let isCursorInWindow = NSPointInRect(NSEvent.mouseLocation, window.frame)
      guard isCursorInWindow else { return }
    case .fullScreen:
      let isCursorInScreen = NSPointInRect(NSEvent.mouseLocation, bestScreen.visibleFrame)
      guard isCursorInScreen else { return }
    case .musicMode, .windowedInteractive, .fullScreenInteractive:
      return
    }
    log.trace("Hiding cursor")
    NSCursor.setHiddenUntilMouseMoves(true)
  }

  // MARK: - Default album art visibility

  func updateDefaultArtVisibility(to showDefaultArt: Bool?) {
    assert(DispatchQueue.isExecutingIn(.main))
    guard let showDefaultArt else { return }

    log.verbose("\(showDefaultArt ? "Showing" : "Hiding") defaultAlbumArt (state=\(player.info.currentPlayback?.state.description ?? "nil"))")
    // Update default album art visibility:
    defaultAlbumArtView.isHidden = !showDefaultArt
  }

  // MARK: - Seek Time & Thumbnail

  func shouldSeekTimeAndThumbnailBeVisible(forPointInWindow pointInWindow: NSPoint) -> Bool {
    guard !player.disableUI,
          !isAnimatingLayoutTransition,
          !osd.isShowingPersistentOSD,
          currentLayout.hasControlBar else {
      return false
    }
    return isInScrollWheelSeek || isDraggingPlaySlider || isPoint(pointInWindow, inAnyOf: [playSlider])
  }

  func resetSeekTimeAndThumbnailTimer() {
    guard seekTimeAndThumbnailAnimationState == .shown else { return }
    hideSeekTimeAndThumbnailTimer?.invalidate()
    hideSeekTimeAndThumbnailTimer = Timer.scheduledTimer(timeInterval: Constants.TimeInterval.seekTimeAndThumbnailHideTimeout,
                                                         target: self, selector: #selector(self.seekTimeAndThumbnailTimeout),
                                                         userInfo: nil, repeats: false)
  }

  @objc private func seekTimeAndThumbnailTimeout() {
    let pointInWindow = window!.convertPoint(fromScreen: NSEvent.mouseLocation)
    guard !shouldSeekTimeAndThumbnailBeVisible(forPointInWindow: pointInWindow) else {
      resetSeekTimeAndThumbnailTimer()
      return
    }
    hideSeekTimeAndThumbnail(animated: true)
  }

  @objc func hideSeekTimeAndThumbnail(animated: Bool = false) {
    hideSeekTimeAndThumbnailTimer?.invalidate()

    if animated {
      var tasks: [IINAAnimation.Task] = []

      tasks.append(IINAAnimation.Task(duration: IINAAnimation.OSDAnimationDuration * 0.5) { [self] in
        // Don't hide overlays when in PIP or when they are not actually shown
        seekTimeAndThumbnailAnimationState = .willHide
        thumbnailPeekView.animator().alphaValue = 0
        timePositionHoverLabel.isHidden = true
        if isShowingFadeableViewsForSeek {
          isShowingFadeableViewsForSeek = false
          resetFadeTimer()
        }
      })

      tasks.append(IINAAnimation.Task(duration: 0) { [self] in
        // if no interrupt then hide animation
        guard seekTimeAndThumbnailAnimationState == .willHide else { return }
        seekTimeAndThumbnailAnimationState = .hidden
        thumbnailPeekView.isHidden = true
        timePositionHoverLabel.isHidden = true
      })

      animationPipeline.submit(tasks)
    } else {
      thumbnailPeekView.isHidden = true
      timePositionHoverLabel.isHidden = true
      seekTimeAndThumbnailAnimationState = .hidden
    }
  }

  /// Display time label & thumbnail when mouse over slider
  func refreshSeekTimeAndThumbnailAsync(forPointInWindow pointInWindow: NSPoint) {
    thumbDisplayTicketCounter += 1
    let currentTicket = thumbDisplayTicketCounter

    DispatchQueue.main.async { [self] in
      guard currentTicket == thumbDisplayTicketCounter else { return }

      guard shouldSeekTimeAndThumbnailBeVisible(forPointInWindow: pointInWindow),
            let duration = player.info.playbackDurationSec else {
        hideSeekTimeAndThumbnail()
        return
      }
      showSeekTimeAndThumbnail(forPointInWindow: pointInWindow, mediaDuration: duration)
    }
  }

  /// Should only be called by `refreshSeekTimeAndThumbnailAsync`
  private func showSeekTimeAndThumbnail(forPointInWindow pointInWindow: NSPoint, mediaDuration: CGFloat) {
    // - 1. Time Hover Label

    let knobCenterOffsetInPlaySlider = playSlider.computeCenterOfKnobInSliderCoordXGiven(pointInWindow: pointInWindow)

    timePositionHoverLabelHorizontalCenterConstraint.constant = knobCenterOffsetInPlaySlider

    let playbackPositionRatio = playSlider.computeProgressRatioGiven(centerOfKnobInSliderCoordX:
                                                                      knobCenterOffsetInPlaySlider)
    let previewTimeSec = mediaDuration * playbackPositionRatio
    let stringRepresentation = VideoTime.string(from: previewTimeSec)
    if timePositionHoverLabel.stringValue != stringRepresentation {
      timePositionHoverLabel.stringValue = stringRepresentation
    }
    timePositionHoverLabel.isHidden = false

    // - 2. Thumbnail Preview

    if isInScrollWheelSeek || isDraggingPlaySlider {
      // Thumbnail preview during seek
      guard Preference.bool(for: .enableThumbnailPreview) && Preference.bool(for: .showThumbnailDuringSliderSeek) else {
        // Feature is disabled
        thumbnailPeekView.isHidden = true
        return
      }
      // Need to ensure OSC is displayed if showing thumbnail preview
      let hasFadeableOSC = currentLayout.hasFadeableOSC
      if hasFadeableOSC {
        let hasTopBarFadeableOSC = currentLayout.oscPosition == .top && currentLayout.topBarView == .showFadeableTopBar
        let isOSCHidden = hasTopBarFadeableOSC ? fadeableTopBarAnimationState == .hidden : fadeableViewsAnimationState == .hidden
        if isOSCHidden {
          showFadeableViews(thenRestartFadeTimer: false, duration: 0, forceShowTopBar: hasTopBarFadeableOSC)
        } else {
          hideFadeableViewsTimer?.invalidate()
        }
        // Set this to remind ourselves to restart the fade timer when seek is done
        isShowingFadeableViewsForSeek = true
      }
    }

    guard let currentControlBar else {
      thumbnailPeekView.isHidden = true
      return
    }
    guard !currentLayout.isMusicMode || (Preference.bool(for: .enableThumbnailForMusicMode) && musicModeGeo.isVideoVisible) else {
      thumbnailPeekView.isHidden = true
      return
    }

    let didShow = thumbnailPeekView.displayThumbnail(forTime: previewTimeSec, originalPosX: pointInWindow.x, player, currentLayout,
                                                     currentControlBar: currentControlBar, geo.video,
                                                     viewportSize: viewportView.frame.size,
                                                     isRightToLeft: videoView.userInterfaceLayoutDirection == .rightToLeft)
    guard didShow else { return }
    seekTimeAndThumbnailAnimationState = .shown
    // Start timer (or reset it), even if just hovering over the play slider. The Cocoa "mouseExited" event doesn't fire
    // reliably, so using a timer works well as a failsafe.
    resetSeekTimeAndThumbnailTimer()
  }

}
