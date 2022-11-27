//
//  ConfTableStateManager.swift
//  iina
//
//  Created by Matt Svoboda on 11/16/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

fileprivate let changeSelectedConfActionName: String = "Change Active Config"

/*
 Responsible for changing the state of the Key Bindings table by building new versions of `BindingTableState`.
 */
class ConfTableStateManager: NSObject {
  private var undoHelper = PrefsWindowUndoHelper()
  private var observers: [NSObjectProtocol] = []
  
  private var fileCache: InputConfFileCache {
    InputConfFile.cache
  }

  override init() {
    super.init()
    Logger.log("ConfTableStateManager init", level: .verbose)

    // This will notify that a pref has changed, even if it was changed by another instance of IINA:
    for key in [Preference.Key.currentInputConfigName, Preference.Key.inputConfigs] {
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }

    let currentState = ConfTableState.current
    for (confName, filePath) in AppData.defaultConfs {
      fileCache.loadConfFile(at: filePath, isReadOnly: true, confName: confName)
    }
    for (confName, filePath) in currentState.userConfDict {
      fileCache.loadConfFile(at: filePath, isReadOnly: false, confName: confName)
    }
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []

    // Remove observers for IINA preferences.
    ObjcUtils.silenced {
      for key in [Preference.Key.currentInputConfigName, Preference.Key.inputConfigs] {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }
    }
  }

  static func initialState() -> ConfTableState {
    let selectedConfName: String
    if let selectedConf = Preference.string(for: .currentInputConfigName) {
      selectedConfName = selectedConf
    } else {
      Logger.log("Could not get pref: \(Preference.Key.currentInputConfigName.rawValue): will use default (\"\(defaultConfName)\")", level: .warning)
      selectedConfName = defaultConfName
    }

    let userConfDict: [String: String]
    if let prefDict = Preference.dictionary(for: .inputConfigs), let userConfigStringDict = prefDict as? [String: String] {
      userConfDict = userConfigStringDict
    } else {
      Logger.log("Could not get pref: \(Preference.Key.inputConfigs.rawValue): will use default empty dictionary", level: .warning)
      userConfDict = [:]
    }

    return ConfTableState(userConfDict: userConfDict, selectedConfName: selectedConfName, specialState: .none)
  }

  static var defaultConfName: String {
    AppData.defaultConfNamesSorted[0]
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let change = change else { return }

    DispatchQueue.main.async {  // had some issues with race conditions
      let curr = ConfTableState.current
      switch keyPath {

        case Preference.Key.currentInputConfigName.rawValue:
          guard let selectedConfNameNew = change[.newKey] as? String, !selectedConfNameNew.equalsIgnoreCase(curr.selectedConfName) else { return }
          guard curr.specialState != .fallBackToDefaultConf else {
            // Avoids infinite loop if two or more instances are running at the same time
            Logger.log("Already in error state; ignoring pref update for selectedConf: \"\(selectedConfNameNew)\"", level: .verbose)
            return
          }
          Logger.log("Detected pref update for selectedConf: \"\(selectedConfNameNew)\"", level: .verbose)
          ConfTableState.current.changeSelectedConf(selectedConfNameNew)  // updates UI in case the update came from an external source
        case Preference.Key.inputConfigs.rawValue:
          guard let userConfDictNew = change[.newKey] as? [String: String] else { return }
          if !userConfDictNew.keys.sorted().elementsEqual(curr.userConfDict.keys.sorted()) {
            Logger.log("Detected pref update for inputConfigs", level: .verbose)
            self.changeState(userConfDictNew, selectedConfName: curr.selectedConfName)
          }
        default:
          return
      }
    }
  }

  // MARK: Do, Undo, Redo

  // This one is a little different, but it doesn't fit anywhere else. Appends bindings to a file in the table which is not the
  // current selection. Also handles the undo of the append. Does not alter anything visible in the UI.
  func appendBindingsToUserConfFile(_ mappingsToAppend: [KeyMapping], targetConfName: String, isUndo: Bool = false) {
    guard targetConfName != ConfTableState.current.selectedConfName else {
      // Should use BindingTableState instead
      Logger.log("appendBindingsToUserConfFile() should not be called for appending to the currently selected conf (\(targetConfName))!", level: .verbose)
      return
    }

    guard let inputConfFile = fileCache.getConfFile(confName: targetConfName), !inputConfFile.failedToLoad else {
      return  // error already logged. Just return.
    }
    var fileMappings = inputConfFile.parseMappings()

    if isUndo {
      Logger.log("Undoing append of \(mappingsToAppend.count) bindings (from current count: \(fileMappings.count)) of conf: \"\(targetConfName)\"")

      for mappingToRemove in mappingsToAppend.reversed() {
        guard let mappingFound = fileMappings.popLast(), mappingToRemove == mappingFound else {
          Logger.log("Undo failed: binding in file is missing or does not match expected (\(mappingToRemove.confFileFormat))", level: .error)
          let alertInfo = Utility.AlertInfo(key: "config.cannot_write", args: [inputConfFile.filePath])
          NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
          return
        }
      }
    } else {
      Logger.log("Appending \(mappingsToAppend.count) bindings to existing \(fileMappings.count) of conf: \"\(targetConfName)\"")
      fileMappings.append(contentsOf: mappingsToAppend)
    }

    inputConfFile.overwriteFile(with: fileMappings)

    undoHelper.registerUndo(actionName: Utility.format(.keyBinding, mappingsToAppend.count, .copyToFile), {
      self.appendBindingsToUserConfFile(mappingsToAppend, targetConfName: targetConfName, isUndo: !isUndo)
    })
  }

  fileprivate struct UndoData {
    var userConfDict: [String:String]?
    var selectedConfName: String?
    var filesRemovedByLastAction: [String:InputConfFile]?
  }

  func changeState(_ userConfDict: [String:String]? = nil, selectedConfName: String? = nil,
                   specialState: ConfTableState.SpecialState = .none,
                   completionHandler: TableUIChange.CompletionHandler? = nil) {

    let selectedConfOverride = specialState == .fallBackToDefaultConf ? ConfTableStateManager.defaultConfName : selectedConfName
    let undoData = UndoData(userConfDict: userConfDict, selectedConfName: selectedConfOverride)

    self.doAction(undoData, specialState: specialState, completionHandler: completionHandler)
  }

  // May be called for do, undo, or redo of an action which changes the table contents or selection
  private func doAction(_ newData: UndoData, specialState: ConfTableState.SpecialState = .none,
                        completionHandler: TableUIChange.CompletionHandler? = nil) {

    let tableStateOld = ConfTableState.current
    var oldData = UndoData(userConfDict: tableStateOld.userConfDict, selectedConfName: tableStateOld.selectedConfName)

    // Action label for Undo (or Redo) menu item, if applicable
    var actionName: String? = nil
    var hasConfListChange = false
    if let userConfDictNew = newData.userConfDict {
      // Figure out which of the 3 basic types of file operations was done by doing a basic diff.
      // This is a lot easier because Move is only allowed on 1 file at a time.
      let newUserConfs = Set(userConfDictNew.keys)
      let oldUserConfs = Set(tableStateOld.userConfDict.keys)

      let addedConfs = newUserConfs.subtracting(oldUserConfs)
      let removedConfs = oldUserConfs.subtracting(newUserConfs)

      if !addedConfs.isEmpty || !removedConfs.isEmpty {
        hasConfListChange = true
      }

      // Apply conf file disk operations before updating the stored prefs or the UI.
      // Almost all operations on conf files are performed here. It can handle anything needed by "undo"
      // and "redo". For the initial "do", it will handle the file operations for "rename" and "remove",
      // but for "add" types (create/import/duplicate), it's expected that the caller already successfully
      // created the new file(s) before getting here.
      if let oldConfName = removedConfs.first, let newConfName = addedConfs.first {
        actionName = "Rename Config"
        if addedConfs.count != 1 || removedConfs.count != 1 {
          // This shouldn't be possible. Make sure we catch it if it is
          Logger.fatal("Can't rename more than 1 InputConfig file at a time! (Added: \(addedConfs); Removed: \(removedConfs))")
        }
        fileCache.renameConfFile(oldConfName: oldConfName, newConfName: newConfName)

      } else if !removedConfs.isEmpty {
        // File(s) removedConfs (This can be more than one if we're undoing a multi-file import)
        actionName = Utility.format(.config, removedConfs.count, .delete)
        oldData.filesRemovedByLastAction = fileCache.removeConfFiles(confNamesToRemove: removedConfs)

      } else if !addedConfs.isEmpty {
        // Files(s) duplicated, created, or imported.
        // Too many different cases and fancy logic: let the UI controller handle the file stuff...
        actionName = Utility.format(.config, addedConfs.count, .add)
        if let filesRemovedByLastAction = newData.filesRemovedByLastAction {
          // ...UNLESS we are in an undo (if `removedConfsFilesForUndo` != nil): then this class must restore deleted files
          fileCache.restoreRemovedConfFiles(addedConfs, filesRemovedByLastAction)
        } else {  // Must be in an initial "do"
          for addedConfName in addedConfs {
            // Assume files were created elsewhere. Just need to load them into memory cache:
            let confFile = loadConfFile(withConfName: addedConfName)
            guard !confFile.failedToLoad else {
              self.sendErrorAlert(key: "error_finding_file", args: ["config"])
              return
            }
          }
        }
      }
    }

    let tableStateNew = ConfTableState(userConfDict: newData.userConfDict ?? tableStateOld.userConfDict,
                                       selectedConfName: newData.selectedConfName ?? tableStateOld.selectedConfName,
                                       specialState: specialState)

    Logger.log("Setting new ConfTableState. (specialState: \(specialState))", level: .verbose)
    ConfTableState.current = tableStateNew

    // Update userConfDict pref if changed
    if hasConfListChange {
      Logger.log("Saving pref: inputConfigs=\(tableStateNew.userConfDict)", level: .verbose)
      Preference.set(tableStateNew.userConfDict, for: .inputConfigs)
    }

    // Update selectedConfName and load new file if changed
    let hasSelectionChange = !tableStateOld.selectedConfName.equalsIgnoreCase(tableStateNew.selectedConfName)
    if hasSelectionChange {
      Logger.log("Saving pref 'currentInputConfigName': '\(tableStateOld.selectedConfName)' -> '\(tableStateNew.selectedConfName)'", level: .verbose)
      Preference.set(tableStateNew.selectedConfName, for: .currentInputConfigName)
      loadBindingsFromSelectedConfFile()
    }

    let hasUndoableChange: Bool = hasSelectionChange || hasConfListChange
    if hasUndoableChange {
      undoHelper.registerUndo(actionName: actionName ?? changeSelectedConfActionName, {
        // Get rid of empty editor before it gets in the way:
        if ConfTableState.current.isAddingNewConfInline {
          ConfTableState.current.cancelInlineAdd()
        }

        self.doAction(oldData)
      })
    }

    updateTableUI(old: tableStateOld, new: tableStateNew, completionHandler: completionHandler)
  }

  private func updateTableUI(old: ConfTableState, new: ConfTableState, completionHandler: TableUIChange.CompletionHandler?) {

    let tableUIChange = TableUIChangeBuilder.buildDiff(oldRows: old.confTableRows, newRows: new.confTableRows,
                                                       completionHandler: completionHandler)
    tableUIChange.scrollToFirstSelectedRow = true

    switch new.specialState {
      case .addingNewInline:  // special case: creating an all-new config
        // Select the new blank row, which will be the last one:
        tableUIChange.newSelectedRowIndexes = IndexSet(integer: new.confTableRows.count - 1)
      case .none, .fallBackToDefaultConf:
        // Always keep the current config selected
        if let selectedConfIndex = new.confTableRows.firstIndex(of: new.selectedConfName) {
          tableUIChange.newSelectedRowIndexes = IndexSet(integer: selectedConfIndex)
        }
    }

    // Finally, fire notification. This covers row selection too
    let notification = Notification(name: .iinaPendingUIChangeForConfTable, object: tableUIChange)
    Logger.log("ConfTableStateManager: posting \"\(notification.name.rawValue)\" notification", level: .verbose)
    NotificationCenter.default.post(notification)
  }

  // Utility function: show error popup to user
  private func sendErrorAlert(key alertKey: String, args: [String]) {
    let alertInfo = Utility.AlertInfo(key: alertKey, args: args)
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
  }

  // MARK: Conf File Disk Operations

  // If `confName` not provided, defaults to currently selected conf.
  // Uses cached copy first, then reads from disk if not found (more reliable results this way)
  // Will report error to user & log if not found, but still need to check whether `inputConfFile.failedToLoad`.
  private func loadConfFile(withConfName confName: String? = nil) -> InputConfFile {
    let currentState = ConfTableState.current
    let targetConfName = confName ?? currentState.selectedConfName
    Logger.log("Loading inputConfFile for \"\(targetConfName)\"")

    let isReadOnly = currentState.isDefaultConf(targetConfName)
    let confFilePath = currentState.getFilePath(forConfName: targetConfName)

    return fileCache.getOrLoadConfFile(at: confFilePath, isReadOnly: isReadOnly, confName: targetConfName)
  }

  // Conf File load. Triggered any time `selectedConfName` is changed
  func loadBindingsFromSelectedConfFile() {
    let inputConfFile = loadConfFile()
    guard !inputConfFile.failedToLoad else { return }
    var userData: [BindingTableStateManager.Key: Any] = [BindingTableStateManager.Key.confFile: inputConfFile]

    // Key Bindings table will reload after it receives new data from AppInputConfig.
    // It will default to an animated transition based on calculated diff.
    // To disable animation, specify type .reloadAll explicitly.
    if !Preference.bool(for: .animateKeyBindingTableReloadAll) {
      userData[BindingTableStateManager.Key.tableUIChange] = TableUIChange(.reloadAll)
    }

    // Send down the pipeline
    let userConfMappingsNew = inputConfFile.parseMappings()
    AppInputConfig.replaceUserConfSectionMappings(with: userConfMappingsNew, attaching: userData)
  }
}
