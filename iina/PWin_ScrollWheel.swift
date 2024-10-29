//
//  PWin_ScrollWheel.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-25.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation


/// An instance of this is stored in the `PlayerWindowController` instance. Also see its `playSliderAction(_:)
class PlaySliderScrollWheel: VirtualScrollWheel {
  /** We need to pause the video when a user starts seeking by scrolling.
   This property records whether the video is paused initially so we can
   recover the status when scrolling finished. */
  private var wasPlayingBeforeSeeking = false

  override func updateSensitivity() {
    let seekTick = Preference.integer(for: .relativeSeekAmount).clamped(to: 1...5)
    sensitivity = pow(10.0, Double(seekTick) * 0.5 - 2)
    Logger.log.verbose("Updated PlaySlider sensitivity=\(sensitivity))")
  }

  override func scrollSessionWillBegin(with event: NSEvent, _ session: ScrollSession) {
    guard let player = delegateSlider?.thisPlayer else { return }

    player.log.verbose("PlaySlider scrollWheel seek began")
    // pause video when seek begins
    if player.info.isPlaying {
      player.pause()
      wasPlayingBeforeSeeking = true
    }
  }

  override func scrollSessionDidEnd(_ session: ScrollSession) {
    guard let player = delegateSlider?.thisPlayer else { return }

    player.log.verbose("PlaySlider scrollWheel seek ended")
    // only resume playback when it was playing before seeking
    if wasPlayingBeforeSeeking {
      player.resume()
      wasPlayingBeforeSeeking = false
    }
  }
}


/// An instance of this is stored in the `PlayerWindowController` instance. Also see its `volumeSliderAction(_:)
class VolumeSliderScrollWheel: VirtualScrollWheel {
  override func updateSensitivity() {
    let sensitivityTick = Preference.integer(for: .volumeScrollAmount).clamped(to: 1...4)
    sensitivity = pow(10.0, Double(sensitivityTick) * 0.5 - 2.0)
    log.verbose("Updated VolumeSlider sensitivity=\(sensitivity)")
  }
}


class PWinScrollWheel: VirtualScrollWheel {
  /// One of `playSliderScrollWheel`, `volumeSliderScrollWheel`, or `nil`
  private(set) var delegate: VirtualScrollWheel? = nil
  let wc: PlayerWindowController

  init(_ playerWindowController: PlayerWindowController) {
    self.wc = playerWindowController
    super.init()
    self.log = playerWindowController.player.log
  }

  override func scrollSessionWillBegin(with event: NSEvent, _ session: ScrollSession) {
    // Determine scroll direction, then scroll action, based on cumulative scroll deltas.
    // Pick direction (X or Y) based on which coordinate the user scrolled farther in.
    // For "step" scrolls, it's easy to pick because the delta should by all in either X or Y…
    var deltaX: CGFloat = event.scrollingDeltaX
    var deltaY: CGFloat = event.scrollingDeltaY
    // For "smooth" scrolls, there is a small grace period before the this method is called. During that time,
    // the session will collect pending scroll events. By summing the distances from all of these, we can make
    // a more accurate determination for the user's intended direction.
    for event in session.eventsPending {
      deltaX += event.scrollingDeltaX
      deltaY += event.scrollingDeltaY
    }

    let scrollAction: Preference.ScrollAction
    let distX = deltaX.magnitude
    let distY = deltaY.magnitude
    if distX > distY {
      log.verbose("Scroll direction is horizontal: \(distX) > \(distY)")
      scrollAction = Preference.enum(for: .horizontalScrollAction)
    } else {
      log.verbose("Scroll direction is vertical: \(distX) ≤ \(distY)")
      scrollAction =  Preference.enum(for: .verticalScrollAction)
    }

    switch scrollAction {
    case .seek:
      delegate = wc.playSliderScrollWheel
    case .volume:
      delegate = wc.volumeSliderScrollWheel
    default:
      delegate = nil
    }

    guard let delegate else { return }
    delegateSlider = delegate.delegateSlider
    sensitivity = delegate.sensitivity

    delegate.scrollSessionWillBegin(with: event, session)
  }

  override func scrollSessionDidEnd(_ session: ScrollSession) {
    delegate?.scrollSessionDidEnd(session)
  }
}


extension PlayerWindowController {

  override func scrollWheel(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    guard !isMouseEvent(event, inAnyOf: [currentControlBar, leadingSidebarView, trailingSidebarView,
                                         titleBarView, subPopoverView]) else { return }

    windowScrollWheel.scrollWheel(with: event)
  }
}
