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

  unowned var pwc: PlayerWindowController! = nil

  @objc func handleMagnifyGesture(recognizer: NSMagnificationGestureRecognizer) {
    guard !pwc.isInInteractiveMode else { return }
    guard !pwc.isInMiniPlayer && !pwc.miniPlayer.isVideoVisible else { return }
    let pinchAction: Preference.PinchAction = Preference.enum(for: .pinchAction)
    guard pinchAction != .none else { return }

    switch pinchAction {
    case .none:
      return
    case .fullScreen:
      // enter/exit fullscreen
      guard !pwc.isInMiniPlayer else { return }  // Disallow full screen toggle from pinch while in music mode
      guard !pwc.isAnimatingLayoutTransition else { return }
      if recognizer.state == .began {
        let isEnlarge = recognizer.magnification > 0
        if isEnlarge != pwc.isFullScreen {
          recognizer.state = .recognized
          pwc.toggleWindowFullScreen()
        }
      }
    case .windowSize:
      IINAAnimation.disableAnimation{ [self] in
        scaleWindow(recognizer: recognizer)
      }
    case .windowSizeOrFullScreen:
      guard !pwc.isAnimatingLayoutTransition else { return }
      guard let window = pwc.window, let screen = window.screen else { return }

      // Check for full screen toggle conditions first
      if !pwc.isInMiniPlayer, recognizer.state != .ended {  // Disallow full screen toggle from pinch while in music mode
        let scale = recognizer.magnification + 1.0
        if pwc.isFullScreen, scale < 1.0 {
          /// Change `windowedModeGeo` so that the window still fills the screen after leaving full screen, rather than whatever size it was
          pwc.windowedModeGeo = pwc.windowedModeGeo.clone(windowFrame: screen.visibleFrame, screenID: screen.screenID)
          // Set this to disable window resize listeners immediately instead of waiting for the transitionn to set it
          // (seems to prevent hiccups in the animation):
          pwc.isAnimatingLayoutTransition = true
          // Exit FS:
          pwc.toggleWindowFullScreen()
          /// Force the gesture to end after toggling FS. Window scaling via `scaleWindow` looks terrible when overlapping FS animation
          // TODO: put effort into truly seamless window scaling which also can toggle legacy FS
          recognizer.state = .ended
          pwc.isMagnifying = false  // really need to work hard to stop future events
          // KLUDGE! AppKit does not give us the correct visibleFrame until after we have exited FS. The resulting window (as of MacOS 14.4)
          // is 6 pts too tall. For now, run another quick resize after exiting FS using the (now) correct visibleFrame
          DispatchQueue.main.async { [self] in
            pwc.animationPipeline.submitInstantTask({ [self] in
              pwc.resizeViewport(to: screen.visibleFrame.size, centerOnScreen: true, duration: IINAAnimation.DefaultDuration * 0.25)
            })
          }
          return
        } else if !pwc.isFullScreen, scale > 1.0 {
          let screenFrame = screen.visibleFrame
          let heightIsMax = window.frame.height >= screenFrame.height
          let widthIsMax = window.frame.width >= screenFrame.width
          // If viewport is not locked, the window must be the size of the screen in both directions before triggering full screen.
          // If viewport is locked, window is considered at maximum if either of its sides is filling all the available space in its dimension.
          if (heightIsMax && widthIsMax) || (Preference.bool(for: .lockViewportToVideoSize) && (heightIsMax || widthIsMax)) {
            pwc.isAnimatingLayoutTransition = true
            pwc.toggleWindowFullScreen()
            /// See note above
            recognizer.state = .ended
            pwc.isMagnifying = false
            return
          }
        }
      }

      // If full screen wasn't toggled, try window size:
      IINAAnimation.disableAnimation{ [self] in
        scaleWindow(recognizer: recognizer)
      }
    }  // end switch
  }

  private func scaleWindow(recognizer: NSMagnificationGestureRecognizer) {
    guard !pwc.isFullScreen else { return }

    var finalGeo: PWinGeometry? = nil
    // adjust window size
    switch recognizer.state {
    case .began:
      pwc.isMagnifying = true

      if pwc.currentLayout.isMusicMode {
        pwc.musicModeGeo = pwc.musicModeGeoForCurrentFrame()
      } else {
        pwc.windowedModeGeo = pwc.windowedGeoForCurrentFrame()
      }
      scaleVideoFromPinchGesture(to: recognizer.magnification)
    case .changed:
      guard pwc.isMagnifying else { return }
      scaleVideoFromPinchGesture(to: recognizer.magnification)
    case .ended:
      guard pwc.isMagnifying else { return }
      finalGeo = scaleVideoFromPinchGesture(to: recognizer.magnification)
      pwc.isMagnifying = false
    case .cancelled, .failed:
      guard pwc.isMagnifying else { return }
      finalGeo = scaleVideoFromPinchGesture(to: 1.0)
      pwc.isMagnifying = false
    default:
      return
    }

    if let finalGeo {
      if pwc.currentLayout.isMusicMode {
        pwc.log.verbose("Updating musicModeGeo from mag gesture state \(recognizer.state.rawValue)")
        let musicModeGeo = pwc.musicModeGeo.clone(windowFrame: finalGeo.windowFrame)
        pwc.applyMusicModeGeo(musicModeGeo, setFrame: false, updateCache: true)
      } else {
        pwc.log.verbose{"Updating windowedModeGeo & calling updateMPVWindowScale from mag gesture state \(recognizer.state.rawValue)"}
        pwc.windowedModeGeo = finalGeo
        pwc.player.updateMPVWindowScale(using: finalGeo)
        pwc.player.info.intendedViewportSize = finalGeo.viewportSize
        pwc.player.saveState()
      }
    }
  }

  @discardableResult
  private func scaleVideoFromPinchGesture(to magnification: CGFloat) -> PWinGeometry? {
    /// For best experience for the user, do not check `isAnimatingLayoutTransition` at state `began` (i.e., allow it to start keeping track
    /// of pinch), but do not allow this method to execute (i.e. do not respond) until after layout transitions are complete.
    guard !pwc.isAnimatingLayoutTransition else { return nil }

    // avoid zero and negative numbers because they will cause problems
    let scale = max(0.0001, magnification + 1.0)
    pwc.log.verbose{"Scaling pinched video, target scale: \(scale)"}
    let currentLayout = pwc.currentLayout

    // If in music mode but playlist is not visible, allow scaling up to screen size like regular windowed mode.
    // If playlist is visible, do not resize window beyond current window height
    if currentLayout.isMusicMode {
      pwc.miniPlayer.loadIfNeeded()

      guard pwc.miniPlayer.isVideoVisible || pwc.miniPlayer.isPlaylistVisible else {
        pwc.log.verbose("Window is in music mode but neither video nor playlist is visible. Ignoring pinch gesture")
        return nil
      }
      let newWidth = round(pwc.musicModeGeo.windowFrame.width * scale)
      var newMusicModeGeo = pwc.musicModeGeo.scalingVideo(to: newWidth)!
      pwc.log.verbose{"Scaling pinched video in music mode → \(newMusicModeGeo)"}

      IINAAnimation.disableAnimation {
        newMusicModeGeo = pwc.applyMusicModeGeo(newMusicModeGeo, updateCache: false)
      }
      // Kind of clunky to convert to PWinGeometry, just to fit the function signature, then convert it back. But...could be worse.
      return newMusicModeGeo.toPWinGeometry()
    }
    // Else: not music mode

    let originalGeo = pwc.windowedModeGeo

    let newViewportSize = originalGeo.viewportSize.multiplyThenRound(scale)

    /// Using `noConstraints` here has the bonus effect of allowing viewport to be resized via pinch when the video is already maximized
    /// (only useful when in windowed mode and `lockViewportToVideoSize` is disabled)
    let intendedGeo = originalGeo.scalingViewport(to: newViewportSize, screenFit: .noConstraints, mode: currentLayout.mode)
    // User has actively resized the video. Assume this is the new intended resolution, even if it is outside the current screen size.
    // This is useful for various features such as resizing without "lockViewportToVideoSize", or toggling visibility of outside bars.
    pwc.player.info.intendedViewportSize = intendedGeo.viewportSize

    let newGeo = intendedGeo.refitted(using: .stayInside)
    pwc.resizeWindowImmediately(using: newGeo)
    return newGeo
  }
}
