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

  var slider: NSSlider { controlView as! NSSlider }

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

  override func barRect(flipped: Bool) -> NSRect {
    let superRect = super.barRect(flipped: flipped)
    let extraHeightNeeded = (RenderCache.shared.maxVolBarHeightNeeded + 2*RenderCache.shared.barMarginRadius) - superRect.height
    if extraHeightNeeded <= 0.0 {
      return superRect
    }

    let extraHeightAvailable = max(0.0, slider.bounds.height - superRect.height)
    let extraHeight = min(extraHeightAvailable, extraHeightNeeded)
    let rect = superRect.insetBy(dx: 0, dy: -(extraHeight * 0.5))
    return rect
  }

  override func drawBar(inside rect: NSRect, flipped: Bool) {
    guard let screen = controlView?.window?.screen else { return }
    guard let appearance = isClearBG ? NSAppearance(iinaTheme: .dark) : controlView?.window?.contentView?.iinaAppearance else { return }
    let knobMinX: CGFloat = round(knobRect(flipped: flipped).origin.x);
    appearance.applyAppearanceFor {
      RenderCache.shared.drawVolumeBar(in: rect, barHeight: RenderCache.shared.barHeight, screen: screen,
                                       darkMode: appearance.isDark, clearBG: isClearBG,
                                       knobMinX: knobMinX, knobWidth: knobWidth, currentValue: doubleValue, maxValue: maxValue)
    }
  }

  override func drawKnob(_ knobRect: NSRect) {
    if isClearBG { return }
    guard let screen = controlView?.window?.screen, let appearance = controlView?.window?.contentView?.iinaAppearance else { return }
    appearance.applyAppearanceFor {
      RenderCache.shared.drawKnob(isHighlighted ? .volumeKnobSelected : .volumeKnob, in: knobRect,
                                  darkMode: appearance.isDark,
                                  clearBG: isClearBG,
                                  knobWidth: knobWidth, mainKnobHeight: knobHeight,
                                  scaleFactor: screen.backingScaleFactor)
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
