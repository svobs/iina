//
//  LogicalScrollWheel.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-22.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

fileprivate let momentumStartTimeout: TimeInterval = 0.05

class LogicalScrollWheel {

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

  var scrollWheelDidStart: ((NSEvent) -> Void)?

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

  func changeState(with event: NSEvent) {
    let newState = mapPhasesToScrollState(event)

    if Logger.log.isTraceEnabled {
      Logger.log.trace("SCROLL WHEEL phases={\(event.phase.name), \(event.momentumPhase.name)} state: \(state) → \(newState)")
    }

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
        if let scrollWheelDidStart {
          scrollWheelDidStart(event)
        }
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
        if let scrollWheelDidEnd {
          scrollWheelDidEnd()
        }
      default:
        state = .notScrolling
        return  // invalid state
      }

    default:
      Logger.log.fatalError("Invalid value for newState: \(newState)")
    }
  }

  /// Executed when `momentumTimer` fires.
  @objc func momentumStartDidTimeOut() {
    guard case .userScrollJustEnded = state else { return }
    Logger.log.verbose("Momentum timer expired")
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
