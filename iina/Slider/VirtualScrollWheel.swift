//
//  VirtualScrollWheel.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-22.
//

import Foundation

// MARK: - Support classes

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

/// Support class for `VirtualScrollWheel` which exists only for the duration of a single continuous scroll.
class ScrollSession {
  /// Slider `doubleValue` at scroll start
  var valueAtStart: Double? = nil
  /// Underlying model value at scroll start (or leave nil if model is same as `doubleValue`)
  var modelValueAtStart: Double? = nil
  var modelValueAtEnd: Double? = nil
  var sensitivity: CGFloat = 1.0
  /// Lock for `eventsPending`
  let lock = Lock()
  /// During the `minQualifyingScrollWheelDuration` time period, no scroll is executed. But simply dropping any user input during
  /// that time can feel laggy. For a much smoother user experience, this list holds the accumulated events until start, then
  /// execute them as if they had started when the user started their scroll action.
  var eventsPending: [NSEvent] = []
#if DEBUG
  var rawDeltaTotal: CGFloat = 0
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
  
  /// Extracts delta values from all pending events by interpreting them as scroll events to be
  /// executed on `slider`. Clears events after. Returns their sum adjusted by `sensitivity`.
  /// This number is independent of the slider's actual `doubleValue` and is open to interpretation.
  func consumePendingEvents(for slider: ScrollableSlider) -> CGFloat {
    // All the pending events need to be applied immediately.
    // Save CPU by adding them all together before calling action:
    return lock.withLock { [self] in
      let rawDeltaSum = eventsPending.reduce(0.0) { sum, event in
        let rawDelta = slider.extractLinearDelta(from: event)
        return sum + rawDelta
      }
      
#if DEBUG
      rawDeltaTotal += rawDeltaSum
      totalEventCount += eventsPending.count
#endif
      
      eventsPending = []
      return rawDeltaSum * sensitivity
    }
  }
}

/// This class provides a wrapper API over Apple's APIs to simplify scroll wheel handling. This is an abstract base class which is
/// intended to be overridden & is not usable out of the box.
///
/// See subclass `SliderScrollWheelDelegate` for something more useful.
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
/// `Constants.TimeInterval.minQualifyingScrollWheelDuration` to help avoid unwanted scrolling. Specifically, it starts the timer
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
/// from the `notScrolling` state to the `didStepScroll` state, then keeping a `TimeoutTimer` so that the session ends when no
/// events are received for `stepScrollSessionTimeout` seconds.
class VirtualScrollWheel {
  var log: Logger.Subsystem = Logger.log

  /// Contains data for the current scroll session.
  ///
  /// Non-nil only while a scroll session is active. A new instance is created each time a new session starts.
  fileprivate var currentSession: ScrollSession? = nil

  private(set) var lastSessionEndTime: TimeInterval = 0

  /// This reflects the current logical/virtual scroll state of this `VirtualScrollWheel`, which may be completely different
  /// from the underlying source of scroll wheel `NSEvent`s.
  private var state: ScrollState = .notScrolling

  /// Calls `self.scrollSessionDidTimeOut` on timeout.
  private let scrollSessionTimer = TimeoutTimer(timeout: Constants.TimeInterval.stepScrollSessionTimeout)

  init() {
    scrollSessionTimer.action = scrollSessionDidTimeOut
  }

  func scrollWheel(with event: NSEvent) {
    currentSession?.addPendingEvent(event)
    changeState(with: event)
    if let currentSession, isScrolling() {
      scrollDidUpdate(currentSession)
    }
  }

  // MARK: State API
  
  /// Called when scroll starts. Subclasses should override.
  ///
  /// - This is only called for scrolls originating from Magic Mouse or trackpad. Will never be called for non-Apple mice.
  /// - This will be at most once per scroll.
  /// - Will not be called if the user scroll duration is shorter than `minQualifyingScrollWheelDuration`.
  func scrollSessionWillBegin(_ session: ScrollSession) {
  }


  /// Called zero-to-many times after `scrollSessionWillBegin` & before `scrollSessionDidEnd`.
  /// Subclasses should override.
  func scrollDidUpdate(_ session: ScrollSession) {
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
    let wasScrolling = isScrolling()
    currentSession = nil
    scrollSessionTimer.cancel()
    state = .notScrolling

    guard wasScrolling else { return }

    scrollSessionDidEnd(session)
    lastSessionEndTime = Date().timeIntervalSince1970
#if DEBUG
    if DebugConfig.enableScrollWheelDebug {
      log.verbose{"ScrollWheel session ended"}
    }
#endif
  }

  private func changeState(with event: NSEvent) {
    let newState = mapPhasesToScrollState(event)

#if DEBUG
    if DebugConfig.enableScrollWheelDebug {
      log.verbose{"ScrollWheel phases: \(event.phase.name)/\(event.momentumPhase.name) State: \(state) → \(newState)"}
    }
#endif

    switch newState {
    case .notScrolling:
      notScrolling()

      // - Non-Apple device:
    case .didStepScroll:   // STEP
      scrollSessionTimer.restart()

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

      // - Smooth Scroll:

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

        let now = Date().timeIntervalSince1970
        var startScrolling = false

        let timeElapsedSinceLastSessionEnd = now - lastSessionEndTime
        if timeElapsedSinceLastSessionEnd < Constants.TimeInterval.instantConsecutiveScrollStartWindow {
          startScrolling = true
          log.verbose{"Time elapsed since last scroll (\(timeElapsedSinceLastSessionEnd.stringTrunc3f)) < instantConsecutiveScrollStartWindow (\(timeElapsedSinceLastSessionEnd.logStr)): starting new scroll session immediately"}
        } else {
          let timeElapsedSinceIntentStart = Date().timeIntervalSince1970 - intentStartTime
          if timeElapsedSinceIntentStart >= Constants.TimeInterval.minQualifyingScrollWheelDuration {
            startScrolling = true
            log.verbose{"Time elapsed (\(timeElapsedSinceIntentStart.stringTrunc3f)) ≥ minQualifyingScrollWheelDuration (\(Constants.TimeInterval.minQualifyingScrollWheelDuration)): starting scroll session"}
          }
        }

        if startScrolling {
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
        /// If some amount of time passes from when we receive a `smoothScrollJustEnded` event but do not receive a
        /// `momentumScrollJustStarted` event, the scroll session should be considered ended.
        /// This addresses an apparent hole in AppKit's API which leaves us waiting for an event which is not
        /// guaranteed to be sent.
        /// In practice this always seems to happen almost immediately. Just reuse existing timer.
        scrollSessionTimer.restart()
      default:
        notScrolling()
      }

      // - Momentum Scroll:

    case .momentumScrollJustStarted:  // START
      switch state {
      case .smoothScrollJustEnded:
        scrollSessionTimer.cancel()
        state = .momentumScrollJustStarted
#if DEBUG
        currentSession?.momentumStartTime = Date()
#endif
      default:
        notScrolling()
      }

    case .momentumScrolling:  // Continue
      switch state {
      case .momentumScrollJustStarted, .momentumScrolling:
        scrollSessionTimer.cancel()
        state = .momentumScrolling
      default:
        notScrolling()
      }

    case .momentumScrollJustEnded:  // END
      switch state {
      case .momentumScrollJustStarted, .momentumScrolling:
        endScrollSession()
      default:
        notScrolling()
      }
    }
  }

  /// Executed when `scrollSessionTimer` fires.
  private func scrollSessionDidTimeOut() {
    Logger.log.verbose{"ScrollWheel timed out: state=\(state)"}
    guard isScrolling() else { return }
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
        // Not sure why this happens exactly, but it does happen. Try to roll with it
        if case .notScrolling = state {
        } else {
          log.debug("Received scroll wheel event with .cancelled phase but state is not .notScrolling")
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
