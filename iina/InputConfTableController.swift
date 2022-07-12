//
//  InputConfTableController.swift
//  iina
//
//  Created by Matt Svoboda on 2022.07.03.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation
import AppKit
import Cocoa

class InputConfTableViewController: NSObject, NSTableViewDelegate, NSTableViewDataSource {

  private unowned var tableView: DoubleClickEditTableView!

  private unowned var configDS: InputConfDataStore!
  private var inputChangedObserver: NSObjectProtocol? = nil
  private var currentInputChangedObserver: NSObjectProtocol? = nil

  init(_ confTableView: DoubleClickEditTableView, _ configDS: InputConfDataStore) {
    self.tableView = confTableView
    self.configDS = configDS

    super.init()

    // Set up callbacks:
    tableView.onTextDidEndEditing = onCurrentConfigNameChanged
    inputChangedObserver = NotificationCenter.default.addObserver(forName: .iinaInputConfListChanged, object: nil, queue: .main, using: onTableDataChanged)
    currentInputChangedObserver = NotificationCenter.default.addObserver(forName: .iinaCurrentInputConfChanged, object: nil, queue: .main, using: onCurrentInputChanged)
  }

  deinit {
    if let observer = inputChangedObserver {
      NotificationCenter.default.removeObserver(observer)
      inputChangedObserver = nil
    }
  }

  private func selectRow(_ confName: String) {
    if let index = configDS.tableRows.firstIndex(of: confName) {
      Logger.log("Selecting row: '\(confName)'", level: .verbose)
      self.tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }
  }

  // Row(s) changed (callback from datasource)
  func onTableDataChanged(_ notification: Notification) {
    guard let tableChanges = notification.object as? TableStateChange else {
      Logger.log("onTableDataChanged(): missing object!", level: .error)
      return
    }

    Logger.log("Got InputConfigListChanged notification; reloading data", level: .verbose)
    self.tableView.smartReload(tableChanges)
  }

  // Current input file changed (callback from datasource)
  func onCurrentInputChanged(_ notification: Notification) {
    Logger.log("Got iinaCurrentInputConfChanged notification; changing selection", level: .verbose)
    // This relies on NSTableView being smart enough to not call tableViewSelectionDidChange() if it did not actually change
    selectRow(self.configDS.currentConfName)
  }

  // NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    return configDS.tableRows.count
  }

  /**
   Make cell view.
   */
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let configName = configDS.tableRows[row]

    guard let identifier = tableColumn?.identifier else { return nil }

    guard let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView else {
      return nil
    }
    let columnName = identifier.rawValue

    switch columnName {
      case "nameColumn":
        cell.textField!.stringValue = configName
        if configDS.isDefaultConfig(configName) {
          if #available(macOS 10.14, *) {
            cell.textField?.textColor = .controlAccentColor
          } else {
            cell.textField?.textColor = .controlTextColor
          }
        } else {
          cell.textField?.textColor = .textColor
        }
        return cell
      case "isDefaultColumn":
        cell.imageView?.isHidden = !configDS.isDefaultConfig(configName)
        return cell
      default:
        Logger.log("Unrecognized column: '\(columnName)'", level: .error)
        return nil
    }
  }

  // NSTableViewDelegate

  // Selection Changed
  func tableViewSelectionDidChange(_ notification: Notification) {
    configDS.changeCurrentConfig(tableView.selectedRow)
  }


  // Rename Current Row (callback from DoubleClickEditTextField)
  func onCurrentConfigNameChanged(_ newName: String) -> Bool {
    guard self.configDS.currentConfName.localizedCompare(newName) != .orderedSame else {
      // No change to current entry: ignore
      return false
    }

    guard let oldFilePath = self.configDS.currentConfFilePath else {
      return false
    }

    guard !self.configDS.tableRows.contains(newName) else {
      // Disallow overwriting another entry in list
      Utility.showAlert("config.name_existing", sheetWindow: self.tableView.window)
      return false
    }

    let newFileName = newName + ".conf"
    let newFilePath = Utility.userInputConfDirURL.appendingPathComponent(newFileName).path

    // Overwrite of unrecognized file which is not in IINA's list is ok as long as we prompt the user first
    guard PrefKeyBindingViewController.handleExistingFile(filePath: newFilePath, self.tableView.window!) else {
      return false  // cancel
    }

    // - Move file on disk
    do {
      Logger.log("Attempting to move configFile \"\(oldFilePath)\" to \"\(newFilePath)\"")
      try FileManager.default.moveItem(atPath: oldFilePath, toPath: newFilePath)
    } catch let error {
      Utility.showAlert("config.cannot_create", arguments: [error.localizedDescription], sheetWindow: self.tableView.window!)
      return false
    }

    // Update config lists and update UI
    return configDS.renameCurrentConfig(to: newName)
  }
}
