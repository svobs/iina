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
    guard let binding = ds.getBindingRow(at: row) else {
      return nil
    }

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
    selectionDidChangeHandler()
  }

  // MARK: Custom callbacks

  func userDidDoubleClickOnCell(_ row: Int, _ column: Int) -> Bool {
    guard ds.isEditEnabledForCurrentConfig() else {
      // Cannot edit one of the default configs. Tell user to duplicate config instead:
      Utility.showAlert("duplicate_config", sheetWindow: tableView.window)
      return false
    }
    if isRaw() {
      // Use in-line editor
      return true
    }

    if let selectedBinding = ds.getBindingRow(at: row) {
      showKeyBindingPanel(key: selectedBinding.rawKey, action: selectedBinding.readableAction) { key, action in
        guard !key.isEmpty && !action.isEmpty else { return }
        selectedBinding.rawKey = key
        selectedBinding.rawAction = action

        // FIXME: ds.update()
      }
    }
    return false
  }

  func userDidEndEditing(_ newValue: String, row: Int, column: Int) -> Bool {
    guard let editedBinding = ds.getBindingRow(at: row) else {
      Logger.log("userDidEndEditing(): failed to get row \(row) (newValue='\(newValue)')")
      return false
    }

    switch column {
      case 0:  // key
        editedBinding.rawKey = newValue
      case 1:  // action
        editedBinding.rawAction = newValue
      default:
        Logger.log("userDidEndEditing(): bad column: \(column)'")
        return false
    }

    // FIXME: ds.update()


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
    var row = self.tableView.selectedRow
    // If row is selected, add row after it. Otherwise add to end
    if row >= 0 {
      row += 1
    } else {
      //
      row = self.tableView.numberOfRows
    }

    if isRaw() {
      // TODO!
      self.ds.insertNewBinding(at: row, KeyMapping(rawKey: "", rawAction: ""))
      self.tableView.scrollRowToVisible(row)
      self.tableView.beginEdit(row: row, column: 0)
    } else {
      showKeyBindingPanel { key, action in
        guard !key.isEmpty && !action.isEmpty else { return }

        self.ds.insertNewBinding(at: row, KeyMapping(rawKey: key, rawAction: action))
        self.tableView.scrollRowToVisible(row)
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
