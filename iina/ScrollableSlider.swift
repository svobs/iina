//
//  ScrollableSlider.swift
//
//  Created by Nate Thompson on 10/24/17.
//  Original source code: https://github.com/thompsonate/Scrollable-NSSlider
//

import Foundation

/// Adds scroll wheel support to `NSSlider`.
///
/// From `developer.apple.com`:
/// The Trackpad preference pane includes an option for scroll gestures: two fingers moving the content view of a scroll view around.
/// Technically, scroll gestures are not specific gestures but mouse events. Unlike a gesture, a scroll wheel event (that is, an event
/// of type NSScrollWheel) can have both a phase property and a momentumPhase property. The momentumPhase property helps you detect
/// momentum scrolling, in which the hardware continues to issue scroll wheel events even though the user is no longer physically
/// scrolling. Devices such as Magic Mouse and Multi-Touch trackpad enable momentum scrolling.

/// During non momentum scrolling, AppKit routes each scroll wheel event to the view that is beneath the pointer for that event. In
/// non momentum scroll wheel events, momentumPhase has the value NSEventPhaseNone.
///
/// During momentum scrolling, AppKit routes each scroll wheel event to the view that was beneath the pointer when momentum scrolling
/// started. In momentum scroll wheel events, phase has the value NSEventPhaseNone. When the device switches from user-performed
/// scroll events to momentum scroll wheel events, momentumPhase is set to NSEventPhaseBegan. For subsequent momentum scroll wheel
/// events, momentumPhase is set to NSEventPhaseChanged until the momentum subsides, or the user stops the momentum scrolling; the
/// final momentum scroll wheel event has a momentumPhase value of NSEventPhaseEnded.
class ScrollableSlider: NSSlider {
  private let scrollWheel: VirtualScrollWheel

  var sensitivity: Double = 1.0
  var stepScrollSensitivity: Double = 10.0

  required init?(coder: NSCoder) {
    self.scrollWheel = VirtualScrollWheel()
    super.init(coder: coder)
    scrollWheel.scrollWheelDidStart = scrollWheelDidStart
    scrollWheel.scrollWheelDidEnd = scrollWheelDidEnd
  }

  /// Subclasses can override
  func scrollWheelDidStart(_ event: NSEvent) { }

  /// Subclasses can override
  func scrollWheelDidEnd() { }

  /// Returns true if this slider is in mid-scroll
  func isScrolling() -> Bool {
    return scrollWheel.isScrolling()
  }

  func isScrollingNonAppleDevice() -> Bool {
    return scrollWheel.isScrollingNonAppleDevice()
  }

  override func scrollWheel(with event: NSEvent) {
    guard isEnabled else { return }

    scrollWheel.changeState(with: event)
    guard scrollWheel.isScrolling() else { return }
    executeScrollAction(with: event, isNonAppleDevice: scrollWheel.isScrollingNonAppleDevice())
  }

  func executeScrollAction(with event: NSEvent, isNonAppleDevice: Bool) {
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

    let adjustment = isNonAppleDevice ? stepScrollSensitivity : sensitivity

    let valueChange = (maxValue - minValue) * delta * adjustment / 100.0
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
