//
//  VolumeSliderCell.swift
//  iina
//
//  Created by lhc on 26/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

/// See also: `PlaySliderCell`
class VolumeSliderCell: NSSliderCell {

  var knobWidth: CGFloat = 3
  var knobHeight: CGFloat = 15

  override var acceptsFirstResponder: Bool {
    return false
  }

  override func awakeFromNib() {
    minValue = 0
    maxValue = Double(Preference.integer(for: .maxVolume))
  }

  override var knobThickness: CGFloat {
    return knobWidth
  }

  override func drawBar(inside rect: NSRect, flipped: Bool) {
    if maxValue > 100 {
      // round this value to obtain a pixel perfect clip line
      let x = round(rect.minX + rect.width * CGFloat(100 / maxValue))
      let clipPath = NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: x - 1, height: rect.height))
      clipPath.append(NSBezierPath(rect: NSRect(x: x + 1, y: rect.minY, width: rect.maxX - x - 1, height: rect.height)))
      clipPath.setClip()
    }
    super.drawBar(inside: rect, flipped: flipped)
  }

  override func drawKnob(_ knobRect: NSRect) {
    guard let appearance = controlView?.window?.contentView?.iinaAppearance else { return }
    appearance.applyAppearanceFor {
      RenderCache.shared.drawKnob(isHighlighted ? .volumeKnobSelected : .volumeKnob, in: knobRect,
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

}
