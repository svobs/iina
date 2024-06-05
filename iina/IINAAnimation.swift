//
//  IINAAnimation.swift
//  iina
//
//  Created by Matt Svoboda on 2023-04-09.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

typealias TaskFunc = (() -> Void)
typealias AnimationBlock = (NSAnimationContext) -> Void

class IINAAnimation {

  // MARK: Durations

  static var DefaultDuration: CGFloat {
    return CGFloat(Preference.float(for: .animationDurationDefault))
  }
  static var VideoReconfigDuration: CGFloat {
    return DefaultDuration * 0.25
  }
  static var InitialVideoReconfigDuration: CGFloat {
    return DefaultDuration
  }
  static var FullScreenTransitionDuration: CGFloat {
    return CGFloat(Preference.float(for: .animationDurationFullScreen))
  }
  static var NativeFullScreenTransitionDuration: CGFloat = 0.5
  static var OSDAnimationDuration: CGFloat {
    return CGFloat(Preference.float(for: .animationDurationOSD))
  }
  static var CropAnimationDuration: CGFloat {
    CGFloat(Preference.float(for: .animationDurationCrop))
  }
  static var MusicModeShowButtonsDuration: CGFloat = 0.2

  // MARK: "Disable all" override switch

  private static var disableAllAnimation = false

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

  static var isAnimationEnabled: Bool {
    get {
      return disableAllAnimation ? false : !AccessibilityPreferences.motionReductionEnabled
    }
  }

  // MARK: - IINAAnimation.Task

  struct Task {
    let duration: CGFloat
    let timingName: CAMediaTimingFunctionName?
    let runFunc: TaskFunc

    init(duration: CGFloat = IINAAnimation.DefaultDuration,
         timing timingName: CAMediaTimingFunctionName? = nil,
         _ runFunc: @escaping TaskFunc) {
      self.duration = duration
      self.timingName = timingName
      self.runFunc = runFunc
    }
  }

  static func suddenTask(_ runFunc: @escaping TaskFunc) -> Task {
    return Task(duration: 0, timing: nil, runFunc)
  }

  // MARK: - IINAAnimation.Pipeline

  /// Serial queue which executes `Task`s one after another.
  class Pipeline {

    private(set) var isRunning = false
    private var taskQueue = LinkedList<Task>()

    /// Convenience function. Same as `submit([Task])`, but for a single animation.
    func submit(_ task: Task, then doAfter: TaskFunc? = nil) {
      submit([task], then: doAfter)
    }

    // Convenience function. Run the task with no animation / zero duration.
    // Useful for updating constraints, etc., which cannot be animated or do not look good animated.
    func submitSudden(_ runFunc: @escaping TaskFunc, then doAfter: TaskFunc? = nil) {
      submit(IINAAnimation.suddenTask(runFunc), then: doAfter)
    }

    /// Recursive function which enqueues each of the given `AnimationTask`s for execution, one after another.
    /// Will execute without animation if motion reduction is enabled, or if wrapped in a call to `IINAAnimation.disableAnimation()`.
    /// If animating, it uses either the supplied `duration` for duration, or if that is not provided, uses `IINAAnimation.DefaultDuration`.
    func submit(_ tasks: [Task], then doAfter: TaskFunc? = nil) {
      // Fail if not running on main thread:
      dispatchPrecondition(condition: .onQueue(.main))

      var needsLaunch = false
      taskQueue.appendAll(tasks)
      if let doAfter = doAfter {
        taskQueue.append(suddenTask(doAfter))
      }

      if isRunning {
        // Let existing chain pick up the new animations
      } else {
        isRunning = true
        needsLaunch = true
      }

      if needsLaunch {
        runTasks()
      }
    }

    private func runTasks() {
      var nextTask: IINAAnimation.Task? = nil

      if let poppedTask = taskQueue.removeFirst() {
        nextTask = poppedTask
      } else {
        self.isRunning = false
      }

      guard let nextTask = nextTask else { return }

      NSAnimationContext.runAnimationGroup({ context in
        CATransaction.begin()
        defer {
          CATransaction.commit()
        }
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
        nextTask.runFunc()
      }, completionHandler: {
        self.runTasks()
      })
    }
  }

  /// Convenience wrapper for chaining multiple tasks together via `NSAnimationContext.runAnimationGroup()`. Does not use pipeline.
  static func runAsync(_ task: Task, then doAfter: TaskFunc? = nil) {
    // Fail if not running on main thread:
    dispatchPrecondition(condition: .onQueue(.main))
    
    NSAnimationContext.runAnimationGroup({ context in
      CATransaction.begin()
      defer {
        CATransaction.commit()
      }
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
      task.runFunc()
    }, completionHandler: {
      if let doAfter = doAfter {
        doAfter()
      }
    })
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
