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
  var stringValueOrig: String = ""
  var editDidEndWithNewText: ((String) -> Bool)?
  var userDidDoubleClickOnCell: (() -> Bool) = { return true }
  var editCell: (() -> Void)?
  var parentTable: EditableTableView? = nil

  override func mouseDown(with event: NSEvent) {
    if (event.clickCount == 2 && !self.isEditable && userDidDoubleClickOnCell()) {
      if let editCallback = editCell {
        // This will ensure that the row is selected if not already:
        editCallback()
      } else {
        Logger.log("Table cell received double-click event without validateProposedFirstResponder() being called first!", level: .error)
      }
    } else {
      super.mouseDown(with: event)
    }
  }

  override func becomeFirstResponder() -> Bool {
    self.beginEditing()
    return true
  }

  override func textDidEndEditing(_ notification: Notification) {
    defer {
      endEditing()
    }

    if stringValue != stringValueOrig {
      if let callbackFunc = editDidEndWithNewText {
        if callbackFunc(stringValue) {
          Logger.log("editDidEndWithNewText() returned TRUE: assuming new value accepted", level: .verbose)
        } else {
          // a return value of false tells us to revert to the previous value
          Logger.log("editDidEndWithNewText() returned FALSE: reverting displayed value to \"\(stringValueOrig)\"", level: .verbose)
          self.stringValue = self.stringValueOrig
        }
      }
    }
    if let parentTable = parentTable {
      let _ = parentTable.editNextCellAfterEditEnd(notification)
    }
  }

  func beginEditing() {
    self.isEditable = true
    self.isSelectable = true
    self.backgroundColor = NSColor.white
    self.selectText(nil)  // creates editor
    self.needsDisplay = true
  }

  func endEditing() {
    self.editCell = nil
    self.window?.endEditing(for: self)
    // Resign first responder status and give focus back to table row selection:
    self.window?.makeFirstResponder(self.parentTable)
    self.isEditable = false
    self.isSelectable = false
    self.backgroundColor = NSColor.clear
    self.needsDisplay = true
  }

}
