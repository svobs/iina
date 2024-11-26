//
//  ScrollableSlider.swift
//
//  Created by Nate Thompson on 10/24/17.
//  Original source code: https://github.com/thompsonate/Scrollable-NSSlider

import Foundation

/// Adds scroll wheel support to `NSSlider`. Must set its `scrollWheelDelegate` property after init.
class ScrollableSlider: NSSlider {
  var scrollWheelDelegate: SliderScrollWheelDelegate?

  override func scrollWheel(with event: NSEvent) {
    guard isEnabled else { return }
    if let scrollWheelDelegate {
      scrollWheelDelegate.scrollWheel(with: event)
    } else {
      super.scrollWheel(with: event)
    }
  }

  /// Converts `deltaX` & `deltaY` from any type of `NSSlider` into a standardized 1-dimensional (+/-) delta
  func extractLinearDelta(from event: NSEvent) -> CGFloat {
    var delta: Double
    // Allow horizontal scrolling on horizontal and circular sliders
    if isVertical && sliderType == .linear {
      delta = event.deltaY
    } else if userInterfaceLayoutDirection == .rightToLeft {
      delta = event.deltaY + event.deltaX
    } else {
      delta = event.deltaY - event.deltaX
    }

    // Account for natural scrolling
    if event.isDirectionInvertedFromDevice {
      delta *= -1
    }
    return delta
  }

}
