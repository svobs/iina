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

  // This can be called both for the "undo" of the original "do", and for the "redo" (AKA the undo of the undo).
  // `actionName` will only be used for the original "do" action, and will be cached for use in "undo" / "redo"
  @discardableResult
  func registerUndo(actionName: String? = nil, _ action: @escaping () -> Void) -> Bool {
    guard let undoMan = self.undoManager else {
      Logger.log("Cannot register for undo: undoManager is nil", level: .verbose)
      return false
    }

    let origActionName: String? = UndoHelper.getOrSetOriginalActionName(actionName, undoMan)
    let actionDebugString = origActionName == nil ? "" : " \(origActionName!)"
    Logger.log("[\(UndoHelper.formatCurrentOp(undoMan))] Registering for \"\(undoMan.isRedoing ? "Redo" : "Undo")\(actionDebugString)\" (\(UndoHelper.extraDebug(undoMan)))")

    undoMan.registerUndo(withTarget: self, handler: { manager in
      Logger.log("Starting \(UndoHelper.formatAction(origActionName, undoMan)) (\(UndoHelper.extraDebug(undoMan)))")

      action()
    })

    return true
  }

  static private func getOrSetOriginalActionName(_ actionName: String?, _ undoMan: UndoManager) -> String? {
    if undoMan.isUndoing {
      return undoMan.undoActionName
    }
    if undoMan.isRedoing {
      return undoMan.redoActionName
    }

    // Action name only needs to be set once per action, and it will displayed for both "Undo {}" and "Redo {}".
    // There's no need to change the name of it for the redo.
    if let origActionName = actionName {
      undoMan.setActionName(origActionName)
      return origActionName
    }
    return nil
  }

  static private func extraDebug(_ undoMan: UndoManager) -> String {
    "canUndo: \(undoMan.canUndo), canRedo: \(undoMan.canRedo)"
  }

  static private func formatCurrentOp(_ undoMan: UndoManager) -> String {
    undoMan.isUndoing ? "Undo" : (undoMan.isRedoing ? "Redo" : "Do")
  }

  static private func formatAction(_ actionName: String?, _ undoMan: UndoManager) -> String {
    let actionString = actionName == nil ? "" :  " \"\(actionName ?? "")\""
    return "\(UndoHelper.formatCurrentOp(undoMan))\(actionString)"
  }
}

class PrefsWindowUndoHelper: UndoHelper {
  override var undoManager: UndoManager? {
    PreferenceWindowController.undoManager
  }
}
