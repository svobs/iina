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
  func applyVidParams(newParams videoParams: MPVVideoParams) {
    dispatchPrecondition(condition: .onQueue(player.mpv.queue))

    guard videoParams.hasValidSize else { return }

    let oldVideoParams = player.info.videoParams
    // Update cached values for use elsewhere:
    player.info.videoParams = videoParams

    // Get this in the mpv thread to avoid race condition
    let justOpenedFile = player.info.justOpenedFile
    let isRestoring = player.info.isRestoring

    if videoParams.totalRotation != player.info.currentMediaThumbnails?.rotationDegrees {
      player.reloadThumbnails()
    }

    DispatchQueue.main.async { [self] in
      animationPipeline.submitZeroDuration({ [self] in
        applyVidParams(newParams: videoParams, oldParams: oldVideoParams, isRestoring: isRestoring, justOpenedFile: justOpenedFile)
      })
    }
  }

  /// Only `applyVidParams` should call this.
  private func applyVidParams(newParams videoParams: MPVVideoParams, oldParams oldVideoParams: MPVVideoParams, isRestoring: Bool, justOpenedFile: Bool) {
    guard let videoSizeACR = videoParams.videoSizeACR else {
      log.error("[applyVidParams] Could not get videoSizeACR from mpv! Cancelling adjustment")
      return
    }

    let newVideoAspect = videoSizeACR.mpvAspect
    log.verbose("[applyVidParams Start] VideoRaw:\(videoParams.videoSizeRaw?.debugDescription ?? "nil") VideoACR:\(videoSizeACR) AspectACR:\(newVideoAspect) Rotation:\(videoParams.totalRotation) Scale:\(videoParams.videoScale)")

    if #available(macOS 10.12, *) {
      pip.aspectRatio = videoSizeACR
    }
    let screen = bestScreen
    let currentLayout = currentLayout

    if isInInteractiveMode, let cropController = self.cropSettingsView, cropController.cropBoxView.didSubmit {
      /// Interactive mode after submit: finish crop submission and exit interactive mode
      cropController.cropBoxView.didSubmit = false
      let uncroppedVideoSize = cropController.cropBoxView.actualSize
      let cropboxUnscaled = NSRect(x: cropController.cropx, y: cropController.cropyFlippedForMac,
                                   width: cropController.cropw, height: cropController.croph)

      log.verbose("[applyVidParams G] Looks like crop was submitted. Exiting interactive mode")
      exitInteractiveMode(cropVideoFrom: uncroppedVideoSize, to: cropboxUnscaled)
      // fall through

    } else if currentLayout.canEnterInteractiveMode, let prevCropFilter = player.info.videoFiltersDisabled[Constants.FilterLabel.crop] {
      // Not yet in interactive mode, but the active crop was just disabled prior to entering it,
      // so that full video can be seen during interactive mode

      let prevCropbox = prevCropFilter.cropRect(origVideoSize: videoSizeACR, flipY: true)
      log.verbose("[applyVidParams E1] Found a disabled crop filter: \(prevCropFilter.stringFormat.quoted). Will enter interactive crop.")
      log.verbose("[applyVidParams E1] VideoDisplayRotatedSize: \(videoSizeACR), PrevCropbox: \(prevCropbox)")

      player.info.videoParams = videoParams
      // Update the cached objects even if not in windowed mode
      windowedModeGeo = windowedModeGeo.uncropVideo(videoSizeACR: videoSizeACR, cropbox: prevCropbox, videoScale: videoParams.videoScale)

      if currentLayout.mode == .windowed {
        let uncroppedWindowedGeo = windowedModeGeo.uncropVideo(videoSizeACR: videoSizeACR, cropbox: prevCropbox, videoScale: videoParams.videoScale)
        applyWindowGeometry(uncroppedWindowedGeo)
      } else if currentLayout.mode != .fullScreen {
        assert(false, "Bad state! Invalid mode: \(currentLayout.spec.mode)")
        return
      }
      enterInteractiveMode(.crop)

    } else if isRestoring {
      if isInInteractiveMode {
        /// If restoring into interactive mode, we didn't have `videoSizeACR` while doing layout. Add it now (if needed)
        let videoSize: NSSize
        if currentLayout.isFullScreen {
          let fsInteractiveModeGeo = currentLayout.buildFullScreenGeometry(inside: screen, videoAspect: newVideoAspect)
          videoSize = fsInteractiveModeGeo.videoSize
          interactiveModeGeo = fsInteractiveModeGeo
        } else { // windowed
          videoSize = interactiveModeGeo?.videoSize ?? windowedModeGeo.videoSize
        }
        log.debug("[applyVidParams F-1] Restoring crop box origVideoSize=\(videoSizeACR), videoSize=\(videoSize)")
        addOrReplaceCropBoxSelection(origVideoSize: videoSizeACR, croppedVideoSize: videoSize)

      } else {
        log.verbose("[applyVidParams A Done] Restore is in progress; ignoring mpv video-reconfig")
      }
      return

    } else if currentLayout.mode == .musicMode {
      log.debug("[applyVidParams M Apply] Player is in music mode; calling applyMusicModeGeometry")
      /// Keep prev `windowFrame`. Just adjust height to fit new video aspect ratio
      /// (unless it doesn't fit in screen; see `applyMusicModeGeometry()`)
      let newGeometry = musicModeGeo.clone(videoAspect: newVideoAspect)
      applyMusicModeGeometryInAnimationPipeline(newGeometry)

    } else { // Windowed or full screen
      if let oldVideoSizeRaw = oldVideoParams.videoSizeRaw, let newVideoSizeRaw = videoParams.videoSizeRaw, oldVideoSizeRaw.equalTo(newVideoSizeRaw),
         let oldVideoSizeACR = oldVideoParams.videoSizeACR, oldVideoSizeACR.equalTo(videoSizeACR) {
        log.debug("[applyVidParams F Done] No change to prev video params. Taking no action")
        return
      }

      let windowGeo = windowedModeGeo.clone(videoAspect: videoSizeACR.mpvAspect)

      let newWindowGeo: WinGeometry
      if let resizedGeo = resizeAfterFileOpen(justOpenedFile: justOpenedFile, windowGeo: windowGeo, videoSizeACR: videoSizeACR) {
        newWindowGeo = resizedGeo
      } else {
        let justOpenedFileManually = justOpenedFile && !isInitialSizeDone
        if justOpenedFileManually {
          log.verbose("[applyVidParams D-1] Just opened file manually with no resize strategy. Using windowedModeGeoLastClosed: \(PlayerWindowController.windowedModeGeoLastClosed)")
          newWindowGeo = currentLayout.convertWindowedModeGeometry(from: PlayerWindowController.windowedModeGeoLastClosed,
                                                                   videoAspect: videoSizeACR.mpvAspect)
        } else {
          // video size changed during playback
          newWindowGeo = resizeMinimallyAfterVideoReconfig(from: windowGeo, videoSizeACR: videoSizeACR)
        }
      }

      var duration = IINAAnimation.VideoReconfigDuration
      if !isInitialSizeDone {
        // Just opened manually. Use a longer duration for this one, because the window starts small and will zoom into place.
        isInitialSizeDone = true
        duration = IINAAnimation.DefaultDuration
      }
      /// Finally call `setFrame()`
      log.debug("[applyVidParams D-2 Apply] Applying result (FS:\(isFullScreen.yn)) → videoSize:\(newWindowGeo.videoSize) newWindowFrame: \(newWindowGeo.windowFrame)")

      if currentLayout.mode == .windowed {
        applyWindowGeometryInAnimationPipeline(newWindowGeo, duration: duration)
      } else if currentLayout.mode == .fullScreen {
        // TODO: break FS into separate function
        applyWindowGeometryInAnimationPipeline(newWindowGeo)
      } else {
        // Update this for later use if not currently in windowed mode
        windowedModeGeo = newWindowGeo
      }

      // UI and slider
      log.debug("[applyVidParams Done] Emitting windowSizeAdjusted")
      player.events.emit(.windowSizeAdjusted, data: newWindowGeo.windowFrame)
    }
  }

  private func resizeAfterFileOpen(justOpenedFile: Bool, windowGeo: WinGeometry, videoSizeACR: NSSize) -> WinGeometry? {
    guard justOpenedFile else {
      // video size changed during playback
      log.verbose("[applyVidParams C] justOpenedFile=NO → returning NO for shouldResize")
      return nil
    }

    // resize option applies
    let resizeTiming = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
    switch resizeTiming {
    case .always:
      log.verbose("[applyVidParams C] justOpenedFile & resizeTiming='Always' → returning YES for shouldResize")
    case .onlyWhenOpen:
      log.verbose("[applyVidParams C] justOpenedFile & resizeTiming='OnlyWhenOpen' → returning justOpenedFile (\(justOpenedFile.yesno)) for shouldResize")
      guard justOpenedFile else {
        return nil
      }
    case .never:
      log.verbose("[applyVidParams C] justOpenedFile & resizeTiming='Never' → returning NO for shouldResize")
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
          log.verbose("[applyVidParams C-6] Using intendedViewportSize \(intendedViewportSize)")
          preferredGeo = windowGeo.scaleViewport(to: intendedViewportSize)
        }
        log.verbose("[applyVidParams C-3] Applying mpv \(mpvGeometry) within screen \(screenVisibleFrame)")
        return windowGeo.apply(mpvGeometry: mpvGeometry, desiredWindowSize: preferredGeo.windowFrame.size)
      } else {
        log.debug("[applyVidParams C-5] No mpv geometry found. Will fall back to default scheme")
        return nil
      }
    case .simpleVideoSizeMultiple:
      let resizeWindowStrategy: Preference.ResizeWindowOption = Preference.enum(for: .resizeWindowOption)
      if resizeWindowStrategy == .fitScreen {
        log.verbose("[applyVidParams C-4] ResizeWindowOption=FitToScreen. Using screenFrame \(screenVisibleFrame)")
        /// When opening a new window and sizing it to match the video, do not add unnecessary margins around video,
        /// even if `lockViewportToVideoSize` is enabled
        let forceLockViewportToVideo = isInitialSizeDone ? nil : true
        return windowGeo.scaleViewport(to: screenVisibleFrame.size, fitOption: .centerInVisibleScreen,
                                       lockViewportToVideoSize: forceLockViewportToVideo)
      } else {
        let resizeRatio = resizeWindowStrategy.ratio
        newVideoSize = videoSizeACR.multiply(CGFloat(resizeRatio))
        log.verbose("[applyVidParams C-2] Applied resizeRatio (\(resizeRatio)) to newVideoSize → \(newVideoSize)")
        let forceLockViewportToVideo = isInitialSizeDone ? nil : true
        return windowGeo.scaleVideo(to: newVideoSize, fitOption: .centerInVisibleScreen, lockViewportToVideoSize: forceLockViewportToVideo)
      }
    }
  }

  private func resizeMinimallyAfterVideoReconfig(from windowGeo: WinGeometry,
                                                 videoSizeACR: NSSize) -> WinGeometry {
    // User is navigating in playlist. retain same window width.
    // This often isn't possible for vertical videos, which will end up shrinking the width.
    // So try to remember the preferred width so it can be restored when possible
    var desiredViewportSize = windowGeo.viewportSize

    if Preference.bool(for: .lockViewportToVideoSize) {
      if let intendedViewportSize = player.info.intendedViewportSize  {
        // Just use existing size in this case:
        desiredViewportSize = intendedViewportSize
        log.verbose("[applyVidParams D-2] Using intendedViewportSize \(intendedViewportSize)")
      }

      let minNewViewportHeight = round(desiredViewportSize.width / videoSizeACR.mpvAspect)
      if desiredViewportSize.height < minNewViewportHeight {
        // Try to increase height if possible, though it may still be shrunk to fit screen
        desiredViewportSize = NSSize(width: desiredViewportSize.width, height: minNewViewportHeight)
      }
    }

    log.verbose("[applyVidParams D-3] Minimal resize: applying desiredViewportSize \(desiredViewportSize)")
    return windowGeo.scaleViewport(to: desiredViewportSize)
  }

  // MARK: - Window geometry functions

  func setVideoScale(_ desiredVideoScale: CGFloat) {
    guard let window = window else { return }
    let currentLayout = currentLayout
    guard currentLayout.mode == .windowed || currentLayout.mode == .musicMode else { return }

    guard let videoSizeACR = player.info.videoParams.videoSizeACR else {
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
      log.verbose("SetVideoScale: calling applyWindowGeometry")
      applyWindowGeometryInAnimationPipeline(newGeometry)
    case .musicMode:
      // will return nil if video is not visible
      guard let newMusicModeGeometry = musicModeGeo.scaleVideo(to: desiredVideoSize) else { return }
      log.verbose("SetVideoScale: calling applyMusicModeGeometry")
      applyMusicModeGeometryInAnimationPipeline(newMusicModeGeometry)
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
      log.verbose("Calling applyWindowGeometry from resizeViewport (center=\(centerOnScreen.yn)), to: \(newGeometry.windowFrame)")
      applyWindowGeometryInAnimationPipeline(newGeometry)
    case .musicMode:
      /// In music mode, `viewportSize==videoSize` always. Will get `nil` here if video is not visible
      guard let newMusicModeGeometry = musicModeGeo.clone(windowFrame: window.frame).scaleVideo(to: desiredViewportSize) else { return }
      log.verbose("Calling applyMusicModeGeometry from resizeViewport, to: \(newMusicModeGeometry.windowFrame)")
      applyMusicModeGeometryInAnimationPipeline(newMusicModeGeometry)
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
        let geo = currentLayout.buildGeometry(windowFrame: window.frame, screenID: bestScreen.screenID, videoAspect: windowedModeGeo.videoAspect)
        if currentLayout.mode == .windowedInteractive {
          assert(interactiveModeGeo?.videoAspect == geo.videoAspect)
          interactiveModeGeo = geo
        } else {
          assert(currentLayout.mode == .windowed)
          assert(windowedModeGeo.videoAspect == geo.videoAspect)
          windowedModeGeo = geo
        }
        if updateMPVWindowScale {
          player.updateMPVWindowScale(using: geo)
        }
        player.saveState()
      case .musicMode:
        musicModeGeo = musicModeGeo.clone(windowFrame: window.frame, screenID: bestScreen.screenID)
        if updateMPVWindowScale {
          player.updateMPVWindowScale(using: musicModeGeo.toWinGeometry())
        }
        player.saveState()
      case .fullScreen, .fullScreenInteractive:
        return  // will never get here; see guard above
      }

    })
  }

  /// Encapsulates logic for `windowWillResize`, but specfically for windowed modes
  func resizeWindow(_ window: NSWindow, to requestedSize: NSSize) -> WinGeometry {
    let currentLayout = currentLayout
    assert(currentLayout.isWindowed, "Trying to resize in windowed mode but current mode is unexpected: \(currentLayout.mode)")
    let currentGeometry: WinGeometry
    switch currentLayout.spec.mode {
    case .windowed:
      currentGeometry = windowedModeGeo.clone(windowFrame: window.frame)
    case .windowedInteractive:
      if let interactiveModeGeo {
        currentGeometry = interactiveModeGeo.clone(windowFrame: window.frame)
      } else {
        log.error("WinWillResize: could not find interactiveModeGeo; will substitute windowedModeGeo")
        let updatedWindowedModeGeometry = windowedModeGeo.clone(windowFrame: window.frame)
        currentGeometry = updatedWindowedModeGeometry.toInteractiveMode()
      }
    default:
      log.error("WinWillResize: requested mode is invalid: \(currentLayout.spec.mode). Will fall back to windowedModeGeo")
      return windowedModeGeo
    }

    assert(currentGeometry.mode == currentLayout.mode)

    if denyNextWindowResize {
      log.verbose("WinWillResize: denying this resize; will stay at \(currentGeometry.windowFrame.size)")
      denyNextWindowResize = false
      return currentGeometry
    }

    if player.info.isRestoring {
      guard let savedState = player.info.priorState else { return currentGeometry }

      if let savedLayoutSpec = savedState.layoutSpec {
        // If getting here, restore is in progress. Don't allow size changes, but don't worry
        // about whether the saved size is valid. It will be handled elsewhere.
        if savedLayoutSpec.mode == .musicMode, let savedMusicModeGeo = savedState.musicModeGeo {
          log.verbose("WinWillResize: denying request due to restore; returning saved musicMode size \(savedMusicModeGeo.windowFrame.size)")
          return savedMusicModeGeo.toWinGeometry()
        } else if savedLayoutSpec.mode == .windowed, let savedWindowedModeGeo = savedState.windowedModeGeo {
          log.verbose("WinWillResize: denying request due to restore; returning saved windowedMode size \(savedWindowedModeGeo.windowFrame.size)")
          return savedWindowedModeGeo
        }
      }
      log.error("WinWillResize: failed to restore window frame; returning existing: \(currentGeometry.windowFrame.size)")
      return currentGeometry
    }

    if !window.inLiveResize {  // Only applies to system requests to resize (not user resize)
      let minWindowWidth = currentGeometry.minWindowWidth(mode: currentLayout.mode)
      let minWindowHeight = currentGeometry.minWindowHeight(mode: currentLayout.mode)
      if (requestedSize.width < minWindowWidth) || (requestedSize.height < minWindowHeight) {
        // Sending the current size seems to work much better with accessibilty requests
        // than trying to change to the min size
        log.verbose("WinWillResize: requested smaller than min (\(minWindowWidth) x \(minWindowHeight)); returning existing \(currentGeometry.windowFrame.size)")
        return currentGeometry
      }
    }

    // Need to resize window to match video aspect ratio, while taking into account any outside panels.
    let lockViewportToVideoSize = Preference.bool(for: .lockViewportToVideoSize) || currentLayout.mode.alwaysLockViewportToVideoSize
    if !lockViewportToVideoSize {
      // No need to resize window to match video aspect ratio.
      let intendedGeo = currentGeometry.scaleWindow(to: requestedSize, fitOption: .noConstraints)

      if currentLayout.mode == .windowed && window.inLiveResize {
        // User has resized the video. Assume this is the new preferred resolution until told otherwise. Do not constrain.
        player.info.intendedViewportSize = intendedGeo.viewportSize
      }
      return intendedGeo.refit(.keepInVisibleScreen)
    }

    // Option A: resize height based on requested width
    let widthDiff = requestedSize.width - currentGeometry.windowFrame.width
    let requestedVideoWidth = currentGeometry.videoSize.width + widthDiff
    let resizeFromWidthRequestedVideoSize = NSSize(width: requestedVideoWidth,
                                                   height: round(requestedVideoWidth / currentGeometry.videoAspect))
    let resizeFromWidthGeo = currentGeometry.scaleVideo(to: resizeFromWidthRequestedVideoSize)

    // Option B: resize width based on requested height
    let heightDiff = requestedSize.height - currentGeometry.windowFrame.height
    let requestedVideoHeight = currentGeometry.videoSize.height + heightDiff
    let resizeFromHeightRequestedVideoSize = NSSize(width: round(requestedVideoHeight * currentGeometry.videoAspect),
                                                    height: requestedVideoHeight)
    let resizeFromHeightGeo = currentGeometry.scaleVideo(to: resizeFromHeightRequestedVideoSize)

    let chosenGeometry: WinGeometry
    if window.inLiveResize {
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
      guard let isLiveResizingWidth else {
        return currentGeometry
      }
      log.verbose("WinWillResize: PREV:\(currentGeometry.windowFrame.size), REQ:\(requestedSize) WIDTH:\(resizeFromWidthGeo.windowFrame.size), HEIGHT:\(resizeFromHeightGeo.windowFrame.size), chose:\(isLiveResizingWidth ? "W" : "H")")

      if isLiveResizingWidth {
        chosenGeometry = resizeFromWidthGeo
      } else {
        chosenGeometry = resizeFromHeightGeo
      }

      if currentLayout.mode == .windowed {
        // User has resized the video. Assume this is the new preferred resolution until told otherwise.
        player.info.intendedViewportSize = chosenGeometry.viewportSize
      }
    } else {
      // Resize request is not coming from the user. Could be BetterTouchTool, Retangle, or some window manager, or the OS.
      // These tools seem to expect that both dimensions of the returned size are less than the requested dimensions, so check for this.

      if resizeFromWidthGeo.windowFrame.width <= requestedSize.width && resizeFromWidthGeo.windowFrame.height <= requestedSize.height {
        chosenGeometry = resizeFromWidthGeo
      } else {
        chosenGeometry = resizeFromHeightGeo
      }
    }
    log.verbose("WinWillResize isLive:\(window.inLiveResize.yn) req:\(requestedSize) lockViewport:Y prevVideoSize:\(currentGeometry.videoSize) returning:\(chosenGeometry.windowFrame.size)")

    // TODO: validate geometry
    return chosenGeometry
  }

  func updateFloatingOSCAfterWindowDidResize() {
    guard let window = window, currentLayout.oscPosition == .floating else { return }
    controlBarFloating.moveTo(centerRatioH: floatingOSCCenterRatioH,
                              originRatioV: floatingOSCOriginRatioV, layout: currentLayout, viewportSize: viewportView.frame.size)

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

  /// Set the window frame and if needed the content view frame to appropriately use the full screen.
  /// For screens that contain a camera housing the content view will be adjusted to not use that area of the screen.
  func applyLegacyFullScreenGeometry(_ geometry: WinGeometry) {
    guard let window = window else { return }
    let currentLayout = currentLayout
    if !currentLayout.isInteractiveMode {
      videoView.apply(geometry)
    }

    if currentLayout.hasFloatingOSC {
      controlBarFloating.moveTo(centerRatioH: floatingOSCCenterRatioH, originRatioV: floatingOSCOriginRatioV,
                                layout: currentLayout, viewportSize: geometry.viewportSize)
    }

    updateOSDTopOffset(geometry, isLegacyFullScreen: true)

    guard !geometry.windowFrame.equalTo(window.frame) else {
      log.verbose("No need to update windowFrame for legacyFullScreen - no change")
      return
    }

    log.verbose("Calling setFrame for legacyFullScreen, to \(geometry)")
    player.window.setFrameImmediately(geometry.windowFrame)
    let topBarHeight = currentLayout.topBarPlacement == .insideViewport ? geometry.insideTopBarHeight : geometry.outsideTopBarHeight
    updateTopBarHeight(to: topBarHeight, topBarPlacement: currentLayout.topBarPlacement, cameraHousingOffset: geometry.topMarginHeight)
  }

  /// Updates/redraws current `window.frame` and its internal views from `newGeometry`. Animated.
  /// Also updates cached `windowedModeGeo` and saves updated state.
  func applyWindowGeometryInAnimationPipeline(_ newGeometry: WinGeometry, duration: CGFloat = IINAAnimation.DefaultDuration) {
    var ticket: Int = 0
    $geoUpdateTicketCounter.withLock {
      $0 += 1
      ticket = $0
    }

    animationPipeline.submit(IINAAnimation.Task(duration: duration, timing: .easeInEaseOut, { [self] in
      guard ticket == geoUpdateTicketCounter else {
        return
      }
      log.verbose("ApplyWindowGeometry (tkt \(ticket)) windowFrame: \(newGeometry.windowFrame), videoAspect: \(newGeometry.videoAspect)")
      applyWindowGeometry(newGeometry)
    }))
  }

  // TODO: split this into separate windowed & FS
  func applyWindowGeometry(_ newGeometry: WinGeometry, setFrame: Bool = true) {
    let currentLayout = currentLayout
    switch currentLayout.spec.mode {

    case .musicMode, .windowedInteractive, .fullScreenInteractive:
      log.error("ApplyWindowGeometry is not used for \(currentLayout.spec.mode) mode")

    case .fullScreen:
      if setFrame {
        // Make sure video constraints are up to date, even in full screen. Also remember that FS & windowed mode share same screen.
        let fsGeo = currentLayout.buildFullScreenGeometry(inScreenID: newGeometry.screenID,
                                                          videoAspect: newGeometry.videoAspect)
        log.verbose("ApplyWindowGeometry: Updating videoView (FS), videoSize: \(fsGeo.videoSize)")
        videoView.apply(fsGeo)
      }

    case .windowed:
      if setFrame {
        if !isWindowHidden {
          player.window.setFrameImmediately(newGeometry.windowFrame)
        }
        // Make sure this is up-to-date
        videoView.apply(newGeometry)
        windowedModeGeo = newGeometry
      }
      log.verbose("ApplyWindowGeometry: Calling updateMPVWindowScale, videoSize: \(newGeometry.videoSize)")
      player.updateMPVWindowScale(using: newGeometry)
      player.saveState()
    }
  }

  /// For (1) pinch-to-zoom, (2) resizing outside sidebars when the whole window needs to be resized or moved.
  /// Not animated. Can be used in windowed mode or full screen modes. Can be used in music mode only if the playlist is hidden.
  func applyWindowGeometryForSpecialResize(_ newGeometry: WinGeometry) {
    log.verbose("ApplySpecialGeo: \(newGeometry)")
    let currentLayout = currentLayout
    // Need this if video is playing
    videoView.videoLayer.enterAsynchronousMode()

    IINAAnimation.disableAnimation{
      if !isFullScreen {
        player.window.setFrameImmediately(newGeometry.windowFrame, animate: false)
      }
      // Make sure this is up-to-date
      videoView.apply(newGeometry)

      // These will no longer be aligned correctly. Just hide them
      thumbnailPeekView.isHidden = true
      timePositionHoverLabel.isHidden = true

      if currentLayout.hasFloatingOSC {
        // Update floating control bar position
        controlBarFloating.moveTo(centerRatioH: floatingOSCCenterRatioH,
                                  originRatioV: floatingOSCOriginRatioV, layout: currentLayout, viewportSize: newGeometry.viewportSize)
      }
    }
  }

  /// Same as `applyMusicModeGeometry()`, but enqueues inside an `IINAAnimation.Task` for a nice smooth animation
  func applyMusicModeGeometryInAnimationPipeline(_ geometry: MusicModeGeometry, setFrame: Bool = true, animate: Bool = true, updateCache: Bool = true) {
    animationPipeline.submit(IINAAnimation.Task(timing: .easeInEaseOut, { [self] in
      applyMusicModeGeometry(geometry)
    }))
  }

  /// Updates the current window and its subviews to match the given `MusicModeGeometry`.
  /// If `updateCache` is true, updates `musicModeGeo` and saves player state.
  @discardableResult
  func applyMusicModeGeometry(_ geometry: MusicModeGeometry, setFrame: Bool = true, animate: Bool = true, updateCache: Bool = true) -> MusicModeGeometry {
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
      /// Make sure to call `apply` AFTER `applyVideoViewVisibilityConstraints`:
      miniPlayer.applyVideoViewVisibilityConstraints(isVideoVisible: geometry.isVideoVisible)
      updateBottomBarHeight(to: geometry.bottomBarHeight, bottomBarPlacement: .outsideViewport)
      videoView.apply(geometry.toWinGeometry())
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
