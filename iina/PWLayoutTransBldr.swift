//
//  PWLayoutTransitionBuilder.swift
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
                             thenRun: Bool = false,
                             _ geo: GeometrySet? = nil) -> LayoutTransition {

    // use latest window frame in case it exists and was moved
    let geo = geo ?? self.buildGeoSet(from: inputLayout)

    var transitionID: Int = 0
    $layoutTransitionCounter.withLock {
      $0 += 1
      transitionID = $0
    }
    let transitionName = "\(transitionName)-\(transitionID)"

    // This also applies to full screen, because full screen always uses the same screen as windowed.
    // Does not apply to music mode, which can be a different screen.
    let windowedModeScreen = NSScreen.getScreenOrDefault(screenID: geo.windowed.screenID)

    // Compile outputLayout
    let outputLayout = LayoutState.buildFrom(outputSpec)

    // - Build GeometrySet

    // InputGeometry
    let inputGeometry: PWinGeometry = buildInputGeometry(from: inputLayout, transitionName: transitionName, geo, windowedModeScreen: windowedModeScreen)
    log.verbose("[\(transitionName)] InputGeometry: \(inputGeometry)")

    // OutputGeometry
    let outputGeometry: PWinGeometry = buildOutputGeometry(inputLayout: inputLayout, inputGeometry: inputGeometry,
                                                         outputLayout: outputLayout, geo, isInitialLayout: isInitialLayout)

    let transition = LayoutTransition(name: transitionName,
                                      from: inputLayout, from: inputGeometry,
                                      to: outputLayout, to: outputGeometry,
                                      isInitialLayout: isInitialLayout)

    // MiddleGeometry if needed (is applied after ClosePanels step)
    transition.middleGeometry = buildMiddleGeometry(forTransition: transition, geo)
    if let middleGeometry = transition.middleGeometry {
      log.verbose("[\(transitionName)] MiddleGeometry: \(middleGeometry)")
    } else {
      log.verbose("[\(transitionName)] MiddleGeometry: nil")
    }

    log.verbose("[\(transitionName)] OutputGeometry: \(outputGeometry)")

    let closeOldPanelsTiming: CAMediaTimingFunctionName
    let openFinalPanelsTiming: CAMediaTimingFunctionName
    let fadeInNewViewsTiming: CAMediaTimingFunctionName = .linear
    if transition.isTogglingFullScreen {
      closeOldPanelsTiming = .easeOut
      openFinalPanelsTiming = .easeOut
    } else if transition.isTogglingVisibilityOfAnySidebar {
      closeOldPanelsTiming = .easeIn
      openFinalPanelsTiming = .easeIn
    } else if transition.isExitingInteractiveMode {
      closeOldPanelsTiming = .easeOut
      openFinalPanelsTiming = .linear
    } else {
      closeOldPanelsTiming = .linear
      openFinalPanelsTiming = .linear
    }

    // - Determine durations

    var startingAnimationDuration = IINAAnimation.DefaultDuration
    if transition.isEnteringFullScreen {
      startingAnimationDuration = 0
    } else if transition.isEnteringMusicMode && !transition.isExitingFullScreen {
      startingAnimationDuration = IINAAnimation.DefaultDuration
    } else if let totalStartingDuration = totalStartingDuration {
      startingAnimationDuration = totalStartingDuration / 3
    }

    var showFadeableViewsDuration: CGFloat = startingAnimationDuration
    var fadeOutOldViewsDuration: CGFloat = startingAnimationDuration
    var closeOldPanelsDuration: CGFloat = startingAnimationDuration
    if transition.isEnteringMusicMode && !transition.isExitingFullScreen {
      showFadeableViewsDuration = startingAnimationDuration * 0.5
      fadeOutOldViewsDuration = startingAnimationDuration * 0.5
    } else if transition.isEnteringInteractiveMode {
      showFadeableViewsDuration = startingAnimationDuration * 0.25
      fadeOutOldViewsDuration = startingAnimationDuration * 0.5
    } else if transition.isExitingInteractiveMode {
      showFadeableViewsDuration = 0
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
    let useExtraAnimationForEnteringLegacyFullScreen = transition.isEnteringLegacyFullScreen && windowedModeScreen.hasCameraHousing && !transition.isInitialLayout

    // Extra animation when exiting legacy full screen: remove camera housing with black bar
    let useExtraAnimationForExitingLegacyFullScreen = transition.isExitingLegacyFullScreen && windowedModeScreen.hasCameraHousing && !transition.isInitialLayout

    var fadeInNewViewsDuration = endingAnimationDuration * 0.5
    var openFinalPanelsDuration = endingAnimationDuration
    if useExtraAnimationForEnteringLegacyFullScreen || useExtraAnimationForEnteringLegacyFullScreen {
      let frameWithoutCameraRatio = windowedModeScreen.frameWithoutCameraHousing.size.height / windowedModeScreen.frame.height
      openFinalPanelsDuration *= frameWithoutCameraRatio
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
    transition.tasks.append(IINAAnimation.suddenTask{ [self] in
      doPreTransitionWork(transition)
    })

    // StartingAnimation 1: Show fadeable views from current layout
    for fadeAnimation in buildAnimationToShowFadeableViews(restartFadeTimer: false, duration: showFadeableViewsDuration, forceShowTopBar: true) {
      transition.tasks.append(fadeAnimation)
    }

    // StartingAnimation 2: Fade out views which no longer will be shown but aren't enclosed in a panel.
    if transition.needsFadeOutOldViews {
      transition.tasks.append(IINAAnimation.Task(duration: fadeOutOldViewsDuration, { [self] in
        fadeOutOldViews(transition)
      }))
    }

    // StartingAnimation 3: Close/Minimize panels which are no longer needed. Applies middleGeometry if it exists.
    // Not enabled for fullScreen transitions.
    if transition.needsCloseOldPanels {
      transition.tasks.append(IINAAnimation.Task(duration: closeOldPanelsDuration, timing: closeOldPanelsTiming, { [self] in
        closeOldPanels(transition)
      }))
    }

    // - Middle animations:

    // 0: Middle point: update style & constraints. Should have minimal visual changes
    transition.tasks.append(IINAAnimation.suddenTask{ [self] in
      // This also can change window styleMask
      updateHiddenViewsAndConstraints(transition)
    })

    // Extra task when entering or exiting music mode: move & resize video frame
    if transition.isTogglingMusicMode && !transition.isInitialLayout {
      transition.tasks.append(IINAAnimation.Task(duration: closeOldPanelsDuration, timing: .easeInEaseOut, { [self] in
        log.verbose("[\(transition.name)] Moving & resizing window")

        let intermediateGeo = transition.outputGeometry.clone(windowFrame: transition.outputGeometry.videoFrameInScreenCoords,
                                                              topMarginHeight: 0,
                                                              outsideBars: MarginQuad.zero, insideBars: MarginQuad.zero)
        player.window.setFrameImmediately(intermediateGeo)
        if transition.isEnteringMusicMode && !musicModeGeo.isVideoVisible {
          // Entering music mode when album art is hidden
          miniPlayer.updateVideoViewVisibilityConstraints(isVideoVisible: false)
        }
      }))
    }

    // - Ending animations:

    // Extra animation for exiting legacy full screen (to Native Windowed Mode)
    if useExtraAnimationForExitingLegacyFullScreen {
      let cameraToTotalFrameRatio = 1 - (windowedModeScreen.frameWithoutCameraHousing.size.height / windowedModeScreen.frame.height)
      let duration = endingAnimationDuration * cameraToTotalFrameRatio

      transition.tasks.append(IINAAnimation.Task(duration: duration, timing: .easeIn, { [self] in
        let newGeo: PWinGeometry
        if transition.inputGeometry.hasTopPaddingForCameraHousing {
          /// Entering legacy FS on a screen with camera housing, but `Use entire Macbook screen` is unchecked in Settings.
          /// Prevent an unwanted bouncing near the top by using this animation to expand to visibleFrame.
          /// (will expand window to cover `cameraHousingHeight` in next animation)
          newGeo = transition.inputGeometry.clone(windowFrame: windowedModeScreen.frameWithoutCameraHousing,
                                                  screenID: windowedModeScreen.screenID, topMarginHeight: 0)
        } else {
          /// `Use entire Macbook screen` is checked in Settings. As of MacOS before Sonoma 14.4, Apple has been making improvements
          /// but we still need to use  a separate animation to give the OS time to hide the menu bar - otherwise there will be a flicker.
          let cameraHeight = windowedModeScreen.cameraHousingHeight ?? 0
          let geo = transition.inputGeometry
          let margins = geo.viewportMargins.addingTo(top: -cameraHeight)
          newGeo = geo.clone(windowFrame: geo.windowFrame.addingTo(top: -cameraHeight), viewportMargins: margins)
        }
        log.verbose("[\(transition.name)] Updating legacy FS window to show camera housing prior to entering native windowed mode with windowFrame=\(newGeo.windowFrame)")
        applyLegacyFSGeo(newGeo)
      }))
    }

    // EndingAnimation: Open new panels and fade in new views
    transition.tasks.append(IINAAnimation.Task(duration: openFinalPanelsDuration, timing: openFinalPanelsTiming, { [self] in
      // If toggling fullscreen, this also changes the window frame:
      openNewPanelsAndFinalizeOffsets(transition)
    }))

    // EndingAnimation: Fade in new views
    if transition.needsFadeInNewViews {
      transition.tasks.append(IINAAnimation.Task(duration: fadeInNewViewsDuration, timing: fadeInNewViewsTiming, { [self] in
        fadeInNewViews(transition)
      }))
    }

    // If entering legacy full screen, will add an extra animation to hiding camera housing / menu bar / dock
    if useExtraAnimationForEnteringLegacyFullScreen {
      let cameraToTotalFrameRatio = 1 - (windowedModeScreen.frameWithoutCameraHousing.size.height / windowedModeScreen.frame.height)
      let duration = endingAnimationDuration * cameraToTotalFrameRatio
      transition.tasks.append(IINAAnimation.Task(duration: duration, timing: .easeIn, { [self] in
        let topBlackBarHeight = Preference.bool(for: .allowVideoToOverlapCameraHousing) ? 0 : windowedModeScreen.cameraHousingHeight ?? 0
        let newGeo = transition.outputGeometry.clone(windowFrame: windowedModeScreen.frame, 
                                                     screenID: windowedModeScreen.screenID, topMarginHeight: topBlackBarHeight)
        log.verbose("[\(transition.name)] Updating legacy FS window to cover camera housing / menu bar / dock with windowFrame=\(newGeo.windowFrame)")
        applyLegacyFSGeo(newGeo)
      }))
    }

    // After animations all finish
    transition.tasks.append(IINAAnimation.suddenTask{ [self] in
      if transition.isTogglingFullScreen {
        // For a better visual experience wait until window finishes moving
        fadeInNewViews(transition)
      }
      doPostTransitionWork(transition)
    })

    if thenRun {
      animationPipeline.submit(transition.tasks)
    }
    return transition
  }

  // MARK: - Geometry

  /// Builds `inputGeometry`.
  private func buildInputGeometry(from inputLayout: LayoutState, transitionName: String, _ geo: GeometrySet, 
                                  windowedModeScreen: NSScreen) -> PWinGeometry {
    // Restore window size & position
    switch inputLayout.mode {
    case .windowed:
      return geo.windowed
    case .fullScreen, .fullScreenInteractive:
      return inputLayout.buildFullScreenGeometry(in: windowedModeScreen, video: geo.video)
    case .windowedInteractive:
      /// `geo.windowed` should already be correct for interactiveWindowed mode, but it is easy enough to derive it
      /// from a small number of variables, and safer to do that than assume it is correct:
      return PWinGeometry.buildInteractiveModeWindow(windowFrame: geo.windowed.windowFrame, screenID: geo.windowed.screenID,
                                                     video: geo.windowed.video)
    case .musicMode:
      /// `musicModeGeo` should have already been deserialized and set.
      /// But make sure we correct any size problems
      return geo.musicMode.refit().toPWinGeometry()
    }
  }

  /// Builds `outputGeometry`.
  /// Note that the result should not necessarily overrite `windowedModeGeo`. It is used by the transition animations.
  private func buildOutputGeometry(inputLayout: LayoutState, inputGeometry: PWinGeometry, 
                                   outputLayout: LayoutState, _ geo: GeometrySet, isInitialLayout: Bool) -> PWinGeometry {

    switch outputLayout.mode {
    case .windowed:
      let prevWindowedGeo: PWinGeometry
      if inputGeometry.mode == .windowedInteractive {
        /// `windowedInteractive` -> `windowed`
        log.verbose("Exiting interactive mode: converting windowedInteractive geo to windowed for outputGeo")
        prevWindowedGeo = inputGeometry.fromWindowedInteractiveMode()
      } else if geo.windowed.mode == .windowedInteractive {
        prevWindowedGeo = geo.windowed.fromWindowedInteractiveMode()
      } else {
        prevWindowedGeo = geo.windowed
      }
      return outputLayout.convertWindowedModeGeometry(from: prevWindowedGeo, video: inputGeometry.video,
                                                      keepFullScreenDimensions: !isInitialLayout)

    case .windowedInteractive:
      if inputGeometry.mode == .windowedInteractive {
        log.verbose("Already in interactive mode: converting windowed geo to interactiveWindowed for outputGeo")
        return PWinGeometry.buildInteractiveModeWindow(windowFrame: geo.windowed.windowFrame, screenID: geo.windowed.screenID,
                                                       video: geo.windowed.video)
      } else if inputGeometry.mode == .fullScreenInteractive {
        if geo.windowed.mode == .windowedInteractive {
          return PWinGeometry.buildInteractiveModeWindow(windowFrame: geo.windowed.windowFrame, screenID: geo.windowed.screenID,
                                                         video: inputGeometry.video)
        }
        return geo.windowed.clone(video: inputGeometry.video).toInteractiveMode()
      }
      /// Entering interactive mode: convert from `windowed` to `windowedInteractive`
      return inputGeometry.toInteractiveMode()

    case .fullScreen, .fullScreenInteractive:
      // Full screen always uses same screen as windowed mode
      return outputLayout.buildFullScreenGeometry(inScreenID: inputGeometry.screenID, video: geo.video)

    case .musicMode:
      /// `videoAspect` may have gone stale while not in music mode. Update it (playlist height will be recalculated if needed):
      let musicModeGeoCorrected = geo.musicMode.clone(video: geo.video).refit()
      return musicModeGeoCorrected.toPWinGeometry()

    }
  }

  /// Builds `middleGeometry`.
  // Currently there are 4 bars. Each can be either inside or outside, exclusively.
  func buildMiddleGeometry(forTransition transition: LayoutTransition, _ geo: GeometrySet) -> PWinGeometry? {
    if transition.isTogglingInteractiveMode {
      if transition.inputLayout.isFullScreen {
        // Need to hide sidebars when entering interactive mode in full screen
        return transition.outputGeometry
      }

      let outsideTopBarHeight = transition.inputLayout.outsideTopBarHeight >= transition.outputLayout.topBarHeight ? transition.outputLayout.outsideTopBarHeight : 0

      if transition.isEnteringInteractiveMode {
        return transition.outputGeometry.withResizedBars(outsideTop: 0, outsideTrailing: 0,
                                                         outsideBottom: 0, outsideLeading: 0,
                                                         insideTop: 0, insideTrailing: 0,
                                                         insideBottom: 0, insideLeading: 0,
                                                         keepFullScreenDimensions: !(Preference.bool(for: .lockViewportToVideoSize)))

      } else if transition.isExitingInteractiveMode {
        let videoFrame = transition.outputGeometry.videoFrameInScreenCoords
        let extraWidthNeeded = max(0, Constants.InteractiveMode.minWindowWidth - videoFrame.width)
        let newWindowFrame = NSRect(origin: NSPoint(x: videoFrame.origin.x - (extraWidthNeeded * 0.5), y: videoFrame.origin.y),
                                    size: CGSize(width: videoFrame.width + extraWidthNeeded, height: videoFrame.height + outsideTopBarHeight))
        let resizedGeo = PWinGeometry(windowFrame: newWindowFrame, screenID: transition.outputGeometry.screenID,
                                      fitOption: transition.outputGeometry.fitOption, mode: .windowed, topMarginHeight: 0,
                                      outsideBars: MarginQuad(top: outsideTopBarHeight),
                                      insideBars: MarginQuad.zero,
                                      video: transition.outputGeometry.video)
        return resizedGeo
      }

    } else if transition.isEnteringMusicMode {
      let baseGeo: PWinGeometry
      if transition.inputLayout.isFullScreen {
        // Need middle geo so that sidebars get closed
        baseGeo = geo.musicMode.clone(video: geo.video, isPlaylistVisible: false).toPWinGeometry()
      } else {
        baseGeo = transition.inputGeometry
      }

      let middleWindowFrame = baseGeo.videoFrameInScreenCoords
      return PWinGeometry(windowFrame: middleWindowFrame, screenID: baseGeo.screenID,
                          fitOption: baseGeo.fitOption, mode: .musicMode, topMarginHeight: 0,
                          outsideBars: MarginQuad.zero, insideBars: MarginQuad.zero,
                          video: baseGeo.video)
    } else if transition.isExitingMusicMode {
      if transition.isEnteringFullScreen {
        return nil
      }
      // Only bottom bar needs to be closed. No need to constrain in screen
      return transition.inputGeometry.withResizedOutsideBars(bottom: 0)
    }

    // TOP
    let insideTopBarHeight: CGFloat
    let outsideTopBarHeight: CGFloat
    if !transition.isInitialLayout && transition.isTopBarPlacementChanging {
      insideTopBarHeight = 0  // close completely. will animate reopening if needed later
      outsideTopBarHeight = 0
    } else if transition.outputLayout.topBarHeight < transition.inputLayout.topBarHeight {
      insideTopBarHeight = 0
      outsideTopBarHeight = transition.outputLayout.topBarHeight
    } else {
      insideTopBarHeight = transition.inputLayout.insideTopBarHeight  // leave the same
      outsideTopBarHeight = transition.inputLayout.outsideTopBarHeight
    }

    // BOTTOM
    let insideBottomBarHeight: CGFloat
    let outsideBottomBarHeight: CGFloat
    if !transition.isInitialLayout && transition.isBottomBarPlacementChanging || transition.isTogglingMusicMode {
      // close completely. will animate reopening if needed later
      insideBottomBarHeight = 0
      outsideBottomBarHeight = 0
    } else if transition.outputGeometry.outsideBars.bottom < transition.inputGeometry.outsideBars.bottom {
      insideBottomBarHeight = 0
      outsideBottomBarHeight = transition.outputGeometry.outsideBars.bottom
    } else if transition.outputGeometry.insideBars.bottom < transition.inputGeometry.insideBars.bottom {
      insideBottomBarHeight = transition.outputGeometry.insideBars.bottom
      outsideBottomBarHeight = 0
    } else {
      insideBottomBarHeight = transition.inputGeometry.insideBars.bottom
      outsideBottomBarHeight = transition.inputGeometry.outsideBars.bottom
    }

    // LEADING
    let insideLeadingBarWidth: CGFloat
    let outsideLeadingBarWidth: CGFloat
    if transition.isHidingLeadingSidebar {
      insideLeadingBarWidth = 0
      outsideLeadingBarWidth = 0
    } else {
      insideLeadingBarWidth = transition.inputGeometry.insideBars.leading
      outsideLeadingBarWidth = transition.inputGeometry.outsideBars.leading
    }

    // TRAILING
    let insideTrailingBarWidth: CGFloat
    let outsideTrailingBarWidth: CGFloat
    if transition.isHidingTrailingSidebar {
      insideTrailingBarWidth = 0
      outsideTrailingBarWidth = 0
    } else {
      insideTrailingBarWidth = transition.inputGeometry.insideBars.trailing
      outsideTrailingBarWidth = transition.inputGeometry.outsideBars.trailing
    }

    if transition.outputLayout.isFullScreen {
      let screen = NSScreen.getScreenOrDefault(screenID: transition.inputGeometry.screenID)
      return PWinGeometry.forFullScreen(in: screen, legacy: transition.outputLayout.isLegacyFullScreen,
                                        mode: transition.outputLayout.mode,
                                        outsideBars: MarginQuad(top: outsideTopBarHeight, trailing: outsideTrailingBarWidth,
                                                                bottom: outsideBottomBarHeight, leading: outsideLeadingBarWidth),
                                        insideBars: MarginQuad(top: insideTopBarHeight, trailing: insideTrailingBarWidth,
                                                                bottom: insideBottomBarHeight, leading: insideLeadingBarWidth),
                                        video: transition.outputGeometry.video,
                                        allowVideoToOverlapCameraHousing: transition.outputLayout.hasTopPaddingForCameraHousing)
    }

    let resizedBarsGeo = transition.outputGeometry.withResizedBars(outsideTop: outsideTopBarHeight,
                                                                   outsideTrailing: outsideTrailingBarWidth,
                                                                   outsideBottom: outsideBottomBarHeight,
                                                                   outsideLeading: outsideLeadingBarWidth,
                                                                   insideTop: insideTopBarHeight,
                                                                   insideTrailing: insideTrailingBarWidth,
                                                                   insideBottom: insideBottomBarHeight,
                                                                   insideLeading: insideLeadingBarWidth,
                                                                   keepFullScreenDimensions: true)
    return resizedBarsGeo.refit()
  }

}
