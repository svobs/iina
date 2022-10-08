//
//  EditableTextField.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.23.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class ActiveCellEdit {
  private static var counter: Int = 0  // FIXME temp

  private var parentTable: EditableTableView
  var delegate: EditableTableViewDelegate
  var editStarted: Bool = false
  let stringValueOrig: String
  let row: Int
  let column: Int

  init(parentTable: EditableTableView, delegate: EditableTableViewDelegate, stringValueOrig: String, row: Int, column: Int) {
    ActiveCellEdit.counter += 1
    self.parentTable = parentTable
    self.delegate = delegate
    self.stringValueOrig = stringValueOrig
    self.row = row
    self.column = column
  }
  deinit {
    ActiveCellEdit.counter -= 1
    Logger.log("deinit() editorCount is now \(ActiveCellEdit.counter)")
  }

  func startNewEdit(for textField: EditableTextField) {
    self.parentTable.editCell(row: self.row, column: self.column)
  }

  func startEdit(for textField: EditableTextField) -> Bool {
    guard !editStarted else {
      Logger.log("BeginEditing(\(row), \(column)): active edit already started!", level: .error)
      return false
    }
    Logger.log("BeginEditing(\(row), \(column))", level: .verbose)
    // TODO: maybe close out old editor here?
    self.editStarted = true
    textField.isEditable = true
    textField.isSelectable = true
    textField.selectText(nil)  // creates editor
    textField.needsDisplay = true
    return true
  }

  func endEdit(for textField: EditableTextField, with textMovement: NSTextMovement? = nil) -> Bool {
//    guard self.editStarted else {
//      Logger.log("EndEditing(\(row), \(column)): active edit not started!", level: .error)
//      return false
//    }
    Logger.log("EndEditing(\(row), \(column))", level: .verbose)
    textField.window?.endEditing(for: self)
    // Resign first responder status and give focus back to table row selection:
    textField.window?.makeFirstResponder(self.parentTable)
    textField.isEditable = false
    textField.isSelectable = false
    textField.needsDisplay = true

    // Tab / return navigation (if provided): start asynchronously so we can return
    if let textMovement = textMovement {
      DispatchQueue.main.async {
        self.parentTable.editAnotherCellAfterEditEnd(oldRow: self.row, oldColumn: self.column, textMovement)
      }
    }
    return true
  }
}

/*
 Should only be used within cells of `EditableTableView`.
 */
class EditableTextField: NSTextField, NSTextFieldDelegate {
  var activeEdit: ActiveCellEdit? = nil

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 {
      Logger.log("Got a double-cick")
      if let activeEdit = self.activeEdit {
        Logger.log("...with active edit")
        let approved = activeEdit.delegate.userDidDoubleClickOnCell(row: activeEdit.row, column: activeEdit.column)
        Logger.log("Double-click approved = \(approved)")
        if approved {
          activeEdit.startNewEdit(for: self)
        }
        // Only case where `super.mouseDown()` should not be called
        return
      } else {
        Logger.log("Table cell received double-click event without validateProposedFirstResponder() being called first!", level: .error)
      }
    }
    super.mouseDown(with: event)
  }

  override func becomeFirstResponder() -> Bool {
    if let activeEdit = activeEdit {
      activeEdit.startEdit(for: self)
    }
    return true
  }

  override func textDidEndEditing(_ notification: Notification) {
    guard let activeEdit = activeEdit else {
      Logger.log("textDidEndEditing(): no active edit!", level: .error)
      return
    }

    if stringValue != activeEdit.stringValueOrig {
      if activeEdit.delegate.textDidEndEditing(newValue: stringValue, row: activeEdit.row, column: activeEdit.column) {
          Logger.log("editDidEndWithNewText() returned TRUE: assuming new value accepted", level: .verbose)
        } else {
          // a return value of false tells us to revert to the previous value
          Logger.log("editDidEndWithNewText() returned FALSE: reverting displayed value to \"\(activeEdit.stringValueOrig)\"", level: .verbose)
          self.stringValue = activeEdit.stringValueOrig
        }
    }

    // Tab / etc navigation (if any) will show up in the notification
    let textMovement: NSTextMovement?
    if let textMovementInt = notification.userInfo?["NSTextMovement"] as? Int {
      textMovement = NSTextMovement(rawValue: textMovementInt)
    } else {
      textMovement = nil
    }

    // This will do all of the cleanup. Fortunately we kept a reference to `activeEdit`.
    endEditing(textMovement)
  }

  func beginEditing() -> Bool {
    guard let activeEdit = activeEdit else {
      return false
    }
    return activeEdit.startEdit(for: self)
  }

  func endEditing(_ textMovement: NSTextMovement? = nil) {
    guard let activeEdit = activeEdit else {
      Logger.log("EndEditing(): no active edit!", level: .error)
      return
    }
    if !activeEdit.editStarted {
      // nothing to clean up. And don't delete yourself
      return
    }
    activeEdit.endEdit(for: self, with: textMovement)
  }
}
