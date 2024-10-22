//
//  ScrollableSlider.swift
//
//  Created by Nate Thompson on 10/24/17.
//  Original source code: https://github.com/thompsonate/Scrollable-NSSlider
//

import Foundation

fileprivate let minScrollWheelDuration: CGFloat = 0.08

/// Adds scroll wheel support to `NSSlider`.
class ScrollableSlider: NSSlider {
  var sensitivity: Double = 1.0
  var lastScrollWheelStartTime: TimeInterval = 0
  private var isIgnoringScroll: Bool = false

  override func scrollWheel(with event: NSEvent) {
    guard isEnabled else { return }

    let isTrackpadBegan = event.phase.contains(.began)
    let isTrackpadEnd = event.phase.contains(.ended)
    let currentTime = Date().timeIntervalSince1970
    if isTrackpadBegan {
      lastScrollWheelStartTime = currentTime
      isIgnoringScroll = false
    }
    let trackpadDuration = currentTime - lastScrollWheelStartTime

    if isTrackpadEnd && trackpadDuration < minScrollWheelDuration {
      Logger.log.verbose("Ignored scroll wheel event; duration too short (\(trackpadDuration))")
      isIgnoringScroll = true
      return
    }


    guard !isIgnoringScroll && trackpadDuration >= minScrollWheelDuration else {
      // Trackpad min time was not met; ignore
      return
    }

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

    let valueChange = (maxValue - minValue) * delta * sensitivity / 100.0
    // There can be a huge number of requests which don't change the existing value.
    // Discard them for a large increase in performance:
    guard valueChange != 0.0 else { return }

    var newValue = doubleValue + valueChange

    // Wrap around if slider is circular
    if sliderType == .circular {
      if newValue < minValue {
        newValue = maxValue - abs(valueChange)
      } else if newValue > maxValue {
        newValue = minValue + abs(valueChange)
      }
    }

    doubleValue = newValue
    sendAction(action, to: target)
  }
}
