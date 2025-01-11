//
//  ScrollableSlider.swift
//
//  Created by Nate Thompson on 10/24/17.
//  Original source code: https://github.com/thompsonate/Scrollable-NSSlider

import Foundation

/// A subclass of `VirtualScrollWheel` which handles all scroll wheel events for a given `ScrollableSlider`.
class SliderScrollWheelDelegate: VirtualScrollWheel {
  let slider: ScrollableSlider

  init(slider: ScrollableSlider, _ log: Logger.Subsystem) {
    self.slider = slider
    super.init()
    self.log = log
  }

  /// Called zero-to-many times after `scrollSessionWillBegin` & before `scrollSessionDidEnd`.
  /// Subclasses should override.
  override func scrollDidUpdate(_ session: ScrollSession) {
    let valueDelta: CGFloat = session.consumePendingEvents(for: slider)
    let newValue = (slider.doubleValue + Double(valueDelta)).clamped(to: slider.range)
    // Prevent very tiny gestures from activating the scroll action.
    // Some actions (e.g. volume) should show an OSD even if slider.doubleValue doesn't change,
    // like when they are at max, so that user receives feedback. A sizeable valueDelta.magnitude
    // can indicate a user intent in this case.
    guard newValue != slider.doubleValue || valueDelta.magnitude > 1.0 else { return }
    slider.doubleValue = newValue
    slider.sendAction(slider.action, to: slider.target)
  }

  override func scrollSessionDidEnd(_ session: ScrollSession) {
#if DEBUG
    if DebugConfig.enableScrollWheelDebug, let player = slider.associatedPlayer {
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
      let deltaPerUserSec = session.rawDeltaTotal / timeUser
      let accelerationPerUserSec = deltaPerUserSec / timeUser
      let valueChange: String
      if let valueAtStart = session.valueAtStart {
        let valueAtEnd = slider.doubleValue
        valueChange = "  ⏐  \((valueAtEnd - valueAtStart).stringMaxFrac2) ⱽᴬᴸᵁᴱ"
      } else {
        valueChange = ""
      }
      let modelValueChange: String
      if let modelValueAtStart = session.modelValueAtStart, let modelValueAtEnd = session.modelValueAtEnd {
        let change = modelValueAtEnd - modelValueAtStart
        modelValueChange = "  ⏐ Δt:  \(change.stringMaxFrac4)s"
      } else {
        modelValueChange = ""
      }
      let msg = "ScrollWheel Δ: ⏐  \(session.rawDeltaTotal.string2FractionDigits) ᴿᴬᵂ\(valueChange)\(modelValueChange)"
      let detail = [
        "Time:       \t\(timeMsg)",
        "Events:     \t\(session.totalEventCount)",
        "Actions:    \t\(session.actionCount)    (\(actionsPerSec.stringMaxFrac2)/s, \(actionRatio.stringMaxFrac2)/event)",
        "Sensitivity: \(session.sensitivity.stringMaxFrac2)",
        "Avg.Speed:  \(deltaPerUserSec.stringMaxFrac2)/s",
        "Accel:      \t\(accelerationPerUserSec.magnitude.stringMaxFrac2)/s²",
      ].joined(separator: "\n")
      player.sendOSD(.debug(msg, detail))
    }
#endif
  }

  func configure(_ slider: ScrollableSlider, _ log: Logger.Subsystem) {
    self.log = log
    slider.scrollWheelDelegate = self
  }
}


/// Adds scroll wheel support to `NSSlider`. Must set its `scrollWheelDelegate` property after init.
class ScrollableSlider: NSSlider {
  var scrollWheelDelegate: SliderScrollWheelDelegate?

  override func scrollWheel(with event: NSEvent) {
    guard isEnabled else { return }
    if let scrollWheelDelegate {
      scrollWheelDelegate.scrollWheel(with: event)
    } else {
      super.scrollWheel(with: event)
    }
  }

  /// Converts `deltaX` & `deltaY` from any type of `NSSlider` into a standardized 1-dimensional (+/-) delta
  func extractLinearDelta(from event: NSEvent) -> CGFloat {
    var delta: Double
    // Allow horizontal scrolling on horizontal and circular sliders
    if isVertical && sliderType == .linear {
      delta = event.deltaY
    } else if userInterfaceLayoutDirection == .rightToLeft {
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
