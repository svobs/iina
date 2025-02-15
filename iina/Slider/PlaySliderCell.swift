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

  override var wantsKnob: Bool {
    guard let pwc else { return false }
    let alwaysShowKnob = Preference.bool(for: .alwaysShowSliderKnob) || !pwc.currentLayout.useSliderFocusEffect
    return alwaysShowKnob || wantsFocusEffect
  }

  var wantsFocusEffect: Bool {
    guard let pwc else { return false }
    return pwc.currentLayout.useSliderFocusEffect && (pwc.isScrollingOrDraggingPlaySlider || pwc.seekPreview.animationState == .shown)
  }

  // MARK:- Displaying the Cell

  override func drawBar(inside barRect: NSRect, flipped: Bool) {
    guard let appearance = sliderAppearance,
          let bf = pwc?.barFactory,
          let scaleFactor = controlView?.window?.screen?.backingScaleFactor else { return }

    /// The position of the knob, rounded for cleaner drawing. If `width==0`, do not draw knob.
    let knobRect = knobRect(flipped: false)

    let durationSec = player.info.playbackDurationSec ?? 0.0
    let currentValueSec = slider.progressRatio * durationSec
    let chapters = drawChapters ? player.info.chapters : []
    let cachedRanges = player.info.cachedRanges  // will be empty if drawing cache is disabled

    // Disable hover zoom effect & indicator while actively scrolling; looks bad
    let currentPreviewTimeSec: Double? = player.windowController.isScrollingOrDraggingPlaySlider ? nil : player.windowController.seekPreview.currentPreviewTimeSec

    appearance.applyAppearanceFor {
      let drawShadow = hasClearBG
      let playBarImg = bf.buildPlayBarImage(useFocusEffect: wantsFocusEffect,
                                            barWidth: barRect.width,
                                            scaleFactor: scaleFactor,
                                            knobRect: knobRect,
                                            currentValueSec: currentValueSec, maxValueSec: durationSec,
                                            currentPreviewTimeSec: currentPreviewTimeSec,
                                            chapters, cachedRanges: cachedRanges)

      bf.drawBar(playBarImg, in: barRect, scaleFactor: scaleFactor,
                 tallestBarHeight: bf.maxPlayBarHeightNeeded, drawShadow: drawShadow)
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
