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
    guard let wc else { return false }
    return wc.isScrollingOrDraggingPlaySlider || wc.seekPreview.animationState == .shown
  }
  
  // MARK:- Displaying the Cell

  override func barRect(flipped: Bool) -> NSRect {
    let superRect = super.barRect(flipped: flipped)
    let bf = BarFactory.shared
    let imgHeight = bf.heightNeeded(tallestBarHeight: bf.maxPlayBarHeightNeeded)
    let extraHeightNeeded = imgHeight - superRect.height
    if extraHeightNeeded <= 0.0 {
      return superRect
    }

    let extraHeightAvailable = max(0.0, slider.bounds.height - superRect.height)
    let extraHeight = min(extraHeightAvailable, extraHeightNeeded)
    let rect = superRect.insetBy(dx: 0, dy: -(extraHeight * 0.5))
    return rect
  }

  override func drawBar(inside barRect: NSRect, flipped: Bool) {
    let bf = BarFactory.shared
    let chapters = drawChapters ? player.info.chapters : []
    let durationSec = player.info.playbackDurationSec ?? 0.0
    /// The position of the knob, rounded for cleaner drawing
    let knobMinX: CGFloat = round(knobRect(flipped: flipped).origin.x);
    let cachedRanges = player.cachedRanges
    let isClearBG = isClearBG

    guard let appearance = isClearBG ? NSAppearance(iinaTheme: .dark) : iinaAppearance,
    let screen = controlView?.window?.screen else { return }
    let progressRatio = slider.progressRatio
    let seekPreview = player.windowController.seekPreview
    let currentPreviewTimeSec = seekPreview.currentPreviewTimeSec
    appearance.applyAppearanceFor {
      let knobWidth = enableDrawKnob ? knobWidth : 0

      var drawRect = bf.imageRect(in: barRect, tallestBarHeight: bf.maxPlayBarHeightNeeded)
      if #unavailable(macOS 11) {
        drawRect = NSRect(x: drawRect.origin.x,
                          y: drawRect.origin.y + 1,
                          width: drawRect.width,
                          height: drawRect.height - 2)
      }

      let barImg = bf.buildPlayBarImage(barWidth: barRect.width,
                                        screen: screen, darkMode: appearance.isDark, clearBG: isClearBG,
                                        knobMinX: knobMinX, knobWidth: knobWidth, currentValueRatio: progressRatio,
                                        durationSec: durationSec, chapters, cachedRanges: cachedRanges,
                                        currentPreviewTimeSec: currentPreviewTimeSec)
      NSGraphicsContext.current!.cgContext.draw(barImg, in: drawRect)
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
