//
//  TimeoutTimer.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-16.
//  Copyright © 2025 lhc. All rights reserved.
//

class TimeoutTimer {
  private var scheduledTimer: Timer? = nil
  let timeout: TimeInterval
  /// nillable because sometimes this needs to be set after the containing class has finished init
  var action: (() -> Void)?

  init(timeout: TimeInterval, action: (() -> Void)? = nil) {
    self.timeout = timeout
    self.action = action
  }

  func restart() {
    scheduledTimer?.invalidate()
    scheduledTimer = Timer.scheduledTimer(timeInterval: timeout,
                                          target: self, selector: #selector(self.timeoutReached),
                                          userInfo: nil, repeats: false)
  }

  func cancel() {
    scheduledTimer?.invalidate()
  }

  @objc private func timeoutReached() {
    cancel()
    if let action {
      action()
    }
  }
}
