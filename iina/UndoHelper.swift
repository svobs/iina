//
//  TableStateManager.swift
//  iina
//
//  Created by Matt Svoboda on 11/26/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Just a bunch of boilerplate code for actionName, logging
class UndoHelper {

  var undoManager: UndoManager? {
    nil  // Subclasses should override
  }

  @discardableResult
  func registerUndo(actionName: String? = nil, _ action: @escaping () -> Void) -> Bool {
    guard let undoManager = self.undoManager else {
      Logger.log("Cannot register for undo: undoManager is nil", level: .verbose)
      return false
    }

    let origActionName: String?
    if undoManager.isUndoing {
      origActionName = undoManager.undoActionName
    } else if undoManager.isRedoing {
      origActionName = undoManager.redoActionName
    } else {
      // Action name only needs to be set once per action, and it will displayed for both "Undo {}" and "Redo {}".
      // There's no need to change the name of it for the redo.
      if let actionName = actionName {
        origActionName = actionName
        undoManager.setActionName(actionName)
      } else {
        origActionName = nil
      }
    }

    let actionDebugString = origActionName == nil ? "" : " of \"\(origActionName!)\""
    Logger.log("Registering for \"\(undoManager.isRedoing ? "Redo" : "Undo")\"\(actionDebugString)", level: .verbose)

    undoManager.registerUndo(withTarget: self, handler: { manager in
      Logger.log("Starting \(self.format(action: origActionName, undoManager))", level: .verbose)

      action()
    })

    return true
  }

  func format(action actionName: String?, _ undoManager: UndoManager) -> String {
    let actionString = actionName == nil ? "" :  " \"\(actionName ?? "")\""
    return "\(undoManager.isUndoing ? "Undo" : (undoManager.isRedoing ? "Redo" : "Do")) action\(actionString)"
  }
}

class PrefsWindowUndoHelper: UndoHelper {
  override var undoManager: UndoManager? {
    PreferenceWindowController.undoManager
  }
}
