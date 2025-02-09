//
//  TimeoutTimer.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-16.
//  Copyright © 2025 lhc. All rights reserved.
//

class TimeoutTimer {
  private var scheduledTimer: Timer? = nil
  var timeout: TimeInterval
  /// nillable because sometimes this needs to be set after the containing class has finished init
  var action: (() -> Void)?
  /// If not nil, is executed before starting or restarting the timer.
  /// If it returns false, the timer will not be started.
  var startFunction: ((TimeoutTimer) -> Bool)?

  init(timeout: TimeInterval,
       startFunction: ((TimeoutTimer) -> Bool)? = nil,
       action: (() -> Void)? = nil) {
    self.timeout = timeout
    self.startFunction = startFunction
    self.action = action
  }

  func restart(withNewTimeout newTimeout: TimeInterval? = nil) {
    cancel()

    if let newTimeout {
      timeout = newTimeout
    }

    if let startFunction {
      let canProceed = startFunction(self)
      guard canProceed else {
        return
      }
    }
    scheduledTimer = Timer.scheduledTimer(timeInterval: timeout,
                                          target: self, selector: #selector(self.timeoutReached),
                                          userInfo: nil, repeats: false)
  }

  var isValid: Bool {
    if let scheduledTimer, scheduledTimer.isValid {
      return true
    }
    return false
  }

  func cancel() {
    scheduledTimer?.invalidate()
  }

  @objc private func timeoutReached() {
    cancel()
    action!()
  }
}
