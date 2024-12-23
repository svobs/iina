//
//  SymButton.swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-22.
//  Copyright © 2024 lhc. All rights reserved.
//

/// Replacement for `NSButton` (which seems to be de-facto deprecated) because that class does not support using symbol animations in newer versions of MacOS.
class SymButton: NSImageView {
  init(image: NSImage, target: NSObject, action: Selector) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    refusesFirstResponder = false
    self.image = image
    self.target = target
    self.action = action
    imageScaling = .scaleProportionallyUpOrDown
    if #available(macOS 11.0, *) {
      /// The only reason for setting this is so that `replayImage`, when used, will be drawn in bold.
      /// This is ignored when using play & pause images (they are static assets).
      /// Looks like `pointSize` here is ignored. Not sure if `scale` is relevant either?
      let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold, scale: .small)
      symbolConfiguration = config
    }
  }

  var pwc: PlayerWindowController? {
    window?.windowController as? PlayerWindowController
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool { true }

  override func mouseDown(with event: NSEvent) {
    updateHighlight(from: event)
    /// Setting this will cause PlayerWindowController to forward `mouseDragged` & `mouseUp` events to this object even when out of bounds
    pwc?.currentDragObject = self
  }

  override func mouseDragged(with event: NSEvent) {
    updateHighlight(from: event)
  }

  override func mouseUp(with event: NSEvent) {
    if isInsideViewFrame(pointInWindow: event.locationInWindow) {
      self.sendAction(action, to: target)

      if #available(macOS 14.0, *) {
        addSymbolEffect(.bounce.down.byLayer, options: .nonRepeating, animated: true)
      } else {
        // Fallback on earlier versions
      }
    }
    contentTintColor = nil
    pwc?.currentDragObject = nil
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  private func updateHighlight(from event: NSEvent) {
    let isInsideBounds = isInsideViewFrame(pointInWindow: event.locationInWindow)
    contentTintColor = isInsideBounds ? .selectedControlTextColor : nil
  }

  var symImage: NSImage? {
    get {
      return image
    }
    set {
      if let newValue, #available(macOS 15.0, *) {
        setSymbolImage(newValue, contentTransition: .replace)
      } else {
        image = newValue
      }
    }
  }
}
