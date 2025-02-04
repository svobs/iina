//
//  PlaySliderCell.swift
//  iina
//
//  Created by lhc on 25/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class PlaySliderCell: ScrollableSliderCell {
  var drawChapters = Preference.bool(for: .showChapterPos)

  var wasPausedBeforeSeeking = false

  var isDarkMode: Bool {
    iinaAppearance?.isDark ?? false
  }

  override var enableDrawKnob: Bool {
    guard let wc else { return false }
    return !player.windowController.currentLayout.useSliderFocusEffect || wc.isScrollingOrDraggingPlaySlider || wc.seekPreview.animationState == .shown
  }
  
  // MARK:- Displaying the Cell

  override func drawBar(inside barRect: NSRect, flipped: Bool) {
    guard let appearance = iinaAppearance,
          let screen = controlView?.window?.screen else { return }

    /// The position of the knob, rounded for cleaner drawing
    let enableDrawKnob = enableDrawKnob
    let knobRect = knobRect(flipped: false)
    let useFocusEffect: Bool = enableDrawKnob && player.windowController.currentLayout.useSliderFocusEffect

    let chapters = drawChapters ? player.info.chapters : []
    let cachedRanges = player.info.cachedRanges
    let durationSec = player.info.playbackDurationSec ?? 0.0

    let progressRatio = slider.progressRatio
    // Disable hover zoom effect & indicator while actively scrolling; looks bad
    let currentPreviewTimeSec: Double? = player.windowController.isScrollingOrDraggingPlaySlider ? nil : player.windowController.seekPreview.currentPreviewTimeSec

    appearance.applyAppearanceFor {
      let bf = BarFactory.current
      let playBarImg = bf.buildPlayBarImage(barWidth: barRect.width,
                                            screen: screen, useFocusEffect: useFocusEffect, drawShadow: isClearBG,
                                            knobMinX: knobRect.minX, knobWidth: knobRect.width, currentValueRatio: progressRatio,
                                            durationSec: durationSec, chapters, cachedRanges: cachedRanges,
                                            currentPreviewTimeSec: currentPreviewTimeSec)

      bf.drawBar(playBarImg, in: barRect, tallestBarHeight: bf.maxPlayBarHeightNeeded)
    }
  }

  // MARK:- Tracking the Mouse

  override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
    player.log.verbose("PlaySlider drag-to-seek began")
    wasPausedBeforeSeeking = player.info.isPaused
    let result = super.startTracking(at: startPoint, in: controlView)
    if result {
      player.pause()
    }
    slider.needsDisplay = true
    return result
  }

  override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
    player.log.verbose("PlaySlider drag-to-seek ended")
    super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
    slider.needsDisplay = true
    if !wasPausedBeforeSeeking {
      player.resume()
    }
  }
}
