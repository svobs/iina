//
//  VirtualScrollWheel.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-22.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

fileprivate let stepScrollSessionTimeout: TimeInterval = 0.05

/// This is a workaround for limitations of the `NSEvent` API and shouldn't need changing.
///
/// If this amount of time passes from when we receive a `userScrollJustEnded` event but do not receive a
/// `momentumScrollJustStarted` event, the scroll session should be considered ended.
fileprivate let momentumStartTimeout: TimeInterval = 0.05

/// This class provides a wrapper API over Apple's APIs to simplify scroll wheel handling.
///
/// Internally this class maintains its own state machine which it updates from the `phase` & `momentumPhase` properties
/// of each `NSEvent` (see `mapPhasesToScrollState`) which is received by the `scrollWheel` method of the view being scrolled,
/// all of which is done by passing each event to the `changeState` method below.
///
/// It's important to note that only Apple devices (Magic Mouse, Magic Trackpad) are supported for full smooth scrolling, which
/// may also include a "momentum" component. Non-Apple devices can only execute coarser-grained "step"-type scrolling. This
/// class does its best to execute value changes smoothly and consolidate all the various states into standard "start" & "end"
/// events, between which queries to `isScrolling` will return `true`.
///
/// For Apple devices, the out-of-the-box functionality is a bit too sensitive. So this class also add logic to ignore scroll
/// sessions which are shorter than `Constants.TimeInterval.minScrollWheelTimeThreshold` to help avoid unwanted scrolling.
///
/// The above is not a concern for non-Apple scroll wheels due to their more discrete "step"-like behavior, and lack of momentum.
/// But this class tries to map them into the same model, by starting a scroll session when transitioning from the `notScrolling`
/// state to the `didStepScroll` state, then keeping a `Timer` so that the session ends when no events are received for
/// `stepScrollSessionTimeout` seconds.
class VirtualScrollWheel {
  var outputSlider: NSSlider? = nil

  var sensitivity: Double = 1.0

  /// This is used for 2 different purposes, each using a different subset of states, which is a little sloppy.
  /// But at least it will stay within this class. (See `state` variable vs `mapPhasesToScrollState()`)
  private enum ScrollState {
    case notScrolling

    case didStepScroll  /// non-Apple devices are limited to this single state

    case scrollMayBegin(_ intentStartTime: TimeInterval)
    case userScroll
    case userScrollJustEnded
    case momentumScrollJustStarted
    case momentumScrolling
    case momentumScrollJustEnded

    /// Only set by `startScrollSession()`. Equivalent of `didStepScroll` state.
    case stepScrollForced
    /// Only set by `startScrollSession()`. Equivalent of `userScroll` state.
    case userScrollForced
  }

  /// This reflects the current logical/virtual scroll state of this `VirtualScrollWheel`, which may be completely different
  /// from the underlying source of scroll wheel `NSEvent`s.
  private var state: ScrollState = .notScrolling
  private var scrollTimer: Timer? = nil
#if DEBUG
  private var scrollSessionDeltaTotal: CGFloat = 0
#endif

  init() {
    updateSensitivity()
  }

  /// Subclasses can override
  func updateSensitivity() { }

  /// Called when scroll starts.
  ///
  /// - This is only called for scrolls originating from Magic Mouse or trackpad. Will never be called for non-Apple mice.
  /// - This will be at most once per scroll.
  /// - Will not be called if the user scroll duration is shorter than `minScrollWheelTimeThreshold`.
  func startScrollSession(with event: NSEvent) {
    if !isScrolling() {
      // If the state is not current, this method was likely called from outside of this class.
      // Update to put it into the scrolling state so we don't break the model and/or confuse
      // ourselves when debugging.
      let newState = mapPhasesToScrollState(event)
      if case .userScroll = newState {
        state = .userScrollForced
      } else {
        state = .stepScrollForced
      }
    }

#if DEBUG
    // Reset counters for start of session
    scrollSessionDeltaTotal = 0
#endif
  }

  /// Called when scroll ends.
  ///
  /// - Will not be called if `scrollWheelDidStart` does not fire first (see notes for that).
  /// - If the scroll has momentum, this will be called when that ends. Otherwise this will be called when user scroll ends.
  func endScrollSession() {
#if DEBUG
    outputSlider?.thisPlayer?.sendOSD(.debug("Δ ScrollWheel: \(scrollSessionDeltaTotal.string2FractionDigits)"))
#endif
  }

  /// Returns true if in one of the scrolling states (i.e. a scroll session is currently active)
  func isScrolling() -> Bool {
    switch state {
    case .notScrolling, .scrollMayBegin:
      return false
    default:
      return true
    }
  }

  /// Returns true if doing a step-type scroll, which non-Apple devices are limited to.
  func isScrollingNonAppleDevice() -> Bool {
    switch state {
    case .didStepScroll,
        .stepScrollForced:
      return true
    default:
      return false
    }
  }

  func changeState(with event: NSEvent) {
    let newState = mapPhasesToScrollState(event)

    if Logger.log.isTraceEnabled {
      Logger.log.trace("ScrollWheel Event: phases={\(event.phase.name), \(event.momentumPhase.name)} state: \(state) → \(newState)")
    }

    switch newState {
    case .notScrolling:
      state = .notScrolling

    case .didStepScroll:
      resetScrollTimer(timeout: stepScrollSessionTimeout)
      if case .didStepScroll = state {
        // already started; nothing to do
        return
      }

      state = .didStepScroll
      startScrollSession(with: event)

    case .scrollMayBegin:
      state = newState

    case .userScroll:
      switch state {
      case .scrollMayBegin(let intentStartTime):
        let timeElapsed = Date().timeIntervalSince1970 - intentStartTime
        guard timeElapsed >= Constants.TimeInterval.minScrollWheelTimeThreshold else {
          return  // not yet reached
        }
        Logger.log.verbose("Time elapsed (\(timeElapsed)) >= minScrollTimeThreshold \(Constants.TimeInterval.minScrollWheelTimeThreshold). Starting scroll")
        state = .userScroll
        startScrollSession(with: event)
      case .userScroll:
        state = .userScroll
      default:
        state = .notScrolling
      }

    case .userScrollJustEnded:
      switch state {
      case .userScroll:
        state = .userScrollJustEnded
        resetScrollTimer(timeout: momentumStartTimeout)
      default:
        state = .notScrolling
      }

    case .momentumScrollJustStarted:
      switch state {
      case .userScrollJustEnded:
        scrollTimer?.invalidate()
        state = .momentumScrollJustStarted
      default:
        state = .notScrolling
      }

    case .momentumScrolling:
      switch state {
      case .momentumScrollJustStarted, .momentumScrolling:
        scrollTimer?.invalidate()
        state = .momentumScrolling
      default:
        state = .notScrolling
      }

    case .momentumScrollJustEnded:
      switch state {
      case .momentumScrollJustStarted, .momentumScrolling:
        state = .notScrolling
        endScrollSession()
      default:
        state = .notScrolling
      }
    case .stepScrollForced, .userScrollForced:
      // programmer error
      Logger.fatal("Invalid state for changeState(): \(newState)")
    }
  }

  private func resetScrollTimer(timeout: TimeInterval) {
    scrollTimer?.invalidate()
    scrollTimer = Timer.scheduledTimer(timeInterval: timeout, target: self,
                                         selector: #selector(self.scrollDidTimeOut), userInfo: nil, repeats: false)
  }

  /// Executed when `scrollTimer` fires.
  @objc func scrollDidTimeOut() {
    guard isScrolling() else { return }
    Logger.log.verbose("Scroll timed out")
    state = .notScrolling
    endScrollSession()
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
      } else if phase.isEmpty {
        return .didStepScroll
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

  func scrollWheel(with event: NSEvent) {
    changeState(with: event)
    guard isScrolling() else { return }
    executeScrollAction(with: event)
  }

  func executeScrollAction(with event: NSEvent) {
    guard let outputSlider else { return }

    let delta = extractDelta(from: event)

#if DEBUG
    scrollSessionDeltaTotal += delta
#endif

    let doubleValue = outputSlider.doubleValue
    let maxValue = outputSlider.maxValue
    let minValue = outputSlider.minValue
    let valueChange = (maxValue - minValue) * delta * sensitivity / 100.0
    // There can be a huge number of requests which don't change the existing value.
    // Discard them for a large increase in performance:
    guard valueChange != 0.0 else { return }

    var newValue = doubleValue + valueChange

    // Wrap around if slider is circular
    if outputSlider.sliderType == .circular {
      if newValue < minValue {
        newValue = maxValue - abs(valueChange)
      } else if newValue > maxValue {
        newValue = minValue + abs(valueChange)
      }
    }

    outputSlider.doubleValue = newValue
    outputSlider.sendAction(outputSlider.action, to: outputSlider.target)
  }


  private func extractDelta(from event: NSEvent) -> CGFloat {
    guard let outputSlider else { return 0.0 }

    var delta: Double
    // Allow horizontal scrolling on horizontal and circular sliders
    if outputSlider.isVertical && outputSlider.sliderType == .linear {
      delta = event.deltaY
    } else if outputSlider.userInterfaceLayoutDirection == .rightToLeft {
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
