//
//  VolumeSliderCell.swift
//  iina
//
//  Created by lhc on 26/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

/// See also: `PlaySliderCell`
class VolumeSliderCell: ScrollableSliderCell {
  override var enableDrawKnob: Bool {
    return wc?.isScrollingOrDraggingVolumeSlider ?? true
  }

  override var currentKnobType: RenderCache.KnobType {
    isHighlighted ? .volumeKnobSelected : .volumeKnob
  }

  override func awakeFromNib() {
    minValue = 0
    maxValue = Double(Preference.integer(for: .maxVolume))

    knobWidth = 3
    knobHeight = 15
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
    let knobWidth = enableDrawKnob ? knobWidth : 0
    appearance.applyAppearanceFor {
      RenderCache.shared.drawVolumeBar(in: rect, barHeight: RenderCache.shared.barHeight, screen: screen,
                                       darkMode: appearance.isDark, clearBG: isClearBG,
                                       knobMinX: knobMinX, knobWidth: knobWidth, currentValue: doubleValue, maxValue: maxValue)
    }
  }

}
