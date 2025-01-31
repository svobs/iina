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

  override func drawBar(inside barRect: NSRect, flipped: Bool) {
    guard let appearance = iinaAppearance,
          let screen = controlView?.window?.screen else { return }

    let enableDrawKnob = enableDrawKnob
    let knobRect = knobRect(flipped: false)
    let useFocusEffect: Bool = enableDrawKnob && player.windowController.currentLayout.useSliderFocusEffect
    let previewValue: CGFloat? = enableDrawKnob ? 0.0 : nil  // FIXME: find actual preview value
 
    appearance.applyAppearanceFor {
      let bf = BarFactory.current
      let volBarImg = bf.buildVolumeBarImage(useFocusEffect: useFocusEffect,
                                             barWidth: barRect.width,
                                             screen: screen, knobMinX: knobRect.minX, knobWidth: knobRect.width,
                                             currentValue: doubleValue, maxValue: maxValue,
                                             currentPreviewValue: previewValue)
      
      bf.drawBar(volBarImg, in: barRect, tallestBarHeight: bf.maxVolBarHeightNeeded)
    }
  }

}
