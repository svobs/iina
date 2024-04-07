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

  /// Set window size when info available, or video size changed. Mostly called after receiving `video-reconfig` msg
  func applyVidGeo(_ newVidGeo: VideoGeometry) {
    dispatchPrecondition(condition: .onQueue(player.mpv.queue))

    guard newVidGeo.hasValidSize else { return }

    let oldVidGeo = player.info.videoGeo
    // Update cached values for use elsewhere:
    player.info.videoGeo = newVidGeo

    // Get this in the mpv thread to avoid race condition
    let justOpenedFile = player.info.justOpenedFile
    let isRestoring = player.info.isRestoring

    if newVidGeo.totalRotation != player.info.currentMedia?.thumbnails?.rotationDegrees {
      player.reloadThumbnails(forMedia: player.info.currentMedia)
    }

    DispatchQueue.main.async { [self] in
      animationPipeline.submitZeroDuration({ [self] in
        updateVidGeo(from: oldVidGeo, to: newVidGeo, isRestoring: isRestoring, justOpenedFile: justOpenedFile)
      })
    }
  }

  // FIXME: refactor to use the videoScale provided (or change the flow). Currently it is ignored and then recalculated afterwards
  /// Only `applyVidGeo` should call this.
  private func updateVidGeo(from oldVidGeo: VideoGeometry, to newVidGeo: VideoGeometry, isRestoring: Bool, justOpenedFile: Bool) {
    guard !isClosing, !player.isStopping, !player.isStopped, !player.isShuttingDown else { return }

    guard !isRestoring else {
      log.verbose("[applyVidGeo] Restore is in progress; no op")
      return
    }

    guard let newVideoSizeACR = newVidGeo.videoSizeACR, let newVideoSizeRaw = newVidGeo.videoSizeRaw else {
      log.error("[applyVidGeo] Could not get videoSizeACR from mpv! Cancelling adjustment")
      return
    }

    let newVideoAspect = newVideoSizeACR.mpvAspect
    log.verbose("[applyVidGeo Start] VideoRaw:\(newVideoSizeRaw) VideoACR:\(newVideoSizeACR) AspectACR:\(newVideoAspect) Rotation:\(newVidGeo.totalRotation) Scale:\(newVidGeo.scale) restoring=\(isRestoring.yn)")

    if #available(macOS 10.12, *) {
      pip.aspectRatio = newVideoSizeACR
    }
    let currentLayout = currentLayout

    if currentLayout.mode == .musicMode {
      log.debug("[applyVidGeo M Apply] Player is in music mode; calling applyMusicModeGeo")
      /// Keep prev `windowFrame`. Just adjust height to fit new video aspect ratio
      /// (unless it doesn't fit in screen; see `applyMusicModeGeo`)
      let newGeometry = musicModeGeo.clone(videoAspect: newVideoAspect)
      applyMusicModeGeoInAnimationPipeline(newGeometry)
      return
    }

    // Windowed or full screen
    // FIXME: incorporate scale
    if isInitialSizeDone,
       let oldVideoSizeRaw = oldVidGeo.videoSizeRaw, oldVideoSizeRaw.equalTo(newVideoSizeRaw),
       let oldVideoSizeACR = oldVidGeo.videoSizeACR, oldVideoSizeACR.equalTo(newVideoSizeACR),
       // must check actual videoView as well - it's not completely concurrent and may have fallen out of date
       videoView.frame.size.mpvAspect == newVideoSizeACR.mpvAspect {
      log.debug("[applyVidGeo F Done] No change to prev video params. Taking no action")
      return
    }

    let windowGeo = windowedModeGeo.clone(videoAspect: newVideoSizeACR.mpvAspect)
    let justOpenedFileManually = justOpenedFile && !isInitialSizeDone

    let newWindowGeo: PWGeometry
    if let resizedGeo = resizeAfterFileOpen(justOpenedFile: justOpenedFile, windowGeo: windowGeo, videoSizeACR: newVideoSizeACR) {
      newWindowGeo = resizedGeo
    } else {
      if justOpenedFileManually {
        log.verbose("[applyVidGeo D-1] Just opened file manually with no resize strategy. Using windowedModeGeoLastClosed: \(PlayerWindowController.windowedModeGeoLastClosed)")
        newWindowGeo = currentLayout.convertWindowedModeGeometry(from: PlayerWindowController.windowedModeGeoLastClosed,
                                                                 videoAspect: newVideoSizeACR.mpvAspect, keepFullScreenDimensions: true)
      } else {
        // video size changed during playback
        newWindowGeo = resizeMinimallyToApplyVidGeometry(from: windowGeo, videoSizeACR: newVideoSizeACR)
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
    log.debug("[applyVidGeo D-2 Apply] Applying result (FS:\(isFullScreen.yn)) → videoSize:\(newWindowGeo.videoSize) newWindowFrame: \(newWindowGeo.windowFrame)")

    if currentLayout.mode == .windowed {
      applyWindowGeoInAnimationPipeline(newWindowGeo, duration: duration, timing: timing)

    } else if currentLayout.mode == .fullScreen {
      let fsGeo = currentLayout.buildFullScreenGeometry(inScreenID: newWindowGeo.screenID, videoAspect: newWindowGeo.videoAspect)

      animationPipeline.submit(IINAAnimation.Task(duration: duration, timing: timing, { [self] in
        // Make sure video constraints are up to date, even in full screen. Also remember that FS & windowed mode share same screen.
        log.verbose("[applyVidGeo Apply]: Updating videoView (FS), videoSize: \(fsGeo.videoSize)")
        videoView.apply(fsGeo)
      }))

    } else {
      // Update this for later use if not currently in windowed mode
      windowedModeGeo = newWindowGeo
    }

    // UI and slider
    log.debug("[applyVidGeo Done] Emitting windowSizeAdjusted")
    player.events.emit(.windowSizeAdjusted, data: newWindowGeo.windowFrame)
  }

  private func resizeAfterFileOpen(justOpenedFile: Bool, windowGeo: PWGeometry, videoSizeACR: NSSize) -> PWGeometry? {
    guard justOpenedFile else {
      // video size changed during playback
      log.verbose("[applyVidGeo C] justOpenedFile=NO → returning NO for shouldResize")
      return nil
    }

    // resize option applies
    let resizeTiming = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
    switch resizeTiming {
    case .always:
      log.verbose("[applyVidGeo C] justOpenedFile & resizeTiming='Always' → returning YES for shouldResize")
    case .onlyWhenOpen:
      log.verbose("[applyVidGeo C] justOpenedFile & resizeTiming='OnlyWhenOpen' → returning justOpenedFile (\(justOpenedFile.yesno)) for shouldResize")
      guard justOpenedFile else {
        return nil
      }
    case .never:
      log.verbose("[applyVidGeo C] justOpenedFile & resizeTiming='Never' → returning NO for shouldResize")
      return nil
    }

    let screenID = player.isInMiniPlayer ? musicModeGeo.screenID : windowedModeGeo.screenID
    let screenVisibleFrame = NSScreen.getScreenOrDefault(screenID: screenID).visibleFrame
    var newVideoSize = windowGeo.videoSize

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
        log.verbose("[applyVidGeo C-3] Applying mpv \(mpvGeometry) within screen \(screenVisibleFrame)")
        return windowGeo.apply(mpvGeometry: mpvGeometry, desiredWindowSize: preferredGeo.windowFrame.size)
      } else {
        log.debug("[applyVidGeo C-5] No mpv geometry found. Will fall back to default scheme")
        return nil
      }
    case .simpleVideoSizeMultiple:
      let resizeWindowStrategy: Preference.ResizeWindowOption = Preference.enum(for: .resizeWindowOption)
      if resizeWindowStrategy == .fitScreen {
        log.verbose("[applyVidGeo C-4] ResizeWindowOption=FitToScreen. Using screenFrame \(screenVisibleFrame)")
        /// When opening a new window and sizing it to match the video, do not add unnecessary margins around video,
        /// even if `lockViewportToVideoSize` is enabled
        let forceLockViewportToVideo = isInitialSizeDone ? nil : true
        return windowGeo.scaleViewport(to: screenVisibleFrame.size, fitOption: .centerInVisibleScreen,
                                       lockViewportToVideoSize: forceLockViewportToVideo)
      } else {
        let resizeRatio = resizeWindowStrategy.ratio
        newVideoSize = videoSizeACR.multiply(CGFloat(resizeRatio))
        log.verbose("[applyVidGeo C-2] Applied resizeRatio (\(resizeRatio)) to newVideoSize → \(newVideoSize)")
        let forceLockViewportToVideo = isInitialSizeDone ? nil : true
        return windowGeo.scaleVideo(to: newVideoSize, fitOption: .centerInVisibleScreen, lockViewportToVideoSize: forceLockViewportToVideo)
      }
    }
  }

  private func resizeMinimallyToApplyVidGeometry(from windowGeo: PWGeometry,
                                                 videoSizeACR: NSSize) -> PWGeometry {
    // User is navigating in playlist. retain same window width.
    // This often isn't possible for vertical videos, which will end up shrinking the width.
    // So try to remember the preferred width so it can be restored when possible
    var desiredViewportSize = windowGeo.viewportSize

    if Preference.bool(for: .lockViewportToVideoSize) {
      if let intendedViewportSize = player.info.intendedViewportSize  {
        // Just use existing size in this case:
        desiredViewportSize = intendedViewportSize
        log.verbose("[applyVidGeo D-2] Using intendedViewportSize \(intendedViewportSize)")
      }

      let minNewViewportHeight = round(desiredViewportSize.width / videoSizeACR.mpvAspect)
      if desiredViewportSize.height < minNewViewportHeight {
        // Try to increase height if possible, though it may still be shrunk to fit screen
        desiredViewportSize = NSSize(width: desiredViewportSize.width, height: minNewViewportHeight)
      }
    }

    log.verbose("[applyVidGeo D-3] Minimal resize: applying desiredViewportSize \(desiredViewportSize)")
    return windowGeo.scaleViewport(to: desiredViewportSize)
  }

  // MARK: - Window geometry functions

  func setVideoScale(_ desiredVideoScale: CGFloat) {
    guard let window = window else { return }
    let currentLayout = currentLayout
    guard currentLayout.mode == .windowed || currentLayout.mode == .musicMode else { return }

    guard let videoSizeACR = player.info.videoGeo.videoSizeACR else {
      log.error("SetWindowScale failed: could not get videoSizeACR")
      return
    }

    var desiredVideoSize = NSSize(width: round(videoSizeACR.width * desiredVideoScale),
                                  height: round(videoSizeACR.height * desiredVideoScale))

    log.verbose("SetVideoScale: requested scale=\(desiredVideoScale)x, videoSizeACR=\(videoSizeACR) → desiredVideoSize=\(desiredVideoSize)")

    // TODO
    if false && Preference.bool(for: .usePhysicalResolution) {
      desiredVideoSize = window.convertFromBacking(NSRect(origin: window.frame.origin, size: desiredVideoSize)).size
      log.verbose("SetWindowScale: converted desiredVideoSize to physical resolution: \(desiredVideoSize)")
    }

    switch currentLayout.mode {
    case .windowed:
      let newGeoUnconstrained = windowedModeGeo.scaleVideo(to: desiredVideoSize, fitOption: .noConstraints, mode: currentLayout.mode)
      // User has actively resized the video. Assume this is the new preferred resolution
      player.info.intendedViewportSize = newGeoUnconstrained.viewportSize

      let newGeometry = newGeoUnconstrained.refit(.keepInVisibleScreen)
      log.verbose("SetVideoScale: calling applyWindowGeo")
      applyWindowGeoInAnimationPipeline(newGeometry)
    case .musicMode:
      // will return nil if video is not visible
      guard let newMusicModeGeometry = musicModeGeo.scaleVideo(to: desiredVideoSize) else { return }
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
  func resizeViewport(to desiredViewportSize: CGSize? = nil, centerOnScreen: Bool = false) {
    guard currentLayout.mode == .windowed || currentLayout.mode == .musicMode else { return }
    guard let window else { return }

    switch currentLayout.mode {
    case .windowed:
      let newGeoUnconstrained = windowedModeGeo.clone(windowFrame: window.frame).scaleViewport(to: desiredViewportSize, fitOption: .noConstraints)
      // User has actively resized the video. Assume this is the new preferred resolution
      player.info.intendedViewportSize = newGeoUnconstrained.viewportSize

      let fitOption: ScreenFitOption = centerOnScreen ? .centerInVisibleScreen : .keepInVisibleScreen
      let newGeometry = newGeoUnconstrained.refit(fitOption)
      log.verbose("Calling applyWindowGeo from resizeViewport (center=\(centerOnScreen.yn)), to: \(newGeometry.windowFrame)")
      applyWindowGeoInAnimationPipeline(newGeometry)
    case .musicMode:
      /// In music mode, `viewportSize==videoSize` always. Will get `nil` here if video is not visible
      guard let newMusicModeGeometry = musicModeGeo.clone(windowFrame: window.frame).scaleVideo(to: desiredViewportSize) else { return }
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
      currentViewportSize = windowedModeGeo.clone(windowFrame: window.frame).viewportSize
    case .musicMode:
      guard let viewportSize = musicModeGeo.clone(windowFrame: window.frame).viewportSize else { return }
      currentViewportSize = viewportSize
    default:
      return
    }
    let heightStep = widthStep / currentViewportSize.mpvAspect
    let desiredViewportSize = CGSize(width: currentViewportSize.width + widthStep, height: currentViewportSize.height + heightStep)
    log.verbose("Incrementing viewport width by \(widthStep), to desired size \(desiredViewportSize)")
    resizeViewport(to: desiredViewportSize)
  }

  /// Updates the appropriate in-memory cached geometry (based on the current window mode) using the current window & view frames.
  /// Param `updatePreferredSizeAlso` only applies to `.windowed` mode.
  func updateCachedGeometry(updateMPVWindowScale: Bool = false) {
    guard !currentLayout.isFullScreen, !player.info.isRestoring else {
      log.verbose("Not updating cached geometry: isFS=\(currentLayout.isFullScreen.yn), isRestoring=\(player.info.isRestoring)")
      return
    }

    var ticket: Int = 0
    $updateCachedGeometryTicketCounter.withLock {
      $0 += 1
      ticket = $0
    }

    animationPipeline.submitZeroDuration({ [self] in
      guard ticket == updateCachedGeometryTicketCounter else { return }
      log.verbose("Updating cached \(currentLayout.mode) geometry from current window (tkt \(ticket))")
      let currentLayout = currentLayout

      guard let window else { return }

      switch currentLayout.mode {
      case .windowed, .windowedInteractive:
        // Use previous geometry's aspect. This method should never be called if aspect is changing - that should be set elsewhere.
        // This method should only be called for changes to windowFrame (origin or size)
        let geo = currentLayout.buildGeometry(windowFrame: window.frame, screenID: bestScreen.screenID, videoAspect: player.info.videoAspect)
        assert(windowedModeGeo.videoAspect == geo.videoAspect, "windowedMode videoAspect (\(windowedModeGeo.videoAspect)) != new videoAspect (\(geo.videoAspect))")
        windowedModeGeo = geo
        if updateMPVWindowScale {
          player.updateMPVWindowScale(using: geo)
        }
        player.saveState()
      case .musicMode:
        miniPlayer.saveCurrentPlaylistHeightToPrefs()
        musicModeGeo = musicModeGeo.clone(windowFrame: window.frame, screenID: bestScreen.screenID)
        if updateMPVWindowScale {
          player.updateMPVWindowScale(using: musicModeGeo.toPWGeometry())
        }
        player.saveState()
      case .fullScreen, .fullScreenInteractive:
        return  // will never get here; see guard above
      }

    })
  }

  /// Encapsulates logic for `windowWillResize`, but specfically for windowed modes
  func resizeWindow(_ window: NSWindow, to requestedSize: NSSize) -> PWGeometry {
    let currentLayout = currentLayout
    assert(currentLayout.isWindowed, "Trying to resize in windowed mode but current mode is unexpected: \(currentLayout.mode)")
    let currentGeometry: PWGeometry
    switch currentLayout.spec.mode {
    case .windowed, .windowedInteractive:
      currentGeometry = windowedModeGeo.clone(windowFrame: window.frame)
    default:
      log.error("WinWillResize: requested mode is invalid: \(currentLayout.spec.mode). Will fall back to windowedModeGeo")
      return windowedModeGeo
    }
    assert(currentGeometry.mode == currentLayout.mode)

    guard !denyNextWindowResize else {
      log.verbose("WinWillResize: denying this resize; will stay at \(currentGeometry.windowFrame.size)")
      denyNextWindowResize = false
      return currentGeometry
    }

    guard !player.info.isRestoring else {
      log.error("WinWillResize was fired before restore was complete! Returning existing geometry: \(currentGeometry.windowFrame.size)")
      return currentGeometry
    }

    let intendedGeo: PWGeometry
    // Need to resize window to match video aspect ratio, while taking into account any outside panels.
    let lockViewportToVideoSize = Preference.bool(for: .lockViewportToVideoSize) || currentLayout.mode.alwaysLockViewportToVideoSize
    if lockViewportToVideoSize && window.inLiveResize {
        /// Notes on the trickiness of live window resize:
        /// 1. We need to decide whether to (A) keep the width fixed, and resize the height, or (B) keep the height fixed, and resize the width.
        /// "A" works well when the user grabs the top or bottom sides of the window, but will not allow resizing if the user grabs the left
        /// or right sides. Similarly, "B" works with left or right sides, but will not work with top or bottom.
        /// 2. We can make all 4 sides allow resizing by first checking if the user is requesting a different height: if yes, use "B";
        /// and if no, use "A".
        /// 3. Unfortunately (2) causes resize from the corners to jump all over the place, because in that case either height or width will change
        /// in small increments (depending on how fast the user moves the cursor) but this will result in a different choice between "A" or "B" schemes
        /// each time, with very different answers, which causes the jumpiness. In this case either scheme will work fine, just as long as we stick
        /// to the same scheme for the whole resize. So to fix this, we add `isLiveResizingWidth`, and once set, stick to scheme "B".
        if isLiveResizingWidth == nil {
          if currentGeometry.windowFrame.height != requestedSize.height {
            isLiveResizingWidth = false
          } else if currentGeometry.windowFrame.width != requestedSize.width {
            isLiveResizingWidth = true
          }
        }
        log.verbose("WinWillResize: PREV:\(currentGeometry.windowFrame.size), REQ:\(requestedSize) choseWidth:\(isLiveResizingWidth?.yesno ?? "nil")")

        let nonViewportAreaSize = currentGeometry.windowFrame.size.subtract(currentGeometry.viewportSize)
        let requestedViewportSize = requestedSize.subtract(nonViewportAreaSize)

        if isLiveResizingWidth ?? true {
          // Option A: resize height based on requested width
          let resizedWidthViewportSize = NSSize(width: requestedViewportSize.width,
                                                height: round(requestedViewportSize.width / currentGeometry.videoAspect))
          intendedGeo = currentGeometry.scaleViewport(to: resizedWidthViewportSize, fitOption: .noConstraints)
        } else {
          // Option B: resize width based on requested height
          let resizedHeightViewportSize = NSSize(width: round(requestedViewportSize.height * currentGeometry.videoAspect),
                                                 height: requestedViewportSize.height)
          intendedGeo = currentGeometry.scaleViewport(to: resizedHeightViewportSize, fitOption: .noConstraints)
        }
    } else {
      if !window.inLiveResize {  // Only applies to system requests to resize (not user resize)
        let minWindowSize = currentGeometry.minWindowSize(mode: currentLayout.mode)
        if (requestedSize.width < minWindowSize.width) || (requestedSize.height < minWindowSize.height) {
          // Sending the current size seems to work much better with accessibilty requests
          // than trying to change to the min size
          log.verbose("WinWillResize: requested smaller than min (\(minWindowSize.width) x \(minWindowSize.height)); returning existing \(currentGeometry.windowFrame.size)")
          return currentGeometry
        }
      }
      /// If `!inLiveResize`: resize request is not coming from the user. Could be BetterTouchTool, Retangle, or some window manager, or the OS.
      /// These tools seem to expect that both dimensions of the returned size are less than the requested dimensions, so check for this.
      /// If `lockViewportToVideoSize && !inLiveResize`: scale window to requested size; `refit()` below will constrain as needed.
      intendedGeo = currentGeometry.scaleWindow(to: requestedSize, fitOption: .noConstraints)
    }

    if currentLayout.mode == .windowed && window.inLiveResize {
      // User has resized the video. Assume this is the new preferred resolution until told otherwise. Do not constrain.
      player.info.intendedViewportSize = intendedGeo.viewportSize
    }

    let chosenGeometry = intendedGeo.refit(currentGeometry.fitOption)
    log.verbose("WinWillResize isLive:\(window.inLiveResize.yn) req:\(requestedSize) lockViewport:Y prevVideoSize:\(currentGeometry.videoSize) returning:\(chosenGeometry.windowFrame.size)")

    return chosenGeometry
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

    defer {
      // Do not cache supplied geometry. Assume caller will handle it.
      if !isFullScreen, newGeometry == nil {
        updateCachedGeometry(updateMPVWindowScale: currentLayout.mode == .windowed)
        player.saveState()
      }
    }

    IINAAnimation.disableAnimation {
      if let newGeometry {
        log.verbose("ApplyWindowResize: \(newGeometry)")
        if !isFullScreen {
          player.window.setFrameImmediately(newGeometry.windowFrame, animate: false)
        }
        // Make sure this is up-to-date
        videoView.apply(newGeometry)
      }

      // These may no longer be aligned correctly. Just hide them
      thumbnailPeekView.isHidden = true
      timePositionHoverLabel.isHidden = true

      if currentLayout.isMusicMode {
        // Re-evaluate space requirements for labels. May need to start scrolling.
        // Will also update saved state
        miniPlayer.windowDidResize()
      }

      // Update floating control bar position if applicable
      updateFloatingOSCAfterWindowDidResize(usingGeometry: newGeometry)

      if currentLayout.isInteractiveMode {
        // Update interactive mode selectable box size. Origin is relative to viewport origin
        cropSettingsView?.cropBoxView.resized(with: videoView.bounds)
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

    updateOSDTopOffset(geometry, isLegacyFullScreen: true)
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
    let task = buildApplyWindowGeoTask(newGeometry, duration: duration, timing: timing)
    animationPipeline.submit(task)
  }

  func buildApplyWindowGeoTask(_ newGeometry: PWGeometry, duration: CGFloat = IINAAnimation.DefaultDuration,
                               timing: CAMediaTimingFunctionName = .easeInEaseOut) -> IINAAnimation.Task {
    assert(currentLayout.spec.mode == .windowed, "applyWindowGeo called outside windowed mode! (found: \(currentLayout.spec.mode))")
    return IINAAnimation.Task(duration: duration, timing: timing, { [self] in
      log.verbose("ApplyWindowGeo: windowFrame: \(newGeometry.windowFrame), videoAspect: \(newGeometry.videoAspect)")
      if !isWindowHidden {
        player.window.setFrameImmediately(newGeometry.windowFrame)
      }
      // Make sure this is up-to-date
      videoView.apply(newGeometry)
      windowedModeGeo = newGeometry

      log.verbose("ApplyWindowGeo: Calling updateMPVWindowScale, videoSize: \(newGeometry.videoSize)")
      player.updateMPVWindowScale(using: newGeometry)
      player.saveState()
    })
  }

  /// Same as `applyMusicModeGeo`, but enqueues inside an `IINAAnimation.Task` for a nice smooth animation
  func applyMusicModeGeoInAnimationPipeline(_ geometry: MusicModeGeometry, setFrame: Bool = true, animate: Bool = true, updateCache: Bool = true) {
    animationPipeline.submit(IINAAnimation.Task(timing: .easeInEaseOut, { [self] in
      applyMusicModeGeo(geometry)
    }))
  }

  /// Updates the current window and its subviews to match the given `MusicModeGeometry`.
  /// If `updateCache` is true, updates `musicModeGeo` and saves player state.
  @discardableResult
  func applyMusicModeGeo(_ geometry: MusicModeGeometry, setFrame: Bool = true, animate: Bool = true, updateCache: Bool = true) -> MusicModeGeometry {
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

    if hasChange {
      if setFrame {
        player.window.setFrameImmediately(geometry.windowFrame, animate: animate)
      }
      /// Make sure to call `apply` AFTER `updateVideoViewVisibilityConstraints`:
      miniPlayer.updateVideoViewVisibilityConstraints(isVideoVisible: geometry.isVideoVisible)
      updateBottomBarHeight(to: geometry.bottomBarHeight, bottomBarPlacement: .outsideViewport)
      videoView.apply(geometry.toPWGeometry())
    } else {
      log.verbose("Not updating music mode windowFrame or constraints - no changes needed")
    }

    if updateCache {
      musicModeGeo = geometry
      player.saveState()
    }

    /// For the case where video is hidden but playlist is shown, AppKit won't allow the window's height to be changed by the user
    /// unless we remove this constraint from the the window's `contentView`. For all other situations this constraint should be active.
    /// Need to execute this in its own task so that other animations are not affected.
    let shouldDisableConstraint = !geometry.isVideoVisible && geometry.isPlaylistVisible
    animationPipeline.submitZeroDuration({ [self] in
      viewportBottomOffsetFromContentViewBottomConstraint.isActive = !shouldDisableConstraint
    })

    return geometry
  }

}
