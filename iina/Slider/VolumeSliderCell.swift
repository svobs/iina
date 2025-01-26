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
    return !player.windowController.currentLayout.useSliderFocusEffect || wc.isScrollingOrDraggingVolumeSlider || wc.isMouseHoveringOverVolumeSlider
  }

  override var currentKnobType: KnobFactory.KnobType {
    isHighlighted ? .volumeKnobSelected : .volumeKnob
  }

  override func awakeFromNib() {
    minValue = 0
    maxValue = Double(Preference.integer(for: .maxVolume))
  }

  override func barRect(flipped: Bool) -> NSRect {
    let superRect = super.barRect(flipped: flipped)
    let bf = BarFactory.current
    let imgHeight = bf.heightNeeded(tallestBarHeight: bf.maxVolBarHeightNeeded)
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
    guard let appearance = isClearBG ? NSAppearance(iinaTheme: .dark) : iinaAppearance,
          let screen = controlView?.window?.screen else { return }

    let enableDrawKnob = enableDrawKnob
    let (knobMinX, knobWidth) = knobMinXAndWidth(enableDrawKnob: enableDrawKnob)
    let useFocusEffect: Bool = enableDrawKnob && player.windowController.currentLayout.useSliderFocusEffect
    let previewValue: CGFloat? = enableDrawKnob ? 0.0 : nil  // FIXME: find actual preview value

    appearance.applyAppearanceFor {
      let bf = BarFactory.current
      let volBarImg = bf.buildVolumeBarImage(darkMode: appearance.isDark, clearBG: isClearBG, useFocusEffect: useFocusEffect,
                                             barWidth: barRect.width,
                                             screen: screen, knobMinX: knobMinX, knobWidth: knobWidth,
                                             currentValue: doubleValue, maxValue: maxValue,
                                             currentPreviewValue: previewValue)
      
      bf.drawBar(volBarImg, in: barRect, tallestBarHeight: bf.maxVolBarHeightNeeded)
    }
  }

}
