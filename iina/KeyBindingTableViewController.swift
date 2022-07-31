//
//  KeyBindingTableViewController.swift
//  iina
//
//  Created by Matt Svoboda on 2022.07.03.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class KeyBindingsTableViewController: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {

  private unowned var tableView: DoubleClickEditTableView!
  private unowned var ds: InputConfigDataStore!
  private var selectionDidChangeHandler: () -> Void
  private var observers: [NSObjectProtocol] = []

  init(_ kbTableView: DoubleClickEditTableView, _ ds: InputConfigDataStore, selectionDidChangeHandler: @escaping () -> Void) {
    self.tableView = kbTableView
    self.ds = ds
    self.selectionDidChangeHandler = selectionDidChangeHandler

    super.init()
    tableView.userDidDoubleClickOnCell = userDidDoubleClickOnCell
    tableView.onTextDidEndEditing = userDidEndEditing
    tableView.registerTableUpdateObserver(forName: .iinaCurrentBindingsDidChange)
    observers.append(NotificationCenter.default.addObserver(forName: .iinaKeyBindingErrorOccurred, object: nil, queue: .main, using: errorDidOccur))
    observers.append(NotificationCenter.default.addObserver(forName: .iinaCurrentInputConfigDidLoad, object: nil, queue: .main, using: currentConfigDidLoad))
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
    return ds.bindingTableRows.count
  }

  /**
   Make cell view when asked
   */
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let bindingRow = ds.getBindingRow(at: row) else {
      return nil
    }

    let binding = bindingRow.binding

    guard let identifier = tableColumn?.identifier else { return nil }

    guard let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView else {
      return nil
    }
    let columnName = identifier.rawValue

    switch columnName {
      case "keyColumn":
        cell.textField!.stringValue = isRaw() ? binding.rawKey : binding.prettyKey
        return cell
      case "actionColumn":
        cell.textField!.stringValue = isRaw() ? binding.rawAction : binding.prettyCommand
        return cell
      default:
        Logger.log("Unrecognized column: '\(columnName)'", level: .error)
        return nil
    }
  }

  func isRaw() -> Bool {
    return Preference.bool(for: .displayKeyBindingRawValues)
  }

  // MARK: NSTableViewDelegate

  func tableViewSelectionDidChange(_ notification: Notification) {
    Logger.log("KeyBindingsTable selection changed!")
    selectionDidChangeHandler()
  }

  // MARK: Custom callbacks

  func userDidDoubleClickOnCell(_ rowIndex: Int, _ columnIndex: Int) -> Bool {
    guard ds.isEditEnabledForCurrentConfig() else {
      // Cannot edit one of the default configs. Tell user to duplicate config instead:
      Utility.showAlert("duplicate_config", sheetWindow: tableView.window)
      return false
    }
    if isRaw() {
      // Use in-line editor
      return true
    }

    if let row = ds.getBindingRow(at: rowIndex) {
      showKeyBindingPanel(key: row.binding.rawKey, action: row.binding.readableAction) { key, action in
        guard !key.isEmpty && !action.isEmpty else { return }
        row.binding.rawKey = key
        row.binding.rawAction = action

        self.ds.updateBinding(at: rowIndex, to: row.binding)
      }
    }
    // Deny in-line editor from opening
    return false
  }

  func userDidEndEditing(_ newValue: String, rowIndex: Int, column: Int) -> Bool {
    guard let editedRow = ds.getBindingRow(at: rowIndex) else {
      Logger.log("userDidEndEditing(): failed to get row \(rowIndex) (newValue='\(newValue)')")
      return false
    }

    switch column {
      case 0:  // key
        editedRow.binding.rawKey = newValue
      case 1:  // action
        editedRow.binding.rawAction = newValue
      default:
        Logger.log("userDidEndEditing(): bad column: \(column)'")
        return false
    }

    ds.updateBinding(at: rowIndex, to: editedRow.binding)
    return true
  }

  // Current input file (re)loaded - callback from datasource
  private func currentConfigDidLoad(_ notification: Notification) {
    // Reload whole table. Do not preserve selection
    self.tableView.reloadData()
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

  func addNewBinding() {
    var rowIndex = self.tableView.selectedRow
    // If row is selected, add row after it. Otherwise add to end
    if rowIndex >= 0 {
      rowIndex += 1
    } else {
      //
      rowIndex = self.tableView.numberOfRows
    }

    Logger.log("Adding new binding at table index: \(rowIndex)")

    if isRaw() {
      // TODO!
      self.ds.insertNewBinding(at: rowIndex, KeyMapping(rawKey: "", rawAction: ""))
      self.tableView.scrollRowToVisible(rowIndex)
      self.tableView.beginEdit(row: rowIndex, column: 0)
    } else {
      showKeyBindingPanel { key, action in
        guard !key.isEmpty && !action.isEmpty else { return }

        self.ds.insertNewBinding(at: rowIndex, KeyMapping(rawKey: key, rawAction: action))
        self.tableView.scrollRowToVisible(rowIndex)
      }
    }
  }

  func removeSelectedBindings() {
    ds.removeBindings(at: tableView.selectedRowIndexes)
  }

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

}
