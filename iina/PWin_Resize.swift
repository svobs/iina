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
    log.trace{"WindowWillStartLiveResize"}
    isLiveResizingWidth = nil  // reset this
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    log.trace{"WindowDidEndLiveResize"}
  }

  func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame: NSRect) -> NSRect {
    // Need to explicitly bypass the denial mechanism
    denyWindowResizeIntervalStartTime = Date(timeIntervalSince1970: 0)
    // FIXME: aspect ratio change animation needs improvement
    let newSize = windowWillResize(window, to: defaultFrame.size)
    let newFrame = NSRect(origin: defaultFrame.origin, size: newSize)
    log.verbose{"WindowWillZoom: \(window.frame) → \(defaultFrame) → \(newFrame)"}
    return newFrame
  }

  /// NSWindowDelegate: windowWillResize
  ///
  /// # Notes for other NSWindowDelegate notifications:
  /// * `windowDidResize()`: Called after window is resized from (almost) any cause. Ca be called many times during every call to `window.setFrame()`.
  /// Do not use because it interferes with animations in progress.
  /// * `windowDidEndLiveResize`: Never use! It is unreliable. Use `windowDidResize` if anything.
  func windowWillResize(_ window: NSWindow, to requestedSize: NSSize) -> NSSize {
    guard !isAnimatingLayoutTransition else {
      return requestedSize
    }
    let currentLayout = currentLayout
    let inLiveResize = window.inLiveResize
    let denyWindowResize = Date() < denyWindowResizeIntervalStartTime + Constants.TimeInterval.denyWindowResizeTimeout

    if !currentLayout.isFullScreen && !inLiveResize {
      guard !denyWindowResize else {
        log.verbose{"[WinWillResize] Denying request=\(requestedSize): still inside denial period. Will stay at \(window.frame.size)"}
        return window.frame.size
      }
    }

    let lockViewportToVideoSize = Preference.bool(for: .lockViewportToVideoSize) || currentLayout.mode.alwaysLockViewportToVideoSize
    log.verbose{"[WinWillResize] \(currentLayout.mode) Curr=\(window.frame.size) Req=\(requestedSize) Live=\(inLiveResize.yn) LockViewport=\(lockViewportToVideoSize.yn)"}

    videoView.videoLayer.enterAsynchronousMode()
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
      log.verbose{"[WinWillResize] choseWidth=\(self.isLiveResizingWidth?.yn ?? "nil")"}
    }

    let newWindowSize: NSSize
    let resizeSubviewsTask: IINAAnimation.Task
    let isLiveResizingWidth = isLiveResizingWidth ?? true
    switch currentLayout.mode {
    case .windowedNormal, .windowedInteractive:

      guard !sessionState.isRestoring else {
        log.error{"[WinWillResize] Still restoring; returning existing geo=\(windowedModeGeo.windowFrame.size)"}
        return windowedModeGeo.windowFrame.size
      }
      let currentGeo = windowedGeoForCurrentFrame()
      assert(currentGeo.mode == currentLayout.mode,
             "[WinWillResize] currentGeo.mode (\(currentGeo.mode)) != currentLayout.mode (\(currentLayout.mode))")

      let newGeometry = currentGeo.resizingWindow(to: requestedSize, lockViewportToVideoSize: lockViewportToVideoSize,
                                                  inLiveResize: inLiveResize, isLiveResizingWidth: isLiveResizingWidth)
      newWindowSize = newGeometry.windowFrame.size

      if currentLayout.mode == .windowedNormal {
        // User has resized the video. Assume this is the new preferred resolution until told otherwise. Do not constrain.
        player.info.intendedViewportSize = newGeometry.viewportSize
      }

      resizeSubviewsTask = .instantTask { [self] in
        /// AppKit calls `setFrame` after this method returns, and we cannot access that code to ensure it is encapsulated
        /// within the same animation transaction as the code below. But this solution seems to get us 99% there; the video
        /// only exhibits a small noticeable wobble for some limited cases ...
        resizeWindowSubviews(using: newGeometry)
      }
      // fall through

    case .fullScreenNormal, .fullScreenInteractive:
      if currentLayout.isNativeFullScreen {
        // This method can be called as a side effect of the animation. If so, ignore.
        return requestedSize
      }

      let newGeometry = currentLayout.buildFullScreenGeometry(inScreenID: windowedModeGeo.screenID, video: geo.video)
      newWindowSize = newGeometry.windowFrame.size
      resizeSubviewsTask = .instantTask { [self] in
        videoView.apply(newGeometry)
      }
      // fall through

    case .musicMode:
      guard !sessionState.isRestoring else {
        log.error{"[WinWillResize] Still restoring; returning existing musicModeGeo=\(musicModeGeo.windowFrame.size)"}
        return musicModeGeo.windowFrame.size
      }

      let currentGeo = musicModeGeoForCurrentFrame()
      let newGeometry = currentGeo.resizingWindow(to: requestedSize, inLiveResize: window.inLiveResize, isLiveResizingWidth: isLiveResizingWidth)
      newWindowSize = newGeometry.windowFrame.size

      resizeSubviewsTask = .instantTask { [self] in
        /// This call is needed to update any necessary constraints & resize internal views
        _ = applyMusicModeGeo(newGeometry, setFrame: false, updateCache: false)
      }
    }

    IINAAnimation.runAsync(resizeSubviewsTask)
    log.verbose{"[WinWillResize] Returning size=\(newWindowSize) for \(currentLayout.mode)"}
    return newWindowSize
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

    CATransaction.begin()
    defer {
      CATransaction.commit()
    }

    let layout = currentLayout
    let isTransientResize = newGeometry != nil
    let isFullScreen = layout.isFullScreen
    log.verbose{"[ResizeWindImmediately] fs=\(isFullScreen.yn) live=\(window.inLiveResize.yn) geo=\(newGeometry?.description ?? "nil")"}

    // These may no longer be aligned correctly. Just hide them
    hideSeekPreviewImmediately()

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
        log.verbose{"[ResizeWindImmediately] calling updateMPVWindowScale"}
        player.updateMPVWindowScale(using: windowedModeGeo)
      }
    }

    player.events.emit(.windowResized, data: window.frame)
  }

  /// Resizes *only* the subviews in the window, not the window frame. Updates other state needed when resizing window.
  func resizeWindowSubviews(using newGeometry: PWinGeometry, updateVideoView: Bool = true) {
    videoView.videoLayer.enterAsynchronousMode()
    if updateVideoView {
      // Not sure if this helps fix the aspect constraint transition
      CATransaction.begin()
      videoView.apply(newGeometry)
      CATransaction.commit()
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

  /// Applies changes to window geometry, possibly animating any changes.
  ///
  /// # Arguments:
  /// - `stateChange`: optional operator function for transforming `sessionState` and/or cancelling the transform.
  ///   - If `nil`, the transform will proceed with the existing `sessionState`.
  ///   - If non-nil, this function will be run in the mpv queue. It is given the current window's `sessionState` & is expected
  ///     to output a new value of `sessionState` to set at the end of the transform if it succeeds.
  ///     But if it returns `nil`, the transform will be cancelled.
  /// - `videoTransform`: optional operator function which, if provided, will run in the mpv queue.
  ///   - If `nil`, the transform will proceed with the existing `VideoGeometry`.
  ///   - If non-`nil`: t is given the current window's `VideoGeometry` (and other context), & is expected to output a new, possibly
  ///     transformed ` VideoGeometry`. But if it returns `nil`, then transform will be cancelled and no state will be changed.
  /// - `windowedTransform`: optional operator function which if provided, will run in the main queue.
  ///   - If non-nil, and if in music mode, this function is given the `PWinGeometry` which would otherwise be applied and is
  ///     is expected to output a ` PWinGeometry` containing further transforms which should be applied. If it returns `nil`,
  ///     the transform will ignore it and will proceed with its calculated values.
  /// - `musicModeTransform`: optional operator function which if provided, will run in the main queue.
  ///   - If non-nil, and if in music mode, this function is given the `MusicModeGeometry` which would otherwise be applied and is
  ///     is expected to output a ` MusicModeGeometry` containing further transforms which should be applied. If it returns `nil`,
  ///     the transform will not transform the geometry.
  func transformGeometry(_ transformName: String,
                         stateChange: ((GeometryTransform.Context) -> PWinSessionState?)? = nil,
                         video videoTransform: VideoGeometry.Transform? = nil,
                         windowed windowedTransform: PWinGeometry.Transform? = nil,
                         musicMode musicModeTransform: MusicModeGeometry.Transform? = nil,
                         onSuccess: (() -> Void)? = nil) {

    animationPipeline.submitInstantTask { [self] in
      let oldGeo = geo

      player.mpv.queue.async { [self] in

        /// Make sure `doAfter` is always executed
        func abort(_ reasonDebugMsg: String) {
          log.verbose{"[applyVideoGeo \(transformName)] Aborting: \(reasonDebugMsg)"}
        }

        guard let currentPlayback = player.info.currentPlayback else {
          return abort("currentPlayback is nil")
        }

        // File needs to be loaded before we can know its video geometry.
        // ...Unless we are restoring. But then we still want to wait until all windows are done loading, so we can open them all at once.
        // ...But streaming files can often fail to connect. So reopen those right away if restoring (we already have their saved geometry anyway).
        guard currentPlayback.state.isAtLeast(.loaded) || (sessionState.isRestoring && currentPlayback.isNetworkResource) else {
          return abort("playbackState=\(currentPlayback.state) restoring=\(sessionState.isRestoring) network=\(currentPlayback.isNetworkResource.yn)")
        }

        guard !player.isStopping else {
          return abort("player stopping (status=\(player.state))")
        }

        let vidTrackID = player.info.vid ?? 0

        var cxt = GeometryTransform.Context(name: transformName, oldGeo: oldGeo, sessionState: sessionState,
                                           currentPlayback: currentPlayback, vidTrackID: vidTrackID,
                                           currentMediaAudioStatus: player.info.currentMediaAudioStatus,
                                           player: player)

        /// Apply `stateChange` if present
        if let stateChange {
          guard let newSessionState = stateChange(cxt) else {
            return abort("state change func returned nil from sessionState=\(sessionState)")
          }
          cxt = cxt.clone(sessionState: newSessionState)
        } else {
          log.verbose{"[applyVideoGeo \(cxt.name)] Reusing current sessionState: \(cxt.sessionState)"}
        }

        /// Apply `videoTransform` if present
        let newVidGeo: VideoGeometry
        if let videoTransform {
          guard let resultGeo = videoTransform(cxt) else {
            return abort("transform \(transformName) returned nil")
          }
          log.verbose{"[applyVideoGeo \(cxt.name)] VideoTransform returned: \(resultGeo)"}
          newVidGeo = resultGeo
        } else {
          newVidGeo = oldGeo.video
        }

        animationPipeline.submitInstantTask { [self] in
          log.verbose{"[applyVideoGeo \(cxt.name)] sessionState=\(cxt.sessionState)"}

          var immediateTasks: [IINAAnimation.Task]

          if cxt.sessionState.isStartingSession {
            let (initialLayout, windowOpenLayoutTasks) = buildWindowInitialLayoutTasks(cxt, newVidGeo: newVidGeo)
            immediateTasks = windowOpenLayoutTasks

            /// These tasks should not execute until *after* `super.showWindow` is called.
            let videoGeoUpdateTasks = buildTasks(forNewVideoGeo: newVidGeo, newLayout: initialLayout, cxt,
                                                 windowedTransform, musicModeTransform, onSuccess: onSuccess)

            let isRestoringMinimizedWindow = cxt.sessionState.isRestoring && UIState.shared.windowsMinimized.contains(window!.savedStateName)
            if isRestoringMinimizedWindow {
              // Minimized: can't rely on showWindow() being called, but window changes won't be seen anyway. Just run end task now.
              log.verbose{"[applyVideoGeo \(cxt.name)] Restoring minimized window: will run tasks immediately instead of queueing"}
              immediateTasks.append(contentsOf: videoGeoUpdateTasks)
            } else {
              pendingVideoGeoUpdateTasks = videoGeoUpdateTasks
            }

          } else {
            let layout = currentLayout
            immediateTasks = buildTasks(forNewVideoGeo: newVidGeo, newLayout: layout, cxt,
                                        windowedTransform, musicModeTransform, onSuccess: onSuccess)

            // Need to switch to music mode? Append to above tasks
            if case .existingSession_startingNewPlayback = cxt.sessionState, Preference.bool(for: .autoSwitchToMusicMode) {
              if player.overrideAutoMusicMode {
                log.verbose("[applyVideoGeo \(cxt.name)] Skipping music mode auto-switch ∴ overrideAutoMusicMode=Y")
              } else if cxt.currentMediaAudioStatus.isAudio && !layout.isMusicMode && !layout.isFullScreen {
                log.debug("[applyVideoGeo \(cxt.name)] Opened media is audio: auto-switching to music mode")
                let geo = buildGeoSet(video: newVidGeo, from: layout)
                let enterMusicModeTransitionTasks = buildTransitionTasksToEnterMusicMode(automatically: true, from: layout, geo)
                immediateTasks += enterMusicModeTransitionTasks
              } else if cxt.currentMediaAudioStatus == .notAudio && layout.isMusicMode {
                log.debug("[applyVideoGeo \(cxt.name)] Opened media is not audio: auto-switching to normal window")
                let geo = buildGeoSet(video: newVidGeo, from: layout)
                let enterMusicModeTransitionTasks = buildTransitionTasksToExitMusicMode(automatically: true, from: layout, geo)
                immediateTasks += enterMusicModeTransitionTasks
              }
            }
          }

          animationPipeline.submit(immediateTasks)
        }

      }
    }
  }

  /// Only `transformGeometry` should call this.
  private func buildTasks(forNewVideoGeo newVidGeo: VideoGeometry, newLayout: LayoutState,
                          _ cxt: GeometryTransform.Context,
                          _ windowedTransform: PWinGeometry.Transform? = nil,
                          _ musicModeTransform: MusicModeGeometry.Transform? = nil,
                          onSuccess: (() -> Void)? = nil) -> [IINAAnimation.Task] {
    var videoGeoUpdateTasks = buildGeoUpdateTasks(forNewVideoGeo: newVidGeo, newLayout: newLayout, cxt,
                                                  windowedTransform, musicModeTransform)
    let doAfterTask = buildEndTask(cxt, newVidGeo: newVidGeo, onSuccess: onSuccess)
    videoGeoUpdateTasks.append(doAfterTask)
    return videoGeoUpdateTasks
  }

  /// Cleanup, update `sessionState` & UI.
  private func buildEndTask(_ cxt: GeometryTransform.Context, newVidGeo: VideoGeometry, onSuccess: (() -> Void)? = nil) -> IINAAnimation.Task {
    IINAAnimation.Task.instantTask{ [self] in
      log.verbose{"[applyVideoGeo \(cxt.name)] Running endTask for sessionState=\(cxt.sessionState) vid=\(cxt.vidTrackID)"}
      if cxt.sessionState.isChangingVideoTrack {
        // Set to prevent future duplicate calls from continuing
        cxt.currentPlayback.vidTrackLastSized = cxt.vidTrackID
        // Return to normal status:
        sessionState = .existingSession_continuing

        // Wait until window is completely opened before setting this, so that OSD will not be displayed until then.
        // The OSD can have weird stretching glitches if displayed while zooming open...
        if cxt.currentPlayback.state == .loaded {
          // If minimized, the call to DispatchQueue.main.async below doesn't seem to execute. Just do this for all cases now.
          log.debug{"[applyVideoGeo \(cxt.name)] Updating playback.state = .loadedAndSized, vidTrackLastSized=\(cxt.vidTrackID), will emit fileLoaded notifications"}
          cxt.currentPlayback.state = .loadedAndSized

          // If is network resource, may not be loaded yet. If file, it will be.
          player.postNotification(.iinaFileLoaded)
          player.events.emit(.fileLoaded, data: cxt.currentPlayback.url.absoluteString)
        }
      }

      // Plugs loophole when restoring:
      videoView.refreshAllVideoState()

      // Need to call here to ensure file title OSD is displayed when navigating playlist...
      player.refreshSyncUITimer()
      // Fix rare case where window is still invisible after closing in music mode and reopening in windowed
      updateWindowBorderAndOpacity()

      // Always do this in case the video geometry changed:
      player.reloadQuickSettingsView()

      if let onSuccess {
        onSuccess()
      }
    }
  }

  /// Only `transformGeometry` should call this.
  private func buildGeoUpdateTasks(forNewVideoGeo newVidGeo: VideoGeometry, newLayout: LayoutState,
                                   _ cxt: GeometryTransform.Context,
                                   _ windowedTransform: PWinGeometry.Transform? = nil,
                                   _ musicModeTransform: MusicModeGeometry.Transform? = nil) -> [IINAAnimation.Task] {

    let sessionState = cxt.sessionState

    var duration: CGFloat
    let didRotate = cxt.oldGeo.video.userRotation != newVidGeo.userRotation
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

    let newCxt = cxt.clone(oldGeo: buildGeoSet(from: newLayout, baseGeoSet: cxt.oldGeo))
    log.verbose{"[applyVideoGeo \(cxt.name)] Mode=\(newLayout.mode): updated cxt=\(newCxt)"}
    switch newLayout.mode {

    case .windowedNormal:
      let resizedGeo: PWinGeometry?

      if let windowedTransform {
        resizedGeo = windowedTransform(newCxt)
      } else {
        switch sessionState {
        case .restoring(_):
          log.verbose{"[applyVideoGeo \(cxt.name)] Restore is in progress; aborting"}
          return []
        case .creatingNew:
          // Just opened new window. Use a longer duration for this one, because the window starts small and will zoom into place.
          duration = IINAAnimation.InitialVideoReconfigDuration
          timing = .linear
          resizedGeo = applyResizePrefsForWindowedFileOpen(cxt, newVidGeo: newVidGeo)
        case .newReplacingExisting:
          resizedGeo = applyResizePrefsForWindowedFileOpen(cxt, newVidGeo: newVidGeo)
        case .existingSession_startingNewPlayback:
          resizedGeo = applyResizePrefsForWindowedFileOpen(cxt, newVidGeo: newVidGeo)
        case .existingSession_videoTrackChangedForSamePlayback,
            .existingSession_continuing:
          // Not a new file. Some other change to a video geo property. Fall through and resize minimally
          resizedGeo = nil
        case .noSession:
          Logger.fatal("[applyVideoGeo \(cxt.name)] Invalid sessionState: \(sessionState)")
        }
      }

      let intendedViewportSize: CGSize? = sessionState.canUseIntendedViewportSize ? player.info.intendedViewportSize : nil
      let newGeo = resizedGeo ?? newCxt.oldGeo.windowed.resizeMinimally(forNewVideoGeo: newVidGeo, intendedViewportSize: intendedViewportSize)

      let showDefaultArt: Bool? = player.info.shouldShowDefaultArt

      log.debug{"[applyVideoGeo \(cxt.name)] Will apply windowed result (newSessionState=\(sessionState), showDefaultArt=\(showDefaultArt?.yn ?? "nil")): \(newGeo)"}
      return buildApplyWindowGeoTasks(newGeo, duration: duration, timing: timing, showDefaultArt: showDefaultArt)

    case .fullScreenNormal:
      let intendedViewportSize: CGSize? = sessionState.canUseIntendedViewportSize ? player.info.intendedViewportSize : nil
      let newWinGeo = cxt.oldGeo.windowed.resizeMinimally(forNewVideoGeo: newVidGeo,
                                                          intendedViewportSize: intendedViewportSize)
      let fsGeo = newLayout.buildFullScreenGeometry(inScreenID: newWinGeo.screenID, video: newVidGeo)
      let showDefaultArt: Bool? = player.info.shouldShowDefaultArt
      log.debug{"[applyVideoGeo \(cxt.name)] Will apply FS result: \(fsGeo), showDefaultArt=\(showDefaultArt?.yn ?? "nil")"}

      return [.init(duration: duration, { [self] in
        // Make sure video constraints are up to date, even in full screen. Also remember that FS & windowed mode share same screen.
        log.verbose{"[applyVideoGeo \(cxt.name)]: Updating videoView (FS), videoSize=\(fsGeo.videoSize)"}
        videoView.apply(fsGeo)
        /// Update even if not currently in windowed mode, as it will be needed when exiting other modes
        windowedModeGeo = newWinGeo

        resetRotationPreview()
        hideSeekPreviewImmediately()
        updateDefaultArtVisibility(to: showDefaultArt)
        player.updateMPVWindowScale(using: fsGeo)
        updateUI()  /// see note about OSD in `buildApplyWindowGeoTasks`
      })]

    case .musicMode:
      if case .creatingNew = sessionState {
        log.verbose{"[applyVideoGeo \(cxt.name)] Music mode already handled for opened window: \(musicModeGeo)"}
        return []
      }
      let oldMusicModeGeo = newCxt.oldGeo.musicMode  // has updated windowFrame
      let newMusicModeGeo: MusicModeGeometry
      if let musicModeTransform {
        guard let transformedGeo = musicModeTransform(newCxt) else {
          return []
        }
        newMusicModeGeo = transformedGeo
      } else {
        newMusicModeGeo = oldMusicModeGeo.clone(video: newVidGeo)
      }
      /// Keep prev `windowFrame`. Just adjust height to fit new video aspect ratio
      /// (unless it doesn't fit in screen; see `applyMusicModeGeo`)

      if oldMusicModeGeo.isVideoVisible != newMusicModeGeo.isVideoVisible {
        // Toggling videoView visiblity: use longer duration for nicety
        duration = IINAAnimation.DefaultDuration
      }
      /// Default album art: check state before doing anything so that we don't duplicate work. Don't change in miniPlayer if videoView not visible.
      /// If `showDefaultArt == nil`, don't change existing visibility.
      let shouldDecideDefaultArtStatus = oldMusicModeGeo.isVideoVisible || newMusicModeGeo.isVideoVisible
      let showDefaultArt: Bool? = shouldDecideDefaultArtStatus ? player.info.shouldShowDefaultArt : nil
      log.verbose{"[applyVideoGeo \(cxt.name)] Applying musicMode result: \(newMusicModeGeo) (sessionState=\(sessionState) showDefaultArt=\(showDefaultArt?.yn ?? "nil"))"}
      return buildApplyMusicModeGeoTasks(from: oldMusicModeGeo, to: newMusicModeGeo,
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
    log.verbose{"Resetting videoView rotation"}
    rotationHandler.rotateVideoView(toDegrees: 0, animate: false)
  }

  /// Applies the prefs `.resizeWindowTiming` & `resizeWindowScheme`, if applicable.
  /// Returns `nil` if no applicable settings were found/applied, and should fall back to minimal resize.
  private func applyResizePrefsForWindowedFileOpen(_ cxt: GeometryTransform.Context, newVidGeo: VideoGeometry) -> PWinGeometry? {
    // resize option applies
    let resizeTiming = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
    switch resizeTiming {
    case .always:
      log.verbose{"[applyVideoGeo \(cxt.name)] FileOpened & resizeTiming='Always' → will resize window"}
    case .onlyWhenOpen:
      if !cxt.sessionState.isOpeningFileManually {
        log.verbose{"[applyVideoGeo \(cxt.name)] FileOpened & resizeTiming='OnlyWhenOpen', but isOpeningFileManually=N → will resize minimally"}
        return nil
      }
    case .never:
      if !cxt.sessionState.isOpeningFileManually {
        log.verbose("[applyVideoGeo \(cxt.name)] FileOpened (not manually) & resizeTiming='Never' → will resize minimally")
        return nil
      }
      log.verbose{"[applyVideoGeo \(cxt.name)] FileOpenedManually & resizeTiming='Never' → using windowedModeGeoLastClosed: \(PlayerWindowController.windowedModeGeoLastClosed)"}
      return currentLayout.convertWindowedModeGeometry(from: PlayerWindowController.windowedModeGeoLastClosed,
                                                       video: newVidGeo, keepFullScreenDimensions: true,
                                                       applyOffsetIndex: player.openedWindowsSetIndex, log)
    }

    let windowGeo = windowedGeoForCurrentFrame(newVidGeo: newVidGeo)
    let screenVisibleFrame = NSScreen.getScreenOrDefault(screenID: windowGeo.screenID).visibleFrame

    let resizeScheme: Preference.ResizeWindowScheme = Preference.enum(for: .resizeWindowScheme)
    switch resizeScheme {
    case .mpvGeometry:
      // check if have mpv geometry set (initial window position/size)
      guard let mpvGeometry = player.getMPVGeometry() else {
        if cxt.sessionState.isOpeningFileManually {
          log.debug{"[applyVideoGeo C-5] No mpv geometry found. Will fall back to windowedModeGeoLastClosed"}
          return currentLayout.convertWindowedModeGeometry(from: PlayerWindowController.windowedModeGeoLastClosed,
                                                           video: newVidGeo, keepFullScreenDimensions: true,
                                                           applyOffsetIndex: player.openedWindowsSetIndex, log)
        } else {
          log.debug{"[applyVideoGeo C-8] No mpv geometry found. Will fall back to minimal resize"}
          return nil
        }
      }

      var preferredGeo = windowGeo
      if Preference.bool(for: .lockViewportToVideoSize), cxt.sessionState.canUseIntendedViewportSize,
         let intendedViewportSize = player.info.intendedViewportSize {
        log.verbose{"[applyVideoGeo C-6] Using intendedViewportSize \(intendedViewportSize)"}
        preferredGeo = windowGeo.scalingViewport(to: intendedViewportSize)
      }
      log.verbose{"[applyVideoGeo C-7] Applying mpv \(mpvGeometry) within screen \(screenVisibleFrame)"}
      return windowGeo.apply(mpvGeometry: mpvGeometry, desiredWindowSize: preferredGeo.windowFrame.size)

    case .simpleVideoSizeMultiple:
      let resizeWindowStrategy: Preference.ResizeWindowOption = Preference.enum(for: .resizeWindowOption)
      if resizeWindowStrategy == .fitScreen {
        log.verbose{"[applyVideoGeo C-4] ResizeWindowOption=FitToScreen. Using screenFrame \(screenVisibleFrame)"}
        return windowGeo.scalingViewport(to: screenVisibleFrame.size, screenFit: .centerInside)
      } else {
        let resizeRatio = resizeWindowStrategy.ratio
        let scaledVideoSize = newVidGeo.videoSizeCAR * resizeRatio
        log.verbose{"[applyVideoGeo C-2] Applied resizeRatio (\(resizeRatio)) to newVideoSize → \(scaledVideoSize)"}
        let centeredScaledGeo = windowGeo.scalingVideo(to: scaledVideoSize, screenFit: .centerInside, mode: currentLayout.mode)
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
    guard currentLayout.mode == .windowedNormal else {
      log.error{"SetVideoScale: skipping; mode is unsupported: \(currentLayout.mode)"}
      return
    }
    guard desiredVideoScale > 0.0 else {
      log.error{"SetVideoScale: requested scale is invalid: \(desiredVideoScale)"}
      return
    }

    transformGeometry("SetVideoScale", windowed: { [self] cxt -> PWinGeometry? in
      let oldWindowedGeo = cxt.oldGeo.windowed
      // TODO: if Preference.bool(for: .usePhysicalResolution) {}
      // Not supported in music mode at this time. Need to resolve backing scale bugs
      // FIXME: regression: viewport keeps expanding when video runs into screen boundary

      // See also: PWinGeometry.mpvVideoScale
      let screen = NSScreen.getScreenOrDefault(screenID: oldWindowedGeo.screenID)
      let backingScaleFactor = screen.backingScaleFactor
      let adjustedVideoScale = desiredVideoScale / backingScaleFactor
      let videoSizeCAR = oldWindowedGeo.video.videoSizeCAR
      let videoSizeScaled = (videoSizeCAR * adjustedVideoScale).rounded()
      log.error{"SetVideoScale: desired=\(desiredVideoScale) adjusted=\(adjustedVideoScale) videoCAR=\(videoSizeCAR) → videoScaled=\(videoSizeScaled)"}
      let newGeoUnconstrained = oldWindowedGeo.scalingVideo(to: videoSizeScaled, screenFit: .noConstraints)
      player.info.intendedViewportSize = newGeoUnconstrained.viewportSize
      return newGeoUnconstrained.refitted(using: .stayInside)
    })
  }

  /**
   Resizes and repositions the window, attempting to match `desiredViewportSize`, but the actual resulting
   video size will be scaled if needed so it is `<= screen.visibleFrame`.
   The window's position will also be updated to maintain its current center if possible, but also to
   ensure it is placed entirely inside `screen.visibleFrame`.
   */
  func resizeViewport(to desiredViewportSize: CGSize? = nil, centerOnScreen: Bool = false,
                      duration: CGFloat = IINAAnimation.DefaultDuration) {
    assert(DispatchQueue.isExecutingIn(.main))

    switch currentLayout.mode {
    case .windowedNormal, .windowedInteractive:
      let oldGeo = windowedGeoForCurrentFrame()
      let newGeoUnconstrained = oldGeo.scalingViewport(to: desiredViewportSize, screenFit: .noConstraints)
      if currentLayout.mode == .windowedNormal {
        // User has actively resized the video. Assume this is the new preferred resolution
        player.info.intendedViewportSize = newGeoUnconstrained.viewportSize
      }

      let screenFit: ScreenFit = centerOnScreen ? .centerInside : .stayInside
      let newGeometry = newGeoUnconstrained.refitted(using: screenFit)
      log.verbose{"Calling applyWindowGeo from resizeViewport (center=\(centerOnScreen.yn)), to: \(newGeometry.windowFrame)"}
      buildApplyWindowGeoTasks(newGeometry, duration: duration, thenRun: true)
    case .musicMode:
      /// In music mode, `viewportSize==videoSize` always. Will get `nil` here if video is not visible
      let oldGeo = musicModeGeoForCurrentFrame()
      guard let newMusicModeGeo = oldGeo.scalingViewport(to: desiredViewportSize) else { return }
      log.verbose{"Calling applyMusicModeGeo from resizeViewport, to: \(newMusicModeGeo.windowFrame)"}
      buildApplyMusicModeGeoTasks(from: oldGeo, to: newMusicModeGeo, thenRun: true)
    default:
      return
    }
  }

  
  // FIXME: interpolate this
  func scaleVideoByIncrement(_ widthStep: CGFloat) {
    assert(DispatchQueue.isExecutingIn(.main))

    func scale(_ viewportSize: CGSize, widthStep: CGFloat) -> CGSize {
      let heightStep = widthStep / viewportSize.mpvAspect
      return CGSize(width: round(viewportSize.width + widthStep),
                    height: round(viewportSize.height + heightStep))
    }

    switch currentLayout.mode {
    case .windowedNormal:
      let windowedTransform: (GeometryTransform.Context) -> PWinGeometry? = { [self] cxt -> PWinGeometry? in
        let oldWindowedGeo = cxt.oldGeo.windowed
        let desiredViewportSize = scale(oldWindowedGeo.viewportSize, widthStep: widthStep)
        log.verbose{"Incrementing viewport width by \(widthStep), to desired size \(desiredViewportSize)"}
        let newGeoUnconstrained = oldWindowedGeo.scalingViewport(to: desiredViewportSize, screenFit: .noConstraints)
        // User has actively resized the video. Assume this is the new preferred resolution
        player.info.intendedViewportSize = newGeoUnconstrained.viewportSize
        return newGeoUnconstrained.refitted(using: .stayInside)
      }
      transformGeometry("ScaleVideoBy\(widthStep)px", windowed: windowedTransform)

    case .musicMode:
      let musicModeTransform: (GeometryTransform.Context) -> MusicModeGeometry? = { [self] cxt -> MusicModeGeometry? in
        guard let oldViewportSize = cxt.oldGeo.musicMode.viewportSize else { return nil }
        let desiredViewportSize = scale(oldViewportSize, widthStep: widthStep)
        log.verbose{"Incrementing viewport width by \(widthStep), to desired size \(desiredViewportSize)"}
        return cxt.oldGeo.musicMode.scalingViewport(to: desiredViewportSize)
      }
      transformGeometry("ScaleVideoBy\(widthStep)px", musicMode: musicModeTransform)
    default:
      return
    }
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
          if views.contains(fragToolbarView) {
            oscFloatingUpperView.removeView(fragToolbarView)
          }
        } else {
          if !views.contains(fragVolumeView) {
            oscFloatingUpperView.addView(fragVolumeView, in: .leading)
          }
          if !views.contains(fragToolbarView) {
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

      hideSeekPreviewImmediately()
      updateDefaultArtVisibility(to: showDefaultArt)
      resetRotationPreview()
    })

    tasks.append(.init(duration: duration, timing: timing, { [self] in

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
    let isShowingVideoView = isTogglingVideoView && outputGeo.isVideoVisible

    // TASK 1: Background prep
    tasks.append(.instantTask { [self] in
      isAnimatingLayoutTransition = true  /// do not trigger `windowDidResize` if possible
      if isShowingVideoView {
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

        hideSeekPreviewImmediately()
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
          player.mpv.queue.async { [self] in
            player._setVideoTrackDisabled()
            DispatchQueue.main.async { [self] in
              videoView.removeFromSuperview()
            }
          }
        }

        let shouldDisableConstraint = outputGeo.isPlaylistVisible
        /// If needing to deactivate this constraint, do it before the toggle animation, so that window doesn't jump.
        /// (See note in `applyMusicModeGeo`)
        if shouldDisableConstraint {
          log.verbose{"Setting viewportBtmOffsetFromContentViewBtmConstraint priority = 1"}
          viewportBtmOffsetFromContentViewBtmConstraint.priority = .minimum
        }
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
      log.verbose{"Setting viewportBtmOffsetFromContentViewBtmConstraint priority = required"}
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
