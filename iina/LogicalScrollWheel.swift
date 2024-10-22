//
//  LogicalScrollWheel.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-22.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

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
/// For Apple devices, the out-of-the-box functionality is a bit too sensitive. So this class also add logic to ignore scrolls
/// which are shorter than `Constants.TimeInterval.minScrollWheelTimeThreshold` to help avoid unwanted scrolling. (This is not
/// a concern for non-Apple scroll wheels due to their more discrete "step"-like behavior, and lack of momentum).
class LogicalScrollWheel {

  /// This is used for 2 different purposes, each using a different subset of states, which is a little sloppy.
  /// But at least it will stay within this class.
  private enum ScrollState {
    case notScrolling
    case didStepScroll  /// non-Apple devices are limited to this single state
    case scrollMayBegin(_ intentStartTime: TimeInterval)
    case userScroll
    case userScrollJustEnded
    case momentumScrollJustStarted
    case momentumScrolling
    case momentumScrollJustEnded
  }
  private var state: ScrollState = .notScrolling
  private var scrollTimer: Timer? = nil

  /// Optional callback. Will be called when scroll starts.
  ///
  /// - This is only called for scrolls originating from Magic Mouse or trackpad. Will never be called for non-Apple mice.
  /// - This will be at most once per scroll.
  /// - Will not be called if the user scroll duration is shorter than `minScrollWheelTimeThreshold`.
  var scrollWheelDidStart: ((NSEvent) -> Void)?

  /// Optional callback. Will be called when scroll ends.
  ///
  /// - Will not be called if `scrollWheelDidStart` does not fire first (see notes for that).
  /// - If the scroll has momentum, this will be called when that ends. Otherwise this will be called when user scroll ends.
  var scrollWheelDidEnd: (() -> Void)?

  init(scrollWheelDidStart: ((NSEvent) -> Void)? = nil, scrollWheelDidEnd: (() -> Void)? = nil) {
    self.scrollWheelDidStart = scrollWheelDidStart
    self.scrollWheelDidEnd = scrollWheelDidEnd
  }

  func isScrolling() -> Bool {
    switch state {
    case .notScrolling, .scrollMayBegin:
      return false
    default:
      return true
    }
  }

  func isScrollingNonAppleDevice() -> Bool {
    if case .didStepScroll = state {
      return true
    }
    return false
  }

  func changeState(with event: NSEvent) {
    let newState = mapPhasesToScrollState(event)

    if Logger.log.isTraceEnabled {
      Logger.log.trace("SCROLL WHEEL phases={\(event.phase.name), \(event.momentumPhase.name)} state: \(state) → \(newState)")
    }

    switch newState {
    case .notScrolling:
      state = .notScrolling

    case .didStepScroll:
      resetScrollTimer(timeout: momentumStartTimeout)
      if case .didStepScroll = state {
        // already started; nothing to do
        return
      }

      state = .didStepScroll
      if let scrollWheelDidStart {
        scrollWheelDidStart(event)
      }

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
        if let scrollWheelDidStart {
          scrollWheelDidStart(event)
        }
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
        if let scrollWheelDidEnd {
          scrollWheelDidEnd()
        }
      default:
        state = .notScrolling
      }

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
    if let scrollWheelDidEnd {
      scrollWheelDidEnd()
    }
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
}
