//
//  PWInitialLayoutBldr.swift
//  iina
//
//  Created by Matt Svoboda on 2024/08/05
//

import Foundation

/// Window Initial Layout
extension PlayerWindowController {

  /// Builds tasks to transition the window to its "initial" layout.
  ///
  /// Sets the window layout when one of the following is happening:
  /// 1. Opening window for new file
  /// 2. Reusing existing window for new file
  /// 3. Restoring from prior launch.
  ///
  /// See `PWinSessionState`.
  func buildWindowInitialLayoutTasks(_ cxt: GeometryTransform.Context,
                                     newVidGeo: VideoGeometry) -> (LayoutState, [IINAAnimation.Task]) {
    assert(DispatchQueue.isExecutingIn(.main))

    let newSessionState = cxt.sessionState
    let currentMediaAudioStatus = cxt.currentMediaAudioStatus

    guard newSessionState.isStartingSession, let window = window else {
      return (currentLayout, [])
    }

    var needsNativeFullScreen = false
    var tasks: [IINAAnimation.Task]
    let initialLayout: LayoutState

    switch newSessionState {
    case .restoring(let priorState):
      if let priorLayoutSpec = priorState.layoutSpec {
        log.verbose("[applyVideoGeo \(cxt.name)] Transitioning to initial layout from prior window state")

        let initialLayoutSpec: LayoutSpec
        if priorLayoutSpec.isNativeFullScreen {
          // Special handling for native fullscreen. Rely on mpv to put us in FS when it is ready
          initialLayoutSpec = priorLayoutSpec.clone(mode: .windowedNormal)
          needsNativeFullScreen = true
        } else {
          initialLayoutSpec = priorLayoutSpec
        }
        initialLayout = LayoutState.buildFrom(initialLayoutSpec)
      } else {
        log.error("[applyVideoGeo \(cxt.name)] Failed to read LayoutSpec object for restore! Will try to assemble window from prefs instead")
        let layoutSpecFromPrefs = LayoutSpec.fromPreferences(andMode: .windowedNormal, fillingInFrom: lastWindowedLayoutSpec)
        initialLayout = LayoutState.buildFrom(layoutSpecFromPrefs)
      }

      let newGeoSet = configureFromRestore(priorState, initialLayout)
      tasks = buildTransitionTasks(from: currentLayout, to: initialLayout, newGeoSet,
                                   isRestoringFromPrevLaunch: true,
                                   needsNativeFullScreen: needsNativeFullScreen)

    case .newReplacingExisting:
      initialLayout = currentLayout
      log.verbose("[applyVideoGeo \(cxt.name)] Opening a new file in an already open window, mode=\(initialLayout.mode)")

      /// `windowFrame` may be slightly off; update it
      if initialLayout.mode == .windowedNormal {
        /// Set this so that `applyVideoGeoTransform` will use the correct default window frame if it looks for it.
        /// Side effect: future opened windows may use this size even if this window wasn't closed. Should be ok?
        PlayerWindowController.windowedModeGeoLastClosed = initialLayout.buildGeometry(windowFrame: window.frame,
                                                                                       screenID: bestScreen.screenID,
                                                                                       video: newVidGeo)
      } else if initialLayout.mode == .musicMode {
        /// Set this so that `applyVideoGeoTransform` will use the correct default window frame if it looks for it.
        PlayerWindowController.musicModeGeoLastClosed = musicModeGeo.clone(windowFrame: window.frame,
                                                                           screenID: bestScreen.screenID,
                                                                           video: newVidGeo)
      }
      // No additional layout needed
      tasks = []

    case .creatingNew:
      log.verbose("[applyVideoGeo \(cxt.name)] Transitioning to initial layout from app prefs")
      var mode: PlayerWindowMode = .windowedNormal

      if Preference.bool(for: .autoSwitchToMusicMode) && currentMediaAudioStatus.isAudio {
        log.debug("[applyVideoGeo \(cxt.name)] Opened media is audio: will auto-switch to music mode")
        mode = .musicMode
      } else if Preference.bool(for: .fullScreenWhenOpen) {
        player.didEnterFullScreenViaUserToggle = false
        let useLegacyFS = Preference.bool(for: .useLegacyFullScreen)
        log.debug("[applyVideoGeo \(cxt.name)] Changing to \(useLegacyFS ? "legacy " : "")fullscreen because \(Preference.Key.fullScreenWhenOpen.rawValue)==Y")
        if useLegacyFS {
          mode = .fullScreenNormal
        } else {
          needsNativeFullScreen = true
        }
      }

      // Set to default layout, but use existing aspect ratio & video size for now, because we don't have that info yet for the new video
      let layoutSpecFromPrefs = LayoutSpec.fromPreferences(andMode: mode, fillingInFrom: lastWindowedLayoutSpec)
      initialLayout = LayoutState.buildFrom(layoutSpecFromPrefs)
      let newGeoSet = configureFromPrefs(initialLayout, newVidGeo)

      tasks = buildTransitionTasks(from: currentLayout, to: initialLayout, newGeoSet, isRestoringFromPrevLaunch: false,
                                   needsNativeFullScreen: needsNativeFullScreen)
    default:
      Logger.fatal("Invalid PWinSessionState for initial layout: \(newSessionState)")
    }

    tasks.append(.instantTask{ [self] in
      defer {
        /// This will fire a notification to `AppDelegate` which will respond by calling `showWindow` when all windows are ready. Post this always.
        log.verbose("Posting windowIsReadyToShow")
        postWindowIsReadyToShow()
      }

      player.refreshSyncUITimer()
      player.touchBarSupport.setupTouchBarUI()

      let shouldDecideDefaultArtStatus = !currentLayout.isMusicMode || (musicModeGeo.isVideoVisible)
      let showDefaultArt: Bool? = shouldDecideDefaultArtStatus ? player.info.shouldShowDefaultArt : nil
      if let showDefaultArt {
        // May need to set this while restoring a network audio stream
        updateDefaultArtVisibility(to: showDefaultArt)
      }

      /// This check is after `reloadSelectedTracks` which will ensure that `info.aid` will have been updated with the
      /// current audio track selection, or `0` if none selected.
      /// Before `fileLoaded` it may change to `0` while the track info is still being processed, but this is unhelpful
      /// because it can mislead us into thinking that the user has deselected the audio track.
      if player.info.aid == 0 {
        muteButton.isEnabled = false
        volumeSlider.isEnabled = false
      }

      hideSeekPreviewImmediately()
      quickSettingView.reload()
      updateTitle()
      playlistView.scrollPlaylistToCurrentItem()

      // FIXME: here be race conditions
      if case .newReplacingExisting = sessionState {
        // Need to switch to music mode?
        if Preference.bool(for: .autoSwitchToMusicMode) {
          if player.overrideAutoMusicMode {
            log.verbose("[applyVideoGeo \(cxt.name)] Skipping music mode auto-switch ∴ overrideAutoMusicMode=Y")
          } else if currentMediaAudioStatus.isAudio && !isInMiniPlayer && !isFullScreen {
            log.debug("[applyVideoGeo \(cxt.name)] Opened media is audio: auto-switching to music mode")
            player.enterMusicMode(automatically: true, withNewVidGeo: newVidGeo)
            return  // do not even try to go to full screen if already going to music mode
          } else if currentMediaAudioStatus == .notAudio && isInMiniPlayer {
            log.debug("[applyVideoGeo \(cxt.name)] Opened media is not audio: auto-switching to normal window")
            player.exitMusicMode(automatically: true, withNewVidGeo: newVidGeo)
            return  // do not even try to go to full screen if already going to windowed mode
          }
        }

        // Need to switch to full screen?
        if Preference.bool(for: .fullScreenWhenOpen) && !isFullScreen && !isInMiniPlayer {
          log.debug("[applyVideoGeo \(cxt.name)] Changing to full screen because \(Preference.Key.fullScreenWhenOpen.rawValue)==Y")
          enterFullScreen()
        }
      }
    })

    return (initialLayout, tasks)
  }

  /// Generates animation tasks to adjust the window layout appropriately for a newly opened file.
  private func buildTransitionTasks(from inputLayout: LayoutState, to outputLayout: LayoutState, _ newGeoSet: GeometrySet,
                                    isRestoringFromPrevLaunch: Bool, needsNativeFullScreen: Bool) -> [IINAAnimation.Task] {

    var tasks: [IINAAnimation.Task] = []

    // Don't want window resize/move listeners doing something untoward
    isAnimatingLayoutTransition = true

    // Send GeometrySet object to builder so that it doesn't default to current window frame
    log.verbose("Setting initial \(outputLayout.spec), windowedModeGeo=\(newGeoSet.windowed), musicModeGeo=\(newGeoSet.musicMode)")

    let transitionName = "\(isRestoringFromPrevLaunch ? "Restore" : "Set")InitialLayout"
    let initialTransition = buildLayoutTransition(named: transitionName,
                                                  from: currentLayout, to: outputLayout.spec, isWindowInitialLayout: true, newGeoSet)

    tasks.append(.instantTask { [self] in

      // For initial layout (when window is first shown), to reduce jitteriness when drawing, do all the layout
      // in a single animation block.

      do {
        for task in initialTransition.tasks {
          try task.runFunc()
        }
      } catch {
        log.error("Failed to run initial layout tasks: \(error)")
      }

      if !isRestoringFromPrevLaunch {
        if outputLayout.mode == .windowedNormal {
          player.info.intendedViewportSize = initialTransition.outputGeometry.viewportSize

          // Set window opacity to 0 initially to start fade-in effect
          updateWindowBorderAndOpacity(using: outputLayout, windowOpacity: 0.0)
        }

        if !outputLayout.isFullScreen, Preference.bool(for: .alwaysFloatOnTop) && !player.info.isPaused {
          log.verbose("Setting window OnTop=Y per app pref")
          setWindowFloatingOnTop(true)
        }
      }

      /// Note: `isAnimatingLayoutTransition` should be `false` now
      log.verbose("Done with transition to initial layout")
    })

    if needsNativeFullScreen {
      tasks.append(.instantTask { [self] in
        enterFullScreen()
      })
      return tasks
    }

    if isRestoringFromPrevLaunch {
      /// Stored window state may not be consistent with global IINA prefs.
      /// To check this, build another `LayoutSpec` from the global prefs, then compare it to the player's.
      let prefsSpec = LayoutSpec.fromPreferences(fillingInFrom: outputLayout.spec)
      if outputLayout.spec.hasSamePrefsValues(as: prefsSpec) {
        log.verbose("Saved layout is consistent with IINA global prefs")
      } else {
        // Not consistent. But we already have the correct spec, so just build a layout from it and transition to correct layout
        log.warn("Player's saved layout does not match IINA app prefs. Will fix & apply corrected layout")
        log.debug("SavedSpec: \(currentLayout.spec). PrefsSpec: \(prefsSpec)")
        let transition = buildLayoutTransition(named: "FixInvalidInitialLayout",
                                               from: initialTransition.outputLayout, to: prefsSpec)

        tasks.append(contentsOf: transition.tasks)
      }
    }
    return tasks
  }

  private func configureFromRestore(_ priorState: PlayerSaveState, _ initialLayout: LayoutState) -> GeometrySet {
    log.verbose("Setting geometries from prior state, windowed=\(priorState.geoSet.windowed), musicMode=\(priorState.geoSet.musicMode)")

    if initialLayout.mode == .musicMode {
      player.overrideAutoMusicMode = true
    }

    // Clean up windowedModeGeo if serious errors found with it
    let priorWindowedModeGeo = priorState.geoSet.windowed
    if !priorWindowedModeGeo.mode.isWindowed || priorWindowedModeGeo.screenFit.isFullScreen {
      log.error("While transitioning to initial layout: windowedModeGeo from prior state has invalid mode (\(priorWindowedModeGeo.mode)) or screenFit (\(priorWindowedModeGeo.screenFit)). Will generate a fresh windowedModeGeo from saved layoutSpec and last closed window instead")
      let lastClosedGeo = PlayerWindowController.windowedModeGeoLastClosed
      let windowed: PWinGeometry
      if lastClosedGeo.mode.isWindowed && !lastClosedGeo.screenFit.isFullScreen {
        windowed = initialLayout.convertWindowedModeGeometry(from: lastClosedGeo, video: priorState.geoSet.video,
                                                             keepFullScreenDimensions: false, log)
      } else {
        windowed = initialLayout.buildDefaultInitialGeometry(screen: bestScreen, video: priorState.geoSet.video)
      }
      return priorState.geoSet.clone(windowed: windowed)
    }
    return priorState.geoSet
  }

  private func configureFromPrefs(_ initialLayout: LayoutState, _ videoGeo: VideoGeometry) -> GeometrySet {
    // Should only be here if window is a new window or was previously closed. Copy layout from the last closed window

    let musicModeGeo = PlayerWindowController.musicModeGeoLastClosed.clone(video: videoGeo)

    let windowedModeGeo: PWinGeometry
    if initialLayout.isFullScreen || initialLayout.isMusicMode {
      windowedModeGeo = PlayerWindowController.windowedModeGeoLastClosed

    } else {
      /// Use `minVideoSize` at first when a new window is opened, so that when `applyVideoGeoTransform()` is called shortly after,
      /// it expands and creates a nice zooming effect. But try to start with video's correct aspect, if available
      let viewportSize = CGSize.computeMinSize(withAspect: videoGeo.videoAspectCAR,
                                               minWidth: Constants.WindowedMode.minViewportSize.width,
                                               minHeight: Constants.WindowedMode.minViewportSize.height)
      let intendedWindowSize = NSSize(width: viewportSize.width + initialLayout.outsideLeadingBarWidth + initialLayout.outsideTrailingBarWidth,
                                      height: viewportSize.height + initialLayout.outsideTopBarHeight + initialLayout.outsideBottomBarHeight)
      let windowFrame = NSRect(origin: NSPoint.zero, size: intendedWindowSize)
      /// Change the window origin so that it opens where the mouse was when `openURLs` was called. This visually reinforces the user-initiated
      /// behavior and is less jarring than popping out of the periphery. It will move while zooming to its final location, which remains
      /// well-defined based on current user prefs and/or last closed window.
      let mouseLoc = PlayerCore.mouseLocationAtLastOpen ?? NSEvent.mouseLocation
      let mouseLocScreenID = NSScreen.getOwnerOrDefaultScreenID(forPoint: mouseLoc)
      let initialGeo = initialLayout.buildGeometry(windowFrame: windowFrame, screenID: mouseLocScreenID, video: videoGeo).refitted(using: .stayInside)
      let windowSize = initialGeo.windowFrame.size
      let windowOrigin = NSPoint(x: round(mouseLoc.x - (windowSize.width * 0.5)), y: round(mouseLoc.y - (windowSize.height * 0.5)))
      log.verbose("Initial layout: starting with tiny window, videoAspect=\(videoGeo.videoAspectCAR), windowSize=\(windowSize)")
      windowedModeGeo = initialGeo.clone(windowFrame: NSRect(origin: windowOrigin, size: windowSize)).refitted(using: .stayInside)
    }

    return GeometrySet(windowed: windowedModeGeo, musicMode: musicModeGeo, video: videoGeo)
  }
}
