//
//  KeyBindingTableViewController.swift
//  iina
//
//  Created by Matt Svoboda on 2022.07.03.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Register custom pasteboard type for KeyBinding (for drag&drop, and possibly eventually copy&paste)
extension NSPasteboard.PasteboardType {
  static let iinaBindingRow = NSPasteboard.PasteboardType("com.colliderli.iina.BindingRow")
}


class KeyBindingsTableViewController: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
  private let COLUMN_INDEX_KEY = 0
  private let COLUMN_INDEX_ACTION = 2
  private let DEFAULT_DRAG_OPERATION = NSDragOperation.move

  private unowned var tableView: DoubleClickEditTableView!
  private unowned var ds: InputConfigDataStore!
  private var selectionDidChangeHandler: () -> Void
  private var observers: [NSObjectProtocol] = []

  init(_ kbTableView: DoubleClickEditTableView, _ ds: InputConfigDataStore, selectionDidChangeHandler: @escaping () -> Void) {
    self.tableView = kbTableView
    self.ds = ds
    self.selectionDidChangeHandler = selectionDidChangeHandler

    super.init()

    tableView.menu = NSMenu()
    tableView.menu?.delegate = self

    tableView.allowsMultipleSelection = true
    tableView.editableTextColumnIndexes = [COLUMN_INDEX_KEY, COLUMN_INDEX_ACTION]
    tableView.userDidDoubleClickOnCell = userDidDoubleClickOnCell
    tableView.onTextDidEndEditing = userDidEndEditing
    tableView.registerTableUpdateObserver(forName: .iinaCurrentBindingsDidChange)
    observers.append(NotificationCenter.default.addObserver(forName: .iinaKeyBindingErrorOccurred, object: nil, queue: .main, using: errorDidOccur))
    if #available(macOS 10.13, *) {
      // Enable drag & drop for MacOS 10.13+. Default to "move"
      tableView.registerForDraggedTypes([.string, .iinaBindingRow])
      tableView.setDraggingSourceOperationMask([DEFAULT_DRAG_OPERATION], forLocal: false)
      tableView.draggingDestinationFeedbackStyle = .regular
    }

    tableView.scrollRowToVisible(0)
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }

  // Display error alert for errors:
  private func errorDidOccur(_ notification: Notification) {
    guard let alertInfo = notification.object as? AlertInfo else {
      Logger.log("Notification.iinaKeyBindingErrorOccurred: cannot display error: invalid object: \(type(of: notification.object))", level: .error)
      return
    }
    Utility.showAlert(alertInfo.key, arguments: alertInfo.args, sheetWindow: self.tableView.window)
  }

  // MARK: NSTableViewDataSource

  /*
   Tell AppKit the number of rows when it asks
   */
  func numberOfRows(in tableView: NSTableView) -> Int {
    return ds.getBindingRowCount()
  }

  /**
   Make cell view when asked
   */
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let bindingRow = ds.getBindingRow(at: row) else {
      return nil
    }

    guard let identifier = tableColumn?.identifier else { return nil }

    guard let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView else {
      return nil
    }
    let columnName = identifier.rawValue
    let binding = bindingRow.binding

    switch columnName {
      case "keyColumn":
        let stringValue = isRaw() ? binding.rawKey : binding.prettyKey
        setFormattedText(for: cell, to: stringValue, isEnabled: bindingRow.isEnabled)
        return cell

      case "actionColumn":
        let stringValue = isRaw() ? binding.rawAction : binding.prettyCommand
        setFormattedText(for: cell, to: stringValue, isEnabled: bindingRow.isEnabled)
        return cell

      case "statusColumn":
        cell.toolTip = bindingRow.statusMessage

        if let imageView: NSImageView = cell.imageView {
          if #available(macOS 11.0, *) {
            imageView.isHidden = false

            if bindingRow.isEnabled {
              imageView.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)!
              imageView.contentTintColor = NSColor.systemRed
              return cell
            }

            switch bindingRow.origin {
              case .iinaPlugin:
                imageView.image = NSImage(systemSymbolName: "powerplug.fill", accessibilityDescription: nil)!
              case .luaScript:
                imageView.image = NSImage(systemSymbolName: "applescript.fill", accessibilityDescription: nil)!
              default:
                if bindingRow.isMenuItem {
                  imageView.image = NSImage(systemSymbolName: "filemenu.and.selection", accessibilityDescription: nil)!
                } else {
                  imageView.image = nil
                }
            }
            imageView.contentTintColor = NSColor.controlTextColor
          } else {
            // FIXME: find icons to use so that all versions are supported
            imageView.isHidden = true
          }
        }

        return cell

      default:
        Logger.log("Unrecognized column: '\(columnName)'", level: .error)
        return nil
    }
  }

  private func setFormattedText(for cell: NSTableCellView, to stringValue: String, isEnabled: Bool) {
    guard let textField = cell.textField else { return }

    let attrString = NSMutableAttributedString(string: stringValue)

    if isEnabled {
      textField.textColor = NSColor.controlTextColor
    } else {
      textField.textColor = NSColor.systemRed

      let strikethroughAttr = [NSAttributedString.Key.strikethroughStyle: NSUnderlineStyle.single.rawValue]
      attrString.addAttributes(strikethroughAttr, range: NSRange(location: 0, length: attrString.length))
    }
    textField.attributedStringValue = attrString
  }

  private func isRaw() -> Bool {
    return Preference.bool(for: .displayKeyBindingRawValues)
  }

  // MARK: NSTableViewDelegate

  func tableViewSelectionDidChange(_ notification: Notification) {
    selectionDidChangeHandler()
  }

  func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
    guard let columnName = tableColumn?.identifier.rawValue else { return false }

    Logger.log("shouldEdit tableColumn called for row: \(row), col: \(columnName)", level: .verbose)
    return ds.isEditEnabledForCurrentConfig() && isRaw()
  }

  // MARK: DoubleClickEditTableView callbacks

  func userDidDoubleClickOnCell(_ rowIndex: Int, _ columnIndex: Int) -> Bool {
    guard ds.isEditEnabledForCurrentConfig() else {
      Logger.log("Row #\(rowIndex) is a defualt config. Telling user to duplicate it instead", level: .verbose)
      Utility.showAlert("duplicate_config", sheetWindow: tableView.window)
      return false
    }
    if isRaw() {
      Logger.log("Opening in-line editor for row \(rowIndex)", level: .verbose)
      // Use in-line editor
      return true
    }

    editWithPopup(rowIndex: rowIndex)
    // Deny in-line editor from opening
    return false
  }

  func userDidEndEditing(_ newValue: String, rowIndex: Int, columnIndex: Int) -> Bool {
    guard let editedRow = ds.getBindingRow(at: rowIndex) else {
      Logger.log("userDidEndEditing(): failed to get row \(rowIndex) (newValue='\(newValue)')")
      return false
    }

    Logger.log("User finished editing value for row \(rowIndex), col \(columnIndex): \"\(newValue)\"", level: .verbose)

    switch columnIndex {
      case COLUMN_INDEX_KEY:
        editedRow.binding.rawKey = newValue
      case COLUMN_INDEX_ACTION:
        editedRow.binding.rawAction = newValue
      default:
        Logger.log("userDidEndEditing(): bad column index: \(columnIndex)")
        return false
    }

    ds.updateBinding(at: rowIndex, to: editedRow.binding)
    return true
  }

  // MARK: Reusable actions

  // Edit either inline or with popup, depending on current mode
  private func edit(rowIndex: Int, columnIndex: Int = 0) {
    guard ds.isEditEnabledForCurrentConfig() else {
      Logger.log("Row #\(rowIndex) is a defualt config. Telling user to duplicate it instead", level: .verbose)
      Utility.showAlert("duplicate_config", sheetWindow: tableView.window)
      return
    }

    if isRaw() {
      // Use in-line editor
      self.tableView.editCell(rowIndex: rowIndex, columnIndex: columnIndex)
    } else {
      editWithPopup(rowIndex: rowIndex)
    }
  }

  // Use this if isRaw()==false (i.e., not inline editing)
  private func editWithPopup(rowIndex: Int) {
    Logger.log("Opening key binding pop-up for row #\(rowIndex)", level: .verbose)

    guard let row = ds.getBindingRow(at: rowIndex) else {
      return
    }

    showEditBindingPopup(key: row.binding.rawKey, action: row.binding.readableAction) { key, action in
      guard !key.isEmpty && !action.isEmpty else { return }
      row.binding.rawKey = key
      row.binding.rawAction = action

      self.ds.updateBinding(at: rowIndex, to: row.binding)
    }
  }

  // Adds a new binding after the current selection and then opens an editor for it. The editor with either be inline or using the popup,
  // depending on whether isRaw() is true or false, respectively.
  func addNewBinding() {
    var rowIndex: Int
    // If there are selected rows, add the new row right below the last selection. Otherwise add to end of table.
    if let lastSelectionIndex = tableView.selectedRowIndexes.max() {
      rowIndex = lastSelectionIndex
    } else {
      rowIndex = self.tableView.numberOfRows - 1
    }
    insertNewBinding(relativeTo: rowIndex, isAfterNotAt: true)
  }

  // Adds a new binding at the given location then opens an editor for it. The editor with either be inline or using the popup,
  // depending on whether isRaw() is true or false, respectively.
  // If isAfterNotAt==true, inserts after the row with given rowIndex. If isAfterNotAt==false, inserts before the row with given rowIndex.
  private func insertNewBinding(relativeTo rowIndex: Int, isAfterNotAt: Bool = false) {
    Logger.log("Inserting new binding \(isAfterNotAt ? "after" : "at") current row index: \(rowIndex)", level: .verbose)

    if isRaw() {
      let insertedRowIndex = self.ds.insertNewBinding(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, KeyMapping(rawKey: "", rawAction: ""))
      self.tableView.editCell(rowIndex: insertedRowIndex, columnIndex: 0)

    } else {
      showEditBindingPopup { key, action in
        guard !key.isEmpty && !action.isEmpty else { return }

        let insertedRowIndex = self.ds.insertNewBinding(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, KeyMapping(rawKey: key, rawAction: action))
        self.tableView.scrollRowToVisible(insertedRowIndex)
      }
    }
  }

  // Displays popup for editing a binding
  private func showEditBindingPopup(key: String = "", action: String = "", ok: @escaping (String, String) -> Void) {
    let panel = NSAlert()
    let keyRecordViewController = KeyRecordViewController()
    keyRecordViewController.keyCode = key
    keyRecordViewController.action = action
    panel.messageText = NSLocalizedString("keymapping.title", comment: "Key Mapping")
    panel.informativeText = NSLocalizedString("keymapping.message", comment: "Press any key to record.")
    panel.accessoryView = keyRecordViewController.view
    panel.window.initialFirstResponder = keyRecordViewController.keyRecordView
    let okButton = panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    okButton.cell!.bind(.enabled, to: keyRecordViewController, withKeyPath: "ready", options: nil)
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    panel.beginSheetModal(for: tableView.window!) { respond in
      if respond == .alertFirstButtonReturn {
        ok(keyRecordViewController.keyCode, keyRecordViewController.action)
      }
    }
  }

  private func copyBindingRows(from rowList: [BindingRow], to rowIndex: Int, isAfterNotAt: Bool = false) {
    // Make sure to use copy() to clone the object here
    let newBindings: [KeyMapping] = rowList.map { $0.binding.copy() as! KeyMapping }

    let firstInsertedRowIndex = self.ds.insertNewBindings(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, newBindings)

    self.tableView.scrollRowToVisible(firstInsertedRowIndex)
  }

  private func moveBindingRows(from rowList: [BindingRow], to rowIndex: Int, isAfterNotAt: Bool = false) {
    let bindings: [KeyMapping] = rowList.map { $0.binding }
    let firstInsertedRowIndex = self.ds.moveBindings(bindings, to: rowIndex, isAfterNotAt: isAfterNotAt)

    self.tableView.scrollRowToVisible(firstInsertedRowIndex)
  }

  func removeSelectedBindings() {
    ds.removeBindings(at: tableView.selectedRowIndexes)
  }

  // MARK: Drag & Drop

  /*
   Drag start: convert tableview rows to clipboard items
   */
  func tableView(_ tableView: NSTableView, pasteboardWriterForRow rowIndex: Int) -> NSPasteboardWriting? {
    return ds.getBindingRow(at: rowIndex)
  }

  /**
   This is implemented to support dropping items onto the Trash icon in the Dock
   */
  func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    guard ds.isEditEnabledForCurrentConfig(), operation == NSDragOperation.delete else {
      return
    }

    let rowList = getBindingRowsOrNothing(from: session.draggingPasteboard)

    guard !rowList.isEmpty else {
      return
    }

    Logger.log("User dragged to the trash: \(rowList)", level: .verbose)

    ds.removeBindings(withIDs: rowList.map{$0.binding.bindingID!})
  }

  private func getBindingRowsOrNothing(from pasteboard: NSPasteboard) -> [BindingRow] {
    var rowList: [BindingRow] = []
    if let objList = pasteboard.readObjects(forClasses: [BindingRow.self], options: nil) {
      for obj in objList {
        if let row = obj as? BindingRow, row.origin == .confFile {
          rowList.append(row)
        } else {
          return [] // return empty list if something was amiss
        }
      }
    }
    return rowList
  }

  /*
   Validate drop while hovering.
   */
  func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {

    guard ds.isEditEnabledForCurrentConfig() else {
      return []  // deny drop
    }

    let rowList = getBindingRowsOrNothing(from: info.draggingPasteboard)

    guard !rowList.isEmpty else {
      return []  // deny drop
    }

    // Update that little red number:
    info.numberOfValidItemsForDrop = rowList.count

    // TODO: change drop row & operatiom if dropping into non-conf-file territory

    if dropOperation == .on {
      // Cannot drop on/into existing rows. Put below it
      tableView.setDropRow(row + 1, dropOperation: .above)
    } else {
      tableView.setDropRow(row, dropOperation: .above)
    }

    let dragMask = info.draggingSourceOperationMask
    switch dragMask {
      case .copy, .move:
        return dragMask
      default:
        return DEFAULT_DRAG_OPERATION
    }
  }

  /*
   Accept the drop and execute changes, or reject drop.
   */
  func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row rowIndex: Int, dropOperation: NSTableView.DropOperation) -> Bool {

    let rowList = getBindingRowsOrNothing(from: info.draggingPasteboard)
    Logger.log("User dropped \(rowList.count) binding rows into table \(dropOperation == .on ? "on" : "above") rowIndex \(rowIndex)")
    guard !rowList.isEmpty else {
      return false
    }

    guard dropOperation == .above else {
      Logger.log("Expected dropOperaion==.above but got: \(dropOperation); bailing")
      return false
    }

    var dragMask = info.draggingSourceOperationMask
    if dragMask == NSDragOperation.every {
      dragMask = DEFAULT_DRAG_OPERATION
    }

    // Return immediately, and import (or fail to) asynchronously
    DispatchQueue.main.async {
      switch dragMask {
        case .copy:
          self.copyBindingRows(from: rowList, to: rowIndex, isAfterNotAt: false)
        case .move:
          self.moveBindingRows(from: rowList, to: rowIndex, isAfterNotAt: false)
        default:
          Logger.log("Unexpected drag operatiom: \(dragMask)")
      }
    }
    return true
  }

  // MARK: NSMenuDelegate

  fileprivate class BindingMenuItem: NSMenuItem {
    let row: BindingRow
    let rowIndex: Int

    public init(_ row: BindingRow, rowIndex: Int, title: String, action selector: Selector?, target: AnyObject?) {
      self.row = row
      self.rowIndex = rowIndex
      super.init(title: title, action: selector, keyEquivalent: "")
      self.target = target
    }

    required init(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  private func addItem(to menu: NSMenu, for row: BindingRow, withIndex rowIndex: Int, title: String, action: Selector?) {
    menu.addItem(BindingMenuItem(row, rowIndex: rowIndex, title: title, action: action, target: self))
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    // This will prevent menu from showing if no items are added
    menu.removeAllItems()

    let clickedIndex = tableView.clickedRow
    guard let clickedRow = ds.getBindingRow(at: tableView.clickedRow) else {
      return
    }

    guard ds.isEditEnabledForCurrentConfig() else {
      return
    }

    if tableView.selectedRowIndexes.contains(clickedIndex) && tableView.selectedRowIndexes.count > 1 {
      // Special menu for right-click on multiple selection

      addItem(to: menu, for: clickedRow, withIndex: clickedIndex, title: "Delete \(tableView.selectedRowIndexes.count) Rows", action: #selector(self.removeSelectedRows(_:)))
      return
    }

    let isRaw = isRaw()

    // Edit
    if isRaw {
      addItem(to: menu, for: clickedRow, withIndex: clickedIndex, title: "Edit Key", action: #selector(self.editKeyColumn(_:)))

      addItem(to: menu, for: clickedRow, withIndex: clickedIndex, title: "Edit Action", action: #selector(self.editActionColumn(_:)))
    } else {
      addItem(to: menu, for: clickedRow, withIndex: clickedIndex, title: "Edit Row...", action: #selector(self.editRow(_:)))
    }

    // ---
    menu.addItem(NSMenuItem.separator())

    // Add
    addItem(to: menu, for: clickedRow, withIndex: clickedIndex, title: "Add New Row Above", action: #selector(self.addNewRowAbove(_:)))
    addItem(to: menu, for: clickedRow, withIndex: clickedIndex, title: "Add New Row Below", action: #selector(self.addNewRowBelow(_:)))

    // ---
    menu.addItem(NSMenuItem.separator())

    // Delete
    addItem(to: menu, for: clickedRow, withIndex: clickedIndex, title: "Delete Row", action: #selector(self.removeRow(_:)))
  }

  @objc fileprivate func editKeyColumn(_ sender: BindingMenuItem) {
    edit(rowIndex: sender.rowIndex, columnIndex: COLUMN_INDEX_KEY)
  }

  @objc fileprivate func editActionColumn(_ sender: BindingMenuItem) {
    edit(rowIndex: sender.rowIndex, columnIndex: COLUMN_INDEX_ACTION)
  }

  @objc fileprivate func editRow(_ sender: BindingMenuItem) {
    edit(rowIndex: sender.rowIndex)
  }

  @objc fileprivate func addNewRowAbove(_ sender: BindingMenuItem) {
    insertNewBinding(relativeTo: sender.rowIndex, isAfterNotAt: false)
  }

  @objc fileprivate func addNewRowBelow(_ sender: BindingMenuItem) {
    insertNewBinding(relativeTo: sender.rowIndex, isAfterNotAt: true)
  }

  @objc fileprivate func removeRow(_ sender: BindingMenuItem) {
    ds.removeBindings(at: IndexSet(integer: sender.rowIndex))
  }

  @objc fileprivate func removeSelectedRows(_ sender: BindingMenuItem) {
    ds.removeBindings(at: tableView.selectedRowIndexes)
  }
}
