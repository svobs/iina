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
  // MARK: - Window delegate: Resize

  /// NSWindowDelegate: start live resize
  func windowWillStartLiveResize(_ notification: Notification) {
    guard !isAnimatingLayoutTransition else { return }
    log.verbose("WindowWillStartLiveResize")
    isLiveResizingWidth = nil  // reset this
  }

  /// NSWindowDelegate: windowWillResize
  func windowWillResize(_ window: NSWindow, to requestedSize: NSSize) -> NSSize {
    guard !isAnimatingLayoutTransition else { return requestedSize }

    let currentLayout = currentLayout
    let inLiveResize = window.inLiveResize
    let lockViewportToVideoSize = Preference.bool(for: .lockViewportToVideoSize) || currentLayout.mode.alwaysLockViewportToVideoSize
    log.verbose{"WinWillResize Mode=\(currentLayout.mode) Curr=\(window.frame.size) Req=\(requestedSize) inLiveResize=\(inLiveResize.yn) isAnimatingTx=\(isAnimatingLayoutTransition.yn) lockViewPort=\(lockViewportToVideoSize.yn) denyNext=\(denyNextWindowResize.yn)"}
    videoView.videoLayer.enterAsynchronousMode()

    if !currentLayout.isFullScreen && denyNextWindowResize {
      log.verbose{"WinWillResize: denying this resize. Will stay at \(window.frame.size)"}
      denyNextWindowResize = false
      return window.frame.size
    }

    if lockViewportToVideoSize && inLiveResize {
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
        if window.frame.height != requestedSize.height {
          isLiveResizingWidth = false
        } else if window.frame.width != requestedSize.width {
          isLiveResizingWidth = true
        }
      }
      log.verbose{"WinWillResize: choseWidth=\(self.isLiveResizingWidth?.yn ?? "nil")"}
    }

    let isLiveResizingWidth = isLiveResizingWidth ?? true
    switch currentLayout.mode {
    case .windowedNormal, .windowedInteractive:

      guard !sessionState.isRestoring else {
        log.error{"WinWillResize was fired while restoring! Returning existing geometry: \(windowedModeGeo.windowFrame.size)"}
        return windowedModeGeo.windowFrame.size
      }
      let currentGeo = windowedGeoForCurrentFrame()
      assert(currentGeo.mode == currentLayout.mode,
             "WinWillResize: currentGeo.mode (\(currentGeo.mode)) != currentLayout.mode (\(currentLayout.mode))")

      let newGeometry = currentGeo.resizingWindow(to: requestedSize, lockViewportToVideoSize: lockViewportToVideoSize,
                                                inLiveResize: inLiveResize, isLiveResizingWidth: isLiveResizingWidth)

      log.verbose{"WinWillResize will return \(newGeometry.windowFrame.size)"}

      if currentLayout.mode == .windowedNormal && inLiveResize {
        // User has resized the video. Assume this is the new preferred resolution until told otherwise. Do not constrain.
        player.info.intendedViewportSize = newGeometry.viewportSize
      }


      /// AppKit calls `setFrame` after this method returns, and we cannot access that code to ensure it is encapsulated
      /// within the same animation transaction as the code below. But this solution seems to get us 99% there; the video
      /// only exhibits a small noticeable wobble for some limited cases ...
      IINAAnimation.disableAnimation { [self] in
        resizeWindowSubviews(using: newGeometry)
      }

      return newGeometry.windowFrame.size

    case .fullScreenNormal, .fullScreenInteractive:
      if currentLayout.isLegacyFullScreen {
        let newGeometry = currentLayout.buildFullScreenGeometry(inScreenID: windowedModeGeo.screenID, video: geo.video)
        IINAAnimation.disableAnimation { [self] in
          videoView.apply(newGeometry)
        }
        return newGeometry.windowFrame.size
      } else {  // is native full screen
        // This method can be called as a side effect of the animation. If so, ignore.
        return requestedSize
      }

    case .musicMode:
      return miniPlayer.musicModeWindowWillResize(window, to: requestedSize, isLiveResizingWidth: isLiveResizingWidth)
    }
  }

  /// Explicitly changes the window frame & window subviews according to `newGeometry` (or generating a geometry if `nil`),
  /// without animation (i.e., immediately).
  /// Do not call in response to WindowWillResize, because this can call `setFrameImmediately`.
  /// Do not call if layout needs to change. For that, use a LayoutTransition.
  ///
  /// Use with non-nil `newGeometry` for: (1) pinch-to-zoom, (2) resizing outside sidebars when the whole window needs to be resized or
  /// moved
  /// Not animated.
  /// Can be used in windowed or full screen modes.
  /// Can be used in music mode only if playlist is hidden.
  func resizeWindowImmediately(using newGeometry: PWinGeometry? = nil) {
    guard let window else { return }
    videoView.videoLayer.enterAsynchronousMode()

    IINAAnimation.disableAnimation { [self] in
      let layout = currentLayout
      let isTransientResize = newGeometry != nil
      let isFullScreen = layout.isFullScreen
      log.verbose{"ResizeWindowImmediately: fs=\(isFullScreen.yn) isLive=\(window.inLiveResize.yn) newGeo=\(newGeometry?.description ?? "nil")"}

      // These may no longer be aligned correctly. Just hide them
      hideSeekPreview()

      if !layout.isNativeFullScreen {
        let geo = newGeometry ?? layout.buildGeometry(windowFrame: window.frame, screenID: bestScreen.screenID, video: geo.video)

        if isFullScreen {
          // custom FS
          resizeWindowSubviews(using: geo)
        } else {
          /// This will also update `videoView`
          player.window.setFrameImmediately(geo, notify: false)
        }
      }

      if !isFullScreen && !isTransientResize {
        player.saveState()
        if layout.mode == .windowedNormal {
          log.verbose("ApplyWindowResize: calling updateMPVWindowScale")
          player.updateMPVWindowScale(using: windowedModeGeo)
        }
      }
    }

    player.events.emit(.windowResized, data: window.frame)
  }

  /// Resizes *only* the subviews in the window, not the window frame. Updates other state needed when resizing window.
  func resizeWindowSubviews(using newGeometry: PWinGeometry, updateVideoView: Bool = true) {
    videoView.videoLayer.enterAsynchronousMode()

    if updateVideoView {
      videoView.apply(newGeometry)
    }

    // Update floating control bar position if applicable
    adjustFloatingControllerOrigin(for: newGeometry)

    if newGeometry.mode == .musicMode {
      miniPlayer.loadIfNeeded()
      // Re-evaluate space requirements for labels. May need to start scrolling.
      // Do not save musicModeGeo here! Pinch gesture will handle itself. Drag-to-resize will be handled elsewhere.
      miniPlayer.resetScrollingLabels()
    } else if newGeometry.mode.isInteractiveMode {
      // Update interactive mode selectable box size. Origin is relative to viewport origin
      let newVideoRect = NSRect(origin: CGPointZero, size: newGeometry.videoSize)
      cropSettingsView?.cropBoxView.resized(with: newVideoRect)
    }

    if osd.animationState == .shown {
      updateOSDTextSize(from: newGeometry)
      if player.info.isFileLoadedAndSized {
        setOSDViews()
      }
    }
  }

  // MARK: - Applying Video Geometry

  /// If current media is file, this should be called after it is done loading.
  /// If current media is network resource, should be called immediately & show buffering msg.
  /// If current media's vid track changed, may need to apply new geometry
  func applyVideoGeoForTrackChange( _ musicModeTransform: MusicModeGeometry.Transform? = nil) {
    let videoTransform: VideoGeometry.Transform = { [self] context in
      assert(DispatchQueue.isExecutingIn(player.mpv.queue))

      let vidTrackID = context.vidTrackID
      let currentPlayback = context.currentPlayback
      log.verbose{"[applyVideoGeo \(context.name)] Starting transform, vid=\(String(vidTrackID))|\(context.currentMediaAudioStatus), sessionState=\(context.sessionState)"}

      if case .existingSession_continuing = context.sessionState {
        if currentPlayback.state.isNotYet(.loadedAndSized) {
          sessionState = .existingSession_startingNewPlayback
        } else if currentPlayback.vidTrackLastSized != vidTrackID {
          sessionState = .existingSession_videoTrackChangedForSamePlayback
        } else {
          log.verbose{"[applyVideoGeo \(context.name)] Aborting: no session change, & video track (\(String(vidTrackID))) is nil or hasn't changed"}
          return nil
        }
      }

      // Use cached video info (if it is available) to set the correct video geometry right away and without waiting for mpv.
      // This is optional but provides a better viewer experience.
      let ffMeta = currentPlayback.isNetworkResource ? nil : MediaMetaCache.shared.getOrReadVideoMeta(forURL: currentPlayback.url, log)

      if isInMiniPlayer, geo.musicMode.isVideoVisible, !player.isRestoring, context.currentMediaAudioStatus == .isAudioWithArtHidden {
        log.verbose{"[applyVideoGeo \(context.name)] Player is in music mode + media is audio + has album art but is not showing it. Will try to enable video track"}
        player.setVideoTrackEnabled(thenShowMiniPlayerVideo: true)
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

      // Try video-params/aspect-name first, for easier lookup. But always store as ratio or decimal number
      let mpvVideoParamsAspectName = player.mpv.getString(MPVProperty.videoParamsAspectName)
      var codecAspect: String?
      if let mpvVideoParamsAspectName, Aspect.isValid(mpvVideoParamsAspectName) {
        codecAspect = Aspect.resolvingMpvName(mpvVideoParamsAspectName)
      } else {
        codecAspect = player.mpv.getString(MPVProperty.videoParamsAspect)  // will be nil if no video track
      }

      // Sync video-aspect-override. This does get synced from an mpv notification, but there is a noticeable delay
      var userAspectLabelDerived = ""
      if let mpvVideoAspectOverride = player.mpv.getString(MPVOption.Video.videoAspectOverride) {
        userAspectLabelDerived = Aspect.bestLabelFor(mpvVideoAspectOverride)
        if userAspectLabelDerived != context.oldGeo.video.userAspectLabel {
          // Not necessarily an error? Need to improve aspect name matching logic
          log.debug{"[applyVideoGeo \(context.name)] Derived userAspectLabel \(userAspectLabelDerived.quoted) from mpv video-aspect-override (\(mpvVideoAspectOverride)), but it does not match existing userAspectLabel (\(context.oldGeo.video.userAspectLabel.quoted))"}
        }
      }

      // If opening window, videoGeo may still have the global (default) log. Update it
      let videoGeo = context.oldGeo.video.clone(rawWidth: rawWidth, rawHeight: rawHeight,
                                               codecAspectLabel: codecAspect,
                                               userAspectLabel: userAspectLabelDerived,
                                               userRotation: userRotation,
                                               log)

      // FIXME: audioStatus==notAudio for playlist which auto-plays audio
      if !context.currentMediaAudioStatus.isAudio, vidTrackID != 0 {
        let dwidth = player.mpv.getInt(MPVProperty.dwidth)
        let dheight = player.mpv.getInt(MPVProperty.dheight)

        let ours = videoGeo.videoSizeCA
        // Apparently mpv can sometimes add a pixel. Not our fault...
        if (Int(ours.width) - dwidth).magnitude > 1 || (Int(ours.height) - dheight).magnitude > 1 {
          player.log.error{"❌ Sanity check for VideoGeometry failed: mpv dsize (\(dwidth) x \(dheight)) != our videoSizeCA \(ours), videoTrack=\(vidTrackID)|\(context.currentMediaAudioStatus)"}
        }
      }

      if let ffMeta {
        log.debug{"[applyVideoGeo \(context.name)] Substituting ffMeta \(ffMeta) into videoGeo \(videoGeo)"}
        return videoGeo.substituting(ffMeta)
      } else if context.currentMediaAudioStatus.isAudio {
        // Square album art
        log.debug{"[applyVideoGeo \(context.name)] Using albumArtGeometry because current media is audio"}
        return VideoGeometry.albumArtGeometry(log)
      } else {
        log.debug{"[applyVideoGeo \(context.name)] Derived videoGeo \(videoGeo)"}
        return videoGeo
      }
    }  // end of transform block

    applyVideoGeoTransform("TrackChanged", videoTransform, musicModeTransform)
  }

  /// Adjust window, viewport, and videoView sizes when `VideoGeometry` has changes.
  func applyVideoGeoTransform(_ transformName: String,
                              _ videoTransform: @escaping VideoGeometry.Transform,
                              _ musicModeTransform: MusicModeGeometry.Transform? = nil,
                              then doAfter: (() -> Void)? = nil) {

    animationPipeline.submitInstantTask { [self] in
      let oldGeo = geo

      player.mpv.queue.async { [self] in
        let sessionState = sessionState  // save in case it changes

        let doAfterTask = IINAAnimation.Task.instantTask{ [self] in
          if sessionState.isChangingVideoTrack {
            // Need to call here to ensure file title OSD is displayed when navigating playlist...
            player.refreshSyncUITimer()
            updateUI()
            // Fix rare case where window is still invisible after closing in music mode and reopening in windowed
            updateWindowBorderAndOpacity()
          }
          if let doAfter {
            doAfter()
          }
        }

        /// Make sure `doAfter` is always executed
        func abort(_ reasonDebugMsg: String) {
          log.verbose{"[applyVideoGeo \(transformName)] Aborting: \(reasonDebugMsg)"}
          if DispatchQueue.isExecutingIn(.main) {
            animationPipeline.submit(doAfterTask)
          } else {
            DispatchQueue.main.async { [self] in
              animationPipeline.submit(doAfterTask)
            }
          }
        }

        guard let currentPlayback = player.info.currentPlayback else {
          return abort("currentPlayback is nil")
        }

        // Need to load file before we can know its video geometry
        // ...Unless we are restoring. But then we still want to wait until all windows have finished loading,
        // so that we can open them all at once
        // ...But streaming files can often fail to connect. So reopen those right away if restoring, since we already
        // have their saved geometry anyway.
        guard currentPlayback.state.isAtLeast(.loaded) || (sessionState.isRestoring && currentPlayback.isNetworkResource) else {
          return abort("playbackState=\(currentPlayback.state) restoring=\(sessionState.isRestoring) network=\(currentPlayback.isNetworkResource.yn)")
        }

        guard !player.isStopping else {
          return abort("player stopping (status=\(player.state))")
        }

        let cxt = GeometryTransformContext(name: transformName, oldGeo: oldGeo, sessionState: sessionState,
                                           currentPlayback: currentPlayback, vidTrackID: player.info.vid ?? 0,
                                           currentMediaAudioStatus: player.info.currentMediaAudioStatus)

        guard let newVidGeo = videoTransform(cxt) else {
          return abort("transform \(transformName) returned nil")
        }

        if sessionState.isChangingVideoTrack {
          // Clear status & state while still in mpv queue (but after making a local copy for final work)
          self.sessionState = .existingSession_continuing

          // Wait until window is completely opened before setting this, so that OSD will not be displayed until then.
          // The OSD can have weird stretching glitches if displayed while zooming open...
          if currentPlayback.state.isAtLeast(.loaded) {
            // If minimized, the call to DispatchQueue.main.async below doesn't seem to execute. Just do this for all cases now.
            log.debug{"[applyVideoGeo \(cxt.name)] Updating playback.state = .loadedAndSized, vidTrackLastSized=\(cxt.vidTrackID)"}
            currentPlayback.state = .loadedAndSized
            // Set immediately to prevent future duplicate calls from continuing
            currentPlayback.vidTrackLastSized = cxt.vidTrackID
          }
        }

        if newVidGeo.totalRotation != currentPlayback.thumbnails?.rotationDegrees {
          player.reloadThumbnails(forMedia: currentPlayback)
        }

        animationPipeline.submitInstantTask { [self] in
          log.verbose{"[applyVideoGeo \(transformName)] sessionState=\(sessionState)"}
          if sessionState.isStartingSession {
            let (initialLayout, windowOpenLayoutTasks) = buildWindowInitialLayoutTasks(cxt, newVidGeo: newVidGeo)
            animationPipeline.submit(windowOpenLayoutTasks)

            /// These tasks should not execute until *after* `super.showWindow` is called.
            var videoGeoUpdateTasks = buildGeoUpdateTasks(forNewVideoGeo: newVidGeo, newLayout: initialLayout, cxt, musicModeTransform)
            videoGeoUpdateTasks.append(doAfterTask)
            pendingVideoGeoUpdateTasks = videoGeoUpdateTasks
          } else {
            var videoGeoUpdateTasks = buildGeoUpdateTasks(forNewVideoGeo: newVidGeo, newLayout: currentLayout, cxt, musicModeTransform)
            videoGeoUpdateTasks.append(doAfterTask)
            animationPipeline.submit(videoGeoUpdateTasks)
          }
        }
      }
    }
  }

  /// Only `applyVideoGeoTransform` should call this.
  private func buildGeoUpdateTasks(forNewVideoGeo newVidGeo: VideoGeometry, newLayout: LayoutState,
                                   _ cxt: GeometryTransformContext,
                                   _ musicModeTransform: MusicModeGeometry.Transform? = nil) -> [IINAAnimation.Task] {

    let sessionState = cxt.sessionState
    let didRotate = cxt.oldGeo.video.totalRotation != newVidGeo.totalRotation

    var duration: CGFloat
    if didRotate {
      // There's no good animation for rotation (yet), so just do as little animation as possible in this case
      duration = 0.0
    } else {
      duration = IINAAnimation.VideoReconfigDuration
    }
    var timing = CAMediaTimingFunctionName.easeInEaseOut

    /// See also: `doPIPEntry`
    // TODO: find place for this in tasks
    pip.controller.aspectRatio = newVidGeo.videoSizeCAR

    switch newLayout.mode {

    case .windowedNormal:
      let resizedGeo: PWinGeometry?

      switch sessionState {
      case .restoring(_):
        log.verbose{"[applyVideoGeo \(cxt.name)] Restore is in progress; aborting"}
        return []
      case .creatingNew:
        // Just opened new window. Use a longer duration for this one, because the window starts small and will zoom into place.
        duration = IINAAnimation.InitialVideoReconfigDuration
        timing = .linear
        fallthrough
      case .newReplacingExisting,
          .existingSession_startingNewPlayback,
          .existingSession_videoTrackChangedForSamePlayback:
        resizedGeo = applyResizePrefsForWindowedFileOpen(isOpeningFileManually: sessionState.isOpeningFileManually, newVidGeo: newVidGeo)
      case .existingSession_continuing:
        // Not a new file. Some other change to a video geo property. Fall through and resize minimally
        resizedGeo = nil
      case .noSession:
        Logger.fatal("[applyVideoGeo \(cxt.name)] Invalid sessionState: \(sessionState)")
      }

      let newGeo = resizedGeo ?? windowedGeoForCurrentFrame().resizeMinimally(forNewVideoGeo: newVidGeo,
                                                                              intendedViewportSize: player.info.intendedViewportSize)

      let showDefaultArt: Bool? = player.info.shouldShowDefaultArt
//      let windowedGeoUpdated = windowedGeoForCurrentFrame(newVidGeo: newVidGeo)
//      let newGeoSet = cxt.oldGeo.clone(windowed: windowedGeoUpdated)

      log.debug("[applyVideoGeo \(cxt.name)] Will apply windowed result (sessionState=\(sessionState), showDefaultArt=\(showDefaultArt?.yn ?? "nil")): \(newGeo)")
      return buildApplyWindowGeoTasks(newGeo, duration: duration, timing: timing, showDefaultArt: showDefaultArt)

    case .fullScreenNormal:
      let newWinGeo = windowedGeoForCurrentFrame().resizeMinimally(forNewVideoGeo: newVidGeo,
                                                                   intendedViewportSize: player.info.intendedViewportSize)
      let fsGeo = newLayout.buildFullScreenGeometry(inScreenID: newWinGeo.screenID, video: newVidGeo)
      log.debug{"[applyVideoGeo \(cxt.name)] Will apply FS result: \(fsGeo)"}

      return [.init(duration: duration, { [self] in
        // Make sure video constraints are up to date, even in full screen. Also remember that FS & windowed mode share same screen.
        log.verbose{"[applyVideoGeo \(cxt.name)]: Updating videoView (FS), videoSize=\(fsGeo.videoSize)"}
        videoView.apply(fsGeo)
        /// Update even if not currently in windowed mode, as it will be needed when exiting other modes
        windowedModeGeo = newWinGeo

        resetRotationPreview()
        updateUI()  /// see note about OSD in `buildApplyWindowGeoTasks`
      })]

    case .musicMode:
      if case .creatingNew = sessionState {
        log.verbose{"[applyVideoGeo \(cxt.name)] Music mode already handled for opened window: \(musicModeGeo)"}
        return []
      }
      /// Keep prev `windowFrame`. Just adjust height to fit new video aspect ratio
      /// (unless it doesn't fit in screen; see `applyMusicModeGeo`)
      log.verbose{"[applyVideoGeo \(cxt.name)] Prev cached value of musicModeGeo: \(musicModeGeo)"}
      let musicModeGeoUpdated = musicModeGeoForCurrentFrame(newVidGeo: newVidGeo)
      let geoSet = cxt.oldGeo.clone(musicMode: musicModeGeoUpdated)
      let cxt2 = cxt.clone(oldGeo: geoSet)
      let newMusicModeGeo = cxt2.oldGeo.musicMode  // TODO: use transform instead!
      if musicModeGeo.isVideoVisible != newMusicModeGeo.isVideoVisible {
        // Toggling videoView visiblity: use longer duration for nicety
        duration = IINAAnimation.DefaultDuration
      }
      /// Default album art: check state before doing anything so that we don't duplicate work. Don't change in miniPlayer if videoView not visible.
      /// If `showDefaultArt == nil`, don't change existing visibility.
      let shouldDecideDefaultArtStatus = musicModeGeo.isVideoVisible || newMusicModeGeo.isVideoVisible
      let showDefaultArt: Bool? = shouldDecideDefaultArtStatus ? player.info.shouldShowDefaultArt : nil
      log.verbose{"[applyVideoGeo \(cxt.name)] Start: sessionState=\(sessionState), showDefaultArt=\(showDefaultArt?.yn ?? "nil")"}

      log.verbose{"[applyVideoGeo Apply] Applying musicMode result: \(newMusicModeGeo)"}
      return buildApplyMusicModeGeoTasks(from: musicModeGeo, to: newMusicModeGeo,
                                         duration: duration, showDefaultArt: showDefaultArt)
    default:
      log.error{"[applyVideoGeo] INVALID MODE: \(newLayout.mode)"}
      return []
    }
  }

  private func resetRotationPreview() {
    guard pip.status == .notInPIP else { return }

    // Seems that this looks better if done before updating the window frame...
    // FIXME: this isn't perfect - a bad frame briefly appears during transition
    log.verbose("Resetting videoView rotation")
    rotationHandler.rotateVideoView(toDegrees: 0, animate: false)
  }

  /// Applies the prefs `.resizeWindowTiming` & `resizeWindowScheme`, if applicable.
  /// Returns `nil` if no applicable settings were found/applied, and should fall back to minimal resize.
  private func applyResizePrefsForWindowedFileOpen(isOpeningFileManually: Bool, newVidGeo: VideoGeometry) -> PWinGeometry? {
    // resize option applies
    let resizeTiming = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
    switch resizeTiming {
    case .always:
      log.verbose("[applyVideoGeo C-1] FileOpened & resizeTiming='Always' → will resize window")
    case .onlyWhenOpen:
      if !isOpeningFileManually {
        log.verbose("[applyVideoGeo C-1] FileOpened & resizeTiming='OnlyWhenOpen', but isOpeningFileManually=N → will resize minimally")
        return nil
      }
    case .never:
      if !isOpeningFileManually {
        log.verbose("[applyVideoGeo C-1] FileOpened (not manually) & resizeTiming='Never' → will resize minimally")
        return nil
      }
      log.verbose("[applyVideoGeo C-1] FileOpenedManually & resizeTiming='Never' → using windowedModeGeoLastClosed: \(PlayerWindowController.windowedModeGeoLastClosed)")
      return currentLayout.convertWindowedModeGeometry(from: PlayerWindowController.windowedModeGeoLastClosed,
                                                       video: newVidGeo, keepFullScreenDimensions: true)
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
          log.verbose{"[applyVideoGeo C-6] Using intendedViewportSize \(intendedViewportSize)"}
          preferredGeo = windowGeo.scalingViewport(to: intendedViewportSize)
        }
        log.verbose{"[applyVideoGeo C-7] Applying mpv \(mpvGeometry) within screen \(screenVisibleFrame)"}
        return windowGeo.apply(mpvGeometry: mpvGeometry, desiredWindowSize: preferredGeo.windowFrame.size)
      } else {
        log.debug{"[applyVideoGeo C-5] No mpv geometry found. Will fall back to default scheme"}
        return nil
      }
    case .simpleVideoSizeMultiple:
      let resizeWindowStrategy: Preference.ResizeWindowOption = Preference.enum(for: .resizeWindowOption)
      if resizeWindowStrategy == .fitScreen {
        log.verbose{"[applyVideoGeo C-4] ResizeWindowOption=FitToScreen. Using screenFrame \(screenVisibleFrame)"}
        return windowGeo.scalingViewport(to: screenVisibleFrame.size, fitOption: .centerInside)
      } else {
        let resizeRatio = resizeWindowStrategy.ratio
        let scaledVideoSize = newVidGeo.videoSizeCAR * resizeRatio
        log.verbose{"[applyVideoGeo C-2] Applied resizeRatio (\(resizeRatio)) to newVideoSize → \(scaledVideoSize)"}
        let centeredScaledGeo = windowGeo.scalingVideo(to: scaledVideoSize, fitOption: .centerInside, mode: currentLayout.mode)
        // User has actively resized the video. Assume this is the new preferred resolution
        player.info.intendedViewportSize = centeredScaledGeo.viewportSize
        log.verbose{"[applyVideoGeo C-3] After scaleVideo: \(centeredScaledGeo)"}
        return centeredScaledGeo
      }
    }
  }

  // MARK: - Other window geometry functions

  func changeVideoScale(to desiredVideoScale: Double) {
    assert(DispatchQueue.isExecutingIn(.main))
    // Not supported in music mode at this time. Need to resolve backing scale bugs
    guard currentLayout.mode == .windowedNormal else { return }

    guard desiredVideoScale > 0.0 else {
      log.verbose("SetVideoScale: requested scale is invalid: \(desiredVideoScale)")
      return
    }

    /*
     TODO: refactor applyVideoGeoTransform so it can include this

     applyVideoGeoTransform("VideoScale", { [self] videoGeo in
     // Not supported in music mode at this time. Need to resolve backing scale bugs
     guard currentLayout.mode == .windowedNormal else { return nil }

     // TODO: if Preference.bool(for: .usePhysicalResolution) {}

     // FIXME: regression: viewport keeps expanding when video runs into screen boundary
     let videoSizeScaled = videoGeo.videoSizeCAR * desiredVideoScale
     return nil
     })


     */

    player.mpv.queue.async { [self] in
      let oldVideoGeo = player.videoGeo

      DispatchQueue.main.async { [self] in
        // TODO: if Preference.bool(for: .usePhysicalResolution) {}

        // FIXME: regression: viewport keeps expanding when video runs into screen boundary
        let videoSizeScaled = oldVideoGeo.videoSizeCAR * desiredVideoScale
        let newGeoUnconstrained = windowedGeoForCurrentFrame().scalingVideo(to: videoSizeScaled, fitOption: .noConstraints)
        player.info.intendedViewportSize = newGeoUnconstrained.viewportSize
        let fitOption: ScreenFitOption = .stayInside
        let newGeometry = newGeoUnconstrained.refitted(using: fitOption)

        log.verbose("SetVideoScale: requested scale=\(desiredVideoScale)x, oldVideoSize=\(oldVideoGeo.videoSizeCAR) → desiredVideoSize=\(videoSizeScaled)")
        buildApplyWindowGeoTasks(newGeometry, thenRun: true)
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

    switch currentLayout.mode {
    case .windowedNormal, .windowedInteractive:
      let newGeoUnconstrained = windowedGeoForCurrentFrame().scalingViewport(to: desiredViewportSize,
                                                                           fitOption: .noConstraints)
      if currentLayout.mode == .windowedNormal {
        // User has actively resized the video. Assume this is the new preferred resolution
        player.info.intendedViewportSize = newGeoUnconstrained.viewportSize
      }

      let fitOption: ScreenFitOption = centerOnScreen ? .centerInside : .stayInside
      let newGeometry = newGeoUnconstrained.refitted(using: fitOption)
      log.verbose{"Calling applyWindowGeo from resizeViewport (center=\(centerOnScreen.yn)), to: \(newGeometry.windowFrame)"}
      buildApplyWindowGeoTasks(newGeometry, duration: duration, thenRun: true)
    case .musicMode:
      /// In music mode, `viewportSize==videoSize` always. Will get `nil` here if video is not visible
      let currentMusicModeGeo = musicModeGeoForCurrentFrame()
      guard let newMusicModeGeo = currentMusicModeGeo.scalingViewport(to: desiredViewportSize) else { return }
      log.verbose{"Calling applyMusicModeGeo from resizeViewport, to: \(newMusicModeGeo.windowFrame)"}
      buildApplyMusicModeGeoTasks(from: currentMusicModeGeo, to: newMusicModeGeo, thenRun: true)
    default:
      return
    }
  }

  func scaleVideoByIncrement(_ widthStep: CGFloat) {
    assert(DispatchQueue.isExecutingIn(.main))
    let currentViewportSize: NSSize
    switch currentLayout.mode {
    case .windowedNormal:
      currentViewportSize = windowedGeoForCurrentFrame().viewportSize
    case .musicMode:
      guard let viewportSize = musicModeGeoForCurrentFrame().viewportSize else { return }
      currentViewportSize = viewportSize
    default:
      return
    }
    let heightStep = widthStep / currentViewportSize.mpvAspect
    let desiredViewportSize = CGSize(width: round(currentViewportSize.width + widthStep),
                                     height: round(currentViewportSize.height + heightStep))
    log.verbose{"Incrementing viewport width by \(widthStep), to desired size \(desiredViewportSize)"}
    resizeViewport(to: desiredViewportSize)
  }

  private func adjustFloatingControllerOrigin(for newGeometry: PWinGeometry? = nil) {
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

  // MARK: - Apply Geometry - NOT Music Mode

  /// Set the window frame and if needed the content view frame to appropriately use the full screen.
  /// For screens that contain a camera housing the content view will be adjusted to not use that area of the screen.
  func applyLegacyFSGeo(_ geometry: PWinGeometry) {
    assert(geometry.mode.isFullScreen, "Expected applyLegacyFSGeo to be called with full screen geometry but got \(geometry)")
    let currentLayout = currentLayout

    if currentLayout.hasFloatingOSC {
      controlBarFloating.moveTo(centerRatioH: floatingOSCCenterRatioH, originRatioV: floatingOSCOriginRatioV,
                                layout: currentLayout, viewportSize: geometry.viewportSize)
    }

    updateOSDTopBarOffset(geometry, isLegacyFullScreen: true)
    let topBarHeight = currentLayout.topBarPlacement == .insideViewport ? geometry.insideBars.top : geometry.outsideBars.top
    updateTopBarHeight(to: topBarHeight, topBarPlacement: currentLayout.topBarPlacement, cameraHousingOffset: geometry.topMarginHeight)

    log.verbose{"Calling setFrame for legacyFullScreen, to \(geometry)"}
    player.window.setFrameImmediately(geometry)
  }

  /// Updates/redraws current `window.frame` and its internal views from `newGeometry`. Animated. Windowed mode only!
  ///
  /// Also updates cached `windowedModeGeo` and saves updated state.
  @discardableResult
  func buildApplyWindowGeoTasks(_ newGeometry: PWinGeometry,
                                duration: CGFloat = IINAAnimation.DefaultDuration,
                                timing: CAMediaTimingFunctionName = .easeInEaseOut,
                                showDefaultArt: Bool? = nil,
                                thenRun: Bool = false) -> [IINAAnimation.Task] {

    log.verbose{"ApplyWindowGeo: showDefaultArt=\(showDefaultArt?.yn ?? "nil"), run=\(thenRun.yn) newGeo=\(newGeometry)"}

    var tasks: [IINAAnimation.Task] = []

    tasks.append(.instantTask{ [self] in
      isAnimatingLayoutTransition = true  /// try not to trigger `windowDidResize` while animating
      videoView.videoLayer.enterAsynchronousMode()

      assert(currentLayout.spec.mode.isWindowed, "applyWindowGeo called outside windowed mode! (found: \(currentLayout.spec.mode))")

      hideSeekPreview()
      updateDefaultArtVisibility(to: showDefaultArt)
      resetRotationPreview()
    })

    tasks.append(IINAAnimation.Task(duration: duration, timing: timing, { [self] in

      // This is only needed to achieve "fade-in" effect when opening window:
      updateWindowBorderAndOpacity()

      /// Make sure this is up-to-date. Do this before `setFrame`
      if !isWindowHidden {
        player.window.setFrameImmediately(newGeometry)
      } else {
        videoView.apply(newGeometry)
      }
      windowedModeGeo = newGeometry

      log.verbose{"ApplyWindowGeo: Calling updateMPVWindowScale, videoSize=\(newGeometry.videoSize)"}
      player.updateMPVWindowScale(using: newGeometry)
      player.saveState()
    }))

    tasks.append(.instantTask{ [self] in
      isAnimatingLayoutTransition = false
      // OSD messages may have been supressed because file was not done loading. Display now if needed:
      updateUI()
      player.events.emit(.windowSizeAdjusted, data: newGeometry.windowFrame)
    })

    if thenRun {
      animationPipeline.submit(tasks)
      return []
    }
    return tasks
  }

  // MARK: - Apply Geometry: Music Mode

  @discardableResult
  func buildApplyMusicModeGeoTasks(from inputGeo: MusicModeGeometry, to outputGeo: MusicModeGeometry,
                                   duration: CGFloat = IINAAnimation.DefaultDuration,
                                   setFrame: Bool = true, updateCache: Bool = true,
                                   showDefaultArt: Bool? = nil,
                                   thenRun: Bool = false) -> [IINAAnimation.Task] {
    var tasks: [IINAAnimation.Task] = []

    let isTogglingVideoView = (inputGeo.isVideoVisible != outputGeo.isVideoVisible)

    // TASK 1: Background prep
    tasks.append(.instantTask { [self] in
      isAnimatingLayoutTransition = true  /// do not trigger `windowDidResize` if possible
      if isTogglingVideoView, outputGeo.isVideoVisible {  // Showing video
        // Show/hide art before showing videoView
        updateDefaultArtVisibility(to: showDefaultArt)
        addVideoViewToWindow(using: outputGeo)
      }

      if isTogglingVideoView {
        // Hide OSD during animation
        hideOSD(immediately: true)
        // Hide PiP overlay (if in PiP) during animation
        pipOverlayView.isHidden = true

        /// Temporarily hide window buttons. Using `isHidden` will conveniently override its alpha value
        closeButtonView.isHidden = true

        hideSeekPreview()
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

      if isTogglingVideoView && !outputGeo.isVideoVisible {  // Hiding video
        if pip.status == .notInPIP {
          player.setVideoTrackDisabled()
          videoView.removeFromSuperview()
        }

        /// If needing to deactivate this constraint, do it before the toggle animation, so that window doesn't jump.
        /// (See note in `applyMusicModeGeo`)
        viewportBtmOffsetFromContentViewBtmConstraint.priority = .minimum
      }

      isAnimatingLayoutTransition = false
      updateUI()  /// see note about OSD in `buildApplyWindowGeoTasks`
    })

    if thenRun {
      animationPipeline.submit(tasks)
    }
    return tasks
  }

  /// Updates the current window and its subviews to match the given `MusicModeGeometry`.
  /// If `updateCache` is true, updates `musicModeGeo` and saves player state.
  @discardableResult
  func applyMusicModeGeo(_ geometry: MusicModeGeometry, setFrame: Bool = true, 
                         updateCache: Bool = true) -> MusicModeGeometry {
    let geometry = geometry.refitted()  // enforces internal constraints, and constrains to screen
    log.verbose{"Applying \(geometry), setFrame=\(setFrame.yn) updateCache=\(updateCache.yn)"}

    videoView.videoLayer.enterAsynchronousMode()

    // This is only needed to achieve "fade-in" effect when opening window:
    updateWindowBorderAndOpacity()

    updateMusicModeButtonsVisibility(using: geometry)

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

    /// Make sure to call `apply` AFTER `updateVideoViewHeightConstraint`!
    miniPlayer.updateVideoViewHeightConstraint(isVideoVisible: geometry.isVideoVisible)

    miniPlayer.resetScrollingLabels()

    updateBottomBarHeight(to: geometry.bottomBarHeight, bottomBarPlacement: .outsideViewport)
    let convertedGeo = geometry.toPWinGeometry()

    if setFrame {
      player.window.setFrameImmediately(convertedGeo, notify: true)
    } else {
      videoView.apply(convertedGeo)
    }

    /// For the case where video is hidden but playlist is shown, AppKit won't allow the window's height to be changed by the user
    /// unless we remove this constraint from the the window's `contentView`. For all other situations this constraint should be active.
    /// Need to execute this in its own task so that other animations are not affected.
    let shouldDisableConstraint = !geometry.isVideoVisible && geometry.isPlaylistVisible
    if !shouldDisableConstraint {
      viewportBtmOffsetFromContentViewBtmConstraint.priority = .required
    }

    // Update defaults:
    Preference.set(geometry.isVideoVisible, for: .musicModeShowAlbumArt)
    Preference.set(geometry.isPlaylistVisible, for: .musicModeShowPlaylist)

    if updateCache {
      musicModeGeo = geometry
      player.saveState()
    }

    return geometry
  }

}
