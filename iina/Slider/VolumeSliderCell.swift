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
    guard let wc else { return false }
    return wc.isScrollingOrDraggingVolumeSlider || wc.isMouseHoveringOverVolumeSlider
  }

  override var currentKnobType: KnobFactory.KnobType {
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
    let extraHeightNeeded = (BarFactory.shared.maxVolBarHeightNeeded + 2*BarFactory.shared.barMarginRadius) - superRect.height
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
    assert(bf.barHeight <= barRect.height, "barHeight \(bf.barHeight) > barRect.height \(barRect.height)")
    guard let screen = controlView?.window?.screen else { return }
    guard let appearance = isClearBG ? NSAppearance(iinaTheme: .dark) : controlView?.window?.contentView?.iinaAppearance else { return }
    let knobMinX: CGFloat = round(knobRect(flipped: flipped).origin.x);
    let knobWidth = enableDrawKnob ? knobWidth : 0
    appearance.applyAppearanceFor {
      var drawRect = bf.imageRect(in: barRect, tallestBarHeight: bf.maxVolBarHeightNeeded)
      if #unavailable(macOS 11) {
        drawRect = NSRect(x: drawRect.origin.x,
                          y: drawRect.origin.y + 1,
                          width: drawRect.width,
                          height: drawRect.height - 2)
      }
      let volBarImg = bf.buildVolumeBarImage(darkMode: appearance.isDark, clearBG: isClearBG, barWidth: barRect.width,
                                             barHeight: bf.barHeight, screen: screen, knobMinX: knobMinX, knobWidth: knobWidth,
                                             currentValue: doubleValue, maxValue: maxValue)
      NSGraphicsContext.current!.cgContext.draw(volBarImg, in: drawRect)
    }
  }

}
