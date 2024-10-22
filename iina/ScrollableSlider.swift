//
//  ScrollableSlider.swift
//
//  Created by Nate Thompson on 10/24/17.
//  Original source code: https://github.com/thompsonate/Scrollable-NSSlider
//

import Foundation

fileprivate let momentumStartTimeout: TimeInterval = 0.05

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
  /// This is used for 2 different purposes, each using a different subset of states, which is a little sloppy.
  /// But at least it will stay within this class.
  private enum ScrollState {
    case notScrolling
    case scrollMayBegin(_ intentStartTime: TimeInterval)
    case userScroll
    case userScrollJustEnded
    case momentumScrollJustStarted
    case momentumScrolling
    case momentumScrollJustEnded
  }
  private var state: ScrollState = .notScrolling
  private var momentumTimer: Timer? = nil

  var sensitivity: Double = 1.0

  /// Subclasses can override
  func scrollWheelDidStart() { }

  /// Subclasses can override
  func scrollWheelDidEnd() { }

  /// Returns true if this slider is in mid-scroll
  func isScrolling() -> Bool {
    switch state {
    case .notScrolling, .scrollMayBegin:
      return false
    default:
      return true
    }
  }

  override func scrollWheel(with event: NSEvent) {
    guard isEnabled else { return }

    let newState = mapPhasesToScrollState(event)

    Logger.log.verbose("SCROLL WHEEL phases={\(event.phase.name), \(event.momentumPhase.name)} State: \(state) → \(newState)")

    switch newState {
    case .scrollMayBegin:
      state = newState
      return

    case .userScroll:
      switch state {
      case .scrollMayBegin(let intentStartTime):
        let timeElapsed = Date().timeIntervalSince1970 - intentStartTime
        guard timeElapsed >= Constants.TimeInterval.minScrollWheelTimeThreshold else {
          return  // not yet reached
        }
        Logger.log.verbose("Time elapsed (\(timeElapsed)) >= minScrollTimeThreshold \(Constants.TimeInterval.minScrollWheelTimeThreshold). Starting scroll")
        state = .userScroll
        scrollWheelDidStart()
      case .userScroll:
        state = .userScroll
      default:
        state = .notScrolling
        return  // invalid state
      }

    case .userScrollJustEnded:
      switch state {
      case .userScroll:
        state = .userScrollJustEnded
        momentumTimer?.invalidate()
        momentumTimer = Timer.scheduledTimer(timeInterval: momentumStartTimeout, target: self,
                                             selector: #selector(self.momentumStartDidTimeOut), userInfo: nil, repeats: false)
      default:
        state = .notScrolling
        return  // invalid state
      }

    case .momentumScrollJustStarted:
      switch state {
      case .userScrollJustEnded:
        momentumTimer?.invalidate()
        state = .momentumScrollJustStarted
      default:
        state = .notScrolling
        return  // invalid state
      }

    case .momentumScrolling:
      switch state {
      case .momentumScrollJustStarted, .momentumScrolling:
        momentumTimer?.invalidate()
        state = .momentumScrolling
      default:
        state = .notScrolling
        return  // invalid state
      }

    case .momentumScrollJustEnded:
      switch state {
      case .momentumScrollJustStarted, .momentumScrolling:
        state = .notScrolling
        scrollWheelDidEnd()
      default:
        state = .notScrolling
        return  // invalid state
      }

    default:
      Logger.log.fatalError("Invalid value for newState: \(newState)")
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
    Logger.log.verbose("Delta: \(delta)")

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

  /// Executed when `momentumTimer` fires.
  @objc func momentumStartDidTimeOut() {
    guard case .userScrollJustEnded = state else { return }
    Logger.log.verbose("Momentum timer expired")
    state = .notScrolling
    scrollWheelDidEnd()
  }

  private func mapPhasesToScrollState(_ event: NSEvent) -> ScrollState {
    let phase = event.phase
    let momentumPhase = event.momentumPhase

    if momentumPhase.isEmpty {
      if phase.contains(.mayBegin) {
        /// This only happens for trackpad. It indicates user pressed down on it but did not change its value.
        /// Just treat it like a `began` event so that it starts the min threshold timer
        return .scrollMayBegin(Date().timeIntervalSince1970)
      } else if phase.contains(.began) {
        if case .scrollMayBegin = state {
          /// This is valid if `mayBegin` was already encountered
          return .userScroll
        }
        return .scrollMayBegin(Date().timeIntervalSince1970)
      } else if phase.contains(.changed) {
        return .userScroll
      } else if phase.contains(.ended) || phase.contains(.cancelled) {
        return .userScrollJustEnded
      }
    } else if phase.isEmpty {
      if momentumPhase.contains(.began) {
        return .momentumScrollJustStarted
      } else if momentumPhase.contains(.changed) {
        return .momentumScrolling
      } else if momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled) {
        return .momentumScrollJustEnded
      }
    }
    fatalError("Unrecognized or invalid scroll wheel event phase (\(phase)) or momentumPhase (\(momentumPhase))")
  }

}
