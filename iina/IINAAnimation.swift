//
//  IINAAnimation.swift
//  iina
//
//  Created by Matt Svoboda on 2023-04-09.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

class IINAAnimation {
  typealias TaskFunc = (() throws -> Void)

  // MARK: Durations

  static var DefaultDuration: CGFloat { CGFloat(Preference.float(for: .animationDurationDefault)) }
  static var VideoReconfigDuration: CGFloat { DefaultDuration * 0.25 }
  static var InitialVideoReconfigDuration: CGFloat { DefaultDuration }
  static var FullScreenTransitionDuration: CGFloat { CGFloat(Preference.float(for: .animationDurationFullScreen)) }
  static var NativeFullScreenTransitionDuration: CGFloat = 0.5
  static var OSDAnimationDuration: CGFloat { CGFloat(Preference.float(for: .animationDurationOSD)) }
  static var CropAnimationDuration: CGFloat { CGFloat(Preference.float(for: .animationDurationCrop)) }
  static var MusicModeShowButtonsDuration: CGFloat = 0.2

  // MARK: Misc static stuff

  /// "Disable all" override switch
  private static var disableAllAnimation = false

  static var isAnimationEnabled: Bool {
    return !disableAllAnimation && !AccessibilityPreferences.motionReductionEnabled
  }

  // Wrap a block of code inside this function to disable its animations
  @discardableResult
  static func disableAnimation<T>(_ closure: () throws -> T) rethrows -> T {
    let prevDisableState = disableAllAnimation
    disableAllAnimation = true
    CATransaction.begin()
    defer {
      CATransaction.commit()
      disableAllAnimation = prevDisableState
    }
    return try closure()
  }

  /// Convenience wrapper for chaining multiple tasks together via `NSAnimationContext.runAnimationGroup()`. Does not use pipeline.
  static func runAsync(_ task: Task, then doAfter: TaskFunc? = nil) {
    // Fail if not running on main thread:
    assert(DispatchQueue.isExecutingIn(.main))

    NSAnimationContext.runAnimationGroup({ context in
      let disableAnimation = !isAnimationEnabled
      if disableAnimation {
        context.duration = 0
      } else {
        context.duration = task.duration
      }
      context.allowsImplicitAnimation = !disableAnimation

      if let timingName = task.timingName {
        context.timingFunction = CAMediaTimingFunction(name: timingName)
      }
      do {
        try task.runFunc()
      } catch IINAError.cancelAnimationTransaction {
        Logger.log.debug("Animation pipeline: async task was cancelled")
      } catch {
        Logger.log.error("Animation pipeline: unexpected error thrown by task: \(error)")
      }
    }, completionHandler: {
      if let doAfter = doAfter {
        do {
          try doAfter()
        } catch {
          Logger.log("Animation pipeline: unexpected error thrown by doAfter func: \(error)")
        }
      }
    })
  }

  /// Convenience func for less verbose code
  static func runAsync(duration: CGFloat? = nil, _ timingName: CAMediaTimingFunctionName? = nil,
                         _ runFunc: @escaping TaskFunc, then doAfter: TaskFunc? = nil) {
    runAsync(Task(duration: duration, timing: timingName, runFunc), then: doAfter)
  }

  /// Convenience func for running the giving closure in a transactional way
  static func runInstantAsync(_ runFunc: @escaping TaskFunc, then doAfter: TaskFunc? = nil) {
    runAsync(.instantTask(runFunc), then: doAfter)
  }
}

extension IINAAnimation {
  struct Task {
    let duration: CGFloat
    let timingName: CAMediaTimingFunctionName?
    let runFunc: TaskFunc

    init(duration: CGFloat? = nil,
         timing timingName: CAMediaTimingFunctionName? = nil,
         _ runFunc: @escaping TaskFunc) {
      self.duration = duration ?? IINAAnimation.DefaultDuration
      self.timingName = timingName
      self.runFunc = runFunc
    }

    static func instantTask(_ runFunc: @escaping TaskFunc) -> Task {
      return Task(duration: 0, timing: nil, runFunc)
    }

  }

  struct Transaction {
    let tasks: [Task]
  }
}

extension IINAAnimation {
  /// Serial queue which executes `Task`s one after another.
  class Pipeline {

    /// ID of the latest transaction to be generated, but not necessarily run.
    /// (Basically used for ID generation).
    private var newestTxID: Int = 0
    /// ID of the currently executing transaction. When enqueued, all tasks in the same transaction are
    /// associated with an identical ID, which is one greater than the previous transaction
    /// (see `newestTxID`). If an exception is thrown by any task, `currentTxID` will be incremented. Any task associated with ID less than `currentTxID` will not be run, but if a task is found to have an ID greater
    /// than `currentTxID`, then `currentTxID` will be updated to its value and the task will be run.
    /// In this way, if any task in the transaction throws an exception, this will cause the remaining tasks
    /// to be skipped.
    private var currentTxID: Int = 0

    private(set) var isRunning = false
    private var taskQueue = LinkedList<(Int, Task)>()

    /// Convenience function. Same as `submit(Task)`
    func submitTask(duration: CGFloat? = nil, timing timingName: CAMediaTimingFunctionName? = nil,
                    _ runFunc: @escaping TaskFunc, then doAfter: TaskFunc? = nil) {
      let task = Task(duration: duration, timing: timingName, runFunc)
      submit(task)
    }

    /// Convenience function. Same as `submit([Task])`, but for a single animation.
    func submit(_ task: Task, then doAfter: TaskFunc? = nil) {
      submit([task], then: doAfter)
    }

    // Convenience function. Run the task with no animation / zero duration.
    // Useful for updating constraints, etc., which cannot be animated or do not look good animated.
    func submitInstantTask(_ runFunc: @escaping TaskFunc, then doAfter: TaskFunc? = nil) {
      submit(.instantTask(runFunc), then: doAfter)
    }

    /// Recursive function which enqueues each of the given `AnimationTask`s for execution, one after another.
    /// Will execute without animation if motion reduction is enabled, or if wrapped in a call to `IINAAnimation.disableAnimation()`.
    /// If animating, it uses either the supplied `duration` for duration, or if that is not provided, uses `IINAAnimation.DefaultDuration`.
    func submit(_ tasks: [Task], then doAfter: TaskFunc? = nil) {
      // Fail if not running on main thread:
      assert(DispatchQueue.isExecutingIn(.main))

      var enqueuedSomething = false

      if !tasks.isEmpty {
        newestTxID += 1
        let transactionID = newestTxID

        for task in tasks {
          taskQueue.append((transactionID, task))
        }
        enqueuedSomething = true
      }

      if let doAfter {
        newestTxID += 1
        taskQueue.append((newestTxID, .instantTask(doAfter)))
        enqueuedSomething = true
      }

      guard enqueuedSomething else { return }

      if isRunning {
        // Let existing chain pick up the new animations
      } else {
        // Launch for new tasks
        isRunning = true
        runTasks()
      }
    }

    private func popNextValidTask() -> IINAAnimation.Task? {
      while true {
        guard let (taskTxID, poppedTask) = taskQueue.removeFirst() else {
          self.isRunning = false
          return nil
        }

        guard taskTxID >= currentTxID else {
          Logger.log.debug("Animation pipeline: skipping task with txID \(taskTxID) (next valid txID: \(currentTxID))")
          continue
        }
        currentTxID = taskTxID
        return poppedTask
      }
    }

    private func runTasks() {
      guard let nextTask = popNextValidTask() else { return }

      NSAnimationContext.runAnimationGroup({ context in
        let disableAnimation = !isAnimationEnabled
        if disableAnimation {
          context.duration = 0
        } else {
          context.duration = nextTask.duration
        }
        context.allowsImplicitAnimation = !disableAnimation

        if let timingName = nextTask.timingName {
          context.timingFunction = CAMediaTimingFunction(name: timingName)
        }
        do {
          try nextTask.runFunc()
        } catch IINAError.cancelAnimationTransaction {
          Logger.log.debug("Animation pipeline: task was cancelled")
        } catch {
          Logger.log.error("Animation pipeline: unexpected error thrown by task: \(error)")
        }
      }, completionHandler: {
        self.runTasks()
      })
    }
  }
}

// MARK: - Extensions for disabling animation

extension NSLayoutConstraint {
  /// Even when executed inside an animation block, MacOS only sometimes creates implicit animations for changes to constraints.
  /// Using an explicit call to `animator()` seems to be required to guarantee it, but we do not always want it to animate.
  /// This function will automatically disable animations in case they are disabled.
  func animateToConstant(_ newConstantValue: CGFloat) {
    if IINAAnimation.isAnimationEnabled {
      self.animator().constant = newConstantValue
    } else {
      self.constant = newConstantValue
    }
  }
}
