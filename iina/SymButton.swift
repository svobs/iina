//
//  SymButton.swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-22.
//

/// Replacement for `NSButton` (which seems to be de-facto deprecated) because that class does not support using symbol animations in newer versions of MacOS.
class SymButton: NSImageView, NSAccessibilityButton {
  var enableAcceleration: Bool = false
  var pressureStage: Int = 0 {
    willSet {
      if pressureStage != newValue {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
      }
    }
  }

  var bounceOnClick: Bool = false

  var regularColor: NSColor? = nil
  var highlightColor: NSColor? = .controlTextColor

  enum ReplacementEffect {
    case downUp
    case upUp
    case offUp
  }

  init() {
    super.init(frame: .zero)
    configureSelf()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configureSelf()
  }

  /// Similar to `NSButton`'s `init` method.
  init(image: NSImage, target: AnyObject?, action: Selector?) {
    super.init(frame: .zero)
    configureSelf()
    self.image = image
    self.target = target
    self.action = action
  }

  private func configureSelf() {
    translatesAutoresizingMaskIntoConstraints = false
    imageScaling = .scaleProportionallyUpOrDown
    imageAlignment = .alignCenter
    useDefaultColors()
  }

  var pwc: PlayerWindowController? {
    window?.windowController as? PlayerWindowController
  }

  override var acceptsFirstResponder: Bool { true }

  override func mouseDown(with event: NSEvent) {
    guard action != nil else {
      super.mouseDown(with: event)
      return
    }

    /// Setting this will cause PlayerWindowController to forward `mouseDragged` & `mouseUp` events to this object even when out of bounds
    pwc?.currentDragObject = self
    let isInsideBounds = updateHighlight(from: event)
    pwc?.log.verbose("SymButton mouseDown insideBounds=\(isInsideBounds.yn)")

    if enableAcceleration && isInsideBounds {
      pressureStage = 1
      sendAction(action, to: target)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard action != nil else {
      super.mouseDragged(with: event)
      return
    }
    let isInsideBounds = updateHighlight(from: event)
    pwc?.log.verbose{"SymButton mouseDragged insideBounds=\(isInsideBounds.yn)"}
  }

  override func mouseUp(with event: NSEvent) {
    guard action != nil else {
      super.mouseUp(with: event)
      return
    }
    let isInsideBounds = isInsideBounds(event)
    pwc?.log.verbose{"SymButton mouseUp insideBounds=\(isInsideBounds.yn)"}
    if isInsideBounds {
      pressureStage = 0
      pwc?.currentDragObject = nil

      if #available(macOS 14.0, *), bounceOnClick {
        addSymbolEffect(.bounce.down.wholeSymbol, options:
            .speed(Constants.symButtonImageTransitionSpeed)
            .nonRepeating,
                        animated: true)
      }

      pwc?.player.log.verbose{"Calling action: \(action?.description ?? "nil")"}
      sendAction(action, to: target)
      updateHighlight(isInsideBounds: false)
    }
  }

  override func pressureChange(with event: NSEvent) {
    guard enableAcceleration else { return }
    let pseudoStage = Int(event.pressure * 5)
    pwc?.player.log.trace{"SymButton: PressureChange: stage=\(event.stage) stageTransition=\(event.stageTransition) pressure=\(event.pressure) pseudoStage=\(pseudoStage)"}
    pressureStage = pseudoStage
    sendAction(action, to: target)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func accessibilityLabel() -> String? {
    return toolTip
  }

  override func accessibilityPerformPress() -> Bool {
    sendAction(action, to: target)
  }

  private func isInsideBounds(_ event: NSEvent) -> Bool {
    guard let pwc else { return false }
    return pwc.currentDragObject == self && isInsideViewFrame(pointInWindow: event.locationInWindow)
  }

  @discardableResult
  private func updateHighlight(from event: NSEvent) -> Bool {
    guard let pwc else { return false }
    let isInsideBounds = pwc.currentDragObject == self && isInsideViewFrame(pointInWindow: event.locationInWindow)
    updateHighlight(isInsideBounds: isInsideBounds)
    return isInsideBounds
  }

  private func updateHighlight(isInsideBounds: Bool) {
    if isInsideBounds {
      contentTintColor = highlightColor
    } else {
      contentTintColor = regularColor
    }
  }

  /// Sets current tint as a side effect! Do not use if currently between mouseDown & mouseUp.
  func useDefaultColors() {
    regularColor = nil
    highlightColor = .controlTextColor
    shadow = nil
    updateHighlight(isInsideBounds: false)
  }

  /// Sets current tint as a side effect! Do not use if currently between mouseDown & mouseUp.
  func useColorsForClearBG() {
    regularColor = .controlForClearBG
    highlightColor = .white
    addShadow()
    updateHighlight(isInsideBounds: false)
  }

  func replaceSymbolImage(with newImage: NSImage?, effect: ReplacementEffect? = nil) {
    guard let newImage, newImage != image else { return }
    if #available(macOS 15.0, *), let effect {
      let nativeEffect: ReplaceSymbolEffect
      switch effect {
      case .downUp:
        nativeEffect = .replace.downUp
      case .upUp:
        nativeEffect = .replace.upUp
      case .offUp:
        nativeEffect = .replace.offUp
      }
      setSymbolImage(newImage, contentTransition: nativeEffect, options:
          .speed(Constants.symButtonImageTransitionSpeed)
          .nonRepeating)
    } else {
      image = newImage
    }
  }

  /// Sets current tint as a side effect! Do not use if currently between mouseDown & mouseUp.
  func setColors(from layoutState: LayoutState) {
    if layoutState.spec.oscBackgroundIsClear {
      useColorsForClearBG()
    } else {
      useDefaultColors()
    }
  }

  func setShadow(enabled: Bool) {
    if enabled {
      guard shadow == nil else { return }
      addShadow(blurRadiusConstant: 2.0, xOffsetConstant: 0, yOffsetConstant: 0, color: .controlAccentColor)
    } else {
      shadow = nil
    }
  }

}
