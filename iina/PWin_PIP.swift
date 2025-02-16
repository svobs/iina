//
//  PWin_PIP.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-08.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

enum PIPStatus {
  case notInPIP
  case inPIP
  case intermediate
}

/// Picture in Picture handling for a single player window
extension PlayerWindowController {

  /// `PIPState`: Encapsulates all state for PiP.
  class PIPState {
    unowned var player: PlayerCore
    var log: Logger.Subsystem { player.log }

    var status = PIPStatus.notInPIP {
      didSet {
        log.verbose("Updated pip.status to: \(status)")
      }
    }

    /// Needs to be retained during PiP, but cannot be reused
    var videoController: NSViewController!

    var controller: PIPViewController { _pip }
    lazy var _pip: PIPViewController = {
      let pip = VideoPIPViewController()
      pip.delegate = player.windowController
      return pip
    }()

    init(_ player: PlayerCore) {
      self.player = player
    }
  }
}

extension PlayerWindowController: PIPViewControllerDelegate {

  func enterPIP(usePipBehavior: Preference.WindowBehaviorWhenPip? = nil, then doOnSuccess: (() -> Void)? = nil) {
    assert(DispatchQueue.isExecutingIn(.main))

    // Must not try to enter PiP if already in PiP - will crash!
    guard pip.status == .notInPIP else { return }
    pip.status = .intermediate

    exitInteractiveMode(then: { [self] in
      log.verbose("About to enter PIP")
      PlayerManager.shared.pipPlayer = player

      guard player.info.isVideoTrackSelected else {
        log.debug("Aborting request for PIP entry: no video track selected!")
        pip.status = .notInPIP
        return
      }
      
      if isInMiniPlayer {
        miniPlayer.loadIfNeeded()
        if !miniPlayer.isVideoVisible {
          // need to re-enable video to enter PiP
          player.setVideoTrackEnabled()
        }
      }

      doPIPEntry(usePipBehavior: usePipBehavior)
      if let doOnSuccess {
        doOnSuccess()
      }
    })
  }

  func showOrHidePipOverlayView() {
    let mustHide: Bool
    if pip.status == .inPIP {
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
    pip.status = .inPIP
    showFadeableViews()

    do {
      videoView.player.mpv.lockAndSetOpenGLContext()
      defer { videoView.player.mpv.unlockOpenGLContext() }

      // Remove these. They screw up PIP drag
      videoView.apply(nil)

      pip.videoController = NSViewController()
      pip.videoController.view = videoView
      // Remove remaining constraints. The PiP superview will manage videoView's layout.
      videoView.removeConstraints(videoView.constraints)
      pip.controller.playing = player.info.isPlaying
      pip.controller.title = window.title

      pip.controller.presentAsPicture(inPicture: pip.videoController)
      showOrHidePipOverlayView()

      let aspectRatioSize = player.videoGeo.videoSizeCAR
      log.verbose("Setting PiP aspect to \(aspectRatioSize.aspect)")
      pip.controller.aspectRatio = aspectRatioSize
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
    guard pip.status == .inPIP else { return }
    log.verbose("Exiting PIP")
    if pipShouldClose(pip.controller) {
      // Prod Swift to pick the dismiss(_ viewController: NSViewController)
      // overload over dismiss(_ sender: Any?). A change in the way implicitly
      // unwrapped optionals are handled in Swift means that the wrong method
      // is chosen in this case. See https://bugs.swift.org/browse/SR-8956.
      pip.controller.dismiss(pip.videoController!)
    }
    player.events.emit(.pipChanged, data: false)
  }

  func prepareForPIPClosure(_ pipController: PIPViewController) {
    guard pip.status == .inPIP else { return }
    guard let window = window else { return }
    log.verbose("Preparing for PIP closure")
    // This is called right before we're about to close the PIP
    pip.status = .intermediate

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
    pipController.replacementRect = geo.videoFrameInWindowCoords
    pipController.replacementWindow = window

    // Bring the window to the front and deminiaturize it
    NSApp.activate(ignoringOtherApps: true)
    if isWindowMiniturized {
      window.deminiaturize(pipController)
    } else {
      // Bring to front so it is more obvious which window is relevant:
      window.makeKeyAndOrderFront(pipController)
    }
  }

  func pipWillClose(_ pip: PIPViewController) {
    prepareForPIPClosure(pip)
  }

  func pipShouldClose(_ pip: PIPViewController) -> Bool {
    prepareForPIPClosure(pip)
    return true
  }

  func pipDidClose(_ pipController: PIPViewController) {
    guard !AppDelegate.shared.isTerminating else { return }
    guard let window else { return }

    // seems to require separate animation blocks to work properly
    var tasks: [IINAAnimation.Task] = []

    if isWindowHidden {
      tasks.append(contentsOf: buildApplyWindowGeoTasks(windowedModeGeo)) // may have skipped updates while hidden
      tasks.append(IINAAnimation.Task({ [self] in
        showWindow(self)

        log.verbose("PIP did close; removing player from hidden windows list: \(window.savedStateName.quoted)")
        isWindowHidden = false
      }))
    }

    tasks.append(.instantTask { [self] in
      /// Must set this before calling `addVideoViewToWindow()`
      pip.status = .notInPIP

      addVideoViewToWindow()

      if isInMiniPlayer {
        miniPlayer.loadIfNeeded()
        if !miniPlayer.isVideoVisible {
          player.setVideoTrackDisabled()
        } else {
          player.setVideoTrackEnabled()
        }

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

      fadeableViews.hideTimer.restart()

      isWindowMiniaturizedDueToPip = false
      player.saveState()
    })

    animationPipeline.submit(tasks)
  }

  func pipActionPlay(_ pipController: PIPViewController) {
    player.resume()
  }

  func pipActionPause(_ pipController: PIPViewController) {
    player.pause()
  }

  func pipActionStop(_ pipController: PIPViewController) {
    // Stopping PIP pauses playback
    player.pause()
  }
}
