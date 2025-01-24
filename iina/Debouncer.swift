//
//  Debouncer.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-23.
//  Copyright © 2025 lhc. All rights reserved.
//

class Debouncer {
  @Atomic private(set) var ticketCount: Int = 0
  private let delay: TimeInterval
  private let queue: DispatchQueue
#if DEBUG
  // Measuring the number of cancels indicates the amount of work saved, so is helpful in quantifying the
  // usefulness of a given debouncer.
  var cancels: Int = 0
#endif

  init(delay: TimeInterval = 0.0, queue: DispatchQueue = .main) {
    self.delay = delay
    self.queue = queue
  }

  func run(_ taskFunc: @escaping () -> Void) {
    let currentTicket = $ticketCount.withLock {
      $0 += 1
      return $0
    }

    queue.asyncAfter(deadline: .now() + delay) { [self] in
      guard currentTicket == ticketCount else {
#if DEBUG
        cancels += 1;
#endif
        return
      }
      taskFunc()
    }
  }

  func invalidate() {
    $ticketCount.withLock { $0 += 1 }
  }
}
