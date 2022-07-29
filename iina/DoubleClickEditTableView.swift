//
//  DoubleClickEditTableView.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.23.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class TableStateChange {
  enum ChangeType {
    case addRows
    case removeRows
    case renameAndMoveOneRow
    case reloadAll
  }

  let changeType: ChangeType

  var oldRows: [String] = []
  var newRows: [String]? = nil

  var newSelectionIndex: Int? = nil

  init(_ changeType: ChangeType) {
    self.changeType = changeType
  }
}

class DoubleClickEditTextField: NSTextField, NSTextFieldDelegate {
  var stringValueOrig: String = ""
  var editDidEndWithNewText: ((String) -> Bool)?

  override func mouseDown(with event: NSEvent) {
    if (event.clickCount == 2 && !self.isEditable) {
      self.beginEditing();
    } else {
      super.mouseDown(with: event)
    }
  }

  override func textDidEndEditing(_ notification: Notification) {
    defer {
      // Must ALWAYS call super method or extreme wackiness will happen
      super.textDidEndEditing(notification)
    }

    if stringValue != stringValueOrig {
      if let callbackFunc = editDidEndWithNewText {
        if callbackFunc(stringValue) {
          Logger.log("editDidEndWithNewText callback returned TRUE", level: .verbose)
        } else {
          // a return value of false tells us to use the previous value
          Logger.log("editDidEndWithNewText callback returned FALSE: reverting displayed value to \"\(stringValueOrig)\"", level: .verbose)
          self.stringValue = self.stringValueOrig
        }
      }
    }
  }

  func beginEditing() {
    self.isEditable = true
    self.isSelectable = true
    self.backgroundColor = NSColor.white
    self.selectText(nil)
    self.needsDisplay = true
  }

  func endEditing() {
    self.currentEditor()?.window?.endEditing(for: self)
    self.isEditable = false
    self.isSelectable = false
    self.backgroundColor = NSColor.clear
    self.needsDisplay = true
  }

}

class DoubleClickEditTableView: NSTableView {
  var rowAnimation: NSTableView.AnimationOptions = .slideDown
  // args are (newText, editorRow, editorColumn)
  var onTextDidEndEditing: ((String, Int, Int) -> Bool)?
  // args are (row, column)
  var allowDoubleClickEditFor: ((Int, Int) -> Bool)?

  private var lastEditedTextField: DoubleClickEditTextField? = nil

  override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
    if let event = event, event.type == .leftMouseDown {
      // stop old editor
      lastEditedTextField?.endEditing()
      lastEditedTextField = nil

      if let editableTextField = responder as? DoubleClickEditTextField {
        // Unortunately, the event with event.clickCount==2 does not present itself here, so we have to filter at 1st click
        if let locationInTable = self.window?.contentView?.convert(event.locationInWindow, to: self) {
          let clickedRow = self.row(at: locationInTable)
          let clickedColumn = self.column(at: locationInTable)
          var isDoubleClickEnabled: Bool = true
          if let allowDoubleClickEditFor = allowDoubleClickEditFor {
            isDoubleClickEnabled = allowDoubleClickEditFor(clickedRow, clickedColumn)
          }

          if isDoubleClickEnabled {
            if let onTextDidEndEditing = onTextDidEndEditing {
              // Use a closure to bind row and column to the callback function:
              editableTextField.editDidEndWithNewText = { onTextDidEndEditing($0, clickedRow, clickedColumn) }
            } else {
              // Remember that AppKit reuses objects as an optimization, so make sure we keep it up-to-date:
              editableTextField.editDidEndWithNewText = nil
            }
            editableTextField.stringValueOrig = editableTextField.stringValue

            // keep track of it for later
            lastEditedTextField = editableTextField

            return true
          }
        }
      }
    }

    return super.validateProposedFirstResponder(responder, for: event)
  }

  /*
   Attempts to be a generic mechanism for updating the table's contents with an animation and
   avoiding unnecessary calls to listeners such as tableViewSelectionDidChange()
   */
  func smartUpdate(_ changes: TableStateChange) {
    // encapsulate animation transaction in this function
    self.beginUpdates()
    defer {
      self.endUpdates()
    }

    switch changes.changeType {
      case .renameAndMoveOneRow:
        renameAndMoveOneRow(changes)
      case .addRows:
        addRows(changes)
      case .removeRows:
        removeRows(changes)
      case .reloadAll:
        Logger.log("ReloadAll", level: .verbose)
        reloadData()
    }

    if let newSelectionIndex = changes.newSelectionIndex {
      // NSTableView already updates previous selection indexes if added/removed rows cause them to move.
      // To select added rows, will need an explicit call here even if oldSelection and newSelection are the same.
      Logger.log("Selecting table index: \(newSelectionIndex)", level: .verbose)
      self.selectRowIndexes(IndexSet(integer: newSelectionIndex), byExtendingSelection: false)
    }
  }

  private func renameAndMoveOneRow(_ changes: TableStateChange) {
    guard let newRowsArray = changes.newRows else {
      return
    }
    guard newRowsArray.count == changes.oldRows.count else {
      return
    }
    var oldRowsSet = Set(changes.oldRows)
    let oldSet = oldRowsSet.subtracting(newRowsArray)
    guard oldSet.count == 1 else {
      return
    }
    guard let oldName = oldSet.first else {
      return
    }
    oldRowsSet.remove(oldName)
    let newSet = oldRowsSet.symmetricDifference(newRowsArray)
    guard newSet.count == 1 else {
      return
    }
    guard let newName = newSet.first else {
      return
    }

    guard let oldIndex = changes.oldRows.firstIndex(of: oldName) else {
      return
    }
    guard let newIndex = newRowsArray.firstIndex(of: newName) else {
      return
    }

    self.moveRow(at: oldIndex, to: newIndex)
  }

  private func addRows(_ changes: TableStateChange) {
    guard let newRowsArray = changes.newRows else {
      return
    }
    var addedRowsSet = Set(newRowsArray)
    assert (addedRowsSet.count == newRowsArray.count)
    addedRowsSet.subtract(changes.oldRows)
    Logger.log("Set of rows to add = \(addedRowsSet)", level: .verbose)

    // Find start indexes of each span of added rows
    var tableIndex = 0
    var indexesOfInserts = IndexSet()
    for newRow in newRowsArray {
      if addedRowsSet.contains(newRow) {
        indexesOfInserts.insert(tableIndex)
      }
      tableIndex += 1
    }
    guard !indexesOfInserts.isEmpty else {
      Logger.log("TableStateChange: \(newRowsArray.count) adds but no inserts!", level: .error)
      return
    }
    Logger.log("Inserting \(indexesOfInserts.count) indexes into table")
    self.insertRows(at: indexesOfInserts, withAnimation: self.rowAnimation)
  }

  private func removeRows(_ changes: TableStateChange) {
    guard let newRowsArray = changes.newRows else {
      return
    }
    var removedRowsSet = Set(changes.oldRows)
    assert (removedRowsSet.count == changes.oldRows.count)
    removedRowsSet.subtract(newRowsArray)

    var indexesOfRemoves = IndexSet()
    for (oldRowIndex, oldRow) in changes.oldRows.enumerated() {
      if removedRowsSet.contains(oldRow) {
        indexesOfRemoves.insert(oldRowIndex)
      }
    }
    Logger.log("Removing rows from table (IDs: \(removedRowsSet); \(indexesOfRemoves.count) indexes)", level: .verbose)
    self.removeRows(at: indexesOfRemoves, withAnimation: self.rowAnimation)
  }
}
