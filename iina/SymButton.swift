//
//  SymButton.swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-22.
//  Copyright © 2024 lhc. All rights reserved.
//

/// Replacement for `NSButton` (which seems to be de-facto deprecated) because that class does not support using symbol animations in newer versions of MacOS.
class SymButton: NSImageView {
  var bounceOnClick: Bool = false

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

  private func configureSelf() {
    translatesAutoresizingMaskIntoConstraints = false
    imageScaling = .scaleProportionallyUpOrDown
    if #available(macOS 11.0, *) {
      /// The only reason for setting this is so that `replayImage`, when used, will be drawn in bold.
      /// This is ignored when using play & pause images (they are static assets).
      /// Looks like `pointSize` here is ignored. Not sure if `scale` is relevant either?
      let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .ultraLight, scale: .large)
      symbolConfiguration = config
    }
  }

  var pwc: PlayerWindowController? {
    window?.windowController as? PlayerWindowController
  }

  override var acceptsFirstResponder: Bool { true }

  override func mouseDown(with event: NSEvent) {
    guard action != nil else { return }
    /// Setting this will cause PlayerWindowController to forward `mouseDragged` & `mouseUp` events to this object even when out of bounds
    pwc?.currentDragObject = self
    updateHighlight(from: event)
  }

  override func mouseDragged(with event: NSEvent) {
    guard action != nil else { return }
    updateHighlight(from: event)
  }

  override func mouseUp(with event: NSEvent) {
    guard action != nil else { return }
    let isInsideBounds = updateHighlight(from: event)
    guard isInsideBounds else { return }

    if #available(macOS 14.0, *), bounceOnClick {
      addSymbolEffect(.bounce.down.wholeSymbol, options:
          .speed(Constants.Speed.symButtonImageTransition)
          .nonRepeating,
                      animated: true)
    }

    pwc?.player.log.verbose("Calling action: \(action?.description ?? "nil")")
    self.sendAction(action, to: target)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  @discardableResult
  private func updateHighlight(from event: NSEvent) -> Bool {
    guard let pwc else { return false }
    let isInsideBounds = pwc.currentDragObject == self && isInsideViewFrame(pointInWindow: event.locationInWindow)
    if isInsideBounds {
      if pwc.currentLayout.spec.oscBackgroundIsClear {
        contentTintColor = .white
      } else {
        contentTintColor = .selectedControlTextColor
      }
    } else {
      if pwc.currentLayout.spec.oscBackgroundIsClear {
        contentTintColor = .controlForClearBG
      } else {
        contentTintColor = nil
      }
    }
    return isInsideBounds
  }

  func replaceSymbolImage(with newImage: NSImage?, effect: ReplacementEffect) {
    if #available(macOS 15.0, *), let newImage, newImage != image {
      let nativeEffect: ReplaceSymbolEffect
      switch effect {
      case .downUp:
        nativeEffect = .replace.downUp
      case .upUp:
        nativeEffect = .replace.upUp
      case .offUp:
        nativeEffect = .replace.offUp
      }
      setSymbolImage(newImage, contentTransition: nativeEffect,
                     options:
          .speed(Constants.Speed.symButtonImageTransition)
          .nonRepeating)
    } else {
      image = newImage
    }
  }
}
