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
/*
  /// Encapsulates all the info needed to transition the window from `inputGeo` to `outputGeo`
  struct VideoGeoTransition {
    /// Name of transition. For debug logging.
    let name: String

    let inputGeo: VideoGeometry
    let outputGeo: VideoGeometry
    let showDefaultArt: Bool?

    let doAfter: (() -> Void)?

    // Other state which affects output:

    let playback: Playback
    let windowState: WindowStateAtFileOpen
    let currentMediaAudioStatus: PlaybackInfo.CurrentMediaAudioStatus

    var isRotating: Bool {
      inputGeo.totalRotation != outputGeo.totalRotation
    }

    var needsToReloadThumbnails: Bool {
      outputGeo.totalRotation != playback.thumbnails?.rotationDegrees
    }
  }*/

  /// If current media is file, this should be called after it is done loading.
  /// If current media is network resource, should be called immediately & show buffering msg.
  func applyVideoGeoAtFileOpen(_ ffMeta: FFVideoMeta? = nil, currentPlayback: Playback,
                               _ currentMediaAudioStatus: PlaybackInfo.CurrentMediaAudioStatus) {
    log.verbose("Calling applyVideoGeoTransform for opened file, vid=\(player.info.vid?.description ?? "nil")")

    let transform: VideoGeometry.Transform = { [self] videoGeo in
      guard player.state.isNotYet(.stopping) else {
        log.verbose("[applyVideoGeoTransform] File loaded but player status is \(player.state); aborting")
        return nil
      }

      // Sync from mpv's rotation. This is essential when restoring from watch-later, which can include video geometries.
      let userRotation = player.mpv.getInt(MPVOption.Video.videoRotate)

      // Sync video's raw dimensions from mpv.
      // This is especially important for streaming videos, which won't have cached ffMeta
      let vidWidth = player.mpv.getInt(MPVProperty.width)
      let vidHeight = player.mpv.getInt(MPVProperty.height)
      let rawWidth: Int?
      let rawHeight: Int?
      if vidWidth > 0 && vidHeight > 0 {
        rawWidth = vidWidth
        rawHeight = vidHeight
      } else {
        rawWidth = nil
        rawHeight = nil
      }

      // TODO: sync video-crop (actually, add support for video-crop...)

      // FIXME: add support for video-params/aspect-name, use it instead
      //    let mpvVideoParamsAspectName = getString(MPVProperty.videoParamsAspectName)
      let mpvVideoParamsAspect = player.mpv.getString(MPVProperty.videoParamsAspect)  // will be nil if no video track

      var userAspectLabelDerived = ""

      // Sync video-aspect-override. This does get synced from an mpv notification, but there is a noticeable delay
      if let mpvVideoAspectOverride = player.mpv.getString(MPVOption.Video.videoAspectOverride) {
        userAspectLabelDerived = Aspect.bestLabelFor(mpvVideoAspectOverride)
        if userAspectLabelDerived != videoGeo.userAspectLabel {
          // Not necessarily an error? Need to improve aspect name matching logic
          log.debug("[applyVideoGeo] Derived userAspectLabel \(userAspectLabelDerived.quoted) from mpv video-aspect-override (\(mpvVideoAspectOverride)), but it does not match existing userAspectLabel (\(videoGeo.userAspectLabel.quoted))")
        }
      }

      // If opening window, videoGeo may still have the global (default) log. Update it
      let videoGeo = videoGeo.clone(rawWidth: rawWidth, rawHeight: rawHeight,
                                    codecAspectLabel: mpvVideoParamsAspect,
                                    userAspectLabel: userAspectLabelDerived,
                                    userRotation: userRotation,
                                    log)

      if let ffMeta {

        log.debug("[applyVideoGeo] Substituting ffMeta \(ffMeta) into videoGeo \(videoGeo)")
        return videoGeo.substituting(ffMeta)
      } else if currentMediaAudioStatus == .isAudio {
        // Square album art
        log.debug("[applyVideoGeo] Using albumArtGeometry because current media is audio")
        return VideoGeometry.albumArtGeometry(log)
      } else {
        return videoGeo
      }
    }

    let doAfter = { [self] in
      // Wait until window is completely opened before setting this, so that OSD will not be displayed until then.
      // The OSD can have weird stretching glitches if displayed while zooming open...
      if currentPlayback.state == .loaded {
        currentPlayback.state = .loadedAndSized
      }
      // Need to call here to ensure file title OSD is displayed when navigating playlist...
      player.refreshSyncUITimer()
      updateUI()
      // Fix rare case where window is still invisible after closing in music mode and reopening in windowed
      updateCustomBorderBoxAndWindowOpacity()
    }

    applyVideoGeoTransform(transform, fileJustOpened: true, then: doAfter)
  }

  /// Adjust window, viewport, and videoView sizes when `VideoGeometry` has changes.
  func applyVideoGeoTransform(_ videoTransform: @escaping VideoGeometry.Transform,
                              fileJustOpened: Bool = false,
                              then doAfter: (() -> Void)? = nil) {
    assert(DispatchQueue.isExecutingIn(player.mpv.queue))
    let isRestoring = player.info.isRestoring
    let priorState = player.info.priorState
    let showDefaultArt = player.info.shouldShowDefaultArt
    let currentMediaAudioStatus = player.info.currentMediaAudioStatus

    log.verbose("[applyVideoGeo] Entered, restoring=\(isRestoring.yn), showDefaultArt=\(showDefaultArt?.yn ?? "nil"), fileJustOpened=\(fileJustOpened.yn)")

    var aborted = false

    /// Make sure `doAfter` is always executed
    defer {
      if aborted, let doAfter {
        DispatchQueue.main.async { [self] in
          animationPipeline.submitInstantTask(doAfter)
        }
      }
    }

    guard let currentPlayback = player.info.currentPlayback else {
      log.verbose("[applyVideoGeo] Aborting: currentPlayback is nil")
      aborted = true
      return
    }

    guard currentPlayback.state.isAtLeast(.loaded) else {
      log.verbose("[applyVideoGeo] Aborting: playbackState=\(currentPlayback.state), isNetwork=\(currentPlayback.isNetworkResource.yn)")
      aborted = true
      return
    }

    if isRestoring {
      // Clear status & state while still in mpv queue (but after making a local copy for final work)
      player.info.priorState = nil
      player.info.isRestoring = false

      log.debug("[applyVideoGeo] Done with restore")
    }

    DispatchQueue.main.async { [self] in
      animationPipeline.submitInstantTask { [self] in
        let oldVidGeo = geo.video
        guard let newVidGeo = videoTransform(oldVidGeo) else {
          log.verbose("[applyVideoGeo] Aborting due to transform returning nil")
          aborted = true
          return
        }

        guard !player.isStopping else {
          log.verbose("[applyVideoGeo] Aborting because player is stopping (status=\(player.state))")
          aborted = true
          return
        }

        if newVidGeo.totalRotation != currentPlayback.thumbnails?.rotationDegrees {
          player.reloadThumbnails(forMedia: currentPlayback)
        }
        
        let newLayout: LayoutState  // kludge/workaround for timing issue, see below
        let state: WindowStateAtFileOpen
        if fileJustOpened {
          if isRestoring, let priorState {
            state = .restoring(playerState: priorState)
            isInitialSizeDone = true
          } else if !isInitialSizeDone {
            isInitialSizeDone = true
            state = .notOpen
          } else {
            state = .alreadyOpen
          }

          log.verbose("[applyVideoGeo] JustOpenedFile, windowState=\(state), showDefaultArt=\(showDefaultArt?.yn ?? "nil")")
          let (initialLayout, windowOpenLayoutTasks) = buildLayoutTasksForFileOpen(windowState: state,
                                                                                   currentPlayback: currentPlayback,
                                                                                   currentMediaAudioStatus: currentMediaAudioStatus,
                                                                                   newVidGeo: newVidGeo,
                                                                                   showDefaultArt: showDefaultArt)
          newLayout = initialLayout

          animationPipeline.submit(windowOpenLayoutTasks)
        } else {
          state = .notApplicable
          newLayout = currentLayout
        }

        let didRotate = oldVidGeo.totalRotation != newVidGeo.totalRotation

        // TODO: guarantee this executes *after* `super.showWindow` is called. The timing seems to work now, but may break in the future...
        pendingVideoGeoUpdateTasks = buildVideoGeoUpdateTasks(forNewVideoGeo: newVidGeo, newLayout: newLayout, windowState: state,
                                              showDefaultArt: showDefaultArt, didRotate: didRotate)

        if let doAfter {
          pendingVideoGeoUpdateTasks.append(.instantTask(doAfter))
        }

        if case .notApplicable = state {
          animationPipeline.submit(pendingVideoGeoUpdateTasks)
          pendingVideoGeoUpdateTasks = []
        }
      }
    }
  }

  /// Only `applyVideoGeoTransform` should call this.
  private func buildVideoGeoUpdateTasks(forNewVideoGeo newVidGeo: VideoGeometry,
                                        newLayout: LayoutState,
                                        windowState: WindowStateAtFileOpen,
                                        showDefaultArt: Bool? = nil,
                                        didRotate: Bool) -> [IINAAnimation.Task] {

    // There's no good animation for rotation (yet), so just do as little animation as possible in this case
    var duration = didRotate ? 0.0 : IINAAnimation.VideoReconfigDuration
    var timing = CAMediaTimingFunctionName.easeInEaseOut

    /// See also: `doPIPEntry`
    // TODO: find place for this in tasks
    pip.aspectRatio = newVidGeo.videoSizeCAR

    switch newLayout.mode {
    case .windowed:

      let newGeo: PWinGeometry
      switch windowState {

      case .notOpen:
        // Just opened manually. Use a longer duration for this one, because the window starts small and will zoom into place.
        duration = IINAAnimation.InitialVideoReconfigDuration
        timing = .linear

        fallthrough

      case .alreadyOpen:
        var notOpen = false
        if case .notOpen = windowState {
          notOpen = true
        }
        if let resizedGeo = resizeAfterFileOpen(notOpen: notOpen, newVidGeo: newVidGeo) {
          newGeo = resizedGeo
        } else {
          assert(!notOpen, "resizeAfterFileOpen returned nil when notOpen was true!")
          /// If in windowed mode: file opened via playlist navigation, or some other change occurred for file.
          /// If in other mode: do as little as possible. `PWinGeometry` will be used mostly for storage for other fields.
          newGeo = windowedGeoForCurrentFrame().resizeMinimally(forNewVideoGeo: newVidGeo,
                                                                intendedViewportSize: player.info.intendedViewportSize)
        }

      case .notApplicable:
        // Not a new file. Some other change to a video geo property
        newGeo = windowedGeoForCurrentFrame().resizeMinimally(forNewVideoGeo: newVidGeo,
                                                              intendedViewportSize: player.info.intendedViewportSize)
      case .restoring(_):
        log.verbose("[applyVideoGeo] Restore is in progress; aborting")
        return []
      }

      log.debug("[applyVideoGeo Apply] Applying windowed result (newOpenedFile=\(windowState), showDefaultArt=\(showDefaultArt?.yn ?? "nil")): \(newGeo)")
      return buildApplyWindowGeoTasks(newGeo, duration: duration, timing: timing, showDefaultArt: showDefaultArt)

    case .fullScreen:
      let newWinGeo = windowedGeoForCurrentFrame().resizeMinimally(forNewVideoGeo: newVidGeo,
                                                                   intendedViewportSize: player.info.intendedViewportSize)
      let fsGeo = newLayout.buildFullScreenGeometry(inScreenID: newWinGeo.screenID, video: newVidGeo)
      log.debug("[applyVideoGeo Apply] Applying FS result: \(fsGeo)")

      return [IINAAnimation.Task(duration: duration, { [self] in
        // Make sure video constraints are up to date, even in full screen. Also remember that FS & windowed mode share same screen.
        log.verbose("[applyVideoGeo Apply]: Updating videoView (FS), videoSize: \(fsGeo.videoSize), showDefaultArt=\(showDefaultArt?.yn ?? "nil")")
        videoView.apply(fsGeo)
        /// Update even if not currently in windowed mode, as it will be needed when exiting other modes
        windowedModeGeo = newWinGeo

        updateDefaultArtVisibility(to: showDefaultArt)
        resetRotationPreview()
        updateUI()  /// see note about OSD in `buildApplyWindowGeoTasks`
      })]

    case .musicMode:
      if case .notOpen = windowState {
        log.verbose("[applyVideoGeo] Music mode already handled for opened window: \(musicModeGeo)")
        return []
      }
      /// Keep prev `windowFrame`. Just adjust height to fit new video aspect ratio
      /// (unless it doesn't fit in screen; see `applyMusicModeGeo`)
      log.verbose("[applyVideoGeo] Prev cached value of musicModeGeo: \(musicModeGeo)")
      let newMusicModeGeo = musicModeGeoForCurrentFrame(newVidGeo: newVidGeo)
      log.verbose("[applyVideoGeo Apply] Applying musicMode result: \(newMusicModeGeo)")
      return buildApplyMusicModeGeoTasks(from: musicModeGeo, to: newMusicModeGeo,
                                         duration: duration, showDefaultArt: showDefaultArt)
    default:
      log.error("[applyVideoGeo Apply] INVALID MODE: \(newLayout.mode)")
      return []
    }
  }

  private func resetRotationPreview() {
    guard pipStatus == .notInPIP else { return }

    // Seems that this looks better if done before updating the window frame...
    // FIXME: this isn't perfect - a bad frame briefly appears during transition
    log.verbose("Resetting videoView rotation")
    rotationHandler.rotateVideoView(toDegrees: 0, animate: false)
  }

  /// `windowGeo` is expected to have the most up-to-date `VideoGeometry` already
  private func resizeAfterFileOpen(notOpen: Bool, newVidGeo: VideoGeometry) -> PWinGeometry? {
    // resize option applies
    let resizeTiming = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
    switch resizeTiming {
    case .always:
      log.verbose("[applyVideoGeo C-1] FileOpened & resizeTiming='Always' → will resize window")
    case .onlyWhenOpen:
      guard notOpen else {
        log.verbose("[applyVideoGeo C-1] FileOpened & resizeTiming='OnlyWhenOpen', but notOpen=NO → will resize minimally")
        return nil
      }
    case .never:
      if notOpen {
        log.verbose("[applyVideoGeo C-1] FileOpenedManually & resizeTiming='Never' → using windowedModeGeoLastClosed: \(PlayerWindowController.windowedModeGeoLastClosed)")
        return currentLayout.convertWindowedModeGeometry(from: PlayerWindowController.windowedModeGeoLastClosed,
                                                         video: newVidGeo, keepFullScreenDimensions: true)
      } else {
        log.verbose("[applyVideoGeo C-1] FileOpened (not manually) & resizeTiming='Never' → will resize minimally")
        return nil
      }
    }

    let windowGeo = windowedGeoForCurrentFrame(newVidGeo: newVidGeo)
    let screenVisibleFrame = NSScreen.getScreenOrDefault(screenID: windowGeo.screenID).visibleFrame

    let resizeScheme: Preference.ResizeWindowScheme = Preference.enum(for: .resizeWindowScheme)
    switch resizeScheme {
    case .mpvGeometry:
      // check if have mpv geometry set (initial window position/size)
      if let mpvGeometry = player.getMPVGeometry() {
        var preferredGeo = windowGeo
        if Preference.bool(for: .lockViewportToVideoSize), let intendedViewportSize = player.info.intendedViewportSize  {
          log.verbose("[applyVideoGeo C-6] Using intendedViewportSize \(intendedViewportSize)")
          preferredGeo = windowGeo.scaleViewport(to: intendedViewportSize)
        }
        log.verbose("[applyVideoGeo C-7] Applying mpv \(mpvGeometry) within screen \(screenVisibleFrame)")
        return windowGeo.apply(mpvGeometry: mpvGeometry, desiredWindowSize: preferredGeo.windowFrame.size)
      } else {
        log.debug("[applyVideoGeo C-5] No mpv geometry found. Will fall back to default scheme")
        return nil
      }
    case .simpleVideoSizeMultiple:
      let resizeWindowStrategy: Preference.ResizeWindowOption = Preference.enum(for: .resizeWindowOption)
      if resizeWindowStrategy == .fitScreen {
        log.verbose("[applyVideoGeo C-4] ResizeWindowOption=FitToScreen. Using screenFrame \(screenVisibleFrame)")
        return windowGeo.scaleViewport(to: screenVisibleFrame.size, fitOption: .centerInside)
      } else {
        let resizeRatio = resizeWindowStrategy.ratio
        let scaledVideoSize = newVidGeo.videoSizeCAR * resizeRatio
        log.verbose("[applyVideoGeo C-2] Applied resizeRatio (\(resizeRatio)) to newVideoSize → \(scaledVideoSize)")
        let centeredScaledGeo = windowGeo.scaleVideo(to: scaledVideoSize, fitOption: .centerInside, mode: currentLayout.mode)
        // User has actively resized the video. Assume this is the new preferred resolution
        player.info.intendedViewportSize = centeredScaledGeo.viewportSize
        log.verbose("[applyVideoGeo C-3] After scaleVideo: \(centeredScaledGeo)")
        return centeredScaledGeo
      }
    }
  }

  // MARK: - Window geometry functions

  func setVideoScale(_ desiredVideoScale: Double) {
    assert(DispatchQueue.isExecutingIn(.main))
    // Not supported in music mode at this time. Need to resolve backing scale bugs
    guard currentLayout.mode == .windowed else { return }
    guard desiredVideoScale > 0.0 else {
      log.verbose("SetVideoScale: requested scale is invalid: \(desiredVideoScale)")
      return
    }

    player.mpv.queue.async { [self] in
      let oldVidGeo = player.videoGeo

      DispatchQueue.main.async { [self] in
        // TODO: if Preference.bool(for: .usePhysicalResolution) {}

        // FIXME: regression: viewport keeps expanding when video runs into screen boundary
        let videoSizeScaled = oldVidGeo.videoSizeCAR * desiredVideoScale
        let newGeoUnconstrained = windowedGeoForCurrentFrame().scaleVideo(to: videoSizeScaled, fitOption: .noConstraints)
        player.info.intendedViewportSize = newGeoUnconstrained.viewportSize
        let fitOption: ScreenFitOption = .stayInside
        let newGeometry = newGeoUnconstrained.refit(fitOption)

        log.verbose("SetVideoScale: requested scale=\(desiredVideoScale)x, oldVideoSize=\(oldVidGeo.videoSizeCAR) → desiredVideoSize=\(videoSizeScaled)")
        applyWindowGeoInAnimationPipeline(newGeometry)
      }
    }
  }

  /**
   Resizes and repositions the window, attempting to match `desiredViewportSize`, but the actual resulting
   video size will be scaled if needed so it is`>= AppData.minVideoSize` and `<= screen.visibleFrame`.
   The window's position will also be updated to maintain its current center if possible, but also to
   ensure it is placed entirely inside `screen.visibleFrame`.
   */
  func resizeViewport(to desiredViewportSize: CGSize? = nil, centerOnScreen: Bool = false, duration: CGFloat = IINAAnimation.DefaultDuration) {
    assert(DispatchQueue.isExecutingIn(.main))
    guard let window else { return }

    switch currentLayout.mode {
    case .windowed, .windowedInteractive:
      let newGeoUnconstrained = windowedGeoForCurrentFrame().scaleViewport(to: desiredViewportSize,
                                                                           fitOption: .noConstraints)
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
      let currentMusicModeGeo = musicModeGeoForCurrentFrame()
      guard let newMusicModeGeo = currentMusicModeGeo.scaleViewport(to: desiredViewportSize) else { return }
      log.verbose("Calling applyMusicModeGeo from resizeViewport, to: \(newMusicModeGeo.windowFrame)")
      applyMusicModeGeoInAnimationPipeline(from: currentMusicModeGeo, to: newMusicModeGeo)
    default:
      return
    }
  }

  // FIXME: use resizeVideo, not resizeViewport
  func scaleVideoByIncrement(_ widthStep: CGFloat) {
    assert(DispatchQueue.isExecutingIn(.main))
    guard let window else { return }
    let currentViewportSize: NSSize
    switch currentLayout.mode {
    case .windowed:
      currentViewportSize = windowedGeoForCurrentFrame().viewportSize
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
  func resizeWindow(_ window: NSWindow, to requestedSize: NSSize, lockViewportToVideoSize: Bool, isLiveResizingWidth: Bool) -> PWinGeometry {
    let currentLayout = currentLayout
    guard currentLayout.isWindowed else {
      log.error("WinWillResize: requested mode is invalid: \(currentLayout.spec.mode). Will fall back to windowedModeGeo")
      return windowedModeGeo
    }
    let currentGeo = windowedGeoForCurrentFrame()
    assert(currentGeo.mode == currentLayout.mode,
           "WinWillResize: currentGeo.mode (\(currentGeo.mode)) != currentLayout.mode (\(currentLayout.mode))")

    guard !player.info.isRestoring else {
      log.error("WinWillResize was fired before restore was complete! Returning existing geometry: \(currentGeo.windowFrame.size)")
      return currentGeo
    }

    let chosenGeo: PWinGeometry
    // Need to resize window to match video aspect ratio, while taking into account any outside panels.
    if lockViewportToVideoSize && window.inLiveResize {
      let nonViewportAreaSize = currentGeo.windowFrame.size - currentGeo.viewportSize
      let requestedViewportSize = requestedSize - nonViewportAreaSize

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

    log.verbose("WinWillResize isLive:\(window.inLiveResize.yn) req:\(requestedSize) lockViewport:\(lockViewportToVideoSize.yn) currWinSize:\(currentGeo.windowFrame.size) returning:\(chosenGeo.windowFrame.size)")

    return chosenGeo
  }

  func updateFloatingOSCAfterWindowDidResize(usingGeometry newGeometry: PWinGeometry? = nil) {
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
  func applyWindowResize(usingGeometry newGeometry: PWinGeometry? = nil) {
    guard let window else { return }
    videoView.videoLayer.enterAsynchronousMode()

    IINAAnimation.disableAnimation { [self] in
      let layout = currentLayout
      let isTransientResize = newGeometry != nil
      let isFullScreen = currentLayout.isFullScreen
      log.verbose("ApplyWindowResize: fs=\(isFullScreen.yn) newGeo=\(newGeometry?.description ?? "nil")")

      // These may no longer be aligned correctly. Just hide them
      hideSeekTimeAndThumbnail()

      // Update floating control bar position if applicable
      updateFloatingOSCAfterWindowDidResize(usingGeometry: newGeometry)

      if !layout.isNativeFullScreen {
        let geo = newGeometry ?? layout.buildGeometry(windowFrame: window.frame, screenID: bestScreen.screenID, video: geo.video)

        if isFullScreen {
          // Keep video margins up to date in almost every case
          videoView.apply(geo)
        } else {
          /// To avoid visual bugs, *ALWAYS* update videoView before updating window frame!
          player.window.setFrameImmediately(geo, notify: false)
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
  func applyLegacyFSGeo(_ geometry: PWinGeometry) {
    let currentLayout = currentLayout

    if currentLayout.hasFloatingOSC {
      controlBarFloating.moveTo(centerRatioH: floatingOSCCenterRatioH, originRatioV: floatingOSCOriginRatioV,
                                layout: currentLayout, viewportSize: geometry.viewportSize)
    }

    updateOSDTopBarOffset(geometry, isLegacyFullScreen: true)
    let topBarHeight = currentLayout.topBarPlacement == .insideViewport ? geometry.insideBars.top : geometry.outsideBars.top
    updateTopBarHeight(to: topBarHeight, topBarPlacement: currentLayout.topBarPlacement, cameraHousingOffset: geometry.topMarginHeight)

    log.verbose("Calling setFrame for legacyFullScreen, to \(geometry)")
    player.window.setFrameImmediately(geometry)
  }

  /// Updates/redraws current `window.frame` and its internal views from `newGeometry`. Animated.
  ///
  /// Also updates cached `windowedModeGeo` and saves updated state. Windowed mode only!
  func applyWindowGeoInAnimationPipeline(_ newGeometry: PWinGeometry, duration: CGFloat = IINAAnimation.DefaultDuration,
                                         timing: CAMediaTimingFunctionName = .easeInEaseOut,
                                         showDefaultArt: Bool? = nil) {
    let tasks = buildApplyWindowGeoTasks(newGeometry, duration: duration, timing: timing, showDefaultArt: showDefaultArt)
    animationPipeline.submit(tasks)
  }

  func buildApplyWindowGeoTasks(_ newGeometry: PWinGeometry, 
                                duration: CGFloat = IINAAnimation.DefaultDuration,
                                timing: CAMediaTimingFunctionName = .easeInEaseOut,
                                showDefaultArt: Bool? = nil) -> [IINAAnimation.Task] {

    var tasks: [IINAAnimation.Task] = []
    tasks.append(.instantTask{ [self] in
      isAnimatingLayoutTransition = true  /// try not to trigger `windowDidResize` while animating
      videoView.videoLayer.enterAsynchronousMode()

      log.verbose("ApplyWindowGeo: windowFrame=\(newGeometry.windowFrame) showDefaultArt=\(showDefaultArt?.yn ?? "nil") video=\(newGeometry)")
      assert(currentLayout.spec.mode.isWindowed, "applyWindowGeo called outside windowed mode! (found: \(currentLayout.spec.mode))")

      hideSeekTimeAndThumbnail()
      updateDefaultArtVisibility(to: showDefaultArt)
      resetRotationPreview()
    })

    tasks.append(IINAAnimation.Task(duration: duration, timing: timing, { [self] in

      // This is only needed to achieve "fade-in" effect when opening window:
      updateCustomBorderBoxAndWindowOpacity()

      /// Make sure this is up-to-date. Do this before `setFrame`
      if !isWindowHidden {
        player.window.setFrameImmediately(newGeometry)
      } else {
        videoView.apply(newGeometry)
      }
      windowedModeGeo = newGeometry

      log.verbose("ApplyWindowGeo: Calling updateMPVWindowScale, videoSize=\(newGeometry.videoSize)")
      player.updateMPVWindowScale(using: newGeometry)
      player.saveState()
    }))

    tasks.append(.instantTask{ [self] in
      isAnimatingLayoutTransition = false
      // OSD messages may have been supressed because file was not done loading. Display now if needed:
      updateUI()
      player.events.emit(.windowSizeAdjusted, data: newGeometry.windowFrame)
    })

    return tasks
  }

  /// Same as `applyMusicModeGeo`, but enqueues inside an `IINAAnimation.Task` for a nice smooth animation
  func applyMusicModeGeoInAnimationPipeline(from inputGeo: MusicModeGeometry, to outputGeo: MusicModeGeometry,
                                            duration: CGFloat = IINAAnimation.DefaultDuration,
                                            setFrame: Bool = true, animate: Bool = true, updateCache: Bool = true,
                                            showDefaultArt: Bool? = nil) {
    let tasks = buildApplyMusicModeGeoTasks(from: inputGeo, to: outputGeo,
                                            duration: duration, setFrame: setFrame,
                                            updateCache: updateCache, showDefaultArt: showDefaultArt)
    animationPipeline.submit(tasks)
  }

  func buildApplyMusicModeGeoTasks(from inputGeo: MusicModeGeometry, to outputGeo: MusicModeGeometry,
                                   duration: CGFloat = IINAAnimation.DefaultDuration,
                                   setFrame: Bool = true, updateCache: Bool = true,
                                   showDefaultArt: Bool? = nil) -> [IINAAnimation.Task] {
    var tasks: [IINAAnimation.Task] = []

    let isTogglingVideoView = (inputGeo.isVideoVisible != outputGeo.isVideoVisible)

    // TASK 1: Background prep
    tasks.append(.instantTask { [self] in
      isAnimatingLayoutTransition = true  /// do not trigger resize listeners
      if isTogglingVideoView, outputGeo.isVideoVisible {
        // Show/hide art before showing videoView
        updateDefaultArtVisibility(to: showDefaultArt)
      }

      if isTogglingVideoView {
        isAnimatingLayoutTransition = true  /// do not trigger `windowDidResize` if possible
        // Hide OSD during animation
        hideOSD(immediately: true)
        // Hide PiP overlay (if in PiP) during animation
        pipOverlayView.isHidden = true

        /// Temporarily hide window buttons. Using `isHidden` will conveniently override its alpha value
        closeButtonView.isHidden = true

        hideSeekTimeAndThumbnail()
      }
      resetRotationPreview()
    })

    // TASK 2: Apply animation
    tasks.append(IINAAnimation.Task(duration: duration, timing: .easeInEaseOut, { [self] in
      applyMusicModeGeo(outputGeo)
    }))

    // TASK 2A (if toggling video view visibility)
    if isTogglingVideoView {
      tasks.append(IINAAnimation.Task{ [self] in
        // Swap window buttons
        updateMusicModeButtonsVisibility()

        /// Allow it to show again
        closeButtonView.isHidden = false

        showOrHidePipOverlayView()

        // Need to force draw if window was restored while paused + video hidden
        if outputGeo.isVideoVisible {
          forceDraw()
        }
      })
    }

    // TASK 3: Background cleanup
    tasks.append(.instantTask { [self] in
      // Make sure to update art after videoView has settled
      updateDefaultArtVisibility(to: showDefaultArt)

      if isTogglingVideoView && !outputGeo.isVideoVisible {
        if pipStatus == .notInPIP {
          player.setVideoTrackEnabled(false)
        }

        /// If needing to deactivate this constraint, do it before the toggle animation, so that window doesn't jump.
        /// (See note in `applyMusicModeGeo`)
        viewportBtmOffsetFromContentViewBtmConstraint.priority = .init(1)
      }

      isAnimatingLayoutTransition = false
      updateUI()  /// see note about OSD in `buildApplyWindowGeoTasks`
    })

    return tasks
  }

  /// Updates the current window and its subviews to match the given `MusicModeGeometry`.
  /// If `updateCache` is true, updates `musicModeGeo` and saves player state.
  @discardableResult
  func applyMusicModeGeo(_ geometry: MusicModeGeometry, setFrame: Bool = true, 
                         updateCache: Bool = true) -> MusicModeGeometry {
    let geometry = geometry.refit()  // enforces internal constraints, and constrains to screen
    log.verbose("Applying \(geometry), setFrame=\(setFrame.yn) updateCache=\(updateCache.yn)")

    videoView.videoLayer.enterAsynchronousMode()

    // This is only needed to achieve "fade-in" effect when opening window:
    updateCustomBorderBoxAndWindowOpacity()

    // Update defaults:
    Preference.set(geometry.isVideoVisible, for: .musicModeShowAlbumArt)
    Preference.set(geometry.isPlaylistVisible, for: .musicModeShowPlaylist)

    updateMusicModeButtonsVisibility()

    /// Try to detect & remove unnecessary constraint updates - `updateBottomBarHeight()` may cause animation glitches if called twice
    var hasChange: Bool = !geometry.windowFrame.equalTo(window!.frame)
    if geometry.isVideoVisible != !(viewportViewHeightContraint?.isActive ?? false) {
      hasChange = true
    } else if let newVideoSize = geometry.videoSize, let oldVideoSize = musicModeGeo.videoSize, !oldVideoSize.equalTo(newVideoSize) {
      hasChange = true
    }

    guard hasChange else {
      log.verbose("No changes needed for music mode windowFrame or constraints")
      return geometry
    }

    /// Make sure to call `apply` AFTER `updateVideoViewVisibilityConstraints`:
    miniPlayer.updateVideoViewVisibilityConstraints(isVideoVisible: geometry.isVideoVisible)
    updateBottomBarHeight(to: geometry.bottomBarHeight, bottomBarPlacement: .outsideViewport)
    let convertedGeo = geometry.toPWinGeometry()

    if setFrame {
      player.window.setFrameImmediately(convertedGeo, notify: true)
    } else {
      videoView.apply(convertedGeo)
    }

    if updateCache {
      musicModeGeo = geometry
      player.saveState()
    }

    /// For the case where video is hidden but playlist is shown, AppKit won't allow the window's height to be changed by the user
    /// unless we remove this constraint from the the window's `contentView`. For all other situations this constraint should be active.
    /// Need to execute this in its own task so that other animations are not affected.
    let shouldDisableConstraint = !geometry.isVideoVisible && geometry.isPlaylistVisible
    if !shouldDisableConstraint {
      viewportBtmOffsetFromContentViewBtmConstraint.priority = .required
    }

    return geometry
  }

}
