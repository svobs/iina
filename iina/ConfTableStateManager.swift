//
//  ConfTableStateManager.swift
//  iina
//
//  Created by Matt Svoboda on 11/16/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

fileprivate let changeSelectedConfigActionName: String = "Change Active Config"

/*
 Responsible for changing the state of the Key Bindings table by building new versions of `BindingTableState`.
 */
class ConfTableStateManager: NSObject {

  // Loading all the conf files into memory shouldn't take too much time or space, and it will help avoid
  // a bunch of tricky failure points for undo/redo.
  private var confFileMemoryCache: [String: InputConfFile] = [:]

  private var observers: [NSObjectProtocol] = []

  override init() {
    super.init()
    Logger.log("ConfTableStateManager init", level: .verbose)

    // This will notify that a pref has changed, even if it was changed by another instance of IINA:
    for key in [Preference.Key.currentInputConfigName, Preference.Key.inputConfigs] {
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }

    for (confName, filePath) in AppData.defaultConfs {
      confFileMemoryCache[confName] =  InputConfFile.loadFile(at: filePath, isReadOnly: true)
    }
    for (confName, filePath) in ConfTableState.current.userConfDict {
      confFileMemoryCache[confName] =  InputConfFile.loadFile(at: filePath, isReadOnly: false)
    }
    assert(ConfTableState.current.confTableRows.count == confFileMemoryCache.count)
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
      let defaultConfig = AppData.defaultConfNamesSorted[0]
      Logger.log("Could not get pref: \(Preference.Key.currentInputConfigName.rawValue): will use default (\"\(defaultConfig)\")", level: .warning)
      selectedConfName = defaultConfig
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

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let change = change else { return }

    DispatchQueue.main.async {  // had some issues with race conditions
      let curr = ConfTableState.current
      switch keyPath {

        case Preference.Key.currentInputConfigName.rawValue:
          guard let selectedConfNameNew = change[.newKey] as? String, !selectedConfNameNew.equalsIgnoreCase(curr.selectedConfName) else { return }
          Logger.log("Detected pref update for selectedConf: \"\(selectedConfNameNew)\"", level: .verbose)
          ConfTableState.current.changeSelectedConf(selectedConfNameNew)  // updates UI in case the update came from an external source
        case Preference.Key.inputConfigs.rawValue:
          guard let userConfDictNew = change[.newKey] as? [String: String] else { return }
          if !userConfDictNew.keys.sorted().elementsEqual(curr.userConfDict.keys.sorted()) {
            Logger.log("Detected pref update for inputConfigs", level: .verbose)
            self.doAction(userConfDictNew, selectedConfNameNew: curr.selectedConfName)
          }
        default:
          return
      }
    }
  }

  // MARK: Do, Undo, Redo

  // This one is a little different, but it doesn't fit anywhere else. Appends bindings to a file in the table which is not the
  // current selection. Also handles the undo of the append. Does not alter anything visible in the UI.
  func appendBindingsToUserConfFile(_ bindingsToAppend: [KeyMapping], targetConfName: String, undo: Bool = false) {
    guard targetConfName != ConfTableState.current.selectedConfName else {
      // Should use BindingTableState instead
      Logger.log("appendBindingsToUserConfFile() should not be called for appending to the currently selected conf (\(targetConfName))!", level: .verbose)
      return
    }
    let inputConfFile = loadConfFile(targetConfName)
    guard !inputConfFile.failedToLoad else {
      return  // error already logged. Just return.
    }
    var fileMappings = inputConfFile.parseMappings()

    if undo {
      Logger.log("Undoing append of \(bindingsToAppend.count) bindings (from current count: \(fileMappings.count)) of conf: \"\(targetConfName)\"")

      for mappingToRemove in bindingsToAppend.reversed() {
        guard let mappingFound = fileMappings.popLast(), mappingToRemove == mappingFound else {
          Logger.log("Undo failed: binding in file is missing or does not match expected (\(mappingToRemove.confFileFormat))", level: .error)
          let alertInfo = Utility.AlertInfo(key: "config.cannot_write", args: [inputConfFile.filePath])
          NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
          return
        }
      }
    } else {
      Logger.log("Appending \(bindingsToAppend.count) bindings to existing \(fileMappings.count) of conf: \"\(targetConfName)\"")
      fileMappings.append(contentsOf: bindingsToAppend)
    }

    do {
      let updatedFile = try inputConfFile.overwriteFile(with: fileMappings)
      Logger.log("Updating memory cache entry for \"\(targetConfName)\"", level: .verbose)
      confFileMemoryCache[targetConfName] = updatedFile
    } catch {
      Logger.log("Failed to save bindings updates to file: \(error)", level: .error)
      let alertInfo = Utility.AlertInfo(key: "config.cannot_write", args: [inputConfFile.filePath])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
    }

    if let undoManager = PreferenceWindowController.undoManager {
      let undoActionName = Utility.format(.keyBinding, bindingsToAppend.count, .copyToFile)
      Logger.log("Registering for undo: \"\(undoActionName)\"", level: .verbose)

      undoManager.registerUndo(withTarget: self, handler: { manager in
        Logger.log(self.format(action: undoActionName, undoManager), level: .verbose)
        manager.appendBindingsToUserConfFile(bindingsToAppend, targetConfName: targetConfName, undo: !undo)
      })

      // Action name only needs to be set once per action, and it will displayed for both "Undo {}" and "Redo {}".
      // There's no need to change the name of it for the redo.
      if !undoManager.isUndoing && !undoManager.isRedoing {
        undoManager.setActionName(undoActionName)
      }
    } else {
      Logger.log("Cannot register undo for append: ConfTableState.undoManager is nil", level: .verbose)
    }
  }

  private func format(action undoActionName: String, _ undoManager: UndoManager) -> String {
    "\(undoManager.isUndoing ? "Undoing" : (undoManager.isRedoing ? "Redoing" : "Doing")) action \"\(undoActionName)\""
  }

  fileprivate struct UndoData {
    var userConfDict: [String:String]?
    var selectedConfName: String?
    var filesRemovedByLastAction: [String:InputConfFile]?
  }

  func doAction(_ userConfDictNew: [String:String]? = nil, selectedConfNameNew: String? = nil,
                enterSpecialState specialState: ConfTableState.SpecialState = .none,
                completionHandler: TableChange.CompletionHandler? = nil) {

    let doData = UndoData(userConfDict: userConfDictNew, selectedConfName: selectedConfNameNew)
    self.doAction(doData, enterSpecialState: specialState, completionHandler: completionHandler)
  }

  // May be called for do, undo, or redo of an action which changes the table contents or selection
  private func doAction(_ newData: UndoData, enterSpecialState specialState: ConfTableState.SpecialState = .none,
                        completionHandler: TableChange.CompletionHandler? = nil) {

    let currentState = ConfTableState.current
    var oldData = UndoData(userConfDict: currentState.userConfDict,
                                  selectedConfName: currentState.selectedConfName)

    // Figure out which entries in the list changed, and update the files on disk to match.
    // If something changed, we'll get back an action label for Undo (or Redo) menu item
    var actionName: String?
    do {
      // Apply file operations before we update the stored prefs or the UI.
      actionName = try self.updateFilesOnDisk(from: &oldData, to: newData)
    } catch {
      // Already logged whatever went wrong. Just cancel
      return
    }

    var selectedConfChanged = false
    if let oldSelectionName = oldData.selectedConfName, let newSelectionName = newData.selectedConfName,
       !oldSelectionName.equalsIgnoreCase(newSelectionName) {
      selectedConfChanged = true
    }

    let foundUndoableChange: Bool = actionName != nil || selectedConfChanged
    Logger.log("SelectedConfChanged: \(selectedConfChanged); requestedNewState: \(specialState)",
               level: .verbose)

    if foundUndoableChange {
      if let undoManager = PreferenceWindowController.undoManager {
        let undoActionName = actionName ?? changeSelectedConfigActionName

        Logger.log("Registering for undo: \"\(undoActionName)\"", level: .verbose)
        undoManager.registerUndo(withTarget: self, handler: { manager in
          Logger.log(self.format(action: undoActionName, undoManager), level: .verbose)

          // Get rid of empty editor before it gets in the way:
          if ConfTableState.current.isAddingNewConfInline {
            ConfTableState.current.cancelInlineAdd()
          }

          manager.doAction(oldData)
        })

        // Action name only needs to be set once per action, and it will displayed for both "Undo {}" and "Redo {}".
        // There's no need to change the name of it for the redo.
        if !undoManager.isUndoing && !undoManager.isRedoing {
          undoManager.setActionName(undoActionName)
        }

      } else {
        Logger.log("Cannot register for undo: ConfTableState.undoManager is nil", level: .verbose)
      }
    }

    let newState = ConfTableState(userConfDict: newData.userConfDict ?? currentState.userConfDict,
                                  selectedConfName: newData.selectedConfName ?? currentState.selectedConfName,
                                  specialState: specialState)
    let oldState = ConfTableState.current
    ConfTableState.current = newState

    if let userConfDictNew = newData.userConfDict {
      Logger.log("Saving pref: inputConfigs=\(userConfDictNew)", level: .verbose)
      // Update userConfDict
      Preference.set(userConfDictNew, for: .inputConfigs)
    }

    // Update selectedConfName and load new file if changed
    if selectedConfChanged {
      Logger.log("Conf selection changed: '\(oldState.selectedConfName)' -> '\(newState.selectedConfName)'")
      Preference.set(newState.selectedConfName, for: .currentInputConfigName)
      loadBindingsFromSelectedConfFile()
    }

    let tableChange = buildConfTableChange(old: oldState, new: newState, completionHandler: completionHandler)
    // Finally, fire notification. This covers row selection too
    let notification = Notification(name: .iinaConfTableShouldChange, object: tableChange)
    Logger.log("ConfTableStateManager: posting \(notification.name.rawValue) notification", level: .verbose)
    NotificationCenter.default.post(notification)
  }

  private func buildConfTableChange(old: ConfTableState, new: ConfTableState,
                                    completionHandler: TableChange.CompletionHandler?) -> TableChange {

    let confTableChange = TableChange.buildDiff(oldRows: old.confTableRows, newRows: new.confTableRows,
                                                completionHandler: completionHandler)
    confTableChange.scrollToFirstSelectedRow = true

    switch new.specialState {
      case .addingNewInline:  // special case: creating an all-new config
        // Select the new blank row, which will be the last one:
        confTableChange.newSelectedRows = IndexSet(integer: new.confTableRows.count - 1)
      case .none:
        // Always keep the current config selected
        if let selectedConfIndex = new.confTableRows.firstIndex(of: new.selectedConfName) {
          confTableChange.newSelectedRows = IndexSet(integer: selectedConfIndex)
        }
    }

    return confTableChange
  }

  // Utility function: show error popup to user
  private func sendErrorAlert(key alertKey: String, args: [String]) {
    let alertInfo = Utility.AlertInfo(key: alertKey, args: args)
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
  }

  // MARK: Conf File Disk Operations

  // Almost all operations on conf files are performed here. It can handle anything needed by "undo"
  // and "redo". For the initial "do", it will handle the file operations for "rename" and "remove",
  // but for "add" types (create/import/duplicate), it's expected that the caller already successfully
  // created the new file(s) before getting here.
  // Returns true if it found a change in the data; false if not
  private func updateFilesOnDisk(from oldData: inout UndoData, to newData: UndoData) throws -> String? {
    guard let userConfDictNew = newData.userConfDict else {
      return nil
    }

    var actionName: String? = nil

    // Figure out which of the 3 basic types of file operations was done by doing a basic diff.
    // This is a lot easier because Move is only allowed on 1 file at a time.
    let newUserConfs = Set(userConfDictNew.keys)
    let oldUserConfs = Set(oldData.userConfDict!.keys)

    let addedConfs = newUserConfs.subtracting(oldUserConfs)
    let removedConfs = oldUserConfs.subtracting(newUserConfs)

    if let oldConfName = removedConfs.first, let newConfName = addedConfs.first {
      actionName = "Rename Config"
      if addedConfs.count != 1 || removedConfs.count != 1 {
        // This shouldn't be possible. Make sure we catch it if it is
        Logger.fatal("Can't rename more than 1 InputConfig file at a time! (Added: \(addedConfs); Removed: \(removedConfs))")
      }
      try renameFile(oldConfName: oldConfName, newConfName: newConfName)

    } else if removedConfs.count > 0 {
      // File(s) removedConfs (This can be more than one if we're undoing a multi-file import)
      actionName = Utility.format(.config, removedConfs.count, .delete)
      oldData.filesRemovedByLastAction = try removeFiles(confNamesToRemove: removedConfs)

    } else if addedConfs.count > 0 {
      // Files(s) duplicated, created, or imported.
      // Too many different cases and fancy logic: let the UI controller handle the file stuff...
      actionName = Utility.format(.config, addedConfs.count, .add)
      // ...UNLESS we are in an undo (if `removedConfsFilesForUndo` != nil): then this class must restore deleted files
      if let filesRemovedByLastAction = newData.filesRemovedByLastAction {
        restoreRemovedFiles(addedConfs, filesRemovedByLastAction)
      }
    }
    return actionName
  }

  private func renameFile(oldConfName: String, newConfName: String) throws {

    let oldFilePath = Utility.buildConfFilePath(for: oldConfName)
    let newFilePath = Utility.buildConfFilePath(for: newConfName)

    let oldExists = FileManager.default.fileExists(atPath: oldFilePath)
    let newExists = FileManager.default.fileExists(atPath: newFilePath)

    if !oldExists && newExists {
      Logger.log("Looks like file has already moved: \"\(oldFilePath)\"")
    } else {
      if !oldExists {
        Logger.log("Can't rename config: could not find file: \"\(oldFilePath)\"", level: .error)
        self.sendErrorAlert(key: "error_finding_file", args: ["config"])
        throw IINAError.confFileError
      } else if newExists {
        Logger.log("Can't rename config: a file already exists at the destination: \"\(newFilePath)\"", level: .error)
        // TODO: more appropriate message
        self.sendErrorAlert(key: "config.cannot_create", args: ["config"])
        throw IINAError.confFileError
      }

      // - Move file on disk
      do {
        Logger.log("Attempting to move InputConf file \"\(oldFilePath)\" to \"\(newFilePath)\"")
        try FileManager.default.moveItem(atPath: oldFilePath, toPath: newFilePath)
      } catch let error {
        Logger.log("Failed to rename file: \(error)", level: .error)
        // TODO: more appropriate message
        self.sendErrorAlert(key: "config.cannot_create", args: ["config"])
        throw IINAError.confFileError
      }
    }

    if let inputConfFile = confFileMemoryCache.removeValue(forKey: oldConfName) {
      Logger.log("Updating memory cache: moving \"\(oldConfName)\" -> \"\(newConfName)\"", level: .verbose)
      confFileMemoryCache[newConfName] = inputConfFile
    }
  }

  // Performs removal of files on disk. Throws exception to indicate failure; otherwise success is assumed even if empty dict returned.
  // Returns a copy of each removed files' contents which must be stored for later undo
  private func removeFiles(confNamesToRemove: Set<String>) throws -> [String:InputConfFile] {

    // Cache each file's contents in memory before removing it, for potential later use by undo
    var removedFileDict: [String:InputConfFile] = [:]

    for confName in confNamesToRemove {
      let inputConfFile = loadConfFile(confName)
      let filePath = inputConfFile.filePath
      guard !inputConfFile.failedToLoad else {
        Logger.log("Failed to read file before removal (this should not happen: \"\(filePath)\"", level: .error)
        self.sendErrorAlert(key: "keybinding_config.error", args: [filePath])
        throw IINAError.confFileError
      }

      removedFileDict[confName] = inputConfFile

      do {
        try FileManager.default.removeItem(atPath: filePath)
      } catch {
        if FileManager.default.fileExists(atPath: filePath) {
          Logger.log("File exists but cannot be deleted; cannot continue", level: .error)
          let fileName = URL(fileURLWithPath: filePath).lastPathComponent
          let alertInfo = Utility.AlertInfo(key: "error_deleting_file", args: [fileName])
          NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
          throw IINAError.confFileError
        } else {
          Logger.log("Looks like file was already removed: \"\(filePath)\"")
        }
      }

      Logger.log("Removing from cache: \"\(confName)\"", level: .verbose)
      confFileMemoryCache.removeValue(forKey: confName)
    }

    return removedFileDict
  }

  private func restoreRemovedFiles(_ confNames: Set<String>, _ filesRemovedByLastAction: [String:InputConfFile]) {
    for (confName, inputConfFile) in filesRemovedByLastAction {
      confFileMemoryCache[confName] = inputConfFile
    }

    for confName in confNames {
      guard let inputConfFile = filesRemovedByLastAction[confName] else {
        // Should never happen
        Logger.log("Cannot restore deleted file: file content is missing! (config name: \(confName)", level: .error)
        self.sendErrorAlert(key: "config.cannot_create", args: [Utility.buildConfFilePath(for: confName)])
        continue
      }
      let filePath = inputConfFile.filePath
      do {
        if FileManager.default.fileExists(atPath: filePath) {
          Logger.log("Cannot restore deleted file: file aleady exists: \(filePath)", level: .error)
          // TODO: more appropriate message
          self.sendErrorAlert(key: "config.cannot_create", args: [filePath])
          continue
        }
        try inputConfFile.saveFile()
      } catch {
        Logger.log("Failed to restore deleted file \"\(filePath)\": \(error)", level: .error)
        self.sendErrorAlert(key: "config.cannot_create", args: [filePath])
        continue
      }

      Logger.log("Restoring file to cache: \(confName)", level: .verbose)
      confFileMemoryCache[confName] = inputConfFile
    }
  }

  // If `confName` not provided, defaults to currently selected conf. Displays error if not found,
  // but still need to check whether `inputConfFile.failedToLoad`.
  // If file not found on disk, uses last cached copy.
  private func loadConfFile(_ confName: String? = nil) -> InputConfFile {
    let currentState = ConfTableState.current
    let targetConfName = confName ?? currentState.selectedConfName
    Logger.log("Loading inputConfFile for \"\(targetConfName)\"")

    let isReadOnly = currentState.isDefaultConf(targetConfName)
    let confFilePath = currentState.getFilePath(forConfName: targetConfName)

    let inputConfFile = InputConfFile.loadFile(at: confFilePath, isReadOnly: isReadOnly)
    guard !inputConfFile.failedToLoad else {
      if let cachedInputFile = confFileMemoryCache[targetConfName], !cachedInputFile.failedToLoad {
        Logger.log("Returning inputConfFile from memory cache", level: .verbose)
        return cachedInputFile
      }
      let alertInfo = Utility.AlertInfo(key: "keybinding_config.error", args: [confFilePath])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
      return inputConfFile
    }

    Logger.log("Updating memory cache entry for \"\(targetConfName)\"", level: .verbose)
    confFileMemoryCache[targetConfName] = inputConfFile

    return inputConfFile
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
      userData[BindingTableStateManager.Key.tableChange] = TableChange(.reloadAll)
    }

    // Send down the pipeline
    let userConfMappingsNew = inputConfFile.parseMappings()
    AppInputConfig.replaceDefaultSectionMappings(with: userConfMappingsNew, attaching: userData)
  }
}
