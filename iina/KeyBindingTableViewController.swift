//
//  KeyBindingTableViewController.swift
//  iina
//
//  Created by Matt Svoboda on 2022.07.03.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class KeyBindingsTableViewController: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
  private let COLUMN_INDEX_KEY = 0
  private let COLUMN_INDEX_ACTION = 2

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

    tableView.userDidDoubleClickOnCell = userDidDoubleClickOnCell
    tableView.onTextDidEndEditing = userDidEndEditing
    tableView.registerTableUpdateObserver(forName: .iinaCurrentBindingsDidChange)
    observers.append(NotificationCenter.default.addObserver(forName: .iinaKeyBindingErrorOccurred, object: nil, queue: .main, using: errorDidOccur))

    tableView.scrollRowToVisible(0)
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
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
        setRowText(for: cell.textField!, to: stringValue, isEnabled: bindingRow.isEnabled)
        return cell

      case "actionColumn":
        let stringValue = isRaw() ? binding.rawAction : binding.prettyCommand
        setRowText(for: cell.textField!, to: stringValue, isEnabled: bindingRow.isEnabled)
        return cell

      case "statusColumn":
        if #available(macOS 11.0, *) {
          if bindingRow.isMenuItem {
            let nsImage = NSImage(systemSymbolName: "filemenu.and.selection", accessibilityDescription: nil)!
            cell.imageView?.image = nsImage
            cell.imageView?.isHidden = false
            cell.imageView?.contentTintColor = .controlTextColor
            cell.toolTip = bindingRow.statusMessage
          } else if !bindingRow.isEnabled {
            let nsImage = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)!
            cell.imageView?.image = nsImage
            cell.imageView?.isHidden = false
            cell.imageView?.contentTintColor = .systemRed
            cell.toolTip = bindingRow.statusMessage
          } else {
            cell.imageView?.isHidden = true
            cell.toolTip = nil
          }
        }
        return cell

      default:
        Logger.log("Unrecognized column: '\(columnName)'", level: .error)
        return nil
    }
  }

  private func setRowText(for textField: NSTextField, to stringValue: String, isEnabled: Bool) {
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

  func isRaw() -> Bool {
    return Preference.bool(for: .displayKeyBindingRawValues)
  }

  // MARK: NSTableViewDelegate

  func tableViewSelectionDidChange(_ notification: Notification) {
    Logger.log("KeyBindingsTable selection changed!")
    selectionDidChangeHandler()
  }

  func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
    guard let identifier = tableColumn?.identifier else { return false }
    let columnName = identifier.rawValue

    Logger.log("shouldEdit tableColumn called for row: \(row), col: \(columnName)")
    return ds.isEditEnabledForCurrentConfig() && isRaw()
  }

  // MARK: Custom callbacks

  func userDidDoubleClickOnCell(_ rowIndex: Int, _ columnIndex: Int) -> Bool {
    guard ds.isEditEnabledForCurrentConfig() else {
      Logger.log("Row #\(rowIndex) is a defualt config. Telling user to duplicate it instead", level: .verbose)
      Utility.showAlert("duplicate_config", sheetWindow: tableView.window)
      return false
    }
    if isRaw() {
      Logger.log("Opening in-line editor for row #\(rowIndex)", level: .verbose)
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

    Logger.log("User finishing entering value for row #\(rowIndex), col #\(columnIndex): \"\(newValue)\"", level: .verbose)

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

  // Display error alert for errors:
  private func errorDidOccur(_ notification: Notification) {
    guard let alertInfo = notification.object as? AlertInfo else {
      Logger.log("Notification.iinaKeyBindingErrorOccurred: cannot display error: invalid object: \(type(of: notification.object))", level: .error)
      return
    }
    Utility.showAlert(alertInfo.key, arguments: alertInfo.args, sheetWindow: self.tableView.window)
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

  func editWithPopup(rowIndex: Int) {
    Logger.log("Opening key binding pop-up for row #\(rowIndex)", level: .verbose)

    guard let row = ds.getBindingRow(at: rowIndex) else {
      return
    }

    showKeyBindingPanel(key: row.binding.rawKey, action: row.binding.readableAction) { key, action in
      guard !key.isEmpty && !action.isEmpty else { return }
      row.binding.rawKey = key
      row.binding.rawAction = action

      self.ds.updateBinding(at: rowIndex, to: row.binding)
    }
  }

  func addNewBinding() {
    var rowIndex: Int
    // If row is selected, add row after it. Otherwise add to end
    if tableView.selectedRow >= 0 {
      rowIndex = tableView.selectedRow
    } else {
      rowIndex = self.tableView.numberOfRows - 1
    }
    insertNewBinding(relativeTo: rowIndex, isAfterNotAt: true)
  }

  func insertNewBinding(relativeTo rowIndex: Int, isAfterNotAt: Bool = false) {
    Logger.log("Inserting new binding \(isAfterNotAt ? "after" : "at") current row index: \(rowIndex)", level: .verbose)

    if isRaw() {
      let insertedRowIndex = self.ds.insertNewBinding(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, KeyMapping(rawKey: "", rawAction: ""))
      self.tableView.editCell(rowIndex: insertedRowIndex, columnIndex: 0)

    } else {
      showKeyBindingPanel { key, action in
        guard !key.isEmpty && !action.isEmpty else { return }

        let insertedRowIndex = self.ds.insertNewBinding(relativeTo: rowIndex, isAfterNotAt: isAfterNotAt, KeyMapping(rawKey: key, rawAction: action))
        self.tableView.scrollRowToVisible(insertedRowIndex)
      }
    }
  }

  func removeSelectedBindings() {
    ds.removeBindings(at: tableView.selectedRowIndexes)
  }

  // Displays popup for editing a binding
  func showKeyBindingPanel(key: String = "", action: String = "", ok: @escaping (String, String) -> Void) {
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

}
