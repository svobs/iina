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
class EditableTextField: NSTextField, NSTextFieldDelegate {
  var editTracker: CellEditTracker? = nil

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 {
      guard let editTracker = self.editTracker else {
        Logger.log("Table textField \(self) received double-click event without validateProposedFirstResponder() being called first!", level: .error)
        super.mouseDown(with: event)
        return
      }

      Logger.log("Got a double-cick", level: .verbose)
      let approved = editTracker.askUserToApproveDoubleClickEdit()
      Logger.log("Double-click approved = \(approved)", level: .verbose)
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
      editTracker.startEdit(for: self)
    } else {
      Logger.log("Table textField \(self) had becomeFirstResponder() called without editTracker being set first!", level: .error)
    }
    return true
  }

  override func textDidEndEditing(_ notification: Notification) {
    guard let editTracker = editTracker else {
      Logger.log("textDidEndEditing(): no active edit!", level: .error)
      return
    }

    // Tab / etc navigation, if any, will show up in the notification
    let textMovement: NSTextMovement?
    if let textMovementInt = notification.userInfo?["NSTextMovement"] as? Int {
      textMovement = NSTextMovement(rawValue: textMovementInt)
    } else {
      textMovement = nil
    }

    // This will handle saviung/discarding newValue, do editor disposal, and possibly start a new edit
    editTracker.endEdit(for: self, newValue: stringValue, with: textMovement)
  }
}
