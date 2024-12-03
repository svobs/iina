//
//  StartupHandler.swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-03.
//  Copyright © 2024 lhc. All rights reserved.
//


import Foundation

class StartupHandler {

  enum OpenWindowsState: Int {
    case stillEnqueuing = 1
    case doneEnqueuing
    case doneOpening
  }

  var state: OpenWindowsState = .stillEnqueuing

  var restoreTimer: Timer? = nil
  var restoreTimeoutAlertPanel: NSAlert? = nil

  /**
   Becomes true once `application(_:openFile:)`, `handleURLEvent()` or `droppedText()` is called.
   Mainly used to distinguish normal launches from others triggered by drag-and-dropping files.
   */
  var openFileCalled = false
  var shouldIgnoreOpenFile = false

  var restoreOpenFileWindow = false

  /// Try to wait until all windows are ready so that we can show all of them at once.
  /// Make sure order of `wcsToRestore` is from back to front to restore the order properly
  var wcsToRestore: [NSWindowController] = []
  var wcForOpenFile: PlayerWindowController? = nil

  var wcsReady = Set<NSWindowController>()
}
