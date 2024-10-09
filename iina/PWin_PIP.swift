//
//  PWin_PIP.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-08.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

// MARK: - Picture in Picture

extension PlayerWindowController: PIPViewControllerDelegate {

  func enterPIP(usePipBehavior: Preference.WindowBehaviorWhenPip? = nil, then doOnSuccess: (() -> Void)? = nil) {
    assert(DispatchQueue.isExecutingIn(.main))

    // Must not try to enter PiP if already in PiP - will crash!
    guard pipStatus == .notInPIP else { return }
    pipStatus = .intermediate

    exitInteractiveMode(then: { [self] in
      log.verbose("About to enter PIP")

      guard player.info.isVideoTrackSelected else {
        log.debug("Aborting request for PIP entry: no video track selected!")
        pipStatus = .notInPIP
        return
      }
      // Special case if in music mode
      miniPlayer.loadIfNeeded()
      if isInMiniPlayer && !miniPlayer.isVideoVisible {
        // need to re-enable video
        player.setVideoTrackEnabled(true)
      }

      doPIPEntry(usePipBehavior: usePipBehavior)
      if let doOnSuccess {
        doOnSuccess()
      }
    })
  }

  func showOrHidePipOverlayView() {
    let mustHide: Bool
    if pipStatus == .inPIP {
      mustHide = isInMiniPlayer && !musicModeGeo.isVideoVisible
    } else {
      mustHide = true
    }
    log.verbose("\(mustHide ? "Hiding" : "Showing") PiP overlay")
    pipOverlayView.isHidden = mustHide
  }

  private func doPIPEntry(usePipBehavior: Preference.WindowBehaviorWhenPip? = nil,
                          then doAfter: (() -> Void)? = nil) {
    guard let window else { return }
    pipStatus = .inPIP
    showFadeableViews()

    do {
      videoView.player.mpv.lockAndSetOpenGLContext()
      defer { videoView.player.mpv.unlockOpenGLContext() }
      pipVideo = NSViewController()
      // Remove these. They screw up PIP drag
      videoView.apply(nil)
      pipVideo.view = videoView
      // Remove remaining constraints. The PiP superview will manage videoView's layout.
      videoView.removeConstraints(videoView.constraints)
      pip.playing = player.info.isPlaying
      pip.title = window.title

      pip.presentAsPicture(inPicture: pipVideo)
      showOrHidePipOverlayView()

      let aspectRatioSize = player.videoGeo.videoSizeCAR
      log.verbose("Setting PiP aspect to \(aspectRatioSize.aspect)")
      pip.aspectRatio = aspectRatioSize
    }

    if !window.styleMask.contains(.fullScreen) && !window.isMiniaturized {
      let pipBehavior = usePipBehavior ?? Preference.enum(for: .windowBehaviorWhenPip) as Preference.WindowBehaviorWhenPip
      log.verbose("Entering PIP with behavior: \(pipBehavior)")
      switch pipBehavior {
      case .doNothing:
        break
      case .hide:
        isWindowHidden = true
        window.orderOut(self)
        log.verbose("PIP entered; adding player to hidden windows list: \(window.savedStateName.quoted)")
        break
      case .minimize:
        isWindowMiniaturizedDueToPip = true
        /// No need to add to `AppDelegate.windowsMinimized` - it will be handled by app-wide listener
        window.miniaturize(self)
        break
      }
      if Preference.bool(for: .pauseWhenPip) {
        player.pause()
      }
    }

    forceDraw()
    player.saveState()
    player.events.emit(.pipChanged, data: true)
  }

  func exitPIP() {
    guard pipStatus == .inPIP else { return }
    log.verbose("Exiting PIP")
    if pipShouldClose(pip) {
      // Prod Swift to pick the dismiss(_ viewController: NSViewController)
      // overload over dismiss(_ sender: Any?). A change in the way implicitly
      // unwrapped optionals are handled in Swift means that the wrong method
      // is chosen in this case. See https://bugs.swift.org/browse/SR-8956.
      pip.dismiss(pipVideo!)
    }
    player.events.emit(.pipChanged, data: false)
  }

  func prepareForPIPClosure(_ pip: PIPViewController) {
    guard pipStatus == .inPIP else { return }
    guard let window = window else { return }
    log.verbose("Preparing for PIP closure")
    // This is called right before we're about to close the PIP
    pipStatus = .intermediate

    // Hide the overlay view preemptively, to prevent any issues where it does
    // not hide in time and ends up covering the video view (which will be added
    // to the window under everything else, including the overlay).
    showOrHidePipOverlayView()

    if AppDelegate.shared.isTerminating {
      // Don't bother restoring window state past this point
      return
    }

    // Set frame to animate back to
    let geo = currentLayout.mode == .musicMode ? musicModeGeo.toPWinGeometry() : windowedModeGeo
    pip.replacementRect = geo.videoFrameInWindowCoords
    pip.replacementWindow = window

    // Bring the window to the front and deminiaturize it
    NSApp.activate(ignoringOtherApps: true)
    if isWindowMiniturized {
      window.deminiaturize(pip)
    }
  }

  func pipWillClose(_ pip: PIPViewController) {
    prepareForPIPClosure(pip)
  }

  func pipShouldClose(_ pip: PIPViewController) -> Bool {
    prepareForPIPClosure(pip)
    return true
  }

  func pipDidClose(_ pip: PIPViewController) {
    guard !AppDelegate.shared.isTerminating else { return }

    // seems to require separate animation blocks to work properly
    var tasks: [IINAAnimation.Task] = []

    if isWindowHidden {
      tasks.append(contentsOf: buildApplyWindowGeoTasks(windowedModeGeo)) // may have skipped updates while hidden
      tasks.append(IINAAnimation.Task({ [self] in
        showWindow(self)

        if let window {
          log.verbose("PIP did close; removing player from hidden windows list: \(window.savedStateName.quoted)")
          isWindowHidden = false
        }
      }))
    }

    tasks.append(.instantTask { [self] in
      /// Must set this before calling `addVideoViewToWindow()`
      pipStatus = .notInPIP

      addVideoViewToWindow()

      if isInMiniPlayer {
        miniPlayer.loadIfNeeded()
        miniPlayer.applyVideoTrackFromVideoVisibility()
      }

      // If using legacy windowed mode, need to manually add title to Window menu & Dock
      updateTitle()
    })

    tasks.append(.instantTask { [self] in
      // Similarly, we need to run a redraw here as well. We check to make sure we
      // are paused, because this causes a janky animation in either case but as
      // it's not necessary while the video is playing and significantly more
      // noticeable, we only redraw if we are paused.
      forceDraw()

      resetFadeTimer()

      isWindowMiniaturizedDueToPip = false
      player.saveState()
    })

    animationPipeline.submit(tasks)
  }

  func pipActionPlay(_ pip: PIPViewController) {
    player.resume()
  }

  func pipActionPause(_ pip: PIPViewController) {
    player.pause()
  }

  func pipActionStop(_ pip: PIPViewController) {
    // Stopping PIP pauses playback
    player.pause()
  }
}
