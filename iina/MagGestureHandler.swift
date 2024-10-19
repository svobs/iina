//
//  MagnificationHandler.swift
//  iina
//
//  Created by Matt Svoboda on 8/31/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// Provides Pinch to Zoom feature.
class MagnificationGestureHandler: NSMagnificationGestureRecognizer {

  lazy var magnificationGestureRecognizer: NSMagnificationGestureRecognizer = {
    return NSMagnificationGestureRecognizer(target: self, action: #selector(PlayerWindowController.handleMagnifyGesture(recognizer:)))
  }()

  unowned var windowController: PlayerWindowController! = nil

  @objc func handleMagnifyGesture(recognizer: NSMagnificationGestureRecognizer) {
    guard !windowController.isInInteractiveMode else { return }
    guard !(windowController.isInMiniPlayer && !windowController.miniPlayer.isVideoVisible) else { return }
    let pinchAction: Preference.PinchAction = Preference.enum(for: .pinchAction)
    guard pinchAction != .none else { return }

    switch pinchAction {
    case .none:
      return
    case .fullScreen:
      // enter/exit fullscreen
      guard !windowController.isInMiniPlayer else { return }  // Disallow full screen toggle from pinch while in music mode
      guard !windowController.isAnimatingLayoutTransition else { return }
      if recognizer.state == .began {
        let isEnlarge = recognizer.magnification > 0
        if isEnlarge != windowController.isFullScreen {
          recognizer.state = .recognized
          windowController.toggleWindowFullScreen()
        }
      }
    case .windowSize:
      scaleWindow(recognizer: recognizer)
    case .windowSizeOrFullScreen:
      guard !windowController.isAnimatingLayoutTransition else { return }
      guard let window = windowController.window, let screen = window.screen else { return }

      // Check for full screen toggle conditions first
      if !windowController.isInMiniPlayer, recognizer.state != .ended {  // Disallow full screen toggle from pinch while in music mode
        let scale = recognizer.magnification + 1.0
        if windowController.isFullScreen, scale < 1.0 {
          /// Change `windowedModeGeo` so that the window still fills the screen after leaving full screen, rather than whatever size it was
          windowController.windowedModeGeo = windowController.windowedModeGeo.clone(windowFrame: screen.visibleFrame, screenID: screen.screenID)
          // Set this to disable window resize listeners immediately instead of waiting for the transitionn to set it
          // (seems to prevent hiccups in the animation):
          windowController.isAnimatingLayoutTransition = true
          // Exit FS:
          windowController.toggleWindowFullScreen()
          /// Force the gesture to end after toggling FS. Window scaling via `scaleWindow` looks terrible when overlapping FS animation
          // TODO: put effort into truly seamless window scaling which also can toggle legacy FS
          recognizer.state = .ended
          windowController.isMagnifying = false  // really need to work hard to stop future events
          // KLUDGE! AppKit does not give us the correct visibleFrame until after we have exited FS. The resulting window (as of MacOS 14.4)
          // is 6 pts too tall. For now, run another quick resize after exiting FS using the (now) correct visibleFrame
          DispatchQueue.main.async { [self] in
            windowController.animationPipeline.submitInstantTask({ [self] in
              windowController.resizeViewport(to: screen.visibleFrame.size, centerOnScreen: true, duration: IINAAnimation.DefaultDuration * 0.25)
            })
          }
          return
        } else if !windowController.isFullScreen, scale > 1.0 {
          let screenFrame = screen.visibleFrame
          let heightIsMax = window.frame.height >= screenFrame.height
          let widthIsMax = window.frame.width >= screenFrame.width
          // If viewport is not locked, the window must be the size of the screen in both directions before triggering full screen.
          // If viewport is locked, window is considered at maximum if either of its sides is filling all the available space in its dimension.
          if (heightIsMax && widthIsMax) || (Preference.bool(for: .lockViewportToVideoSize) && (heightIsMax || widthIsMax)) {
            windowController.isAnimatingLayoutTransition = true
            windowController.toggleWindowFullScreen()
            /// See note above
            recognizer.state = .ended
            windowController.isMagnifying = false
            return
          }
        }
      }

      // If full screen wasn't toggled, try window size:
      scaleWindow(recognizer: recognizer)
    }  // end switch
  }

  private func scaleWindow(recognizer: NSMagnificationGestureRecognizer) {
    guard !windowController.isFullScreen else { return }

    var finalGeometry: PWinGeometry? = nil
    // adjust window size
    switch recognizer.state {
    case .began:
      windowController.isMagnifying = true

      guard let window = windowController.window else { return }
      let screenID = NSScreen.getOwnerOrDefaultScreenID(forViewRect: window.frame)
      if windowController.currentLayout.isMusicMode {
        windowController.musicModeGeo = windowController.musicModeGeo.clone(windowFrame: window.frame, screenID: screenID)
      } else {
        windowController.windowedModeGeo = windowController.windowedGeoForCurrentFrame()
      }
      scaleVideoFromPinchGesture(to: recognizer.magnification)
    case .changed:
      guard windowController.isMagnifying else { return }
      scaleVideoFromPinchGesture(to: recognizer.magnification)
    case .ended:
      guard windowController.isMagnifying else { return }
      finalGeometry = scaleVideoFromPinchGesture(to: recognizer.magnification)
      windowController.isMagnifying = false
    case .cancelled, .failed:
      guard windowController.isMagnifying else { return }
      finalGeometry = scaleVideoFromPinchGesture(to: 1.0)
      windowController.isMagnifying = false
    default:
      return
    }

    if let finalGeometry {
      if windowController.currentLayout.isMusicMode {
        windowController.log.verbose("Updating musicModeGeo from mag gesture state \(recognizer.state.rawValue)")
        let musicModeGeo = windowController.musicModeGeo.clone(windowFrame: finalGeometry.windowFrame)
        windowController.applyMusicModeGeo(musicModeGeo, setFrame: false, updateCache: true)
      } else {
        windowController.log.verbose("Updating windowedModeGeo & calling updateMPVWindowScale from mag gesture state \(recognizer.state.rawValue)")
        windowController.windowedModeGeo = finalGeometry
        windowController.player.updateMPVWindowScale(using: finalGeometry)
        windowController.player.info.intendedViewportSize = finalGeometry.viewportSize
        windowController.player.saveState()
      }
    }
  }

  @discardableResult
  private func scaleVideoFromPinchGesture(to magnification: CGFloat) -> PWinGeometry? {
    /// For best experience for the user, do not check `isAnimatingLayoutTransition` at state `began` (i.e., allow it to start keeping track
    /// of pinch), but do not allow this method to execute (i.e. do not respond) until after layout transitions are complete.
    guard !windowController.isAnimatingLayoutTransition else { return nil }

    // avoid zero and negative numbers because they will cause problems
    let scale = max(0.0001, magnification + 1.0)
    windowController.log.verbose("Scaling pinched video, target scale: \(scale)")
    let currentLayout = windowController.currentLayout

    // If in music mode but playlist is not visible, allow scaling up to screen size like regular windowed mode.
    // If playlist is visible, do not resize window beyond current window height
    if currentLayout.isMusicMode {
      windowController.miniPlayer.loadIfNeeded()

      guard windowController.miniPlayer.isVideoVisible || windowController.miniPlayer.isPlaylistVisible else {
        windowController.log.verbose("Window is in music mode but neither video nor playlist is visible. Ignoring pinch gesture")
        return nil
      }
      let newWidth = round(windowController.musicModeGeo.windowFrame.width * scale)
      var newMusicModeGeometry = windowController.musicModeGeo.scaleVideo(to: newWidth)!
      windowController.log.verbose("Scaling pinched video in music mode, result: \(newMusicModeGeometry)")

      IINAAnimation.disableAnimation{
        newMusicModeGeometry = windowController.applyMusicModeGeo(newMusicModeGeometry, updateCache: false)
      }
      // Kind of clunky to convert to PWinGeometry, just to fit the function signature, then convert it back. But...could be worse.
      return newMusicModeGeometry.toPWinGeometry()
    }
    // Else: not music mode

    let originalGeometry = windowController.windowedModeGeo

    let newViewportSize = originalGeometry.viewportSize.multiplyThenRound(scale)

    /// Using `noConstraints` here has the bonus effect of allowing viewport to be resized via pinch when the video is already maximized
    /// (only useful when in windowed mode and `lockViewportToVideoSize` is disabled)
    let intendedGeo = originalGeometry.scaleViewport(to: newViewportSize, fitOption: .noConstraints, mode: currentLayout.mode)
    // User has actively resized the video. Assume this is the new intended resolution, even if it is outside the current screen size.
    // This is useful for various features such as resizing without "lockViewportToVideoSize", or toggling visibility of outside bars.
    windowController.player.info.intendedViewportSize = intendedGeo.viewportSize

    let newGeometry = intendedGeo.refit(.stayInside)
    windowController.applyWindowResize(usingGeometry: newGeometry)
    return newGeometry
  }
}
