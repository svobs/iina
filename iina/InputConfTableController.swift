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

class InputConfTableViewController: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {

  private unowned var tableView: DoubleClickEditTableView!

  private unowned var configDS: InputConfDataStore!
  private var inputChangedObserver: NSObjectProtocol? = nil
  private var currentInputChangedObserver: NSObjectProtocol? = nil

  init(_ confTableView: DoubleClickEditTableView, _ configDS: InputConfDataStore) {
    self.tableView = confTableView
    self.configDS = configDS

    super.init()

    self.tableView.menu = NSMenu()
    self.tableView.menu?.delegate = self

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

  func selectCurrentInputRow() {
    let confName = self.configDS.currentConfName
    if let index = configDS.tableRows.firstIndex(of: confName) {
      Logger.log("Selecting row: '\(confName)' (index \(index))", level: .verbose)
      self.tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
      Logger.log("Selected row is now: \(self.tableView.selectedRow)", level: .verbose)
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
    selectCurrentInputRow()
  }

  // MARK: NSTableViewDataSource

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
        return cell
      case "isDefaultColumn":
        cell.imageView?.isHidden = !configDS.isDefaultConfig(configName)
        return cell
      default:
        Logger.log("Unrecognized column: '\(columnName)'", level: .error)
        return nil
    }
  }

  // MARK: NSTableViewDelegate

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
    guard self.handleExistingFile(filePath: newFilePath) else {
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

  // MARK: NSMenuDelegate

  fileprivate class InputConfMenuItem: NSMenuItem {
    let configName: String

    public init(configName: String, title: String, action selector: Selector?) {
      self.configName = configName
      super.init(title: title, action: selector, keyEquivalent: "")
    }

    required init(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  private func getClickedConfigName() -> String? {
    guard tableView.clickedRow >= 0 else {
      return nil
    }
    return configDS.getRow(at: tableView.clickedRow)
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    guard let clickedConfigName = getClickedConfigName() else {
      // This will prevent menu from showing
      menu.removeAllItems()
      return
    }

    rebuildMenu(menu, clickedConfigName: clickedConfigName)
  }

  private func rebuildMenu(_ menu: NSMenu, clickedConfigName: String) {
    menu.removeAllItems()

    // Reveal in Finder
    var menuItem = InputConfMenuItem(configName: clickedConfigName, title: "Reveal in Finder", action: #selector(self.revealConfigFromMenu(_:)))
    menuItem.target = self
    menu.addItem(menuItem)

    // Duplicate
    menuItem = InputConfMenuItem(configName: clickedConfigName, title: "Duplicate...", action: #selector(self.duplicateConfigFromMenu(_:)))
    menuItem.target = self
    menu.addItem(menuItem)

    // ---
    menu.addItem(NSMenuItem.separator())

    // Delete
    menuItem = InputConfMenuItem(configName: clickedConfigName, title: "Delete", action: #selector(self.deleteConfigFromMenu(_:)))
    menuItem.target = self
    menu.addItem(menuItem)
  }

  @objc fileprivate func deleteConfigFromMenu(_ sender: InputConfMenuItem) {
    self.deleteConfig(sender.configName)
  }

  @objc fileprivate func revealConfigFromMenu(_ sender: InputConfMenuItem) {
    self.revealConfig(sender.configName)
  }

  @objc fileprivate func duplicateConfigFromMenu(_ sender: InputConfMenuItem) {
    self.duplicateConfig(sender.configName)
  }

  // MARK: Reusable UI actions

  @objc public func deleteConfig(_ configName: String) {
    guard let confFilePath = self.requireFilePath(forConfig: configName) else {
      return
    }

    do {
      try FileManager.default.removeItem(atPath: confFilePath)
    } catch {
      Utility.showAlert("error_deleting_file", sheetWindow: tableView.window)
    }
    // update prefs & refresh UI
    configDS.removeConfig(configName)
  }

  @objc func revealConfig(_ configName: String) {
    guard let confFilePath = self.requireFilePath(forConfig: configName) else {
      return
    }
    let url = URL(fileURLWithPath: confFilePath)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  @objc func duplicateConfig(_ configName: String) {
    guard let currFilePath = self.requireFilePath(forConfig: configName) else {
      return
    }
    
    // prompt
    Utility.quickPromptPanel("config.duplicate", sheetWindow: tableView.window) { newName in
      guard !newName.isEmpty else {
        Utility.showAlert("config.empty_name", sheetWindow: self.tableView.window)
        return
      }
      guard !self.configDS.tableRows.contains(newName) else {
        Utility.showAlert("config.name_existing", sheetWindow: self.tableView.window)
        return
      }

      self.makeNewConfFile(newName, doAction: { (newFilePath: String) in
        // - copy file
        do {
          try FileManager.default.copyItem(atPath: currFilePath, toPath: newFilePath)
          return true
        } catch let error {
          Utility.showAlert("config.cannot_create", arguments: [error.localizedDescription], sheetWindow: self.tableView.window)
          return false
        }
      })
    }
  }

  func makeNewConfFile(_ newName: String, doAction: (String) -> Bool) {
    let newFileName = newName + ".conf"
    let newFilePath = Utility.userInputConfDirURL.appendingPathComponent(newFileName).path
    // - if exists
    guard self.handleExistingFile(filePath: newFilePath) else {
      return
    }

    guard doAction(newFilePath) else {
      return
    }

    self.configDS.addUserConfig(name: newName, filePath: newFilePath)
  }

  // Check whether file already exists at `filePath`.
  // If it does, prompt the user to overwrite it or show it in Finder; return true if the former and successful, false otherwise
  private func handleExistingFile(filePath: String) -> Bool {
    let fm = FileManager.default
    if fm.fileExists(atPath: filePath) {
      if Utility.quickAskPanel("config.file_existing", sheetWindow: self.tableView.window) {
        // - delete file
        do {
          try fm.removeItem(atPath: filePath)
        } catch {
          Utility.showAlert("error_deleting_file", sheetWindow: self.tableView.window)
          return false
        }
      } else {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: filePath)])
        return false
      }
    }
    return true
  }

  private func requireFilePath(forConfig configName: String) -> String? {
    if let confFilePath = self.configDS.getFilePath(forConfig: configName) {
      return confFilePath
    }

    Utility.showAlert("error_finding_file", arguments: ["config"], sheetWindow: tableView.window)
    return nil
  }
}
