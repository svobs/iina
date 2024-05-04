//
//  PlayerWinResizeExtension.swift
//  iina
//
//  Created by Matt Svoboda on 12/13/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// `PlayerWindowController` geometry functions
extension PlayerWindowController {

  /// Adjust window, viewport, and videoView sizes when `VideoGeometry` has changes.
  func applyVidGeo(_ newVidGeo: VideoGeometry) {
    dispatchPrecondition(condition: .onQueue(player.mpv.queue))
    log.verbose("[applyVidGeo] Entered, newVidGeo=\(newVidGeo)")

    guard newVidGeo.hasValidSize else { return }
    guard let currentMedia = player.info.currentMedia else {
      log.verbose("[applyVidGeo] Aborting: currentMedia is nil")
      return
    }

    let oldVidGeo = player.info.videoGeo
    // Update cached values for use elsewhere:
    player.info.videoGeo = newVidGeo

    // Get this in the mpv thread to avoid race condition
    let justOpenedFile = player.info.justOpenedFile
    let isRestoring = player.info.isRestoring

    if newVidGeo.totalRotation != currentMedia.thumbnails?.rotationDegrees {
      player.reloadThumbnails(forMedia: player.info.currentMedia)
    }

    // Show default album art?
    let showDefaultArt: Bool?
    // if received video size before switching to music mode, hide default album art
    // Don't show art if currently loading
    let isCompletelyLoaded = currentMedia.loadStatus.isAtLeast(.completelyLoaded)
    if isCompletelyLoaded, !player.isStopping, !player.isStopped {
      // Check whether to show album art
      let showAlbumArt = player.info.currentMediaAudioStatus == .isAudio

      if player.info.isVideoTrackSelected {
        log.verbose("[applyVidGeo] Hiding defaultAlbumArt because vidSelected=Y (showArt=\(showAlbumArt.yn))")
        showDefaultArt = false
      } else {
        log.verbose("[applyVidGeo] Showing defaultAlbumArt because vidSelected=N (showArt=\(showAlbumArt.yn))")
        showDefaultArt = true
      }

      /// If `true`, then `player.info.videoAspect` will return 1:1.
      player.info.isShowingAlbumArt = showDefaultArt! || showAlbumArt
    } else {
      showDefaultArt = nil
    }

    DispatchQueue.main.async { [self] in
      animationPipeline.submitSudden({ [self] in

        if let showDefaultArt {
          // Update default album art visibility:
          defaultAlbumArtView.isHidden = !showDefaultArt
        }

        updateVidGeo(from: oldVidGeo, to: newVidGeo, isRestoring: isRestoring, justOpenedFile: justOpenedFile)
      })
    }
  }

  // FIXME: refactor to use the videoScale provided (or change the flow). Currently it is ignored and then recalculated afterwards
  /// Only `applyVidGeo` should call this.
  private func updateVidGeo(from oldVidGeo: VideoGeometry, to newVidGeo: VideoGeometry, isRestoring: Bool, justOpenedFile: Bool) {
    guard !isClosing, !player.isStopping, !player.isStopped, !player.isShuttingDown else { return }
    guard let window else { return }

    guard !isRestoring else {
      log.verbose("[applyVidGeo] Restore is in progress; no op")
      return
    }

    guard let newVideoSizeACR = newVidGeo.videoSizeACR, let newVideoSizeRaw = newVidGeo.videoSizeRaw else {
      log.error("[applyVidGeo] Could not get videoSizeACR from mpv! Cancelling adjustment")
      return
    }

    let newVideoAspect = newVideoSizeACR.mpvAspect
    log.verbose("[applyVidGeo Start] restoring=\(isRestoring.yn) justOpenedFile=\(justOpenedFile.yn) NewVidGeo=\(newVidGeo)")

    if #available(macOS 10.12, *) {
      pip.aspectRatio = newVideoSizeACR
    }
    let currentLayout = currentLayout

    if currentLayout.mode == .musicMode {
      /// Keep prev `windowFrame`. Just adjust height to fit new video aspect ratio
      /// (unless it doesn't fit in screen; see `applyMusicModeGeo`)
      guard musicModeGeo.videoAspect != newVideoAspect else {
        log.debug("[applyVidGeo M Done] Player is in music mode but no change to videoAspect (\(musicModeGeo.videoAspect))")
        return
      }
      log.debug("[applyVidGeo M Apply] Player is in music mode; calling applyMusicModeGeo")
      let newGeometry = musicModeGeo.clone(windowFrame: window.frame, screenID: bestScreen.screenID, videoAspect: newVideoAspect)
      applyMusicModeGeoInAnimationPipeline(newGeometry)
      return
    }

    // Windowed or full screen
    // FIXME: incorporate scale
    if isInitialSizeDone,
       let oldVideoSizeRaw = oldVidGeo.videoSizeRaw, oldVideoSizeRaw.equalTo(newVideoSizeRaw),
       let oldVideoSizeACR = oldVidGeo.videoSizeACR, oldVideoSizeACR.equalTo(newVideoSizeACR),
       // must check actual videoView as well - it's not completely concurrent and may have fallen out of date
       videoView.frame.size.mpvAspect == newVideoAspect {
      log.debug("[applyVidGeo F Done] No change to prev video params. Taking no action")
      return
    }

    // If user moved the window recently, window frame might not be completely up to date
    let currentWindowFrame = currentLayout.mode.isWindowed ? window.frame : nil
    let currentScreenID = currentLayout.mode.isWindowed ? bestScreen.screenID : nil
    let windowGeo = windowedModeGeo.clone(windowFrame: currentWindowFrame, screenID: currentScreenID, videoAspect: newVideoAspect)
    let justOpenedFileManually = justOpenedFile && !isInitialSizeDone

    let newWindowGeo: PWGeometry
    if justOpenedFile, let resizedGeo = resizeAfterFileOpen(justOpenedFileManually: justOpenedFileManually,
                                                            windowGeo: windowGeo, videoSizeACR: newVideoSizeACR) {
      newWindowGeo = resizedGeo
    } else {
      if justOpenedFileManually {
        log.verbose("[applyVidGeo D-1] Just opened file manually with no resize strategy. Using windowedModeGeoLastClosed: \(PlayerWindowController.windowedModeGeoLastClosed)")
        newWindowGeo = currentLayout.convertWindowedModeGeometry(from: PlayerWindowController.windowedModeGeoLastClosed,
                                                                 videoAspect: newVideoAspect, keepFullScreenDimensions: true)
      } else {
        // File opened via playlist navigation, or some other change occurred for file
        newWindowGeo = resizeMinimallyForNewVideoAspect(from: windowGeo, newVideoAspect: newVideoAspect)
      }
    }

    var duration = IINAAnimation.VideoReconfigDuration
    var timing = CAMediaTimingFunctionName.easeInEaseOut
    if !isInitialSizeDone {
      // Just opened manually. Use a longer duration for this one, because the window starts small and will zoom into place.
      log.verbose("[applyVidGeo D-1a] Setting isInitialSizeDone=YES")
      isInitialSizeDone = true
      duration = IINAAnimation.InitialVideoReconfigDuration
      timing = .linear
    }
    /// Finally call `setFrame()`
    log.debug("[applyVidGeo D-2 Apply] Applying result (FS:\(isFullScreen.yn)) → \(newWindowGeo)")
    /// Update even if not currently in windowed mode, as it will be needed when exiting other modes
    windowedModeGeo = newWindowGeo

    if currentLayout.mode == .windowed {
      applyWindowGeoInAnimationPipeline(newWindowGeo, duration: duration, timing: timing)

    } else if currentLayout.mode == .fullScreen {
      let fsGeo = currentLayout.buildFullScreenGeometry(inScreenID: newWindowGeo.screenID, videoAspect: newWindowGeo.videoAspect)

      animationPipeline.submit(IINAAnimation.Task(duration: duration, timing: timing, { [self] in
        // Make sure video constraints are up to date, even in full screen. Also remember that FS & windowed mode share same screen.
        log.verbose("[applyVidGeo Apply]: Updating videoView (FS), videoSize: \(fsGeo.videoSize)")
        videoView.apply(fsGeo)
      }))

    }

    // UI and slider
    log.debug("[applyVidGeo Done] Emitting windowSizeAdjusted")
    player.events.emit(.windowSizeAdjusted, data: newWindowGeo.windowFrame)
  }

  private func resizeAfterFileOpen(justOpenedFileManually: Bool, windowGeo: PWGeometry, videoSizeACR: NSSize) -> PWGeometry? {
    assert(windowGeo.videoAspect == videoSizeACR.mpvAspect, "Expected videoSizeACR aspect: \(videoSizeACR.mpvAspect), found: \(windowGeo.videoAspect)")
    // resize option applies
    let resizeTiming = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
    switch resizeTiming {
    case .always:
      log.verbose("[applyVidGeo C] justOpenedFile & resizeTiming='Always' → returning YES for shouldResize")
    case .onlyWhenOpen:
      log.verbose("[applyVidGeo C] justOpenedFile & resizeTiming='OnlyWhenOpen' → returning justOpenedFileManually (\(justOpenedFileManually.yesno)) for shouldResize")
      guard justOpenedFileManually else {
        return nil
      }
    case .never:
      log.verbose("[applyVidGeo C] justOpenedFile & resizeTiming='Never' → returning NO for shouldResize")
      return nil
    }

    let screenID = player.isInMiniPlayer ? musicModeGeo.screenID : windowGeo.screenID
    let screenVisibleFrame = NSScreen.getScreenOrDefault(screenID: screenID).visibleFrame

    let resizeScheme: Preference.ResizeWindowScheme = Preference.enum(for: .resizeWindowScheme)
    switch resizeScheme {
    case .mpvGeometry:
      // check if have mpv geometry set (initial window position/size)
      if let mpvGeometry = player.getMPVGeometry() {
        var preferredGeo = windowGeo
        if Preference.bool(for: .lockViewportToVideoSize), let intendedViewportSize = player.info.intendedViewportSize  {
          log.verbose("[applyVidGeo C-6] Using intendedViewportSize \(intendedViewportSize)")
          preferredGeo = windowGeo.scaleViewport(to: intendedViewportSize)
        }
        log.verbose("[applyVidGeo C-7] Applying mpv \(mpvGeometry) within screen \(screenVisibleFrame)")
        return windowGeo.apply(mpvGeometry: mpvGeometry, desiredWindowSize: preferredGeo.windowFrame.size)
      } else {
        log.debug("[applyVidGeo C-5] No mpv geometry found. Will fall back to default scheme")
        return nil
      }
    case .simpleVideoSizeMultiple:
      let resizeWindowStrategy: Preference.ResizeWindowOption = Preference.enum(for: .resizeWindowOption)
      if resizeWindowStrategy == .fitScreen {
        log.verbose("[applyVidGeo C-4] ResizeWindowOption=FitToScreen. Using screenFrame \(screenVisibleFrame)")
        return windowGeo.scaleViewport(to: screenVisibleFrame.size, fitOption: .centerInside)
      } else {
        let resizeRatio = resizeWindowStrategy.ratio
        let newVideoSize = videoSizeACR.multiply(CGFloat(resizeRatio))
        log.verbose("[applyVidGeo C-2] Applied resizeRatio (\(resizeRatio)) to newVideoSize → \(newVideoSize)")
        let centeredScaledGeo = windowGeo.scaleVideo(to: newVideoSize, fitOption: .centerInside, mode: currentLayout.mode)
        // User has actively resized the video. Assume this is the new preferred resolution
        player.info.intendedViewportSize = centeredScaledGeo.viewportSize
        log.verbose("[applyVidGeo C-3] After scaleVideo: \(centeredScaledGeo)")
        return centeredScaledGeo
      }
    }
  }

  private func resizeMinimallyForNewVideoAspect(from windowGeo: PWGeometry,
                                                newVideoAspect: CGFloat) -> PWGeometry {
    // User is navigating in playlist. Try to retain same window width.
    // This often isn't possible for vertical videos, which will end up shrinking the width.
    // So try to remember the preferred width so it can be restored when possible
    var desiredViewportSize = windowGeo.viewportSize

    if Preference.bool(for: .lockViewportToVideoSize) {
      if let intendedViewportSize = player.info.intendedViewportSize  {
        // Just use existing size in this case:
        desiredViewportSize = intendedViewportSize
        log.verbose("[applyVidGeo D-2] Using intendedViewportSize \(intendedViewportSize)")
      }

      let minNewViewportHeight = round(desiredViewportSize.width / newVideoAspect)
      if desiredViewportSize.height < minNewViewportHeight {
        // Try to increase height if possible, though it may still be shrunk to fit screen
        desiredViewportSize = NSSize(width: desiredViewportSize.width, height: minNewViewportHeight)
      }
    }

    log.verbose("[applyVidGeo D-3] Minimal resize: applying desiredViewportSize \(desiredViewportSize)")
    return windowGeo.scaleViewport(to: desiredViewportSize)
  }

  // MARK: - Window geometry functions

  // FIXME: merge this into applyVidGeo()
  func setVideoScale(_ desiredVideoScale: Double) {
    guard let window = window else { return }
    let currentLayout = currentLayout
    // Not supported in music mode at this time. Need to resolve backing scale bugs
    guard currentLayout.mode == .windowed else { return }

    guard let videoSizeACR = player.info.videoGeo.videoSizeACR else {
      log.error("SetVideoScale failed: could not get videoSizeACR")
      return
    }

    var desiredVideoSize = NSSize(width: round(videoSizeACR.width * desiredVideoScale),
                                  height: round(videoSizeACR.height * desiredVideoScale))

    log.verbose("SetVideoScale: requested scale=\(desiredVideoScale)x, videoSizeACR=\(videoSizeACR) → desiredVideoSize=\(desiredVideoSize)")

    // TODO
    if false && Preference.bool(for: .usePhysicalResolution) {
      desiredVideoSize = window.convertFromBacking(NSRect(origin: window.frame.origin, size: desiredVideoSize)).size
      log.verbose("SetVideoScale: converted desiredVideoSize to physical resolution: \(desiredVideoSize)")
    }

    switch currentLayout.mode {
    case .windowed:
      let windowedModeGeo = windowedModeGeo.clone(windowFrame: window.frame, screenID: bestScreen.screenID)
      let newGeometry = windowedModeGeo.scaleVideo(to: desiredVideoSize, mode: currentLayout.mode)
      // User has actively resized the video. Assume this is the new preferred resolution
      player.info.intendedViewportSize = newGeometry.viewportSize
      log.verbose("SetVideoScale: calling applyWindowGeo")
      applyWindowGeoInAnimationPipeline(newGeometry)
    case .musicMode:
      let musicModeGeo = musicModeGeo.clone(windowFrame: window.frame, screenID: bestScreen.screenID)
      // will return nil if video is not visible
      guard let newMusicModeGeometry = musicModeGeo.scaleViewport(to: desiredVideoSize) else { return }
      log.verbose("SetVideoScale: calling applyMusicModeGeo")
      applyMusicModeGeoInAnimationPipeline(newMusicModeGeometry)
    default:
      return
    }
  }

  /**
   Resizes and repositions the window, attempting to match `desiredViewportSize`, but the actual resulting
   video size will be scaled if needed so it is`>= AppData.minVideoSize` and `<= screen.visibleFrame`.
   The window's position will also be updated to maintain its current center if possible, but also to
   ensure it is placed entirely inside `screen.visibleFrame`.
   */
  func resizeViewport(to desiredViewportSize: CGSize? = nil, centerOnScreen: Bool = false, duration: CGFloat = IINAAnimation.DefaultDuration) {
    guard let window else { return }

    switch currentLayout.mode {
    case .windowed, .windowedInteractive:
      let newGeoUnconstrained = windowedModeGeo.clone(windowFrame: window.frame, screenID: bestScreen.screenID)
        .scaleViewport(to: desiredViewportSize, fitOption: .noConstraints)
      if currentLayout.mode == .windowed {
        // User has actively resized the video. Assume this is the new preferred resolution
        player.info.intendedViewportSize = newGeoUnconstrained.viewportSize
      }

      let fitOption: ScreenFitOption = centerOnScreen ? .centerInside : .stayInside
      let newGeometry = newGeoUnconstrained.refit(fitOption)
      log.verbose("Calling applyWindowGeo from resizeViewport (center=\(centerOnScreen.yn)), to: \(newGeometry.windowFrame)")
      applyWindowGeoInAnimationPipeline(newGeometry, duration: duration)
    case .musicMode:
      /// In music mode, `viewportSize==videoSize` always. Will get `nil` here if video is not visible
      guard let newMusicModeGeometry = musicModeGeo.clone(windowFrame: window.frame, screenID: bestScreen.screenID)
        .scaleViewport(to: desiredViewportSize) else { return }
      log.verbose("Calling applyMusicModeGeo from resizeViewport, to: \(newMusicModeGeometry.windowFrame)")
      applyMusicModeGeoInAnimationPipeline(newMusicModeGeometry)
    default:
      return
    }
  }

  func scaleVideoByIncrement(_ widthStep: CGFloat) {
    guard let window else { return }
    let currentViewportSize: NSSize
    switch currentLayout.mode {
    case .windowed:
      currentViewportSize = windowedModeGeo.clone(windowFrame: window.frame, screenID: bestScreen.screenID).viewportSize
    case .musicMode:
      guard let viewportSize = musicModeGeo.clone(windowFrame: window.frame, screenID: bestScreen.screenID).viewportSize else { return }
      currentViewportSize = viewportSize
    default:
      return
    }
    let heightStep = widthStep / currentViewportSize.mpvAspect
    let desiredViewportSize = CGSize(width: currentViewportSize.width + widthStep, height: currentViewportSize.height + heightStep)
    log.verbose("Incrementing viewport width by \(widthStep), to desired size \(desiredViewportSize)")
    resizeViewport(to: desiredViewportSize)
  }

  /// Encapsulates logic for `windowWillResize`, but specfically for windowed modes.
  func resizeWindow(_ window: NSWindow, to requestedSize: NSSize, lockViewportToVideoSize: Bool, isLiveResizingWidth: Bool) -> PWGeometry {
    let currentLayout = currentLayout
    guard currentLayout.isWindowed else {
      log.error("WinWillResize: requested mode is invalid: \(currentLayout.spec.mode). Will fall back to windowedModeGeo")
      return windowedModeGeo
    }
    let currentGeo = windowedModeGeo.clone(windowFrame: window.frame, screenID: bestScreen.screenID)
    assert(currentGeo.mode == currentLayout.mode,
           "WinWillResize: currentGeo.mode (\(currentGeo.mode)) != currentLayout.mode (\(currentLayout.mode))")

    guard !player.info.isRestoring else {
      log.error("WinWillResize was fired before restore was complete! Returning existing geometry: \(currentGeo.windowFrame.size)")
      return currentGeo
    }

    let chosenGeo: PWGeometry
    // Need to resize window to match video aspect ratio, while taking into account any outside panels.
    if lockViewportToVideoSize && window.inLiveResize {
      let nonViewportAreaSize = currentGeo.windowFrame.size.subtract(currentGeo.viewportSize)
      let requestedViewportSize = requestedSize.subtract(nonViewportAreaSize)

      if isLiveResizingWidth {
        // Option A: resize height based on requested width
        let resizedWidthViewportSize = NSSize(width: requestedViewportSize.width,
                                              height: round(requestedViewportSize.width / currentGeo.videoAspect))
        chosenGeo = currentGeo.scaleViewport(to: resizedWidthViewportSize)
      } else {
        // Option B: resize width based on requested height
        let resizedHeightViewportSize = NSSize(width: round(requestedViewportSize.height * currentGeo.videoAspect),
                                               height: requestedViewportSize.height)
        chosenGeo = currentGeo.scaleViewport(to: resizedHeightViewportSize)
      }
    } else {
      /// If `!inLiveResize`: resize request is not coming from the user. Could be BetterTouchTool, Retangle, or some window manager, or the OS.
      /// These tools seem to expect that both dimensions of the returned size are less than the requested dimensions, so check for this.
      /// If `lockViewportToVideoSize && !inLiveResize`: scale window to requested size; `refit()` below will constrain as needed.
      chosenGeo = currentGeo.scaleWindow(to: requestedSize)
    }

    if currentLayout.mode == .windowed && window.inLiveResize {
      // User has resized the video. Assume this is the new preferred resolution until told otherwise. Do not constrain.
      player.info.intendedViewportSize = chosenGeo.viewportSize
    }

    log.verbose("WinWillResize isLive:\(window.inLiveResize.yn) req:\(requestedSize) lockViewport:Y currWinSize:\(currentGeo.windowFrame.size) returning:\(chosenGeo.windowFrame.size)")

    return chosenGeo
  }

  func updateFloatingOSCAfterWindowDidResize(usingGeometry newGeometry: PWGeometry? = nil) {
    guard let window = window, currentLayout.hasFloatingOSC else { return }

    let newViewportSize = newGeometry?.viewportSize ?? viewportView.frame.size
    controlBarFloating.moveTo(centerRatioH: floatingOSCCenterRatioH,
                              originRatioV: floatingOSCOriginRatioV, layout: currentLayout, viewportSize: newViewportSize)

    // Detach the views in oscFloatingUpperView manually on macOS 11 only; as it will cause freeze
    if #available(macOS 11.0, *) {
      if #unavailable(macOS 12.0) {
        guard let maxWidth = [fragVolumeView, fragToolbarView].compactMap({ $0?.frame.width }).max() else {
          return
        }

        // window - 10 - controlBarFloating
        // controlBarFloating - 12 - oscFloatingUpperView
        let margin: CGFloat = (10 + 12) * 2
        let hide = (window.frame.width
                    - oscFloatingPlayButtonsContainerView.frame.width
                    - maxWidth*2
                    - margin) < 0

        let views = oscFloatingUpperView.views
        if hide {
          if views.contains(fragVolumeView) {
            oscFloatingUpperView.removeView(fragVolumeView)
          }
          if let fragToolbarView = fragToolbarView, views.contains(fragToolbarView) {
            oscFloatingUpperView.removeView(fragToolbarView)
          }
        } else {
          if !views.contains(fragVolumeView) {
            oscFloatingUpperView.addView(fragVolumeView, in: .leading)
          }
          if let fragToolbarView = fragToolbarView, !views.contains(fragToolbarView) {
            oscFloatingUpperView.addView(fragToolbarView, in: .trailing)
          }
        }
      }
    }
  }

  // MARK: - Apply Geometry

  /// Use for resizing window. Not animated. Can be used in windowed or full screen modes. Can be used in music mode only if playlist is hidden.
  /// Use with non-nil `newGeometry` for: (1) pinch-to-zoom, (2) resizing outside sidebars when the whole window needs to be resized or moved
  func applyWindowResize(usingGeometry newGeometry: PWGeometry? = nil) {
    guard let window else { return }
    videoView.videoLayer.enterAsynchronousMode()

    IINAAnimation.disableAnimation {
      let layout = currentLayout
      let isTransientResize = newGeometry != nil
      let isFullScreen = currentLayout.isFullScreen
      log.verbose("ApplyWindowResize: fs=\(isFullScreen.yn) newGeo=\(newGeometry?.description ?? "nil")")
      if !layout.isNativeFullScreen {
        // Keep video margins up to date in almost every case
        videoView.apply(newGeometry ?? layout.buildGeometry(windowFrame: window.frame, screenID: bestScreen.screenID, videoAspect: player.info.videoAspect))

        if let newGeometry, !isFullScreen {
          /// To avoid visual bugs, *ALWAYS* update videoView before updating window frame!
          player.window.setFrameImmediately(newGeometry.windowFrame, animate: false)
        }
      }

      if currentLayout.isMusicMode {
        // Re-evaluate space requirements for labels. May need to start scrolling.
        // Will also update saved state
        miniPlayer.windowDidResize()
      } else if currentLayout.isInteractiveMode {
        // Update interactive mode selectable box size. Origin is relative to viewport origin
        if let newGeometry {
          let newVideoRect = NSRect(origin: CGPointZero, size: newGeometry.videoSize)
          cropSettingsView?.cropBoxView.resized(with: newVideoRect)
        } else {
          cropSettingsView?.cropBoxView.resized(with: videoView.bounds)
        }
      }

      // These may no longer be aligned correctly. Just hide them
      hideSeekTimeAndThumbnail()

      // Update floating control bar position if applicable
      updateFloatingOSCAfterWindowDidResize(usingGeometry: newGeometry)

      // Do not cache supplied geometry. Assume caller will handle it.
      if !isFullScreen && !isTransientResize {
        player.saveState()
        if currentLayout.mode == .windowed {
          log.verbose("ApplyWindowResize: calling updateMPVWindowScale")
          player.updateMPVWindowScale(using: windowedModeGeo)
        }
      }
    }

    player.events.emit(.windowResized, data: window.frame)
  }

  /// Set the window frame and if needed the content view frame to appropriately use the full screen.
  /// For screens that contain a camera housing the content view will be adjusted to not use that area of the screen.
  func applyLegacyFSGeo(_ geometry: PWGeometry) {
    guard let window = window else { return }
    let currentLayout = currentLayout
    videoView.apply(geometry)

    if currentLayout.hasFloatingOSC {
      controlBarFloating.moveTo(centerRatioH: floatingOSCCenterRatioH, originRatioV: floatingOSCOriginRatioV,
                                layout: currentLayout, viewportSize: geometry.viewportSize)
    }

    updateOSDTopBarOffset(geometry, isLegacyFullScreen: true)
    let topBarHeight = currentLayout.topBarPlacement == .insideViewport ? geometry.insideTopBarHeight : geometry.outsideTopBarHeight
    updateTopBarHeight(to: topBarHeight, topBarPlacement: currentLayout.topBarPlacement, cameraHousingOffset: geometry.topMarginHeight)

    guard !geometry.windowFrame.equalTo(window.frame) else {
      log.verbose("No need to update windowFrame for legacyFullScreen - no change")
      return
    }

    log.verbose("Calling setFrame for legacyFullScreen, to \(geometry)")
    player.window.setFrameImmediately(geometry.windowFrame)
  }

  /// Updates/redraws current `window.frame` and its internal views from `newGeometry`. Animated.
  ///
  /// Also updates cached `windowedModeGeo` and saves updated state. Windowed mode only!
  func applyWindowGeoInAnimationPipeline(_ newGeometry: PWGeometry, duration: CGFloat = IINAAnimation.DefaultDuration,
                                         timing: CAMediaTimingFunctionName = .easeInEaseOut) {
    let tasks = buildApplyWindowGeoTasks(newGeometry, duration: duration, timing: timing)
    animationPipeline.submit(tasks)
  }

  func buildApplyWindowGeoTasks(_ newGeometry: PWGeometry, duration: CGFloat = IINAAnimation.DefaultDuration,
                               timing: CAMediaTimingFunctionName = .easeInEaseOut) -> [IINAAnimation.Task] {
    assert(currentLayout.spec.mode.isWindowed, "applyWindowGeo called outside windowed mode! (found: \(currentLayout.spec.mode))")

    var tasks: [IINAAnimation.Task] = []
    tasks.append(IINAAnimation.suddenTask{ [self] in
      isAnimatingLayoutTransition = true  /// try not to trigger `windowDidResize` while animating
      hideSeekTimeAndThumbnail()
    })

    tasks.append(IINAAnimation.Task(duration: duration, timing: timing, { [self] in
      applyWindowGeo(newGeometry)
    }))

    tasks.append(IINAAnimation.suddenTask{ [self] in
      isAnimatingLayoutTransition = false
    })

    return tasks
  }

  func applyWindowGeo(_ newGeometry: PWGeometry) {
    log.verbose("ApplyWindowGeo: windowFrame=\(newGeometry.windowFrame) videoSize=\(newGeometry.videoSize) videoAspect=\(newGeometry.videoAspect)")

    videoView.videoLayer.enterAsynchronousMode()
    // This is only needed to achieve "fade-in" effect when opening window:
    updateCustomBorderBoxAndWindowOpacity()

    /// Make sure this is up-to-date. Do this before `setFrame`
    videoView.apply(newGeometry)
    if !isWindowHidden {
      player.window.setFrameImmediately(newGeometry.windowFrame)
    }
    windowedModeGeo = newGeometry

    log.verbose("ApplyWindowGeo: Calling updateMPVWindowScale, videoSize=\(newGeometry.videoSize)")
    player.updateMPVWindowScale(using: newGeometry)
    player.saveState()
  }

  /// Same as `applyMusicModeGeo`, but enqueues inside an `IINAAnimation.Task` for a nice smooth animation
  func applyMusicModeGeoInAnimationPipeline(_ geometry: MusicModeGeometry, setFrame: Bool = true, animate: Bool = true, updateCache: Bool = true) {
    var tasks: [IINAAnimation.Task] = []
    tasks.append(IINAAnimation.suddenTask { [self] in
      isAnimatingLayoutTransition = true  /// do not trigger resize listeners
    })
    tasks.append(IINAAnimation.Task(timing: .easeInEaseOut, { [self] in
      applyMusicModeGeo(geometry)
    }))
    tasks.append(IINAAnimation.suddenTask { [self] in
      isAnimatingLayoutTransition = false
    })

    animationPipeline.submit(tasks)
  }

  /// Updates the current window and its subviews to match the given `MusicModeGeometry`.
  /// If `updateCache` is true, updates `musicModeGeo` and saves player state.
  @discardableResult
  func applyMusicModeGeo(_ geometry: MusicModeGeometry, setFrame: Bool = true, animate: Bool = true, 
                         updateCache: Bool = true) -> MusicModeGeometry {
    let geometry = geometry.refit()  // enforces internal constraints, and constrains to screen
    log.verbose("Applying \(geometry), setFrame=\(setFrame.yn) updateCache=\(updateCache.yn)")

    videoView.videoLayer.enterAsynchronousMode()

    // Update defaults:
    Preference.set(geometry.isVideoVisible, for: .musicModeShowAlbumArt)
    Preference.set(geometry.isPlaylistVisible, for: .musicModeShowPlaylist)

    updateMusicModeButtonsVisibility()

    /// Try to detect & remove unnecessary constraint updates - `updateBottomBarHeight()` may cause animation glitches if called twice
    var hasChange: Bool = !geometry.windowFrame.equalTo(window!.frame)
    let isVideoVisible = !(viewportViewHeightContraint?.isActive ?? false)
    if geometry.isVideoVisible != isVideoVisible {
      hasChange = true
    }
    if let newVideoSize = geometry.videoSize, let oldVideoSize = musicModeGeo.videoSize, !oldVideoSize.equalTo(newVideoSize) {
      hasChange = true
    }

    guard hasChange else {
      log.verbose("Not updating music mode windowFrame or constraints - no changes needed")
      return geometry
    }

    /// Make sure to call `apply` AFTER `updateVideoViewVisibilityConstraints`:
    miniPlayer.updateVideoViewVisibilityConstraints(isVideoVisible: geometry.isVideoVisible)
    updateBottomBarHeight(to: geometry.bottomBarHeight, bottomBarPlacement: .outsideViewport)
    let convertedGeo = geometry.toPWGeometry()
    videoView.apply(convertedGeo)

    if let derivedVideoScale = player.deriveVideoScale(from: convertedGeo) {
      player.info.videoGeo = player.info.videoGeo.clone(scale: derivedVideoScale)
    }

    if setFrame {
      player.window.setFrameImmediately(geometry.windowFrame, animate: animate)
    }

    if updateCache {
      musicModeGeo = geometry
      player.saveState()
    }

    /// For the case where video is hidden but playlist is shown, AppKit won't allow the window's height to be changed by the user
    /// unless we remove this constraint from the the window's `contentView`. For all other situations this constraint should be active.
    /// Need to execute this in its own task so that other animations are not affected.
    let shouldEnableConstraint = !geometry.isVideoVisible && geometry.isPlaylistVisible
    if shouldEnableConstraint {
      animationPipeline.submitSudden({ [self] in
        viewportBottomOffsetFromContentViewBottomConstraint.isActive = shouldEnableConstraint
      })
    }

    return geometry
  }

}
