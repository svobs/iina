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


class ScrollableSliderCell: NSSliderCell {
  unowned var _player: PlayerCore!
  var player: PlayerCore {
    if let player = _player { return player }
    _player = wc?.player
    return _player
  }

  var wc: PlayerWindowController? {
    controlView?.window?.windowController as? PlayerWindowController
  }

  var slider: ScrollableSlider { controlView as! ScrollableSlider }

  var iinaAppearance: NSAppearance? {
    if isClearBG {
      return NSAppearance(iinaTheme: .dark)
    }
    return controlView?.window?.contentView?.iinaAppearance
  }

  var isDragging = false

  var isClearBG: Bool {
    wc?.currentLayout.spec.oscBackgroundIsClear ?? false
  }
  var wantsKnob: Bool {
    return !isClearBG || isDragging
  }

  override var knobThickness: CGFloat {
    return knobWidth
  }

  var knobWidth: CGFloat = Constants.Distance.Slider.defaultKnobWidth
  var knobHeight: CGFloat = Constants.Distance.Slider.defaultKnobHeight

  var currentKnobType: KnobFactory.KnobType {
    isHighlighted ? .mainKnobSelected : .mainKnob
  }

  override func drawKnob(_ knobRect: NSRect) {
    guard wantsKnob else { return }
    guard let screen = controlView?.window?.screen, let appearance = iinaAppearance else { return }
    appearance.applyAppearanceFor {
      KnobFactory.shared.drawKnob(currentKnobType, in: knobRect,
                                  darkMode: appearance.isDark,
                                  clearBG: isClearBG,
                                  knobWidth: knobWidth, mainKnobHeight: knobHeight,
                                  scaleFactor: screen.backingScaleFactor)
    }
  }

  override func knobRect(flipped: Bool) -> NSRect {
    let knobWidth = wantsKnob ? knobWidth : 0
    let barRect = barRect(flipped: flipped)
    // The usable width of the bar is reduced by the width of the knob.
    let effectiveBarWidth = barRect.width - knobWidth
    let originX = (barRect.origin.x + slider.progressRatio * effectiveBarWidth).rounded()
    let superKnobRect = super.knobRect(flipped: flipped)

    let height: CGFloat
    if #available(macOS 11, *) {
      height = (barRect.origin.y - superKnobRect.origin.y) * 2 + barRect.height
    } else {
      height = superKnobRect.height
    }

    return NSRect(x: originX, y: superKnobRect.origin.y, width: knobWidth, height: height)
  }

  override func barRect(flipped: Bool) -> NSRect {
    let superRect = super.barRect(flipped: flipped)
    let bf = BarFactory.current
    // Important: use knobHeight because it is the tallest thing being redrawn.
    // When seeking, anything being rapidly redrawn needs to have all its possible bounds included in
    // the slider's barRect, so that it knows what to mark dirty. Otherwise we will see artifacts!
    let imgHeight = bf.heightNeeded(tallestBarHeight: knobHeight)
    let extraHeightNeeded = imgHeight - superRect.height
    if extraHeightNeeded <= 0.0 {
      return superRect
    }

    let extraHeightAvailable = max(0.0, slider.bounds.height - superRect.height)
    let extraHeight = min(extraHeightAvailable, extraHeightNeeded)
    let rect = superRect.insetBy(dx: 0, dy: -(extraHeight * 0.5))
    return rect
  }

  override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
    let result = super.startTracking(at: startPoint, in: controlView)
    if result {
      isDragging = true
    }
    return result
  }

  override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
    super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
    isDragging = false
  }
}
