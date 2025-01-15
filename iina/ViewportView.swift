//
//  ViewportView.swift
//  iina
//
//  Created by Matt Svoboda on 11/24/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

class ViewportView: NSView {
  unowned var player: PlayerCore!

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    registerForDraggedTypes([.nsFilenames, .nsURL, .string])
    setContentCompressionResistancePriority(.required, for: .horizontal)
    setContentCompressionResistancePriority(.required, for: .vertical)
    setContentHuggingPriority(.required, for: .horizontal)
    setContentHuggingPriority(.required, for: .vertical)
  }

  private var playerWindowController: PlayerWindowController? {
    return window?.windowController as? PlayerWindowController
  }

  // Need to forward this so that dragging to resize sidebar works in native full screen
  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    playerWindowController?.mouseDown(with: event)
  }

  // Need to forward this so that dragging to resize sidebar works in native full screen
  override func mouseDragged(with event: NSEvent) {
    super.mouseDragged(with: event)
    playerWindowController?.mouseDragged(with: event)
  }

  // Need to forward this so that dragging to resize sidebar works in native full screen
  override func mouseUp(with event: NSEvent) {
    super.mouseUp(with: event)
    playerWindowController?.mouseUp(with: event)
  }

  override func rightMouseDown(with event: NSEvent) {
    super.rightMouseDown(with: event)
    playerWindowController?.rightMouseDown(with: event)
  }

  override func rightMouseUp(with event: NSEvent) {
    playerWindowController?.rightMouseUp(with: event)
    super.rightMouseUp(with: event)
  }

  override func pressureChange(with event: NSEvent) {
    playerWindowController?.pressureChange(with: event)
    super.pressureChange(with: event)
  }

  override func otherMouseDown(with event: NSEvent) {
    playerWindowController?.otherMouseDown(with: event)
    super.otherMouseDown(with: event)
  }

  override func otherMouseUp(with event: NSEvent) {
    playerWindowController?.otherMouseUp(with: event)
    super.otherMouseUp(with: event)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return Preference.bool(for: .videoViewAcceptsFirstMouse)
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    return player.acceptFromPasteboard(sender)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    return player.openFromPasteboard(sender)
  }

  // This is a little bit of a kludge, but could not find a more direct solution.
  // Need to use an NSView to notify the window when the system theme has changed
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    player?.windowController.applyThemeMaterial()
  }
}

