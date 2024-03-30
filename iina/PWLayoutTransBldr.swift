//
//  PWLayoutTransitionExtension.swift
//  iina
//
//  Created by Matt Svoboda on 8/20/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// This file is not really a factory class due to limitations of the AppKit paradigm, but it contain
/// methods for creating/running `LayoutTransition`s to change between `LayoutState`s for the
/// given `PlayerWindowController`.
extension PlayerWindowController {

  // MARK: - Window Initial Layout

  func setInitialWindowLayout() {
    let initialLayoutSpec: LayoutSpec
    let isRestoringFromPrevLaunch: Bool
    var needsNativeFullScreen = false

    // Don't want window resize/move listeners doing something untoward
    isAnimatingLayoutTransition = true

    if let priorState = player.info.priorState, let priorLayoutSpec = priorState.layoutSpec {
      log.verbose("Transitioning to initial layout from prior window state")
      isRestoringFromPrevLaunch = true
      // Don't need this because we already know how to size the window
      isInitialSizeDone = true

      // Restore saved geometries
      if let priorWindowedModeGeometry = priorState.windowedModeGeo {
        log.verbose("Setting windowedModeGeo from prior state: \(priorWindowedModeGeometry)")
        windowedModeGeo = priorWindowedModeGeometry
        if priorLayoutSpec.mode != .musicMode {
          videoView.apply(windowedModeGeo)
        }
      } else {
        log.error("Failed to get player window geometry from prefs")
      }

      if let priorMusicModeGeometry = priorState.musicModeGeo {
        log.verbose("Setting musicModeGeo from prior state: \(priorMusicModeGeometry)")
        musicModeGeo = priorMusicModeGeometry
        // Restore primary videoAspect
        if priorLayoutSpec.mode == .musicMode {
          videoView.apply(priorMusicModeGeometry.toPWGeometry())
        }
      } else {
        log.error("Failed to get player window layout and/or geometry from prefs")
      }

      if priorLayoutSpec.mode == .musicMode {
        player.overrideAutoMusicMode = true
      }

      if priorLayoutSpec.isNativeFullScreen {
        // Special handling for native fullscreen. Rely on mpv to put us in FS when it is ready
        initialLayoutSpec = priorLayoutSpec.clone(mode: .windowed)
        needsNativeFullScreen = true
      } else {
        initialLayoutSpec = priorLayoutSpec
      }

    } else {
      log.verbose("Transitioning to initial layout from app prefs")
      isRestoringFromPrevLaunch = false

      let mode: PlayerWindowMode
      if Preference.bool(for: .fullScreenWhenOpen) {
        log.debug("Changing to fullscreen because \(Preference.Key.fullScreenWhenOpen.rawValue) == true")
        mode = .fullScreen
      } else {
        mode = .windowed
      }

      // Set to default layout, but use existing aspect ratio & video size for now, because we don't have that info yet for the new video
      initialLayoutSpec = LayoutSpec.fromPreferences(andMode: mode, fillingInFrom: lastWindowedLayoutSpec)

      // Should only be here if window is a new window or was previously closed. Copy layout from the last closed window
      assert(!isOpen)
      assert(!isInitialSizeDone)
      let initialLayout = LayoutState.buildFrom(initialLayoutSpec)

      let resizeTimingPref = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
      if resizeTimingPref == .always || resizeTimingPref == .onlyWhenOpen {
        /// Use `minVideoSize` at first when a new window is opened, so that when `resizeWindowAfterVideoReconfig()` is called shortly after,
        /// it expands and creates a nice zooming effect.
        let videoSize = AppData.minVideoSize
        let windowFrame = NSRect(origin: CGPoint.zero, size: videoSize)
        let defaultScreenID = NSScreen.main!.screenID
        let initialGeo = initialLayout.buildGeometry(windowFrame: windowFrame, screenID: defaultScreenID, videoAspect: videoSize.mpvAspect)
        windowedModeGeo = initialGeo.refit(.centerInVisibleScreen)
      } else {
        // No configured resize strategy. So just apply the last closed geometry right away, with no extra animations
        windowedModeGeo = initialLayout.convertWindowedModeGeometry(from: PlayerWindowController.windowedModeGeoLastClosed)
      }

      musicModeGeo = PlayerWindowController.musicModeGeoLastClosed
    }

    log.verbose("Setting initial \(initialLayoutSpec), windowedModeGeo: \(windowedModeGeo), musicModeGeo: \(musicModeGeo)")

    let transitionName = "\(isRestoringFromPrevLaunch ? "Restore" : "Set")InitialLayout"
    let initialTransition = buildLayoutTransition(named: transitionName,
                                                  from: currentLayout, to: initialLayoutSpec, isInitialLayout: true)

    if !isRestoringFromPrevLaunch && initialLayoutSpec.mode == .windowed {
      player.info.intendedViewportSize = initialTransition.outputGeometry.viewportSize
    }

    /// Although the animations in the `LayoutTransition` below will set the window layout, they
    /// mostly assume they are incrementally changing a previous layout, which can result in brief visual
    /// artifacts in the process if we start with an undefined layout.
    /// To smooth out the process, restore window position & size before laying out its internals.
    switch initialLayoutSpec.mode {
    case .fullScreen, .fullScreenInteractive:
      /// Don't need to set window frame here because it will be set by `LayoutTransition` to full screen (below).
      /// Similarly, when window exits full screen, the windowed mode position will be restored from `windowedModeGeo`.
      break
    case .windowed, .windowedInteractive, .musicMode:
      player.window.setFrameImmediately(initialTransition.outputGeometry.windowFrame)
      videoView.apply(initialTransition.outputGeometry)
    }

    // For initial layout (when window is first shown), to reduce jitteriness when drawing,
    // do all the layout in a single animation block
    IINAAnimation.disableAnimation{
      for task in initialTransition.animationTasks {
        task.runFunc()
      }
      /// Note: `isAnimatingLayoutTransition` should be `false` now
      log.verbose("Done with transition to initial layout")
    }

    if !isRestoringFromPrevLaunch && Preference.bool(for: .alwaysFloatOnTop) && !player.info.isPaused {
      log.verbose("Setting window OnTop=true per app pref")
      setWindowFloatingOnTop(true)
    }

    if needsNativeFullScreen {
      animationPipeline.submitZeroDuration({ [self] in
        enterFullScreen()
      })
      return
    }

    guard isRestoringFromPrevLaunch else { return }

    /// Stored window state may not be consistent with global IINA prefs.
    /// To check this, build another `LayoutSpec` from the global prefs, then compare it to the player's.
    let prefsSpec = LayoutSpec.fromPreferences(fillingInFrom: currentLayout.spec)
    if initialLayoutSpec.hasSamePrefsValues(as: prefsSpec) {
      log.verbose("Saved layout is consistent with IINA global prefs")
    } else {
      // Not consistent. But we already have the correct spec, so just build a layout from it and transition to correct layout
      log.warn("Player's saved layout does not match IINA app prefs. Will build and apply a corrected layout")
      log.debug("SavedSpec: \(currentLayout.spec). PrefsSpec: \(prefsSpec)")
      buildLayoutTransition(named: "FixInvalidInitialLayout",
                            from: initialTransition.outputLayout, to: prefsSpec, thenRun: true)
    }
  }

  // MARK: - Building LayoutTransition

  /// First builds a new `LayoutState` based on the given `LayoutSpec`, then builds & returns a `LayoutTransition`,
  /// which contains all the information needed to animate the UI changes from the current `LayoutState` to the new one.
  @discardableResult
  func buildLayoutTransition(named transitionName: String,
                             from inputLayout: LayoutState,
                             to outputSpec: LayoutSpec,
                             isInitialLayout: Bool = false,
                             totalStartingDuration: CGFloat? = nil,
                             totalEndingDuration: CGFloat? = nil,
                             thenRun: Bool = false) -> LayoutTransition {

    var transitionID: Int = 0
    $layoutTransitionCounter.withLock {
      $0 += 1
      transitionID = $0
    }
    let transitionName = "\(transitionName)-\(transitionID)"

    // This also applies to full screen, because full screen always uses the same screen as windowed.
    // Does not apply to music mode, which can be a different screen.
    let windowedModeScreen = NSScreen.getScreenOrDefault(screenID: windowedModeGeo.screenID)

    // Compile outputLayout
    let outputLayout = LayoutState.buildFrom(outputSpec)

    // - Build geometries

    // InputGeometry
    let inputGeometry: PWGeometry = buildInputGeometry(from: inputLayout, transitionName: transitionName, windowedModeScreen: windowedModeScreen)
    log.verbose("[\(transitionName)] InputGeometry: \(inputGeometry)")

    // OutputGeometry
    let outputGeometry: PWGeometry = buildOutputGeometry(inputLayout: inputLayout, inputGeometry: inputGeometry,
                                                         outputLayout: outputLayout, isInitialLayout: isInitialLayout)

    let transition = LayoutTransition(name: transitionName,
                                      from: inputLayout, from: inputGeometry,
                                      to: outputLayout, to: outputGeometry,
                                      isInitialLayout: isInitialLayout)

    // MiddleGeometry if needed (is applied after ClosePanels step)
    transition.middleGeometry = buildMiddleGeometry(forTransition: transition)
    if let middleGeometry = transition.middleGeometry {
      log.verbose("[\(transitionName)] MiddleGeometry: \(middleGeometry)")
    } else {
      log.verbose("[\(transitionName)] MiddleGeometry: nil")
    }

    log.verbose("[\(transitionName)] OutputGeometry: \(outputGeometry)")

    let panelTimingName: CAMediaTimingFunctionName
    if transition.isTogglingFullScreen {
      panelTimingName = .easeInEaseOut
    } else if transition.isTogglingVisibilityOfAnySidebar {
      panelTimingName = .easeIn
    } else {
      panelTimingName = .linear
    }

    // - Determine durations

    var startingAnimationDuration = IINAAnimation.DefaultDuration
    if transition.isTogglingFullScreen {
      startingAnimationDuration = 0
    } else if transition.isEnteringMusicMode {
      startingAnimationDuration = IINAAnimation.DefaultDuration
    } else if let totalStartingDuration = totalStartingDuration {
      startingAnimationDuration = totalStartingDuration / 3
    }

    var showFadeableViewsDuration: CGFloat = startingAnimationDuration
    var fadeOutOldViewsDuration: CGFloat = startingAnimationDuration
    var closeOldPanelsDuration: CGFloat = startingAnimationDuration
    if transition.isEnteringMusicMode {
      showFadeableViewsDuration = startingAnimationDuration * 0.5
      fadeOutOldViewsDuration = startingAnimationDuration * 0.5
    } else {
      if !transition.needsAnimationForShowFadeables {
        showFadeableViewsDuration = 0
      }
      if !transition.needsFadeOutOldViews {
        fadeOutOldViewsDuration = 0
      }
      if !transition.needsCloseOldPanels {
        closeOldPanelsDuration = 0
      }
    }

    let endingAnimationDuration: CGFloat = totalEndingDuration ?? IINAAnimation.DefaultDuration

    // Extra animation when entering legacy full screen: cover camera housing with black bar
    let useExtraAnimationForEnteringLegacyFullScreen = transition.isEnteringLegacyFullScreen && windowedModeScreen.hasCameraHousing && !transition.isInitialLayout && endingAnimationDuration > 0.0

    var fadeInNewViewsDuration = endingAnimationDuration * 0.5
    var openFinalPanelsDuration = endingAnimationDuration
    if useExtraAnimationForEnteringLegacyFullScreen {
      openFinalPanelsDuration *= 0.8
    } else if transition.isEnteringInteractiveMode {
      openFinalPanelsDuration *= 0.5
      fadeInNewViewsDuration *= 0.5
    } else {
      if !transition.needsFadeInNewViews {
        fadeInNewViewsDuration = 0
      }
      if !transition.needsAnimationForOpenFinalPanels {
        openFinalPanelsDuration = 0
      }
    }

    log.verbose("[\(transitionName)] Task durations: ShowOldFadeables=\(showFadeableViewsDuration), FadeOutOldViews:\(fadeOutOldViewsDuration), CloseOldPanels:\(closeOldPanelsDuration), FadeInNewViews:\(fadeInNewViewsDuration), OpenFinalPanels:\(openFinalPanelsDuration)")

    // - Starting animations:

    // 0: Set initial var or other tasks which happen before main animations
    transition.animationTasks.append(IINAAnimation.zeroDurationTask{ [self] in
      doPreTransitionWork(transition)
    })

    // StartingAnimation 1: Show fadeable views from current layout
    for fadeAnimation in buildAnimationToShowFadeableViews(restartFadeTimer: false, duration: showFadeableViewsDuration, forceShowTopBar: true) {
      transition.animationTasks.append(fadeAnimation)
    }

    // StartingAnimation 2: Fade out views which no longer will be shown but aren't enclosed in a panel.
    if transition.needsFadeOutOldViews {
      transition.animationTasks.append(IINAAnimation.Task(duration: fadeOutOldViewsDuration, { [self] in
        fadeOutOldViews(transition)
      }))
    }

    // StartingAnimation 3: Close/Minimize panels which are no longer needed. Applies middleGeometry if it exists.
    // Not enabled for fullScreen transitions.
    if transition.needsCloseOldPanels {
      transition.animationTasks.append(IINAAnimation.Task(duration: closeOldPanelsDuration, timing: panelTimingName, { [self] in
        closeOldPanels(transition)
      }))
    }

    // - Middle animations:

    // 0: Middle point: update style & constraints. Should have minimal visual changes
    transition.animationTasks.append(IINAAnimation.zeroDurationTask{ [self] in
      // This also can change window styleMask
      updateHiddenViewsAndConstraints(transition)
    })

    // Extra task when entering or exiting music mode: move & resize video frame
    if transition.isTogglingMusicMode && !transition.isInitialLayout && !transition.isTogglingFullScreen {
      transition.animationTasks.append(IINAAnimation.Task(duration: closeOldPanelsDuration, timing: .easeInEaseOut, { [self] in
        log.verbose("[\(transition.name)] Moving & resizing window")

        let intermediateGeo = transition.outputGeometry.clone(windowFrame: transition.outputGeometry.videoFrameInScreenCoords, topMarginHeight: 0,
                                                              outsideTopBarHeight: 0, outsideTrailingBarWidth: 0,
                                                              outsideBottomBarHeight: 0, outsideLeadingBarWidth: 0,
                                                              insideTopBarHeight: 0, insideTrailingBarWidth: 0,
                                                              insideBottomBarHeight: 0, insideLeadingBarWidth: 0)
        player.window.setFrameImmediately(intermediateGeo.windowFrame)
        videoView.apply(intermediateGeo)
        if transition.isEnteringMusicMode && !musicModeGeo.isVideoVisible {
          // Entering music mode when album art is hidden
          miniPlayer.applyVideoViewVisibilityConstraints(isVideoVisible: false)
        }
      }))
    }

    // - Ending animations:

    // EndingAnimation: Open new panels and fade in new views
    transition.animationTasks.append(IINAAnimation.Task(duration: openFinalPanelsDuration, timing: panelTimingName, { [self] in
      // If toggling fullscreen, this also changes the window frame:
      openNewPanelsAndFinalizeOffsets(transition)

      if transition.isTogglingFullScreen {
        // Full screen animations don't have much time. Combine fadeIn step in same animation:
        fadeInNewViews(transition)
      }
    }))

    // EndingAnimation: Fade in new views
    if !transition.isTogglingFullScreen && transition.needsFadeInNewViews {
      transition.animationTasks.append(IINAAnimation.Task(duration: fadeInNewViewsDuration, timing: panelTimingName, { [self] in
        fadeInNewViews(transition)
      }))
    }

    // If entering legacy full screen, will add an extra animation to hiding camera housing / menu bar / dock
    if useExtraAnimationForEnteringLegacyFullScreen {
      transition.animationTasks.append(IINAAnimation.Task(duration: endingAnimationDuration * 0.2, timing: .easeIn, { [self] in
        let topBlackBarHeight = Preference.bool(for: .allowVideoToOverlapCameraHousing) ? 0 : windowedModeScreen.cameraHousingHeight ?? 0
        let newGeo = transition.outputGeometry.clone(windowFrame: windowedModeScreen.frame, topMarginHeight: topBlackBarHeight)
        log.verbose("[\(transition.name)] Updating legacy FS window to cover camera housing / menu bar / dock")
        applyLegacyFullScreenGeometry(newGeo)
      }))
    }

    // After animations all finish
    transition.animationTasks.append(IINAAnimation.zeroDurationTask{ [self] in
      doPostTransitionWork(transition)
    })

    if thenRun {
      animationPipeline.submit(transition.animationTasks)
    }
    return transition
  }

  // MARK: - Geometry

  private func buildInputGeometry(from inputLayout: LayoutState, transitionName: String, windowedModeScreen: NSScreen) -> PWGeometry {
    // Restore window size & position
    switch inputLayout.mode {
    case .windowed:
      return windowedModeGeo.clone(windowFrame: window!.frame)
    case .fullScreen, .fullScreenInteractive:
      return inputLayout.buildFullScreenGeometry(inside: windowedModeScreen, videoAspect: player.info.videoAspect)
    case .windowedInteractive:
      if let interactiveModeGeo {
        return interactiveModeGeo.clone(windowFrame: window!.frame)
      } else {
        log.warn("[\(transitionName)] Failed to find interactiveModeGeo! Will change from windowedModeGeo (may be wrong)")
        return windowedModeGeo.clone(windowFrame: window!.frame).toInteractiveMode()
      }
    case .musicMode:
      /// `musicModeGeo` should have already been deserialized and set.
      /// But make sure we correct any size problems
      return musicModeGeo.clone(windowFrame: window!.frame).refit().toPWGeometry()
    }
  }

  /// Note that the result should not necessarily overrite `windowedModeGeo`. It is used by the transition animations.
  private func buildOutputGeometry(inputLayout: LayoutState, inputGeometry: PWGeometry, 
                                   outputLayout: LayoutState, isInitialLayout: Bool) -> PWGeometry {

    switch outputLayout.mode {
    case .musicMode:
      /// `videoAspect` may have gone stale while not in music mode. Update it (playlist height will be recalculated if needed):
      let musicModeGeoCorrected = musicModeGeo.clone(videoAspect: player.info.videoAspect).refit()
      return musicModeGeoCorrected.toPWGeometry()

    case .fullScreen, .fullScreenInteractive:
      // Full screen always uses same screen as windowed mode
      return outputLayout.buildFullScreenGeometry(inScreenID: inputGeometry.screenID, videoAspect: player.info.videoAspect)

    case .windowedInteractive:
      if let cachedInteractiveModeGeometry = interactiveModeGeo {
        log.verbose("Using cached interactiveModeGeo for outputGeo: \(cachedInteractiveModeGeometry)")
        return cachedInteractiveModeGeometry
      }
      let imGeo = windowedModeGeo.toInteractiveMode()
      log.verbose("Derived interactiveModeGeo from windowedModeGeo for outputGeo: \(imGeo)")
      return imGeo

    case .windowed:
      let prevWindowedGeo = windowedModeGeo
      let outputGeo = outputLayout.convertWindowedModeGeometry(from: prevWindowedGeo, videoAspect: inputGeometry.videoAspect)
      if isInitialLayout {
        return outputGeo
      }

      let ΔOutsideWidth = outputGeo.outsideBarsTotalWidth - prevWindowedGeo.outsideBarsTotalWidth
      let ΔOutsideHeight = outputGeo.outsideBarsTotalHeight - prevWindowedGeo.outsideBarsTotalHeight

      if let screenFrame = PWGeometry.getContainerFrame(forScreenID: prevWindowedGeo.screenID, fitOption: prevWindowedGeo.fitOption) {
        // If window already fills screen width, do not shrink window width when collapsing outside sidebars.
        // So it will seem to "stick" to the screen edges when filling the screen but if already smaller, will allow the window to shrink.
        // This should be more intuitive to the user than trying to keep track of the user's past intent.
        if ΔOutsideWidth != 0, prevWindowedGeo.windowFrame.width == screenFrame.width {
          let newViewportWidth = screenFrame.width - outputGeo.outsideBarsTotalWidth
          let widthRatio = newViewportWidth / prevWindowedGeo.viewportSize.width
          let heightFillsScreen = prevWindowedGeo.windowFrame.height == screenFrame.height
          let newViewportHeight = heightFillsScreen ? prevWindowedGeo.viewportSize.height : round(prevWindowedGeo.viewportSize.height * widthRatio)
          let resizedViewport = NSSize(width: newViewportWidth, height: newViewportHeight)
          let resizedGeo = outputGeo.scaleViewport(to: resizedViewport, mode: outputLayout.mode)
          /// Kludge to fix unwanted window movement when opening/closing sidebars and `Preference.moveWindowIntoVisibleScreenOnResize` is false.
          /// 1 of 2 - See below
          if resizedGeo.fitOption.shouldMoveWindowToKeepInContainer {
            // Window origin was changed to keep it on screen. OK to use this
            return resizedGeo
          } else {
            // Use previous origin, because scaleViewport() causes it to move when we don't want it to
            return resizedGeo.clone(windowFrame: prevWindowedGeo.windowFrame.clone(size: resizedGeo.windowFrame.size))
          }
        }

        // If window already fills screen height, keep window height (do not shrink window) when collapsing outside bars.
        if ΔOutsideHeight != 0, prevWindowedGeo.windowFrame.height == screenFrame.height {
          let newViewportHeight = screenFrame.height - outputGeo.outsideBarsTotalHeight
          let heightRatio = newViewportHeight / prevWindowedGeo.viewportSize.height
          let widthFillsScreen = prevWindowedGeo.windowFrame.width == screenFrame.width
          let newViewportWidth = widthFillsScreen ? prevWindowedGeo.viewportSize.width : round(prevWindowedGeo.viewportSize.width * heightRatio)
          let resizedViewport = NSSize(width: newViewportWidth, height: newViewportHeight)
          let resizedGeo = outputGeo.scaleViewport(to: resizedViewport, mode: outputLayout.mode)
          /// Kludge to fix unwanted window movement when opening/closing sidebars and `Preference.moveWindowIntoVisibleScreenOnResize` is false.
          /// 2 of 2
          if resizedGeo.fitOption.shouldMoveWindowToKeepInContainer {
            // Window origin was changed to keep it on screen. OK to use this
            return resizedGeo
          } else {
            return resizedGeo.clone(windowFrame: prevWindowedGeo.windowFrame.clone(size: resizedGeo.windowFrame.size))
          }
        }
      }

      return outputGeo
    }
  }

  // Currently there are 4 bars. Each can be either inside or outside, exclusively.
  func buildMiddleGeometry(forTransition transition: LayoutTransition) -> PWGeometry? {
    if transition.isEnteringMusicMode {
      let middleWindowFrame: NSRect
      if transition.inputLayout.isFullScreen {
        // Need middle geo so that sidebars get closed
        middleWindowFrame = windowedModeGeo.videoFrameInScreenCoords
      } else {
        middleWindowFrame = transition.inputGeometry.videoFrameInScreenCoords
      }

      return PWGeometry(windowFrame: middleWindowFrame, screenID: transition.inputGeometry.screenID,
                             fitOption: transition.inputGeometry.fitOption, mode: .musicMode, topMarginHeight: 0,
                             outsideTopBarHeight: 0, outsideTrailingBarWidth: 0, outsideBottomBarHeight: 0, outsideLeadingBarWidth: 0,
                             insideTopBarHeight: 0, insideTrailingBarWidth: 0, insideBottomBarHeight: 0, insideLeadingBarWidth: 0,
                             videoAspect: transition.inputGeometry.videoAspect)
    } else if transition.isExitingMusicMode {
      // Only bottom bar needs to be closed. No need to constrain in screen
      return transition.inputGeometry.withResizedOutsideBars(newOutsideBottomBarHeight: 0)
    } else if transition.isTogglingInteractiveMode {
      if transition.inputLayout.isFullScreen {
        // Need to hide sidebars when entering interactive mode in full screen
        return transition.outputGeometry
      }

      let outsideTopBarHeight = transition.inputLayout.outsideTopBarHeight >= transition.outputLayout.topBarHeight ? transition.outputLayout.outsideTopBarHeight : 0
      let resizedGeo = transition.inputGeometry.withResizedBars(mode: transition.inputLayout.mode,
                                                                outsideTopBarHeight: outsideTopBarHeight, outsideTrailingBarWidth: 0,
                                                                outsideBottomBarHeight: 0, outsideLeadingBarWidth: 0,
                                                                insideTopBarHeight: 0, insideTrailingBarWidth: 0,
                                                                insideBottomBarHeight: 0, insideLeadingBarWidth: 0)
      if transition.isEnteringInteractiveMode {
        return resizedGeo.scaleViewport(to: resizedGeo.videoSize)
      } else if transition.isExitingInteractiveMode {
        return resizedGeo
      }
    }

    // TOP
    let topBarHeight: CGFloat
    if !transition.isInitialLayout && transition.isTopBarPlacementChanging {
      topBarHeight = 0  // close completely. will animate reopening if needed later
    } else if transition.outputLayout.topBarHeight < transition.inputLayout.topBarHeight {
      topBarHeight = transition.outputLayout.topBarHeight
    } else {
      topBarHeight = transition.inputLayout.topBarHeight  // leave the same
    }
    let insideTopBarHeight = transition.outputLayout.topBarPlacement == .insideViewport ? topBarHeight : 0
    let outsideTopBarHeight = transition.outputLayout.topBarPlacement == .outsideViewport ? topBarHeight : 0

    // BOTTOM
    let insideBottomBarHeight: CGFloat
    let outsideBottomBarHeight: CGFloat
    if !transition.isInitialLayout && transition.isBottomBarPlacementChanging || transition.isTogglingMusicMode {
      // close completely. will animate reopening if needed later
      insideBottomBarHeight = 0
      outsideBottomBarHeight = 0
    } else if transition.outputGeometry.outsideBottomBarHeight < transition.inputGeometry.outsideBottomBarHeight {
      insideBottomBarHeight = 0
      outsideBottomBarHeight = transition.outputGeometry.outsideBottomBarHeight
    } else if transition.outputGeometry.insideBottomBarHeight < transition.inputGeometry.insideBottomBarHeight {
      insideBottomBarHeight = transition.outputGeometry.insideBottomBarHeight
      outsideBottomBarHeight = 0
    } else {
      insideBottomBarHeight = transition.inputGeometry.insideBottomBarHeight
      outsideBottomBarHeight = transition.inputGeometry.outsideBottomBarHeight
    }

    // LEADING
    let insideLeadingBarWidth: CGFloat
    let outsideLeadingBarWidth: CGFloat
    if transition.isHidingLeadingSidebar {
      insideLeadingBarWidth = 0
      outsideLeadingBarWidth = 0
    } else {
      insideLeadingBarWidth = transition.inputGeometry.insideLeadingBarWidth
      outsideLeadingBarWidth = transition.inputGeometry.outsideLeadingBarWidth
    }

    // TRAILING
    let insideTrailingBarWidth: CGFloat
    let outsideTrailingBarWidth: CGFloat
    if transition.isHidingTrailingSidebar {
      insideTrailingBarWidth = 0
      outsideTrailingBarWidth = 0
    } else {
      insideTrailingBarWidth = transition.inputGeometry.insideTrailingBarWidth
      outsideTrailingBarWidth = transition.inputGeometry.outsideTrailingBarWidth
    }

    if transition.outputLayout.isFullScreen {
      let screen = NSScreen.getScreenOrDefault(screenID: transition.inputGeometry.screenID)
      return PWGeometry.forFullScreen(in: screen, legacy: transition.outputLayout.isLegacyFullScreen,
                                           mode: transition.outputLayout.mode,
                                           outsideTopBarHeight: outsideTopBarHeight,
                                           outsideTrailingBarWidth: outsideTrailingBarWidth,
                                           outsideBottomBarHeight: outsideBottomBarHeight,
                                           outsideLeadingBarWidth: outsideLeadingBarWidth,
                                           insideTopBarHeight: insideTopBarHeight,
                                           insideTrailingBarWidth: insideTrailingBarWidth,
                                           insideBottomBarHeight: insideBottomBarHeight,
                                           insideLeadingBarWidth: insideLeadingBarWidth,
                                           videoAspect: transition.outputGeometry.videoAspect,
                                           allowVideoToOverlapCameraHousing: transition.outputLayout.hasTopPaddingForCameraHousing)
    }

    return transition.outputGeometry.withResizedBars(outsideTopBarHeight: outsideTopBarHeight,
                                                     outsideTrailingBarWidth: outsideTrailingBarWidth,
                                                     outsideBottomBarHeight: outsideBottomBarHeight,
                                                     outsideLeadingBarWidth: outsideLeadingBarWidth,
                                                     insideTopBarHeight: insideTopBarHeight,
                                                     insideTrailingBarWidth: insideTrailingBarWidth,
                                                     insideBottomBarHeight: insideBottomBarHeight,
                                                     insideLeadingBarWidth: insideLeadingBarWidth)
  }
}
