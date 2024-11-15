//
//  PlaySliderCell.swift
//  iina
//
//  Created by lhc on 25/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class PlaySliderCell: NSSliderCell {
  unowned var _player: PlayerCore!
  var player: PlayerCore {
    if let player = _player { return player }

    let windowController = self.controlView!.window!.windowController
    let player = (windowController as! PlayerWindowController).player
    _player = player
    return player
  }

  override var knobThickness: CGFloat {
    return knobWidth
  }

  var knobWidth: CGFloat = 3
  var knobHeight: CGFloat = 15

  var drawChapters = Preference.bool(for: .showChapterPos)

  var isPausedBeforeSeeking = false

  func updateColorsFromPrefs() {
    RenderCache.shared.updateBarColorsFromPrefs()
    controlView?.needsDisplay = true
  }

  override func awakeFromNib() {
    minValue = 0
    maxValue = 100
  }

  // MARK:- Displaying the Cell

  override func drawKnob(_ knobRect: NSRect) {
    guard let appearance = controlView?.window?.contentView?.iinaAppearance else { return }
    appearance.applyAppearanceFor {
      RenderCache.shared.drawKnob(isHighlighted ? .mainKnobSelected : .mainKnob, in: knobRect,
                                  darkMode: appearance.isDark, knobWidth: knobWidth, mainKnobHeight: knobHeight)
    }
  }

  override func knobRect(flipped: Bool) -> NSRect {
    let slider = self.controlView as! NSSlider
    let barRect = barRect(flipped: flipped)
    // The usable width of the bar is reduced by the width of the knob.
    let effectiveBarWidth = barRect.width - knobWidth
    let pos = barRect.origin.x + slider.progressRatio * effectiveBarWidth
    let rect = super.knobRect(flipped: flipped)

    let height: CGFloat
    if #available(macOS 11, *) {
      height = (barRect.origin.y - rect.origin.y) * 2 + barRect.height
    } else {
      height = rect.height
    }
    return NSMakeRect(pos, rect.origin.y, knobWidth, height)
  }

  override func drawBar(inside rect: NSRect, flipped: Bool) {
    let chapters = player.info.chapters
    let durationSec = player.info.playbackDurationSec ?? 0.0
    /// The position of the knob, rounded for cleaner drawing
    let knobMinX: CGFloat = round(knobRect(flipped: flipped).origin.x);
    let cachedRanges = player.cachedRanges

    guard let appearance = controlView?.window?.contentView?.iinaAppearance,
    let screen = controlView?.window?.screen else { return }
    let chaptersToDraw = drawChapters ? chapters : []
    appearance.applyAppearanceFor {
      RenderCache.shared.drawBar(in: rect, darkMode: appearance.isDark, screen: screen, knobMinX: knobMinX, knobWidth: knobWidth,
                                 durationSec: durationSec, chapters: chaptersToDraw, cachedRanges: cachedRanges)
    }
  }

  // MARK:- Tracking the Mouse

  override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
    player.log.verbose("PlaySlider drag-to-seek began")
    player.windowController.isDraggingPlaySlider = true
    isPausedBeforeSeeking = player.info.isPaused
    let result = super.startTracking(at: startPoint, in: controlView)
    if result {
      player.pause()
    }
    return result
  }

  override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
    player.log.verbose("PlaySlider drag-to-seek ended")
    super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
    guard let wc = player.windowController else { return }
    wc.isDraggingPlaySlider = false
    if !isPausedBeforeSeeking {
      player.resume()
    }
  }
}
