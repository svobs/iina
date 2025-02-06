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

  var isMouseHoveringOverVolumeSlider = false

  /// Calls `wc.refreshVolumeSliderHoverEffect` on timeout
  let hoverTimer = TimeoutTimer(timeout: Constants.TimeInterval.seekPreviewHideTimeout)

  override var wantsKnob: Bool {
    let alwaysShowKnob = Preference.bool(for: .alwaysShowSliderKnob) || !player.windowController.currentLayout.useSliderFocusEffect
    return alwaysShowKnob || wantsFocusEffect
  }

  var wantsFocusEffect: Bool {
    guard let wc else { return false }
    return player.windowController.currentLayout.useSliderFocusEffect && (wc.isScrollingOrDraggingVolumeSlider || isMouseHoveringOverVolumeSlider)
  }

  override var currentKnobType: KnobFactory.KnobType {
    isHighlighted ? .volumeKnobSelected : .volumeKnob
  }

  override func awakeFromNib() {
    minValue = 0
    maxValue = Double(Preference.integer(for: .maxVolume))
    hoverTimer.action = refreshVolumeSliderHoverEffect
  }

  override func drawBar(inside barRect: NSRect, flipped: Bool) {
    guard let appearance = sliderAppearance,
          let screen = controlView?.window?.screen else { return }

    /// The position of the knob, rounded for cleaner drawing. If `width==0`, do not draw knob.
    let knobRect = knobRect(flipped: false)
    let previewValue: CGFloat? = nil  // FIXME: find actual preview value, implement preview

    appearance.applyAppearanceFor {
      let bf = BarFactory.current
      let drawShadow = hasClearBG
      let scaleFactor = screen.backingScaleFactor
      let volBarImg = bf.buildVolumeBarImage(useFocusEffect: wantsFocusEffect,
                                             barWidth: barRect.width,
                                             scaleFactor: scaleFactor, knobRect: knobRect,
                                             currentValue: doubleValue, maxValue: maxValue,
                                             currentPreviewValue: previewValue)
      
      bf.drawBar(volBarImg, in: barRect, scaleFactor: scaleFactor,
                 tallestBarHeight: bf.maxVolBarHeightNeeded, drawShadow: drawShadow)
    }
  }

  func refreshVolumeSliderHoverEffect() {
    guard let wc else { return }
    let priorHoverState = isMouseHoveringOverVolumeSlider
    let newHoverState = wc.isMouseActuallyInside(view: slider)
    isMouseHoveringOverVolumeSlider = newHoverState
    if priorHoverState != newHoverState {
      slider.needsDisplay = true
    }
    if newHoverState {
      hoverTimer.restart()
    } else {
      hoverTimer.cancel()
    }
  }

}
