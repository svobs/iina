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
  private var observers: [NSObjectProtocol] = []

  init(_ kbTableView: DoubleClickEditTableView, _ ds: InputConfigDataStore) {
    self.tableView = kbTableView
    self.ds = ds

    super.init()

    observers.append(NotificationCenter.default.addObserver(forName: .iinaKeyBindingErrorOccurred, object: nil, queue: .main, using: errorLoadingConfigFile))
    observers.append(NotificationCenter.default.addObserver(forName: .iinaCurrentInputConfigChanged, object: nil, queue: .main) { _ in
      self.tableView.reloadData()
    })
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }


  func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
    return Preference.bool(for: .displayKeyBindingRawValues)
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    // re-evaluate this each time either table changed selection:

    // FIXME
//    parentPrefPanelController.updateRemoveButtonEnablement()
  }

  func allowDoubleClickEditForRow(_ rowNumber: Int) -> Bool {
    return ds.isEditEnabled()
  }

  // Display error alert if load error occurred:
  private func errorLoadingConfigFile(_ notification: Notification) {
    let args: [String]?
      if let fileName = notification.object as? String {
        args = [fileName]
      } else {
        args = nil
      }
    Utility.showAlert("keybinding_config.error", arguments: args, sheetWindow: self.tableView.window)
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

}
