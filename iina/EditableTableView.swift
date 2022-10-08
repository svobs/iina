//
//  EditableTableView.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.23.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class EditableTableView: NSTableView {
  // Must provide this for EditableTableView extended functionality
  var editableDelegate: EditableTableViewDelegate? = nil

  var rowAnimation: NSTableView.AnimationOptions = .slideDown

  var editableTextColumnIndexes: [Int] = []

  private var lastEditedTextField: EditableTextField? = nil
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
          guard !editableTextColumnIndexes.isEmpty else {
            Logger.log("TableView.KeyDown: editableTextColumnIndexes is empty!", level: .error)
            return
          }
          editCell(row: selectedRow, column: editableTextColumnIndexes[0])
          return
        }
      default:
        break
    }
    super.keyDown(with: event)
  }

  @objc func copy(_ sender: AnyObject?) {
    editableDelegate?.doEditMenuCopy()
  }

  @objc func cut(_ sender: AnyObject?) {
    editableDelegate?.doEditMenuCut()
  }

  @objc func paste(_ sender: AnyObject?) {
    editableDelegate?.doEditMenuPaste()
  }

  @objc func delete(_ sender: AnyObject?) {
    editableDelegate?.doEditMenuDelete()
  }

  // According to ancient Apple docs, the following is also called for toolbar items:
  override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    let actionDescription = item.action == nil ? "nil" : "\(item.action!)"
    guard let delegate = self.editableDelegate else {
      Logger.log("EditableTableView.validateUserInterfaceItem(): no delegate! Disabling \"\(actionDescription)\"", level: .error)
      return false
    }
    var isAllowed = false
    switch item.action {
      case #selector(copy(_:)):
        isAllowed = delegate.isCopyEnabled()
      case #selector(cut(_:)):
        isAllowed = delegate.isCutEnabled()
      case #selector(paste(_:)):
        isAllowed = delegate.isPasteEnabled()
      case #selector(delete(_:)):
        isAllowed = delegate.isDeleteEnabled()
      default:
        Logger.log("EditableTableView.validateUserInterfaceItem(): defaulting isAllowed=false for \"\(actionDescription)\"", level: .verbose)
        return false
    }
    Logger.log("EditableTableView.validateUserInterfaceItem(): isAllowed=\(isAllowed) for \"\(actionDescription)\"", level: .verbose)
    return isAllowed
  }

  override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
    if let event = event, event.type == .leftMouseDown {
      // stop old editor
      if let oldTextField = lastEditedTextField {
        self.lastEditedTextField = nil
        oldTextField.endEditing()
      }

      if let editableTextField = responder as? EditableTextField {
        // Unortunately, the event with event.clickCount==2 does not seem to present itself here.
        // Workaround: pass everything to the EditableTextField, which does see double-click.
        if let locationInTable = self.window?.contentView?.convert(event.locationInWindow, to: self) {
          let clickedRow = self.row(at: locationInTable)
          let clickedColumn = self.column(at: locationInTable)
          // qualifies so far!
          prepareTextFieldForEdit(editableTextField, row: clickedRow, column: clickedColumn)
          return true
        }
      }
    }

    return super.validateProposedFirstResponder(responder, for: event)
  }

  private func prepareTextFieldForEdit(_ textField: EditableTextField, row: Int, column: Int) {
    guard let editableDelegate = self.editableDelegate else {
      // it's valid for a table not to use this functionality
      return
    }
    textField.activeEdit = ActiveCellEdit(parentTable: self, delegate: editableDelegate,
                                          stringValueOrig: textField.stringValue, row: row, column: column)

    // keep track of it for later
    lastEditedTextField = textField
  }

  // Convenience function, for debugging
  private func eventTypeText(_ event: NSEvent?) -> String {
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

  override func editColumn(_ columnIndex: Int, row rowIndex: Int, with event: NSEvent?, select: Bool) {
    Logger.log("Opening in-line editor for row \(rowIndex), column \(columnIndex) (event: \(eventTypeText(event)))")
    guard rowIndex >= 0 && columnIndex >= 0 else {
      Logger.log("Discarding request to edit cell: rowIndex (\(rowIndex)) or columnIndex (\(columnIndex)) is less than 0", level: .error)
      return
    }
    guard rowIndex < numberOfRows else {
      Logger.log("Discarding request to edit cell: rowIndex (\(rowIndex)) cannot be less than numberOfRows (\(numberOfRows))", level: .error)
      return
    }
    guard columnIndex < numberOfColumns else {
      Logger.log("Discarding request to edit cell: columnIndex (\(columnIndex)) cannot be less than numberOfColumns (\(numberOfColumns))", level: .error)
      return
    }

    // Close old editor (if any):
    if let oldTextField = lastEditedTextField {
      self.lastEditedTextField = nil
      oldTextField.endEditing()
    }

    if rowIndex != selectedRow {
      self.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
    }

    self.scrollRowToVisible(rowIndex)
    let view = self.view(atColumn: columnIndex, row: rowIndex, makeIfNecessary: false)
    if let cellView = view as? NSTableCellView {
      if let editableTextField = cellView.textField as? EditableTextField {
        prepareTextFieldForEdit(editableTextField, row: rowIndex, column: columnIndex)
        self.window?.makeFirstResponder(editableTextField)
      }
    }
  }

  // Convenience method
  func editCell(row rowIndex: Int, column columnIndex: Int) {
    self.editColumn(columnIndex, row: rowIndex, with: nil, select: true)
  }

  private func getIndexOfEditableColumn(_ columnIndex: Int) -> Int? {
    for (indexIndex, index) in editableTextColumnIndexes.enumerated() {
      if columnIndex == index {
        return indexIndex
      }
    }
    Logger.log("Failed to find index in editableTextColumnIndexes (\(editableTextColumnIndexes)): \(columnIndex)", level: .error)
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
  // Returns true if it resulted in another editor being opened [asychronously], false if not.
  @discardableResult
  func editAnotherCellAfterEditEnd(oldRow rowIndex: Int, oldColumn columnIndex: Int, _ textMovement: NSTextMovement) -> Bool {
    let isInterRowTabEditingEnabled = Preference.bool(for: .enableInterRowTabEditingInKeyBindingsTable)

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
      self.editCell(row: newRowIndex, column: newColIndex)
    }
    // handled
    return true
  }

  // MARK: Special "reload" functions

  // Use this instead of reloadData() if the table data needs to be reloaded but the row count is the same.
  // This will preserve the selection indexes (whereas reloadData() will not)
  func reloadExistingRows() {
    reloadData(forRowIndexes: IndexSet(0..<numberOfRows), columnIndexes: IndexSet(0..<numberOfColumns))
  }

  // The default implementation of reloadData() removes the selection. This method restores it.
  // NOTE: this will result in an unncessary call to NSTableViewDelegate.tableViewSelectionDidChange().
  // Wherever possible, update via the underlying datasource using a `TableChange` object.
  func reloadDataKeepingSelectedIndexes() {
    let selectedRows = self.selectedRowIndexes
    reloadData()
    // Fires change listener...
    selectRowIndexes(selectedRows, byExtendingSelection: false)
  }

  // MARK: TableChange

  func registerTableChangeObserver(forName name: Notification.Name) {
    observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main, using: tableShouldChange))
  }

  // Row(s) changed in datasource. Could be insertions, deletions, selection change, etc (see: `ChangeType`).
  // This notification contains the information needed to make the updates to the table (see: `TableChange`).
  private func tableShouldChange(_ notification: Notification) {
    guard let tableChange = notification.object as? TableChange else {
      Logger.log("tableShouldChange: invalid object: \(type(of: notification.object))", level: .error)
      return
    }

    Logger.log("Got '\(notification.name.rawValue)' notification with changeType \(tableChange.changeType)", level: .verbose)
    tableChange.execute(on: self)
  }

}
