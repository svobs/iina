//
//  VirtualScrollWheel.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-22.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

/// May need adjustment for optimal results
fileprivate let stepScrollSessionTimeout: TimeInterval = 0.05

/// This is a workaround for limitations of the `NSEvent` API and shouldn't need changing.
///
/// If this amount of time passes from when we receive a `smoothScrollJustEnded` event but do not receive a
/// `momentumScrollJustStarted` event, the scroll session should be considered ended.
fileprivate let momentumStartTimeout: TimeInterval = 0.05

/// This is used for 2 different purposes, each using a different subset of states, which is a little sloppy.
/// But at least it will stay within this file. (See `state` variable vs `mapPhasesToScrollState()`)
fileprivate enum ScrollState {
  /// No scroll session is currently active
  case notScrolling

  // "Step" scrolling (non-Apple)

  /// Non-Apple devices are limited to this single state
  case didStepScroll

  // "Smooth" Scrolling (Apple mouse / trackpad)

  case smoothScrollMayBegin(_ intentStartTime: TimeInterval)
  case smoothScrolling
  case smoothScrollJustEnded
  case momentumScrollJustStarted
  case momentumScrolling
  case momentumScrollJustEnded
}

class ScrollSession {
  var sensitivity: CGFloat = 1.0
  /// Lock for `eventsPending`
  let lock = Lock()
  /// During the `minScrollWheelTimeThreshold` time period, no scroll is executed. But simply dropping any user input during
  /// that time can feel laggy. For a much smoother user experience, this list holds the accumulated events until start, then
  /// execute them as if they had started when the user started their scroll action.
  var eventsPending: [NSEvent] = []
#if DEBUG
  var deltaTotal: CGFloat = 0
  var totalEventCount: Int = 0
  var actionCount: Int = 0
  let startTime = Date()
  var momentumStartTime: Date? = nil
#endif

  func addPendingEvent(_ event: NSEvent) {
    lock.withLock { [self] in
      eventsPending.append(event)
    }
  }

  /// Based on `ScrollableSlider.swift`, created by Nate Thompson on 10/24/17.
  /// Original source code: https://github.com/thompsonate/Scrollable-NSSlider
  func executeScroll(on delegateSlider: NSSlider) {

    // All the pending events need to be applied immediately.
    // Save CPU by adding them all together before calling action:
    var newValue: CGFloat = 0.0
    lock.withLock { [self] in
      newValue = eventsPending.reduce(delegateSlider.doubleValue) { value, event in
        computeNewValue(for: delegateSlider, from: event, usingCurrentValue: value)
      }
      eventsPending = []
    }

    callAction(on: delegateSlider, applyingNewValue: newValue)
  }

  /// Computes new `doubleValue` for `slider` assuming the given `currentValue` and returns it.
  /// Uses some properties from `slider` but ignores `slider.doubleValue` entirely.
  private func computeNewValue(for slider: NSSlider, from event: NSEvent,
                       usingCurrentValue currentValue: CGFloat) -> CGFloat {
    let delta = extractLinearDelta(from: event, slider)

#if DEBUG
    deltaTotal += delta
    totalEventCount += 1
#endif

    // Convert delta into valueChange
    let maxValue = slider.maxValue
    let minValue = slider.minValue

    let valueChange = /*(maxValue - minValue) / 100 * */delta //* sensitivity

    // Compute & set new value for slider
    var newValue = currentValue + valueChange
    // Wrap around if slider is circular
    if slider.sliderType == .circular {
      if newValue < minValue {
        newValue = maxValue - abs(valueChange)
      } else if newValue > maxValue {
        newValue = minValue + abs(valueChange)
      }
    }

    return newValue.clamped(to: minValue...maxValue)
  }

  /// Converts `deltaX` & `deltaY` from any type of `NSSlider` into a standardized +/- delta
  private func extractLinearDelta(from event: NSEvent, _ slider: NSSlider) -> CGFloat {
    var delta: Double
    // Allow horizontal scrolling on horizontal and circular sliders
    if slider.isVertical && slider.sliderType == .linear {
      delta = event.deltaY
    } else if slider.userInterfaceLayoutDirection == .rightToLeft {
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

  private func callAction(on slider: NSSlider, applyingNewValue newValue: CGFloat) {
    // There can be a huge number of requests which don't change the existing value.
    // But in the case of mpv seeks, these can cause noticeable slowdown.
    // Discard them for a large increase in performance.
    guard slider.doubleValue != newValue else { return }

#if DEBUG
    actionCount += 1
#endif
    slider.doubleValue = newValue
    slider.sendAction(slider.action, to: slider.target)
  }
}

/// This class provides a wrapper API over Apple's APIs to simplify scroll wheel handling.
///
/// Internally this class maintains its own state machine which it updates from the `phase` & `momentumPhase` properties
/// of each `NSEvent` (see `mapPhasesToScrollState`) which is received by the `scrollWheel` method of the view being scrolled,
/// all of which is done by passing each event to the `changeState` method below.
///
/// It's important to note that only Apple devices (Magic Mouse, Magic Trackpad) are supported for full "smooth" scrolling, which
/// may also include a "momentum" component. Non-Apple devices can only execute coarser-grained "step"-type scrolling. This
/// class does its best to execute value changes smoothly and consolidate all the various states into standard "start" & "end"
/// events, between which queries to `isScrolling` will return `true`.
///
/// <h1>Smooth scrolling</h1>
///
/// For Apple devices, the out-of-the-box functionality is a bit too sensitive. So this class also add logic to measure the
/// time the user is actively scrolling and ignore any potential scroll sessions which shorter than
/// `Constants.TimeInterval.minScrollWheelTimeThreshold` to help avoid unwanted scrolling. Specifically, it starts the timer
/// when a `.mayBegin` or `.began` state is seen in `.phase`, and if `.ended` or `.cancelled` is seen too soon, all remaining
/// received events are discarded (including momentum scroll events) until the next `.mayBegin` or `.began` is seen for `.phase`.
///
/// The start of the qualifying scroll session, when determined by the logic above, is kicked off with a call to
/// `beginScrollSession`. Its end is indicated by a call to `endScrollSession`, and between the two, any number of calls may be
/// made to `executeScroll` to execute additional scroll traversal.
///
/// <h1>Step scrolling</h1>
///
/// Non-Apple scroll wheels are limited to a more discrete "step"-like behavior, and do not support momentum.
/// But this class tries to map them into the same model as smooth scrolling, by starting a scroll session when transitioning
/// from the `notScrolling` state to the `didStepScroll` state, then keeping a `Timer` so that the session ends when no events
/// are received for `stepScrollSessionTimeout` seconds.
class VirtualScrollWheel {
  var delegateSlider: NSSlider? = nil
  var log: Logger.Subsystem = Logger.log

  /// Contains data for the current scroll session.
  ///
  /// Non-nil only while a scroll session is active. A new instance is created each time a new session starts.
  private var currentSession: ScrollSession? = nil

  /// This reflects the current logical/virtual scroll state of this `VirtualScrollWheel`, which may be completely different
  /// from the underlying source of scroll wheel `NSEvent`s.
  private var state: ScrollState = .notScrolling

  private var scrollSessionTimer: Timer? = nil

  func scrollWheel(with event: NSEvent) {
    currentSession?.addPendingEvent(event)
    changeState(with: event)
    if let currentSession, let delegateSlider, isScrolling() {
      currentSession.executeScroll(on: delegateSlider)
    }
  }

  // MARK: State API
  
  /// Called when scroll starts. Subclasses should override.
  ///
  /// - This is only called for scrolls originating from Magic Mouse or trackpad. Will never be called for non-Apple mice.
  /// - This will be at most once per scroll.
  /// - Will not be called if the user scroll duration is shorter than `minScrollWheelTimeThreshold`.
  func scrollSessionWillBegin(_ session: ScrollSession) {
  }


  /// Called after scroll ends. Subclasses should override.
  ///
  /// - Will not be called if `scrollWheelDidStart` does not fire first (see notes for that).
  /// - If the scroll has momentum, this will be called when that ends. Otherwise this will be called when user scroll ends.
  func scrollSessionDidEnd(_ session: ScrollSession) {
  }

  /// Returns true if in one of the scrolling states (i.e. a scroll session is currently active)
  func isScrolling() -> Bool {
    switch state {
    case .notScrolling, .smoothScrollMayBegin:
      return false
    default:
      assert(currentSession != nil, "currentSession should not be nil for state \(state)")
      return true
    }
  }

  /// Returns true if doing a step-type scroll, which non-Apple devices are limited to.
  func isScrollingNonAppleDevice() -> Bool {
    switch state {
    case .didStepScroll:
      return true
    default:
      return false
    }
  }

  func configure(_ slider: ScrollableSlider, _ log: Logger.Subsystem) {
    self.log = log
    self.delegateSlider = slider
    slider.scrollWheel = self
  }

  // MARK: - Internal state machine

  private func notScrolling() {
    if case .notScrolling = state {
      // nothing to do
      return
    }
    endScrollSession()
  }

  private func endScrollSession() {
    guard let session = currentSession else { Logger.fatal("currentSession==nil for state \(state) → \(ScrollState.notScrolling)") }
    state = .notScrolling

#if DEBUG
    if DebugConfig.enableScrollWheelDebug, let player = delegateSlider?.thisPlayer {
      let timeTotal = session.startTime.timeIntervalToNow
      let timeUser: TimeInterval
      let timeMsg: String
      if let momTime = session.momentumStartTime?.timeIntervalToNow {
        timeUser = timeTotal - momTime
        timeMsg = "\(timeUser.string2FractionDigits)s user  +  \(momTime.string2FractionDigits)s inertia  =  \(timeTotal.string2FractionDigits)s"
      } else {
        timeUser = timeTotal
        timeMsg = "\(timeTotal.string2FractionDigits)s"
      }
      let actionsPerSec = CGFloat(session.actionCount) / timeTotal
      let actionRatio = CGFloat(session.actionCount) / CGFloat(session.totalEventCount)
      let deltaPerUserSec = session.deltaTotal / timeUser
      let accelerationPerUserSec = deltaPerUserSec / timeUser
      let msg = "ScrollWheel Δ: \(session.deltaTotal.string2FractionDigits)    Actions/s: \(actionsPerSec.stringMaxFrac2)"
      let detail = [
        "Time: \t\(timeMsg)",
        "Events: \t\(session.totalEventCount)",
        "Actions: \t\(session.actionCount)    (ratio: \(actionRatio.stringMaxFrac2))",
        "Avg Speed: \t\(deltaPerUserSec.stringMaxFrac2)/s",
        "Accel: \t\(accelerationPerUserSec.magnitude.stringMaxFrac2)/s²",
      ].joined(separator: "\n")
      player.sendOSD(.debug(msg, detail))
    }
#endif

    currentSession = nil
    scrollSessionDidEnd(session)
  }

  private func changeState(with event: NSEvent) {
    let newState = mapPhasesToScrollState(event)

#if DEBUG
    if DebugConfig.enableScrollWheelDebug {
      log.verbose("ScrollWheel phases: \(event.phase.name)/\(event.momentumPhase.name) State: \(state) → \(newState)")
    }
#endif

    switch newState {
    case .notScrolling:
      notScrolling()

    case .didStepScroll:  // Non-Apple device
      resetScrollSessionTimer(timeout: stepScrollSessionTimeout)
      if case .didStepScroll = state {
        // Continuing scroll session. No state changes needed
        break
      }
      // Else: starting (non-Apple) scroll
      state = newState
      let newSession = ScrollSession()
      // No lock needed here, since we own the only reference
      newSession.eventsPending.append(event)
      currentSession = newSession

      scrollSessionWillBegin(newSession)

    case .smoothScrollMayBegin:
      state = newState
      let newSession = ScrollSession()
      // No lock needed here, since we own the only reference
      newSession.eventsPending.append(event)
      currentSession = newSession

    case .smoothScrolling:
      switch state {
      case .smoothScrollMayBegin(let intentStartTime):
        guard let currentSession else { Logger.fatal("No current session for state \(state) → \(newState)") }

        let timeElapsed = Date().timeIntervalSince1970 - intentStartTime
        if timeElapsed >= Constants.TimeInterval.minScrollWheelTimeThreshold {
          log.verbose("Time elapsed (\(timeElapsed.stringTrunc3f)) ≥ minScrollWheelTimeThreshold (\(Constants.TimeInterval.minScrollWheelTimeThreshold)): starting scroll session")
          state = .smoothScrolling
          scrollSessionWillBegin(currentSession)
        }
        // Else: minimum scroll time not yet reached. But will keep track of scrolls for use when it is reached
      case .smoothScrolling:
        state = .smoothScrolling
      default:
        notScrolling()
      }

    case .smoothScrollJustEnded:
      switch state {
      case .smoothScrolling:
        state = .smoothScrollJustEnded
        resetScrollSessionTimer(timeout: momentumStartTimeout)
      default:
        notScrolling()
      }

    case .momentumScrollJustStarted:
      switch state {
      case .smoothScrollJustEnded:
        scrollSessionTimer?.invalidate()
        state = .momentumScrollJustStarted
#if DEBUG
        currentSession?.momentumStartTime = Date()
#endif
      default:
        notScrolling()
      }

    case .momentumScrolling:
      switch state {
      case .momentumScrollJustStarted, .momentumScrolling:
        scrollSessionTimer?.invalidate()
        state = .momentumScrolling
      default:
        notScrolling()
      }

    case .momentumScrollJustEnded:
      switch state {
      case .momentumScrollJustStarted, .momentumScrolling:
        endScrollSession()
      default:
        notScrolling()
      }
    }
  }

  private func resetScrollSessionTimer(timeout: TimeInterval) {
    scrollSessionTimer?.invalidate()
    scrollSessionTimer = Timer.scheduledTimer(timeInterval: timeout, target: self,
                                       selector: #selector(self.scrollSessionDidTimeOut), userInfo: nil, repeats: false)
  }

  /// Executed when `scrollSessionTimer` fires.
  @objc private func scrollSessionDidTimeOut() {
    guard isScrolling() else { return }
    Logger.log.verbose("ScrollWheel timed out")
    endScrollSession()
  }

  private func mapPhasesToScrollState(_ event: NSEvent) -> ScrollState {
    let phase = event.phase
    let momentumPhase = event.momentumPhase

    if momentumPhase.isEmpty {
      if phase.contains(.mayBegin) {
        /// This only happens for trackpad. It indicates user pressed down on it but did not change its value.
        /// This event can be emitted if the user (e.g.) starts with 3 fingers. If they switch to 2, it will change to `began`;
        /// otherwise it will end in `cancelled`. Treat this like a `notScrolling` so that it can be ignored or even cancel
        /// any pre-existing session.
        return .notScrolling
      } else if phase.contains(.began) {
        return .smoothScrollMayBegin(Date().timeIntervalSince1970)
      } else if phase.contains(.changed) {
        return .smoothScrolling
      } else if phase.contains(.ended) {
        return .smoothScrollJustEnded
      } else if phase.contains(.cancelled) {
        // This isn't expected to be seen while in an active scroll session. But be wary if it ever changes
        if case .notScrolling = state {
        } else {
          assert(false, "Received scroll wheel event with .cancelled phase but state is not .notScrolling!")
          log.error("Received scroll wheel event with .cancelled phase but state is not .notScrolling!")
        }
        return .notScrolling
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

}
