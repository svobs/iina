//
//  PWin_ScrollWheel.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-25.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation


/// Processes scroll wheel events for a play slider.
///
/// Also see `playSliderAction(_:)` in `PlayerWindowController`.
class PlaySliderScrollWheel: SliderScrollWheelDelegate {
  /** We need to pause the video when a user starts seeking by scrolling.
   This property records whether the video is paused initially so we can
   recover the status when scrolling finished. */
  private var wasPlayingBeforeSeeking = false

  override func scrollSessionWillBegin(_ session: ScrollSession) {
    guard let player = slider.associatedPlayer else { return }

    player.log.verbose("PlaySlider scrollWheel seek began")
    // pause video when seek begins
    if player.info.isPlaying {
      player.pause()
      wasPlayingBeforeSeeking = true
    }

    session.sensitivity = Preference.seekScrollSensitivity()
    // Do not even bother to set session.valueAtStart - will only pollute logs with inaccuracies
    session.modelValueAtStart = player.info.playbackPositionSec
  }

  override func scrollSessionDidEnd(_ session: ScrollSession) {
    guard let player = slider.associatedPlayer else { return }

    session.modelValueAtEnd = player.info.playbackPositionSec

    player.log.verbose("PlaySlider scrollWheel seek ended")
    // only resume playback when it was playing before seeking
    if wasPlayingBeforeSeeking {
      player.resume()
      wasPlayingBeforeSeeking = false
    }

    // Need to call this to enable debug logging
    super.scrollSessionDidEnd(session)
  }

  override func scrollDidUpdate(_ session: ScrollSession) {
    guard let player = slider.associatedPlayer else { return }
    guard let position = player.info.playbackPositionSec,
          let duration = player.info.playbackDurationSec else { return }
    let valueDelta: CGFloat = session.consumePendingEvents(for: slider)
    let newAbsolutePosition = (position + Double(valueDelta)).clamped(to: 0.0...duration)
    // Use modelValueAtEnd to keep track of last seek, to prevent sending duplicate seek requests
    guard session.modelValueAtEnd != newAbsolutePosition else { return }
    session.modelValueAtEnd = newAbsolutePosition
    player.windowController.seekFromPlaySlider(absoluteSecond: newAbsolutePosition, forceExactSeek: false)
  }

}  /// end `class PlaySliderScrollWheel`


/// Processes scroll wheel events for a volume slider.
///
/// Also see `volumeSliderAction(_:)` in `PlayerWindowController`.
class VolumeSliderScrollWheel: SliderScrollWheelDelegate {
  override func scrollSessionWillBegin(_ session: ScrollSession) {
    session.sensitivity = Preference.volumeScrollSensitivity()
    session.valueAtStart = slider.doubleValue
  }

}  /// end `class VolumeSliderScrollWheel`


/// A virtual scroll wheel which contains logic needed to start a scroll wheel session, and when a scroll session is able to start,
/// chooses between `PlaySliderScrollWheel` or `VolumeSliderScrollWheel`, and sends all scroll events to the chosen object for the
/// remainder of the session.
///
/// An instance of this class is used to handle scroll wheel events inside a single player. See `PlayerWindowController.scrollWheel`
class PWinScrollWheel: VirtualScrollWheel {
  /// One of `playSliderScrollWheel`, `volumeSliderScrollWheel`, or `nil`
  private(set) var delegate: VirtualScrollWheel? = nil
  let wc: PlayerWindowController

  init(_ playerWindowController: PlayerWindowController) {
    self.wc = playerWindowController
    super.init()
    self.log = playerWindowController.player.log
  }

  override func scrollSessionWillBegin(_ session: ScrollSession) {
    var scrollAction: Preference.ScrollAction? = nil
    // Determine scroll direction, then scroll action, based on cumulative scroll deltas.
    // Pick direction (X or Y) based on which coordinate the user scrolled farther in.
    // For "step" scrolls, it's easy to pick because the delta should by all in either X or Y…
    // For "smooth" scrolls, there is a small grace period before the this method is called. During that time,
    // the session will collect pending scroll events. By summing the distances from all of these, we can make
    // a more accurate determination for the user's intended direction.
    session.lock.withLock {
      var deltaX: CGFloat = 0.0
      var deltaY: CGFloat = 0.0
      for event in session.eventsPending {
        deltaX += event.scrollingDeltaX
        deltaY += event.scrollingDeltaY
      }

      let distX = deltaX.magnitude
      let distY = deltaY.magnitude
      if distX > distY {
        log.verbose("Scroll direction is horizontal: \(distX) > \(distY)")
        scrollAction = Preference.enum(for: .horizontalScrollAction)
      } else {
        log.verbose("Scroll direction is vertical: \(distX) ≤ \(distY)")
        scrollAction =  Preference.enum(for: .verticalScrollAction)
      }
    }

    switch scrollAction {
    case .seek:
      delegate = wc.playSlider.scrollWheelDelegate!
    case .volume:
      delegate = wc.volumeSlider.scrollWheelDelegate!
    default:
      delegate = nil
    }

    delegate?.scrollSessionWillBegin(session)
  }

  override func scrollDidUpdate(_ session: ScrollSession) {
    delegate?.scrollDidUpdate(session)
  }

  override func scrollSessionDidEnd(_ session: ScrollSession) {
    delegate?.scrollSessionDidEnd(session)
  }

}  /// end `class PWinScrollWheel`


extension PlayerWindowController {

  override func scrollWheel(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    guard !isMouseEvent(event, inAnyOf: [currentControlBar, leadingSidebarView, trailingSidebarView,
                                         titleBarView, subPopoverView]) else { return }

    windowScrollWheel.scrollWheel(with: event)
  }
}
