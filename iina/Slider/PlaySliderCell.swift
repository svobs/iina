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

  var isPausedBeforeSeeking = false

  var iinaAppearance: NSAppearance? {
    controlView?.window?.contentView?.iinaAppearance
  }

  var isDarkMode: Bool {
    iinaAppearance?.isDark ?? false
  }

  override var enableDrawKnob: Bool {
    return wc?.isScrollingOrDraggingPlaySlider ?? true
  }
  
  // MARK:- Displaying the Cell

  override func barRect(flipped: Bool) -> NSRect {
    let superRect = super.barRect(flipped: flipped)
    let extraHeightNeeded = (BarFactory.shared.maxPlayBarHeightNeeded + 2 * BarFactory.shared.barMarginRadius) - superRect.height
    if extraHeightNeeded <= 0.0 {
      return superRect
    }

    let extraHeightAvailable = max(0.0, slider.bounds.height - superRect.height)
    let extraHeight = min(extraHeightAvailable, extraHeightNeeded)
    let rect = superRect.insetBy(dx: 0, dy: -(extraHeight * 0.5))
    return rect
  }

  override func drawBar(inside rect: NSRect, flipped: Bool) {
    let chapters = player.info.chapters
    let durationSec = player.info.playbackDurationSec ?? 0.0
    /// The position of the knob, rounded for cleaner drawing
    let knobMinX: CGFloat = round(knobRect(flipped: flipped).origin.x);
    let cachedRanges = player.cachedRanges
    let isClearBG = isClearBG

    guard let appearance = isClearBG ? NSAppearance(iinaTheme: .dark) : iinaAppearance,
    let screen = controlView?.window?.screen else { return }
    let chaptersToDraw = drawChapters ? chapters : []
    let progressRatio = slider.progressRatio
    let seekPreviewState = player.windowController.seekPreview.animationState
    let barHeight = BarFactory.shared.barHeight
    let isShowingSeekPreview = seekPreviewState == .shown || seekPreviewState == .willShow
    appearance.applyAppearanceFor {
      let knobWidth = enableDrawKnob ? knobWidth : 0
      BarFactory.shared.drawPlayBar(in: rect, barHeight: barHeight, darkMode: appearance.isDark, clearBG: isClearBG,
                                     screen: screen, knobMinX: knobMinX, knobWidth: knobWidth, progressRatio: progressRatio,
                                     durationSec: durationSec, chapters: chaptersToDraw, cachedRanges: cachedRanges,
                                     isShowingSeekPreview: isShowingSeekPreview)
    }
  }

  // MARK:- Tracking the Mouse

  override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
    player.log.verbose("PlaySlider drag-to-seek began")
    isPausedBeforeSeeking = player.info.isPaused
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
    if !isPausedBeforeSeeking {
      player.resume()
    }
  }
}
