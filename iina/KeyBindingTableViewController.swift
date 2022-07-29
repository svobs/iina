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
    tableView.allowDoubleClickEditFor = allowDoubleClickEditFor
    tableView.onTextDidEndEditing = userDidEndEditing
    observers.append(NotificationCenter.default.addObserver(forName: .iinaKeyBindingErrorOccurred, object: nil, queue: .main, using: errorDidOccur))
    observers.append(NotificationCenter.default.addObserver(forName: .iinaCurrentInputConfigChanged, object: nil, queue: .main, using: currentConfigDidChange))
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

    let isRaw = Preference.bool(for: .displayKeyBindingRawValues)

    switch columnName {
      case "keyColumn":
        cell.textField!.stringValue = isRaw ? binding.rawKey : binding.keyForDisplay
        return cell
      case "actionColumn":
        cell.textField!.stringValue = isRaw ? binding.rawAction : binding.actionForDisplay
        return cell
      default:
        Logger.log("Unrecognized column: '\(columnName)'", level: .error)
        return nil
    }
  }

  // MARK: NSTableViewDelegate

  func tableViewSelectionDidChange(_ notification: Notification) {
    selectionDidChangeHandler()
  }

  // MARK: Custom callbacks

  func allowDoubleClickEditFor(_ rowNumber: Int, _ colNumber: Int) -> Bool {
    return ds.isEditEnabled()
  }

  func userDidEndEditing(_ newValue: String, row: Int, column: Int) -> Bool {
    // TODO
    return false
  }

  // Current input file changed (callback from datasource)
  private func currentConfigDidChange(_ notification: Notification) {
    self.tableView.reloadData()
  }

  // Display error alert if load error occurred:
  private func errorDidOccur(_ notification: Notification) {
    let args: [String]?
      if let fileName = notification.object as? String {
        args = [fileName]
      } else {
        args = nil
      }
    Utility.showAlert("keybinding_config.error", arguments: args, sheetWindow: self.tableView.window)
  }

}
