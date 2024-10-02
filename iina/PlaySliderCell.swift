//
//  PlaySliderCell.swift
//  iina
//
//  Created by lhc on 25/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class PlaySliderCell: NSSliderCell {
  unowned var _playerCore: PlayerCore!
  var playerCore: PlayerCore {
    if let player = _playerCore { return player }

    let windowController = self.controlView!.window!.windowController
    let player = (windowController as! PlayerWindowController).player
    _playerCore = player
    return player
  }

  override var knobThickness: CGFloat {
    return knobWidth
  }

  var knobWidth: CGFloat = 3
  var knobHeight: CGFloat = 15
  var knobRadius: CGFloat = 1
  var barRadius: CGFloat = 1.5

  private var knobColor = NSColor(named: .mainSliderKnob)!
  private var knobActiveColor = NSColor(named: .mainSliderKnobActive)!
  private var barColorLeft = NSColor.controlAccentColor
  private var barColorPreCache = NSColor(named: .mainSliderBarPreCache)!
  private var barColorRight = NSColor(named: .mainSliderBarRight)!
  private var chapterStrokeColor = NSColor(named: .mainSliderBarChapterStroke)!

  var drawChapters = Preference.bool(for: .showChapterPos)

  var isPausedBeforeSeeking = false

  func updateColorsFromPrefs() {
    let userSetting: Preference.SliderBarLeftColor = Preference.enum(for: .playSliderBarLeftColor)
    switch userSetting {
    case .gray:
      barColorLeft = NSColor(named: .mainSliderBarLeft)!
    default:
      barColorLeft = NSColor.controlAccentColor
    }
    controlView?.needsDisplay = true
  }

  override func awakeFromNib() {
    minValue = 0
    maxValue = 100
  }

  // MARK:- Displaying the Cell

  override func drawKnob(_ knobRect: NSRect) {
    // Round the X position for cleaner drawing
    let rect = NSMakeRect(round(knobRect.origin.x),
                          knobRect.origin.y + 0.5 * (knobRect.height - knobHeight),
                          knobRect.width,
                          knobHeight)
    let isLightTheme = !controlView!.window!.effectiveAppearance.isDark

    if isLightTheme {
      NSGraphicsContext.saveGraphicsState()
      let shadow = NSShadow()
      shadow.shadowBlurRadius = 1
      shadow.shadowColor = .shadowColor
      shadow.shadowOffset = NSSize(width: 0, height: -0.5)
      shadow.set()
    }

    let path = NSBezierPath(roundedRect: rect, xRadius: knobRadius, yRadius: knobRadius)
    (isHighlighted ? knobActiveColor : knobColor).setFill()
    path.fill()

    if isLightTheme {
      path.lineWidth = 0.4
      NSColor.shadowColor.setStroke()
      path.stroke()
      NSGraphicsContext.restoreGraphicsState()
    }
  }

  override func knobRect(flipped: Bool) -> NSRect {
    let slider = self.controlView as! NSSlider
    let barRect = barRect(flipped: flipped)
    let percentage = slider.doubleValue / (slider.maxValue - slider.minValue)
    // The usable width of the bar is reduced by the width of the knob.
    let effectiveBarWidth = barRect.width - knobWidth
    let pos = barRect.origin.x + CGFloat(percentage) * effectiveBarWidth
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
    let info = playerCore.info

    let slider = self.controlView as! NSSlider

    /// The position of the knob, rounded for cleaner drawing
    let knobPos: CGFloat = round(knobRect(flipped: flipped).origin.x);

    /// How far progressed the current video is, used for drawing the bar background
    let progress = knobPos;

    NSGraphicsContext.saveGraphicsState()
    let barRect: NSRect
    if #available(macOS 11, *) {
      barRect = rect
    } else {
      barRect = NSRect(x: rect.origin.x,
                       y: rect.origin.y + 1,
                       width: rect.width,
                       height: rect.height - 2)
    }
    let fullPath = NSBezierPath(roundedRect: barRect, xRadius: barRadius, yRadius: barRadius)

    if controlView!.window!.effectiveAppearance.isDark {
      // Clip where the knob will be, including 1px from left & right of the knob
      fullPath.append(NSBezierPath(rect: NSRect(x: knobPos - 1, y: barRect.origin.y, width: knobWidth + 2, height: barRect.height)).reversed);
    }

    // draw left (the "finished" section of the progress bar)
    let leftBarRect = NSRect(x: barRect.origin.x,
                             y: barRect.origin.y,
                             width: progress,
                             height: barRect.height)
    NSBezierPath(rect: leftBarRect).addClip();

    barColorLeft.setFill()
    fullPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Draw cached sections (if applicable), drawing over the unfinished span:
    // FIXME: draw *all* cached sections
    let cacheTime = info.cacheTime
    if cacheTime != 0,
        let durationSec = info.playbackDurationSec, durationSec != 0 {

      NSGraphicsContext.saveGraphicsState()

      let cachePercentage = Double(cacheTime) / Double(durationSec) * 100
      let cacheWidth = round(rect.width * CGFloat(cachePercentage / (slider.maxValue - slider.minValue))) + 2;

      // draw cache
      let cacheRect = NSRect(x: barRect.origin.x,
                             y: barRect.origin.y,
                             width: cacheWidth,
                             height: barRect.height)
      NSBezierPath(rect: cacheRect).addClip();

      barColorPreCache.setFill()
      fullPath.fill()
      NSGraphicsContext.restoreGraphicsState()
    }


    // draw right (the "unfinished" section of the progress bar)
    NSGraphicsContext.saveGraphicsState()
    let rightBarRect = NSRect(x: barRect.origin.x + progress,
                              y: barRect.origin.y,
                              width: barRect.width - progress,
                              height: barRect.height)
    let rightPath = NSBezierPath(rect: rightBarRect)
    barColorRight.setFill()
    fullPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // draw chapters
    if drawChapters, let totalSec = info.playbackDurationSec {
      let isRetina = controlView?.window?.screen?.backingScaleFactor ?? 1.0 > 1.0
      let scaleFactor = controlView?.window?.screen?.screenScaleFactor ?? 1
      let lineWidth = round(1 + 1 / (isRetina ? (scaleFactor * 0.5) : scaleFactor))

      NSGraphicsContext.saveGraphicsState()
      chapterStrokeColor.setStroke()
      let chapters = info.chapters
      if chapters.count > 1 {
        for chapt in chapters[1...] {
          let chapPos = CGFloat(chapt.time.second) / CGFloat(totalSec) * barRect.width
          let linePath = NSBezierPath()
          linePath.lineWidth = lineWidth
          linePath.move(to: NSPoint(x: chapPos, y: barRect.origin.y))
          linePath.line(to: NSPoint(x: chapPos, y: barRect.origin.y + barRect.height))
          linePath.stroke()
        }
      }
      NSGraphicsContext.restoreGraphicsState()
    }
  }


  // MARK:- Tracking the Mouse

  override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
    isPausedBeforeSeeking = playerCore.info.isPaused
    let result = super.startTracking(at: startPoint, in: controlView)
    if result {
      playerCore.pause()
      playerCore.windowController.hideSeekTimeAndThumbnail()
    }
    return result
  }

  override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
    if !isPausedBeforeSeeking {
      playerCore.resume()
    }
    super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
  }
}
