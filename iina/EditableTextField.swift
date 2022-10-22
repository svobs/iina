//
//  EditableTextField.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.23.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/*
 Should only be used within cells of `EditableTableView`.
 */
class EditableTextField: NSTextField {
  var editTracker: CellEditTracker? = nil

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 {
      guard let editTracker = self.editTracker else {
        Logger.log("Table textField \(self) received double-click event without validateProposedFirstResponder() being called first!", level: .error)
        super.mouseDown(with: event)
        return
      }

      Logger.log("EditableTextField: Got a double-cick", level: .verbose)
      let approved = editTracker.askUserToApproveDoubleClickEdit()
      Logger.log("Double-click approved: \(approved)", level: .verbose)
      if approved {
        self.window?.makeFirstResponder(self)
      }
      // These are the only cases where `super.mouseDown()` should not be called
      return
    }
    super.mouseDown(with: event)
  }

  override func becomeFirstResponder() -> Bool {
    if let editTracker = editTracker {
      editTracker.startEdit()
    } else {
      Logger.log("Table textField \(self) had becomeFirstResponder() called without editTracker being set first!", level: .error)
    }
    return true
  }
}
