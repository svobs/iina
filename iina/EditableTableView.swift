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
  var editableDelegate: EditableTableViewDelegate? = nil {
    didSet {
      if let editableDelegate = editableDelegate {
        cellEditTracker = CellEditTracker(parentTable: self, delegate: editableDelegate)
      } else {
        cellEditTracker = nil
      }
    }
  }

  private var cellEditTracker: CellEditTracker? = nil

  var rowAnimation: NSTableView.AnimationOptions = .slideDown

  // Must provide this for editCell() to work
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
    if let keyChar = KeyCodeHelper.keyMap[event.keyCode]?.0 {
      switch keyChar {
        case "ENTER", "KP_ENTER":
          if selectedRow >= 0 && selectedRow < numberOfRows && !editableTextColumnIndexes.isEmpty {
            if let delegate = self.editableDelegate, delegate.userDidPressEnterOnRow(selectedRow) {
              Logger.log("TableView.KeyDown: \(keyChar) on row \(selectedRow)")
              editCell(row: selectedRow, column: editableTextColumnIndexes[0])
              return
            }
          }
        default:
          break
      }
    }
    super.keyDown(with: event)
  }

  // MARK: Edit menu > Cut, Copy, Paste, Delete

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
      Logger.log("EditableTableView.validateUserInterfaceItem(): no delegate! Disabling \"\(actionDescription)\"", level: .warning)
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
      case #selector(selectAll(_:)):
        isAllowed = delegate.isSelectAllEnabled()
      default:
        Logger.log("EditableTableView.validateUserInterfaceItem(): defaulting isAllowed=false for \"\(actionDescription)\"", level: .verbose)
        return false
    }
    Logger.log("EditableTableView.validateUserInterfaceItem(): isAllowed=\(isAllowed) for \"\(actionDescription)\"", level: .verbose)
    return isAllowed
  }

  // MARK: In-line cell editing

  override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
    if let event = event, event.type == .leftMouseDown {
      if let editableTextField = responder as? EditableTextField, let cellEditTracker = cellEditTracker {
        // Unortunately, the event with event.clickCount==2 does not seem to present itself here.
        // Workaround: pass everything to the EditableTextField, which does see double-click.
        if let locationInTable = self.window?.contentView?.convert(event.locationInWindow, to: self) {
          let clickedRow = self.row(at: locationInTable)
          let clickedColumn = self.column(at: locationInTable)
          // qualifies!
          cellEditTracker.changeCurrentCell(to: editableTextField, row: clickedRow, column: clickedColumn)
          return true
        }
      }
    }

    return super.validateProposedFirstResponder(responder, for: event)
  }

  override func editColumn(_ columnIndex: Int, row rowIndex: Int, with event: NSEvent?, select: Bool) {
    Logger.log("editColumn called for row \(rowIndex), column \(columnIndex) (event: \(eventTypeText(event)))", level: .verbose)
    guard let cellEditTracker = cellEditTracker else {
      return
    }

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

    guard let view = self.view(atColumn: columnIndex, row: rowIndex, makeIfNecessary: true),
       let cellView = view as? NSTableCellView,
          let editableTextField = cellView.textField as? EditableTextField else {
      return
    }

    Logger.log("Opening in-line editor for row \(rowIndex), column \(columnIndex) (event: \(eventTypeText(event)), textField: \(editableTextField))")

    self.scrollRowToVisible(rowIndex)
    cellEditTracker.changeCurrentCell(to: editableTextField, row: rowIndex, column: columnIndex)

    if select && self.selectedRow != rowIndex {
      Logger.log("Selecting rowIndex \(rowIndex)", level: .verbose)
      self.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
    }

    // Hypothesis: There seems to be a race condition in NSTableView which can result in half-complete updates to its UI.
    // If the call to changeCurrentCell() above resulted in another cell editor being closed, those updates needs to be allowed
    // to complete before proceeding, or they may never complete. In the case here, the last edited cell may still show the
    // "text editing" cursor until its row is next refreshed. By calling `async` here, we postpone our updates to the end of
    // the current update queue, which allows previously queued updates to complete.
    DispatchQueue.main.async {
      if let view = self.view(atColumn: columnIndex, row: rowIndex, makeIfNecessary: true),
         let cellView = view as? NSTableCellView,
         let editableTextField = cellView.textField as? EditableTextField {
        self.window?.makeFirstResponder(editableTextField)
      }
    }
  }

  // Convenience method
  func editCell(row rowIndex: Int, column columnIndex: Int) {
    self.editColumn(columnIndex, row: rowIndex, with: nil, select: true)
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

  // MARK: Special "reload" functions

  // Use this instead of reloadData() if the table data needs to be reloaded but the row count is the same.
  // This will preserve the selection indexes (whereas reloadData() will not)
  func reloadExistingRows() {
    let selectedRows = self.selectedRowIndexes
    reloadData(forRowIndexes: IndexSet(0..<numberOfRows), columnIndexes: IndexSet(0..<numberOfColumns))
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
