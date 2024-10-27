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

  override func beginScrollSession(with event: NSEvent) {
    super.beginScrollSession(with: event)
    guard let player = delegateSlider?.thisPlayer else { return }

    player.log.verbose("PlaySlider scrollWheel seek began")
    // pause video when seek begins
    if player.info.isPlaying {
      player.pause()
      wasPlayingBeforeSeeking = true
    }
  }

  override func endScrollSession() {
    super.endScrollSession()
    guard let player = delegateSlider?.thisPlayer else { return }

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
  /// One of `playSliderScrollWheel`, `volumeSliderScrollWheel`, or `nil`
  private(set) var delegate: VirtualScrollWheel? = nil
  let wc: PlayerWindowController

  init(_ playerWindowController: PlayerWindowController) {
    self.wc = playerWindowController
  }

  override func executeScrollAction(with event: NSEvent) {
    delegate?.executeScrollAction(with: event)
  }

  override func beginScrollSession(with event: NSEvent) {
    super.beginScrollSession(with: event)

    let scrollAction: Preference.ScrollAction

    // Determine scroll direction, and thus scroll action, based on cumulative scroll deltas.
    // By using the sum
    var deltaX: CGFloat = 0
    var deltaY: CGFloat = 0
    for event in currentSession!.eventsBeforeStart {
      deltaX += event.scrollingDeltaX
      deltaY += event.scrollingDeltaY
    }
    deltaX += event.scrollingDeltaX
    deltaY += event.scrollingDeltaY
    if deltaX.magnitude > deltaY.magnitude {
      wc.player.log.verbose("Scroll direction is horizontal")
      scrollAction = Preference.enum(for: .horizontalScrollAction)
    } else {
      wc.player.log.verbose("Scroll direction is vertical")
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

    delegate?.beginScrollSession(with: event, usingSession: currentSession!)
  }

  override func endScrollSession() {
    super.endScrollSession()
    delegate?.endScrollSession()
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
