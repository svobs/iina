//
//  KeyBindingTableViewController.swift
//  iina
//
//  Created by Matt Svoboda on 2022.07.03.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class KeyBindingsTableViewController: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
  fileprivate unowned let parentPrefPanelController: PrefKeyBindingViewController!
  init(_ parentPrefPanelController: PrefKeyBindingViewController) {
    self.parentPrefPanelController = parentPrefPanelController
  }

  func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
    return Preference.bool(for: .displayKeyBindingRawValues)
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    // re-evaluate this each time either table changed selection:
    parentPrefPanelController.updateRemoveButtonEnablement()
  }

//  func allowDoubleClickEditForRow(_ rowNumber: Int) -> Bool {
//    if let configName = configDS.getRow(at: rowNumber), !configDS.isDefaultConfig(configName) {
//      return true
//    }
//    return false
//  }
//
//  // Row(s) changed (callback from datasource)
//  func tableDataDidChange(_ notification: Notification) {
//    guard let tableChanges = notification.object as? TableStateChange else {
//      Logger.log("tableDataDidChange(): missing object!", level: .error)
//      return
//    }
//
//    Logger.log("Got InputConfigListChanged notification; reloading data", level: .verbose)
//    self.tableView.smartUpdate(tableChanges)
//  }
//
//  // Current input file changed (callback from datasource)
//  func currentInputDidChange(_ notification: Notification) {
//    Logger.log("Got iinaCurrentInputConfChanged notification; changing selection", level: .verbose)
//    // This relies on NSTableView being smart enough to not call tableViewSelectionDidChange() if it did not actually change
//    selectCurrenConfigRow()
//  }
//
//  // MARK: NSTableViewDataSource
//
//  /*
//   Tell AppKit the number of rows when it asks
//   */
//  func numberOfRows(in tableView: NSTableView) -> Int {
//    return configDS.tableRows.count
//  }
//
//  /**
//   Make cell view when asked
//   */
//  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
//    let configName = configDS.tableRows[row]
//
//    guard let identifier = tableColumn?.identifier else { return nil }
//
//    guard let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView else {
//      return nil
//    }
//    let columnName = identifier.rawValue
//
//    switch columnName {
//      case "nameColumn":
//        cell.textField!.stringValue = configName
//        return cell
//      case "isDefaultColumn":
//        cell.imageView?.isHidden = !configDS.isDefaultConfig(configName)
//        return cell
//      default:
//        Logger.log("Unrecognized column: '\(columnName)'", level: .error)
//        return nil
//    }
//  }

}
