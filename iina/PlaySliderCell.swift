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
  private var barColorLeftGlow = NSColor.controlAccentColor
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
    barColorLeftGlow = barColorLeft.withAlphaComponent(0.5)
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
    let path = NSBezierPath(roundedRect: rect, xRadius: knobRadius, yRadius: knobRadius)
    let fillColor = isHighlighted ? knobActiveColor : knobColor

    let isLightTheme = !controlView!.window!.effectiveAppearance.isDark

    if isLightTheme {
      NSGraphicsContext.saveGraphicsState()
      let shadow = NSShadow()
      shadow.shadowBlurRadius = 1
      shadow.shadowOffset = NSSize(width: 0, height: -0.5)
      shadow.set()
    }

    fillColor.setFill()
    path.fill()

    if isLightTheme {
      if let shadowColor = NSShadow().shadowColor {
        path.lineWidth = 0.4
        shadowColor.setStroke()
        path.stroke()
      }
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

  private func drawGraphic(_ drawFunc: () -> Void) {
    NSGraphicsContext.saveGraphicsState()

    drawFunc()

    NSGraphicsContext.restoreGraphicsState()
  }

  override func drawBar(inside rect: NSRect, flipped: Bool) {
    let chapters = playerCore.info.chapters
    let durationSec = (playerCore.info.playbackDurationSec ?? 0.0)
    let cacheTime = playerCore.info.cacheTime

    let slider = self.controlView as! NSSlider
    let sliderValueTotal = slider.maxValue - slider.minValue

    /// The position of the knob, rounded for cleaner drawing
    let knobPos: CGFloat = round(knobRect(flipped: flipped).origin.x);

    /// How far progressed the current video is, used for drawing the bar background
    let progress = knobPos;

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


    let leftBarRect = NSRect(x: barRect.origin.x,
                             y: barRect.origin.y,
                             width: progress,
                             height: barRect.height)

    let rightBarRect = NSRect(x: barRect.origin.x + progress,
                              y: barRect.origin.y,
                              width: barRect.width - progress,
                              height: barRect.height)

    // Draw LEFT (the "finished" section of the progress bar)
    drawGraphic {
      NSBezierPath(rect: leftBarRect).addClip();

      barColorLeft.setFill()
      fullPath.fill()
    }

    /* FIXME: 
    // Draw LEFT glow
    drawGraphic {
      let leftBarGlowRect = NSRect(x: barRect.origin.x,
                               y: barRect.origin.y - 4,
                               width: progress,
                               height: barRect.height + 4 + 4)
      let leftBarGlowPath = NSBezierPath(rect: leftBarGlowRect)
      leftBarGlowPath.append(NSBezierPath(rect: leftBarRect).reversed)

      barColorLeftGlow.setFill()
      leftBarGlowRect.fill()
    }
     */

    // Draw cached sections (if applicable), drawing over the unfinished span:
    // FIXME: draw *all* cached sections
    if cacheTime > 0, durationSec > 0 {
      drawGraphic {
        let cachePercentage = cacheTime / durationSec * 100
        let cacheWidth = round(rect.width * CGFloat(cachePercentage / (sliderValueTotal))) + 2;

        let cacheRect = NSRect(x: barRect.origin.x,
                               y: barRect.origin.y,
                               width: cacheWidth,
                               height: barRect.height)
        NSBezierPath(rect: cacheRect).addClip();

        barColorPreCache.setFill()
        fullPath.fill()
      }
    }


    // Draw RIGHT (the "unfinished" section of the progress bar)
    drawGraphic {
      let rightPath = NSBezierPath(rect: rightBarRect)
      rightPath.addClip();
      barColorRight.setFill()
      fullPath.fill()
    }

    // Draw chapters (if configured)
    if drawChapters, durationSec > 0, chapters.count > 1 {
      drawGraphic {
        let isRetina = controlView?.window?.screen?.backingScaleFactor ?? 1.0 > 1.0
        let scaleFactor = controlView?.window?.screen?.screenScaleFactor ?? 1
        let lineWidth = round(1 + 1 / (isRetina ? (scaleFactor * 0.5) : scaleFactor))

        chapterStrokeColor.setStroke()
        for chapter in chapters[1...] {
          let chapPos = chapter.startTime / durationSec * barRect.width
          let linePath = NSBezierPath()
          linePath.lineWidth = lineWidth
          linePath.move(to: NSPoint(x: chapPos, y: barRect.origin.y))
          linePath.line(to: NSPoint(x: chapPos, y: barRect.origin.y + barRect.height))
          linePath.stroke()
        }
      }
    }
  }

  // MARK:- Tracking the Mouse

  override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
    playerCore.log.verbose("PlaySlider drag-to-seek began")
    playerCore.windowController.isDraggingPlaySlider = true
    isPausedBeforeSeeking = playerCore.info.isPaused
    let result = super.startTracking(at: startPoint, in: controlView)
    if result {
      playerCore.pause()
    }
    return result
  }

  override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
    playerCore.log.verbose("PlaySlider drag-to-seek ended")
    super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
    guard let wc = playerCore.windowController else { return }
    wc.isDraggingPlaySlider = false
    if !isPausedBeforeSeeking {
      playerCore.resume()
    }
  }
}
