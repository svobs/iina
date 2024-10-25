//
//  PWin_ScrollWheel.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-25.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation


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

  override func startScrollSession(with event: NSEvent) {
    super.startScrollSession(with: event)
    guard let player = outputSlider?.thisPlayer else { return }

    player.log.verbose("PlaySlider scrollWheel seek began")
    // pause video when seek begins
    if player.info.isPlaying {
      player.pause()
      wasPlayingBeforeSeeking = true
    }
  }

  override func endScrollSession() {
    super.endScrollSession()
    guard let player = outputSlider?.thisPlayer else { return }

    player.log.verbose("PlaySlider scrollWheel seek ended")
    // only resume playback when it was playing before seeking
    if wasPlayingBeforeSeeking {
      player.resume()
      wasPlayingBeforeSeeking = false
    }
  }
}


class VolumeSliderScrollWheel: VirtualScrollWheel {
  override func updateSensitivity() {
    let sensitivityTick = Preference.integer(for: .volumeScrollAmount).clamped(to: 1...4)
    sensitivity = pow(10.0, Double(sensitivityTick) * 0.5 - 2.0)
    Logger.log.verbose("Updated VolumeSlider sensitivity=\(sensitivity)")
  }
}


class PWinScrollWheel: VirtualScrollWheel {
  /// One of `playSlider`, `volumeSlider`, or `nil`
  var scrollActionSlider: VirtualScrollWheel? = nil
  let wc: PlayerWindowController

  init(_ playerWindowController: PlayerWindowController) {
    self.wc = playerWindowController
  }

  override func executeScrollAction(with event: NSEvent) {
    scrollActionSlider?.executeScrollAction(with: event)
  }

  override func startScrollSession(with event: NSEvent) {
    super.startScrollSession(with: event)

    let scrollAction: Preference.ScrollAction
    // determine scroll direction, and thus scroll action, based on cumulative scroll deltas
    if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
      wc.player.log.verbose("Scroll direction is horizontal")
      scrollAction = Preference.enum(for: .horizontalScrollAction)
    } else {
      wc.player.log.verbose("Scroll direction is vertical")
      scrollAction =  Preference.enum(for: .verticalScrollAction)
    }

    switch scrollAction {
    case .seek:
      scrollActionSlider = wc.playSliderScrollWheel
    case .volume:
      scrollActionSlider = wc.volumeSliderScrollWheel
    default:
      scrollActionSlider = nil
    }

    scrollActionSlider?.startScrollSession(with: event)
  }

  override func endScrollSession() {
    super.endScrollSession()
    scrollActionSlider?.endScrollSession()
  }
}


extension PlayerWindowController {

  override func scrollWheel(with event: NSEvent) {
    guard !isInInteractiveMode else { return }

    guard !isMouseEvent(event, inAnyOf: [currentControlBar, leadingSidebarView, trailingSidebarView,
                                         titleBarView, subPopoverView]) else { return }
    scrollWheel.scrollWheel(with: event)
  }

}
