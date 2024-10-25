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
  var scrollWheel: VirtualScrollWheel?

  override func scrollWheel(with event: NSEvent) {
    guard isEnabled else { return }
    scrollWheel?.scrollWheel(with: event)
  }
}
