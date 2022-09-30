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

class InputConfigTableViewController: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
  private let COLUMN_INDEX_NAME = 0

  private unowned var tableView: EditableTableView!
  private unowned var tableStore: InputConfigTableStore!
  private var observers: [NSObjectProtocol] = []

  init(_ inputConfigTableView: EditableTableView, _ tableStore: InputConfigTableStore) {
    self.tableView = inputConfigTableView
    self.tableStore = tableStore

    super.init()

    tableView.menu = NSMenu()
    tableView.menu?.delegate = self

    // Set up callbacks:
    tableView.editableTextColumnIndexes = [COLUMN_INDEX_NAME]
    tableView.userDidDoubleClickOnCell = userDidDoubleClickOnCell
    tableView.onTextDidEndEditing = userDidEndEditingCurrentName
    tableView.registerTableChangeObserver(forName: .iinaInputConfigTableShouldUpdate)

    if #available(macOS 10.13, *) {
      // Enable drag & drop for MacOS 10.13+
      tableView.registerForDraggedTypes([.fileURL])
      tableView.setDraggingSourceOperationMask([.copy], forLocal: false)
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

  func selectCurrentConfigRow() {
    let configName = self.tableStore.currentConfigName
    guard let index = tableStore.configTableRows.firstIndex(of: configName) else {
      Logger.log("selectCurrentConfigRow(): Failed to find '\(configName)' in table; falling back to default", level: .error)
      tableStore.changeCurrentConfigToDefault()
      return
    }

    self.tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    Logger.log("Selected row: '\(configName)' (index \(index)). Selected rows are now: \(self.tableView.selectedRowIndexes)", level: .verbose)
  }

  // MARK: NSTableViewDataSource

  /*
   Tell AppKit the number of rows when it asks
   */
  func numberOfRows(in tableView: NSTableView) -> Int {
    return tableStore.configTableRows.count
  }

  /**
   Make cell view when asked
   */
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let configName = tableStore.configTableRows[row]

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
        cell.imageView?.isHidden = !tableStore.isDefaultConfig(configName)
        return cell
      default:
        Logger.log("Unrecognized column: '\(columnName)'", level: .error)
        return nil
    }
  }

  // MARK: NSTableViewDelegate

  // Selection Changed
  func tableViewSelectionDidChange(_ notification: Notification) {
    tableStore.changeCurrentConfig(tableView.selectedRow)
  }

  // MARK: EditableTableView callbacks

  func userDidDoubleClickOnCell(_ rowNumber: Int, _ colNumber: Int) -> Bool {
    if let configName = tableStore.getConfigRow(at: rowNumber), !tableStore.isDefaultConfig(configName) {
      return true
    }
    return false
  }

  // User finished editing (callback from EditableTextField).
  // Renames current comfig & its file on disk
  func userDidEndEditingCurrentName(_ newName: String, row: Int, column: Int) -> Bool {
    guard !self.tableStore.currentConfigName.equalsIgnoreCase(newName) else {
      // No change to current entry: ignore
      return false
    }

    Logger.log("User renamed current config to \"\(newName)\" in editor", level: .verbose)

    guard let oldFilePath = self.tableStore.currentConfigFilePath else {
      Logger.log("Failed to find file for current config! Aborting rename", level: .error)
      return false
    }

    guard !self.tableStore.configTableRows.contains(newName) else {
      // Disallow overwriting another entry in list
      Utility.showAlert("config.name_existing", sheetWindow: self.tableView.window)
      return false
    }

    let newFilePath =  Utility.buildConfigFilePath(for: newName)

    if newFilePath != oldFilePath { // allow this...it helps when user is trying to fix corrupted file list
      // Overwrite of unrecognized file which is not in IINA's list is ok as long as we prompt the user first
      guard self.handlePossibleExistingFile(filePath: newFilePath) else {
        return false  // cancel
      }
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
    return tableStore.renameCurrentConfig(newName: newName)
  }

  // MARK: Drag & Drop

  /*
   Drag start: convert tableview rows to clipboard items
   */
  func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
    if let configName = tableStore.getConfigRow(at: row),
       let filePath = tableStore.getFilePath(forConfig: configName) {
      return NSURL(fileURLWithPath: filePath)
    }
    return nil
  }

  /**
   This is implemented to support dropping items onto the Trash icon in the Dock
   */
  func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    guard operation == NSDragOperation.delete else {
        return
    }

    let userConfigList = filterCurrentUserConfigs(from: session.draggingPasteboard)

    guard userConfigList.count == 1 else {
      return
    }

    Logger.log("User dragged to the trash: \(userConfigList[0])", level: .verbose)

    self.deleteConfig(userConfigList[0])
  }

  /*
   Validate drop while hovering.
   Override drag operation to "copy" always, and set drag target to whole table.
   */
  func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {

    let newFilePathList = filterNewFilePaths(from: info.draggingPasteboard)

    if newFilePathList.isEmpty {
      // no files, or no ".conf" files, or dragging existing items over self
      return []
    }

    // Update that little red number:
    info.numberOfValidItemsForDrop = newFilePathList.count

    tableView.setDropRow(-1, dropOperation: .above)
    return NSDragOperation.copy
  }

  /*
   Accept the drop and import file(s), or reject drop.
   */
  func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {

    let newFilePathList = filterNewFilePaths(from: info.draggingPasteboard)
    Logger.log("User dropped \(newFilePathList.count) new config files into table")
    guard !newFilePathList.isEmpty else {
      return false
    }

    // Return immediately, and import (or fail to) asynchronously
    DispatchQueue.main.async {
      self.importConfigFiles(newFilePathList)
    }
    return true
  }

  private func filterNewFilePaths(from pasteboard: NSPasteboard) -> [String] {
    var newFilePathList: [String] = []

    if let filePathList = InputConfigTableViewController.extractFileList(from: pasteboard) {

      for filePath in filePathList {
        // Filter out files which are already in the table, and files which don't end in ".conf"
        if filePath.lowercasedPathExtension == AppData.configFileExtension && tableStore.getUserConfigName(forFilePath: filePath) == nil &&
            !AppData.defaultConfigs.values.contains(filePath) {
          newFilePathList.append(filePath)
        }
      }
    }

    return newFilePathList
  }

  private func filterCurrentUserConfigs(from pasteboard: NSPasteboard) -> [String] {
    var userConfigList: [String] = []

    if let filePathList = InputConfigTableViewController.extractFileList(from: pasteboard) {

      for filePath in filePathList {
        if let configName = tableStore.getUserConfigName(forFilePath: filePath) {
          userConfigList.append(configName)
        }
      }
    }

    return userConfigList
  }

  private static func extractFileList(from pasteboard: NSPasteboard) -> [String]? {
    var fileList: [String] = []

    pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.forEach {
      if let url = $0 as? URL {
        fileList.append(url.path)
      }
    }
    return fileList
  }

  // MARK: NSMenuDelegate

  fileprivate class InputConfMenuItem: NSMenuItem {
    let configName: String

    public init(configName: String, title: String, action selector: Selector?, target: AnyObject?) {
      self.configName = configName
      super.init(title: title, action: selector, keyEquivalent: "")
      self.target = target
    }

    required init(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    // This will prevent menu from showing if no items are added
    menu.removeAllItems()

    guard let clickedConfigName = tableStore.getConfigRow(at: tableView.clickedRow) else {
      return
    }

    buildMenu(menu, clickedConfigName: clickedConfigName)
  }

  private func buildMenu(_ menu: NSMenu, clickedConfigName: String) {
    // Reveal in Finder
    menu.addItem(InputConfMenuItem(configName: clickedConfigName, title: "Reveal in Finder", action: #selector(self.revealConfigFromMenu(_:)), target: self))

    // Duplicate
    menu.addItem(InputConfMenuItem(configName: clickedConfigName, title: "Duplicate...", action: #selector(self.duplicateConfigFromMenu(_:)), target: self))

    // ---
    menu.addItem(NSMenuItem.separator())

    // Delete
    menu.addItem(InputConfMenuItem(configName: clickedConfigName, title: "Delete", action: #selector(self.deleteConfigFromMenu(_:)), target: self))
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
    tableStore.removeConfig(configName)
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
      guard !self.tableStore.configTableRows.contains(newName) else {
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

  /*
   Imports conf file(s).
   Checks that each file can be opened and parsed and if any cannot, prints an error and does nothing.
   If any of the imported files would overwrite an existing one, for each conflict the user is asked whether to
   delete the existing; the import is aborted after the first one the user declines.

   If successful, adds new rows to the UI, with the last added row being selected as the new current config.
   */
  func importConfigFiles(_ fileList: [String]) {
    Logger.log("Importing input config files: \(fileList)", level: .verbose)

    // configName -> (srcFilePath, dstFilePath)
    var createdConfigDict: [String: (String, String)] = [:]

    for filePath in fileList {
      let url = URL(fileURLWithPath: filePath)
      
      guard InputConfigFileData.loadFile(at: filePath) != nil else {
        let fileName = url.lastPathComponent
        Utility.showAlert("keybinding_config.error", arguments: [fileName], sheetWindow: tableView.window)
        Logger.log("Error reading config file '\(filePath)'; aborting import", level: .error)
        // Do not import any files if we can't parse one.
        // This probably means the user doesn't know what they are doing, or something is very wrong
        return
      }
      let newName = url.deletingPathExtension().lastPathComponent
      let newFilePath =  Utility.buildConfigFilePath(for: newName)

      guard self.handlePossibleExistingFile(filePath: newFilePath) else {
        // Do not proceed if user does not want to delete.
        Logger.log("Aborting config file import: user did not delete file: \(newFilePath)", level: .verbose)
        return
      }
      createdConfigDict[newName] = (filePath, newFilePath)
    }

    // Copy files one by one. Allow copy errors but keep track of which failed
    var failedNameSet = Set<String>()
    for (newName, (filePath, newFilePath)) in createdConfigDict {
      do {
        Logger.log("Import: copying: '\(filePath)' -> '\(newFilePath)'", level: .verbose)
        try FileManager.default.copyItem(atPath: filePath, toPath: newFilePath)
      } catch let error {
        Utility.showAlert("config.cannot_create", arguments: [error.localizedDescription], sheetWindow: self.tableView.window)
        Logger.log("Import: failed to copy: '\(filePath)' -> '\(newFilePath)': \(error.localizedDescription)", level: .error)
        failedNameSet.insert(newName)
      }
    }

    // Filter failed rows from being added to UI
    let configsToAdd: [String: String] = createdConfigDict.filter{ !failedNameSet.contains($0.key) }.mapValues { $0.1 }
    guard !configsToAdd.isEmpty else {
      return
    }
    Logger.log("Successfully imported: \(configsToAdd.count)' input config files")

    // update prefs & refresh UI
    self.tableStore.addUserConfigs(configsToAdd)
  }

  func makeNewConfFile(_ newName: String, doAction: (String) -> Bool) {
    let newFilePath =  Utility.buildConfigFilePath(for: newName)

    // - if exists with same name
    guard self.handlePossibleExistingFile(filePath: newFilePath) else {
      return
    }

    guard doAction(newFilePath) else {
      return
    }

    self.tableStore.addUserConfig(name: newName, filePath: newFilePath)
  }

  // Check whether file already exists at `filePath`.
  // If it does, prompt the user to overwrite it or show it in Finder. Return true if user agrees, false otherwise
  private func handlePossibleExistingFile(filePath: String) -> Bool {
    let fm = FileManager.default
    if fm.fileExists(atPath: filePath) {
      Logger.log("Blocked by existing file: \"\(filePath)'\"", level: .verbose)
      let fileName = URL(fileURLWithPath: filePath).lastPathComponent
      // TODO: show the filename in the dialog
      if Utility.quickAskPanel("config.file_existing", messageComment: "\"\(fileName)\"") {
        // - delete file
        do {
          try fm.removeItem(atPath: filePath)
          Logger.log("Successfully removed file: \"\(filePath)'\"")
          return true
        } catch  {
          Utility.showAlert("error_deleting_file", sheetWindow: self.tableView.window)
          Logger.log("Failed to remove file: \"\(filePath)'\": \(error)")
          return false
        }
      } else {
        // - show file. cancel delete
        Logger.log("User chose to show file in Finder: \"\(filePath)'\"", level: .verbose)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: filePath)])
        return false
      }
    }
    return true
  }

  private func requireFilePath(forConfig configName: String) -> String? {
    if let confFilePath = self.tableStore.getFilePath(forConfig: configName) {
      return confFilePath
    }

    Utility.showAlert("error_finding_file", arguments: ["config"], sheetWindow: tableView.window)
    return nil
  }
}
