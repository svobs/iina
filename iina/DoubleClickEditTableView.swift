//
//  DoubleClickEditTableView.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.23.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

fileprivate func eventTypeText(_ event: NSEvent?) -> String {
  if let event = event {
    switch event.type {
      case .leftMouseDown:
        return "leftMouseDown"
      case .leftMouseUp:
        return "leftMouseUp"
      case .cursorUpdate:
        return "cursorUpdate"
      default:
        return "\(event.type)"
    }
  }
  return "nil"
}

class TableUpdate {
  enum ChangeType {
    case selectionChangeOnly
    case addRows
    case removeRows
    case moveRows
    case renameAndMoveOneRow
    case updateRows
    case reloadAll
  }

  let changeType: ChangeType

  var newSelectedRows: IndexSet? = nil

  fileprivate init(_ changeType: ChangeType) {
    self.changeType = changeType
  }
}

class TableUpdateByRowID: TableUpdate {
  var oldRows: [String] = []
  var newRows: [String]? = nil

  override init(_ changeType: ChangeType) {
    super.init(changeType)
  }
}

class TableUpdateByRowIndex: TableUpdate {
  var toInsert: IndexSet? = nil
  var toRemove: IndexSet? = nil
  var toUpdate: IndexSet? = nil
  var toMove: [(Int, Int)]? = nil

  override init(_ changeType: ChangeType) {
    super.init(changeType)
  }
}

class DoubleClickEditTextField: NSTextField, NSTextFieldDelegate {
  var stringValueOrig: String = ""
  var editDidEndWithNewText: ((String) -> Bool)?
  var userDidDoubleClickOnCell: (() -> Bool) = { return true }
  var editCell: (() -> Void)?
  var parentTable: DoubleClickEditTableView? = nil

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

class DoubleClickEditTableView: NSTableView {
  var rowAnimation: NSTableView.AnimationOptions = .slideDown
  // args are (newText, editorRow, editorColumn)
  var onTextDidEndEditing: ((String, Int, Int) -> Bool)?
  // args are (row, column). If true is returned, a row editor will be displayed for editing cell text
  var userDidDoubleClickOnCell: ((Int, Int) -> Bool) = {(row: Int, column: Int) -> Bool in
    return true
  }

  var editableTextColumnIndexes: [Int] = []

  private var lastEditedTextField: DoubleClickEditTextField? = nil
  private var observers: [NSObjectProtocol] = []

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }

  override func keyDown(with event: NSEvent) {
    let keyChar = KeyCodeHelper.keyMap[event.keyCode]?.0
    switch keyChar {
      case "ENTER", "KP_ENTER":
        if selectedRow >= 0 && selectedRow < numberOfRows {
          Logger.log("TableView.KeyDown: ENTER on row \(selectedRow)")
          editCell(rowIndex: selectedRow, columnIndex: editableTextColumnIndexes[0])
          return
        }
      default:
        break
    }
    super.keyDown(with: event)
  }

  override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
    if let event = event, event.type == .leftMouseDown {
      // stop old editor
      if let oldTextField = lastEditedTextField {
        oldTextField.endEditing()
        self.lastEditedTextField = nil
      }

      if let editableTextField = responder as? DoubleClickEditTextField {
        // Unortunately, the event with event.clickCount==2 does not seem to present itself here.
        // Workaround: pass everything to the DoubleClickEditTextField, which does see double-click.
        if let locationInTable = self.window?.contentView?.convert(event.locationInWindow, to: self) {
          let clickedRow = self.row(at: locationInTable)
          let clickedColumn = self.column(at: locationInTable)
          prepareTextFieldForEdit(editableTextField, row: clickedRow, column: clickedColumn)
          // approved!
          return true
        }
      }
    }

    return super.validateProposedFirstResponder(responder, for: event)
  }

  private func prepareTextFieldForEdit(_ textField: DoubleClickEditTextField, row: Int, column: Int) {
    // Use a closure to bind row and column to the callback function:
    textField.userDidDoubleClickOnCell = { self.userDidDoubleClickOnCell(row, column) }
    textField.editCell = { self.editCell(rowIndex: row, columnIndex: column) }

    if let onTextDidEndEditing = onTextDidEndEditing {
      // Use a closure to bind row and column to the callback function:
      textField.editDidEndWithNewText = { onTextDidEndEditing($0, row, column) }
    } else {
      // Remember that AppKit reuses objects as an optimization, so make sure we keep it up-to-date:
      textField.editDidEndWithNewText = nil
    }
    textField.stringValueOrig = textField.stringValue
    textField.parentTable = self

    // keep track of it for later
    lastEditedTextField = textField
  }

  override func editColumn(_ column: Int, row: Int, with event: NSEvent?, select: Bool) {
    Logger.log("Opening in-line editor for row \(row), column \(column) (event: \(eventTypeText(event)))")
    guard row >= 0 && column >= 0 else {
      return
    }

    // Close old editor (if any):
    if let oldTextField = lastEditedTextField {
      oldTextField.endEditing()
      self.lastEditedTextField = nil
    }

    if row != selectedRow {
      self.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    self.scrollRowToVisible(row)
    let view = self.view(atColumn: column, row: row, makeIfNecessary: false)
    if let cellView = view as? NSTableCellView {
      if let editableTextField = cellView.textField as? DoubleClickEditTextField {
        self.prepareTextFieldForEdit(editableTextField, row: row, column: column)
        self.window?.makeFirstResponder(editableTextField)
      }
    }
  }

  // Convenience method
  func editCell(rowIndex: Int, columnIndex: Int) {
    self.editColumn(columnIndex, row: rowIndex, with: nil, select: true)
  }

  private func getIndexOfEditableColumn(_ columnIndex: Int) -> Int? {
    for (indexIndex, index) in editableTextColumnIndexes.enumerated() {
      if columnIndex == index {
        return indexIndex
      }
    }
    Logger.log("Failed to find index in editableTextColumnIndexes: \(columnIndex)", level: .error)
    return nil
  }

  private func nextTabColumnIndex(_ columnIndex: Int) -> Int {
    if let indexIndex = getIndexOfEditableColumn(columnIndex) {
      return editableTextColumnIndexes[(indexIndex+1) %% editableTextColumnIndexes.count]
    }
    return editableTextColumnIndexes[0]
  }

  private func prevTabColumnIndex(_ columnIndex: Int) -> Int {
    if let indexIndex = getIndexOfEditableColumn(columnIndex) {
      return editableTextColumnIndexes[(indexIndex-1) %% editableTextColumnIndexes.count]
    }
    return editableTextColumnIndexes[0]
  }

  // Thanks to:
  // https://samwize.com/2018/11/13/how-to-tab-to-next-row-in-nstableview-view-based-solution/
  // Returns true if another editor was opened for another cell which means no
  // further action needed to end editing.
  fileprivate func editNextCellAfterEditEnd(_ notification: Notification) -> Bool {
    guard
      let view = notification.object as? NSView,
      let textMovementInt = notification.userInfo?["NSTextMovement"] as? Int,
      let textMovement = NSTextMovement(rawValue: textMovementInt) else { return false }

    let isInterRowTabEditingEnabled = Preference.bool(for: .enableInterRowTabEditingInKeyBindingsTable)

    let columnIndex = column(for: view)
    let rowIndex = row(for: view)

    var newRowIndex: Int
    var newColIndex: Int
    switch textMovement {
      case .tab:
        // Snake down the grid, left to right, top down
        newColIndex = nextTabColumnIndex(columnIndex)
        if newColIndex <= columnIndex {
          guard isInterRowTabEditingEnabled else {
            return false
          }
          newRowIndex = rowIndex + 1
          if newRowIndex >= numberOfRows {
            return false
          }
        } else {
          newRowIndex = rowIndex
        }
      case .backtab:
        // Snake up the grid, right to left, bottom up
        newColIndex = prevTabColumnIndex(columnIndex)
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
        if newRowIndex >= numberOfRows {
          return false
        }
        newColIndex = columnIndex
      default: return false
    }

    DispatchQueue.main.async {
      self.editCell(rowIndex: newRowIndex, columnIndex: newColIndex)
    }
    // handled
    return true
  }

  func registerTableUpdateObserver(forName name: Notification.Name) {
    observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main, using: tableDataDidUpdate))
  }

  // Row(s) changed in datasource. Could be insertions, deletions, selection change, etc (see: `ChangeType`)
  private func tableDataDidUpdate(_ notification: Notification) {
    guard let tableUpdate = notification.object as? TableUpdate else {
      Logger.log("tableDataDidUpdate: invalid object: \(type(of: notification.object))", level: .error)
      return
    }

    Logger.log("Got '\(notification.name.rawValue)' notification with changeType \(tableUpdate.changeType)", level: .verbose)
    if let updateByRowId = tableUpdate as? TableUpdateByRowID {
      self.smartUpdate(updateByRowId)
    } else if let updateByIndex = tableUpdate as? TableUpdateByRowIndex {
      self.smartUpdate(updateByIndex)
    }
  }

  func smartUpdate(_ update: TableUpdateByRowIndex) {
    self.beginUpdates()
    defer {
      self.endUpdates()
    }

    switch update.changeType {
      case .selectionChangeOnly:
        fallthrough
      case .renameAndMoveOneRow:
        Logger.fatal("Not yet supported: renameAndMoveOneRow for TableUpdateByRowIndex")
      case .moveRows:
        if let movePairs = update.toMove {
          for (oldIndex, newIndex) in movePairs {
            self.moveRow(at: oldIndex, to: newIndex)
          }
        }
      case .addRows:
        if let indexes = update.toInsert {
          self.insertRows(at: indexes, withAnimation: self.rowAnimation)
        }
      case .removeRows:
        if let indexes = update.toRemove {
          self.removeRows(at: indexes, withAnimation: self.rowAnimation)
        }
      case .updateRows:
        // Just redraw all of them. This is a very inexpensive operation, and much easier
        // than chasing down all the possible ways other rows could be updated.
        reloadExistingRows()
      case .reloadAll:
        // Try not to use this much, if at all
        Logger.log("ReloadAll", level: .verbose)
        reloadData()
    }

    if let newSelectedRows = update.newSelectedRows {
      // NSTableView already updates previous selection indexes if added/removed rows cause them to move.
      // To select added rows, will need an explicit call here even if oldSelection and newSelection are the same.
      Logger.log("Updating table selection to indexes: \(newSelectedRows.reduce("[", { "\($0) \($1)"  })) ]", level: .verbose)
      self.selectRowIndexes(newSelectedRows, byExtendingSelection: false)
      // Make sure the table gets focus:
      self.window!.makeFirstResponder(self)
    }
  }

  /*
   Attempts to be a generic mechanism for updating the table's contents with an animation and
   avoiding unnecessary calls to listeners such as tableViewSelectionDidChange()
   */
  func smartUpdate(_ update: TableUpdateByRowID) {
    // encapsulate animation transaction in this function
    self.beginUpdates()
    defer {
      self.endUpdates()
    }

    switch update.changeType {
      case .selectionChangeOnly:
        fallthrough
      case .renameAndMoveOneRow:
        renameAndMoveOneRow(update)
      case .addRows:
        addRows(update)
      case .removeRows:
        removeRows(update)
      case .updateRows:
        // Just redraw all of them. This is a very inexpensive operation
        reloadExistingRows()
      case .moveRows:
        Logger.fatal("Not yet supported: moveRows for TableUpdateByRowID")
      case .reloadAll:
        // Try not to use this much, if at all
        Logger.log("ReloadAll", level: .verbose)
        reloadData()
    }

    if let newSelectedRows = update.newSelectedRows {
      // NSTableView already updates previous selection indexes if added/removed rows cause them to move.
      // To select added rows, will need an explicit call here even if oldSelection and newSelection are the same.
      Logger.log("Updating table selection to indexes: \(newSelectedRows.reduce("[", { "\($0) \($1)"  })) ]", level: .verbose)
      self.selectRowIndexes(newSelectedRows, byExtendingSelection: false)
    }
  }

  // Use this instead of reloadData() if the table data needs to be reloaded but the row count is the same.
  // This will preserve the selection indexes (whereas reloadData() will not)
  func reloadExistingRows() {
    reloadData(forRowIndexes: IndexSet(0..<numberOfRows), columnIndexes: IndexSet(0..<numberOfColumns))
  }

  // The default implementation of reloadData() removes the selection. This method restores it.
  // NOTE: this will result in an unncessary call to NSTableViewDelegate.tableViewSelectionDidChange().
  // Wherever possible, update via the underlying datasource and then call smartUpdate()
  func reloadDataKeepingSelectedIndexes() {
    let selectedRows = self.selectedRowIndexes
    reloadData()
    // Fires change listener...
    self.selectRowIndexes(selectedRows, byExtendingSelection: false)
  }

  private func renameAndMoveOneRow(_ update: TableUpdateByRowID) {
    guard let newRowsArray = update.newRows else {
      return
    }
    guard newRowsArray.count == update.oldRows.count else {
      return
    }
    var oldRowsSet = Set(update.oldRows)
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

    guard let oldIndex = update.oldRows.firstIndex(of: oldName) else {
      return
    }
    guard let newIndex = newRowsArray.firstIndex(of: newName) else {
      return
    }

    Logger.log("Moving row from index \(oldIndex) to index \(newIndex)", level: .verbose)
    self.moveRow(at: oldIndex, to: newIndex)
  }

  private func addRows(_ update: TableUpdateByRowID) {
    guard let newRowsArray = update.newRows else {
      return
    }
    var addedRowsSet = Set(newRowsArray)
    assert (addedRowsSet.count == newRowsArray.count)
    addedRowsSet.subtract(update.oldRows)
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
      Logger.log("TableUpdate: \(newRowsArray.count) adds but no inserts!", level: .error)
      return
    }
    Logger.log("Inserting \(indexesOfInserts.count) indexes into table")
    self.insertRows(at: indexesOfInserts, withAnimation: self.rowAnimation)
  }

  private func removeRows(_ update: TableUpdateByRowID) {
    guard let newRowsArray = update.newRows else {
      return
    }
    var removedRowsSet = Set(update.oldRows)
    assert (removedRowsSet.count == update.oldRows.count)
    removedRowsSet.subtract(newRowsArray)

    var indexesOfRemoves = IndexSet()
    for (oldRowIndex, oldRow) in update.oldRows.enumerated() {
      if removedRowsSet.contains(oldRow) {
        indexesOfRemoves.insert(oldRowIndex)
      }
    }
    Logger.log("Removing rows from table (IDs: \(removedRowsSet); \(indexesOfRemoves.count) indexes)", level: .verbose)
    self.removeRows(at: indexesOfRemoves, withAnimation: self.rowAnimation)
  }
}
