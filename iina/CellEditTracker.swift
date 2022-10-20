//
//  FocusedTableCell.swift
//  iina
//
//  Created by Matt Svoboda on 10/8/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Plays the role of mediator: coordinates between EditableTableView and its EditableTextFields, to manage
// in-line cell editing.
class CellEditTracker {
  // Stores info for the currently focused cell, whether or not the cell is being edited
  private struct CurrentFocus {
    let textField: EditableTextField
    let stringValueOrig: String
    let row: Int
    let column: Int
  }
  private var current: CurrentFocus? = nil
  // If true, `current` has had `startEdit()` called but not `endEdit()`:
  private var editInProgress = false

  private let parentTable: EditableTableView
  private let delegate: EditableTableViewDelegate

  init(parentTable: EditableTableView, delegate: EditableTableViewDelegate) {
    self.parentTable = parentTable
    self.delegate = delegate
  }

  func changeCurrentCell(to textField: EditableTextField, row: Int, column: Int) {
    // Close old editor, if any:
    if let prev = self.current {
      if row == prev.row && column == prev.column && textField == prev.textField {
        return
      } else {
        Logger.log("CellEditTracker: changing cell from (\(prev.row), \(prev.column)) to (\(row), \(column))")
        // Clean up state here:
        endEdit(for: prev.textField, newValue: prev.textField.stringValue)
      }
    } else {
      Logger.log("CellEditTracker: changing cell to (\(row), \(column))")
    }
    // keep track of it all
    self.current = CurrentFocus(textField: textField, stringValueOrig: textField.stringValue, row: row, column: column)
    textField.editTracker = self
  }

  func startEdit(for textField: EditableTextField) {
    guard let current = current else {
      return
    }
    self.endEdit(for: current.textField)

    Logger.log("BeginEditing(\(current.row), \(current.column))", level: .verbose)
    self.editInProgress = true
    textField.isEditable = true
    textField.isSelectable = true
    textField.selectText(nil)  // creates editor
    textField.needsDisplay = true
  }

  func endEdit(for textField: EditableTextField, newValue: String? = nil, with textMovement: NSTextMovement? = nil) {
    guard let current = current, editInProgress else {
      return
    }

    // Don't tab to the next value if there is an error; stay where we are
    var allowContinuedNavigation: Bool = true

    if let newValue = newValue, newValue != current.stringValueOrig {
      if self.delegate.editDidEndWithNewText(newValue: newValue, row: current.row, column: current.column) {
        Logger.log("editDidEndWithNewText() returned TRUE: assuming new value accepted", level: .verbose)
      } else {
        // a return value of false tells us to revert to the previous value
        Logger.log("editDidEndWithNewText() returned FALSE: reverting displayed value to \"\(current.stringValueOrig)\"", level: .verbose)
        textField.stringValue = current.stringValueOrig
        allowContinuedNavigation = false
      }
    }

    Logger.log("EndEditing(\(current.row), \(current.column))", level: .verbose)
    self.editInProgress = false
    textField.window?.endEditing(for: textField)
    // Resign first responder status and give focus back to table row selection:
    textField.window?.makeFirstResponder(self.parentTable)
    textField.isEditable = false
    textField.isSelectable = false
    textField.needsDisplay = true

    // Tab / return navigation (if provided): start asynchronously so we can return
    if let textMovement = textMovement, allowContinuedNavigation {
      DispatchQueue.main.async {
        self.editAnotherCellAfterEditEnd(oldRow: current.row, oldColumn: current.column, textMovement)
      }
    }
  }

  // MARK: Navigation between edited cells

  func askUserToApproveDoubleClickEdit() -> Bool {
    if let current = current {
      return self.delegate.userDidDoubleClickOnCell(row: current.row, column: current.column)
    }
    return false
  }

  private func getIndexOfEditableColumn(_ columnIndex: Int) -> Int? {
    let editColumns = self.parentTable.editableTextColumnIndexes
    for (indexIndex, index) in editColumns.enumerated() {
      if columnIndex == index {
        return indexIndex
      }
    }
    Logger.log("Failed to find index \(columnIndex) in editableTextColumnIndexes (\(editColumns))", level: .error)
    return nil
  }

  private func nextTabColumnIndex(_ columnIndex: Int) -> Int {
    let editColumns = self.parentTable.editableTextColumnIndexes
    if let indexIndex = getIndexOfEditableColumn(columnIndex) {
      return editColumns[(indexIndex+1) %% editColumns.count]
    }
    return editColumns[0]
  }

  private func prevTabColumnIndex(_ columnIndex: Int) -> Int {
    let editColumns = self.parentTable.editableTextColumnIndexes
    if let indexIndex = getIndexOfEditableColumn(columnIndex) {
      return editColumns[(indexIndex-1) %% editColumns.count]
    }
    return editColumns[0]
  }

  // Thanks to:
  // https://samwize.com/2018/11/13/how-to-tab-to-next-row-in-nstableview-view-based-solution/
  // Returns true if it resulted in another editor being opened [asychronously], false if not.
  @discardableResult
  func editAnotherCellAfterEditEnd(oldRow rowIndex: Int, oldColumn columnIndex: Int, _ textMovement: NSTextMovement) -> Bool {
    let isInterRowTabEditingEnabled = Preference.bool(for: .tableEditKeyNavContinuesBetweenRows)

    var newRowIndex: Int
    var newColIndex: Int
    switch textMovement {
      case .tab:
        // Snake down the grid, left to right, top down
        newColIndex = nextTabColumnIndex(columnIndex)
        if newColIndex < 0 {
          Logger.log("Invalid value for next column: \(newColIndex)", level: .error)
          return false
        }
        if newColIndex <= columnIndex {
          guard isInterRowTabEditingEnabled else {
            return false
          }
          newRowIndex = rowIndex + 1
          if newRowIndex >= self.parentTable.numberOfRows {
            // Always done after last row
            return false
          }
        } else {
          newRowIndex = rowIndex
        }
      case .backtab:
        // Snake up the grid, right to left, bottom up
        newColIndex = prevTabColumnIndex(columnIndex)
        if newColIndex < 0 {
          Logger.log("Invalid value for prev column: \(newColIndex)", level: .error)
          return false
        }
        if newColIndex >= columnIndex {
          guard isInterRowTabEditingEnabled else {
            return false
          }
          newRowIndex = rowIndex - 1
          if newRowIndex < 0 {
            return false
          }
        } else {
          newRowIndex = rowIndex
        }
      case .return:
        guard isInterRowTabEditingEnabled else {
          return false
        }
        // Go to cell directly below
        newRowIndex = rowIndex + 1
        if newRowIndex >= self.parentTable.numberOfRows {
          // Always done after last row
          return false
        }
        newColIndex = columnIndex
      default: return false
    }

    DispatchQueue.main.async {
      self.parentTable.editCell(row: newRowIndex, column: newColIndex)
    }
    // handled
    return true
  }

}
