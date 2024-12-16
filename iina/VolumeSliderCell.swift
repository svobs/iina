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
  var isClearBG: Bool = false

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
    guard let appearance = isClearBG ? NSAppearance(iinaTheme: .dark) : controlView?.window?.contentView?.iinaAppearance else { return }
    let knobMinX: CGFloat = round(knobRect(flipped: flipped).origin.x);
    appearance.applyAppearanceFor {
      RenderCache.shared.drawVolumeBar(in: rect, darkMode: appearance.isDark, clearBG: isClearBG,
                                       knobMinX: knobMinX, knobWidth: knobWidth, currentValue: doubleValue, maxValue: maxValue)
    }
  }

  override func drawKnob(_ knobRect: NSRect) {
    if isClearBG { return }
    guard let appearance = controlView?.window?.contentView?.iinaAppearance else { return }
    appearance.applyAppearanceFor {
      RenderCache.shared.drawKnob(isHighlighted ? .volumeKnobSelected : .volumeKnob, in: knobRect,
                                  darkMode: appearance.isDark,
                                  clearBG: isClearBG,
                                  knobWidth: knobWidth, mainKnobHeight: knobHeight)
    }
  }

  override func knobRect(flipped: Bool) -> NSRect {
    let slider = self.controlView as! NSSlider
    let barRect = barRect(flipped: flipped)
    // The usable width of the bar is reduced by the width of the knob.
    let effectiveBarWidth = barRect.width - knobThickness
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
