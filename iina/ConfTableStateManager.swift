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
            self.update(userConfDictNew, selectedConfName: curr.selectedConfName)
          }
        default:
          return
      }
    }
  }

  // MARK: Do, Undo, Redo

  // This one is a little different, but it doesn't fit anywhere else. Appends bindings to a file in the table which is not the
  // current selection. Also handles the undo of the append. Does not alter anything visible in the UI.
  func appendBindingsToUserConfFile(_ mappingsToAppend: [KeyMapping], targetConfName: String, undo: Bool = false) {
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
      let undoActionName = Utility.format(.keyBinding, mappingsToAppend.count, .copyToFile)
      Logger.log("Registering for undo: \"\(undoActionName)\"", level: .verbose)

      undoManager.registerUndo(withTarget: self, handler: { manager in
        Logger.log(self.format(action: undoActionName, undoManager), level: .verbose)
        manager.appendBindingsToUserConfFile(mappingsToAppend, targetConfName: targetConfName, undo: !undo)
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

  func update(_ userConfDict: [String:String]? = nil, selectedConfName: String? = nil,
              specialState: ConfTableState.SpecialState = .none,
              completionHandler: TableChange.CompletionHandler? = nil) {

    let selectedConfOverride = specialState == .fallBackToDefaultConf ? ConfTableStateManager.defaultConfName : selectedConfName
    let doData = UndoData(userConfDict: userConfDict, selectedConfName: selectedConfOverride)

    self.doAction(doData, specialState: specialState, completionHandler: completionHandler)
  }

  // May be called for do, undo, or redo of an action which changes the table contents or selection
  private func doAction(_ newData: UndoData, specialState: ConfTableState.SpecialState = .none,
                        completionHandler: TableChange.CompletionHandler? = nil) {

    let oldState = ConfTableState.current
    var oldData = UndoData(userConfDict: oldState.userConfDict, selectedConfName: oldState.selectedConfName)

    // Action label for Undo (or Redo) menu item, if applicable
    var actionName: String? = nil
    var hasConfListChange = false
    if let userConfDictNew = newData.userConfDict {
      // Figure out which of the 3 basic types of file operations was done by doing a basic diff.
      // This is a lot easier because Move is only allowed on 1 file at a time.
      let newUserConfs = Set(userConfDictNew.keys)
      let oldUserConfs = Set(oldState.userConfDict.keys)

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
        renameConfFile(oldConfName: oldConfName, newConfName: newConfName)

      } else if !removedConfs.isEmpty {
        // File(s) removedConfs (This can be more than one if we're undoing a multi-file import)
        actionName = Utility.format(.config, removedConfs.count, .delete)
        oldData.filesRemovedByLastAction = removeConfFiles(confNamesToRemove: removedConfs)

      } else if !addedConfs.isEmpty {
        // Files(s) duplicated, created, or imported.
        // Too many different cases and fancy logic: let the UI controller handle the file stuff...
        actionName = Utility.format(.config, addedConfs.count, .add)
        if let filesRemovedByLastAction = newData.filesRemovedByLastAction {
          // ...UNLESS we are in an undo (if `removedConfsFilesForUndo` != nil): then this class must restore deleted files
          restoreRemovedConfFiles(addedConfs, filesRemovedByLastAction)
        } else {  // Must be in an initial "do"
          for addedConfName in addedConfs {
            // Assume files were created elsewhere. Just need to load them into memory cache:
            let confFile = loadConfFile(addedConfName)
            guard !confFile.failedToLoad else {
              self.sendErrorAlert(key: "error_finding_file", args: ["config"])
              return
            }
          }
        }
      }
    }

    let hasSelectionChange = !oldState.selectedConfName.equalsIgnoreCase(newData.selectedConfName ?? oldState.selectedConfName)
    let hasUndoableChange: Bool = hasSelectionChange || hasConfListChange
    Logger.log("HasUndoableChange: \(hasUndoableChange), HasSelectionChange: \(hasSelectionChange), SpecialState: \(specialState)", level: .verbose)

    if hasUndoableChange {
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

    let newState = ConfTableState(userConfDict: newData.userConfDict ?? oldState.userConfDict,
                                  selectedConfName: newData.selectedConfName ?? oldState.selectedConfName,
                                  specialState: specialState)
    ConfTableState.current = newState

    if hasConfListChange {
        Logger.log("Saving pref: inputConfigs=\(newState.userConfDict)", level: .verbose)
      // Update userConfDict
        Preference.set(newState.userConfDict, for: .inputConfigs)
    }

    // Update selectedConfName and load new file if changed
    if hasSelectionChange {
      Logger.log("Saving pref 'currentInputConfigName': '\(oldState.selectedConfName)' -> '\(newState.selectedConfName)'", level: .verbose)
      Preference.set(newState.selectedConfName, for: .currentInputConfigName)
      loadBindingsFromSelectedConfFile()
    }

    updateTableUI(old: oldState, new: newState, completionHandler: completionHandler)
  }

  private func updateTableUI(old: ConfTableState, new: ConfTableState, completionHandler: TableChange.CompletionHandler?) {

    let tableChange = TableChange.buildDiff(oldRows: old.confTableRows, newRows: new.confTableRows,
                                                completionHandler: completionHandler)
    tableChange.scrollToFirstSelectedRow = true

    switch new.specialState {
      case .addingNewInline:  // special case: creating an all-new config
        // Select the new blank row, which will be the last one:
        tableChange.newSelectedRows = IndexSet(integer: new.confTableRows.count - 1)
      case .none, .fallBackToDefaultConf:
        // Always keep the current config selected
        if let selectedConfIndex = new.confTableRows.firstIndex(of: new.selectedConfName) {
          tableChange.newSelectedRows = IndexSet(integer: selectedConfIndex)
        }
    }

    // Finally, fire notification. This covers row selection too
    let notification = Notification(name: .iinaConfTableShouldChange, object: tableChange)
    Logger.log("ConfTableStateManager: posting \"\(notification.name.rawValue)\" notification", level: .verbose)
    NotificationCenter.default.post(notification)
  }

  // Utility function: show error popup to user
  private func sendErrorAlert(key alertKey: String, args: [String]) {
    let alertInfo = Utility.AlertInfo(key: alertKey, args: args)
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
  }

  // MARK: Conf File Disk Operations

  private func renameConfFile(oldConfName: String, newConfName: String) {
    Logger.log("Updating memory cache: moving \"\(oldConfName)\" -> \"\(newConfName)\"", level: .verbose)
    guard let inputConfFile = confFileMemoryCache.removeValue(forKey: oldConfName) else {
      Logger.log("Cannot move conf file: no entry in cache for \"\(oldConfName)\" (this should never happen)", level: .error)
      self.sendErrorAlert(key: "error_finding_file", args: ["config"])
      return
    }
    confFileMemoryCache[newConfName] = inputConfFile

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
      } else if newExists {
        Logger.log("Can't rename config: a file already exists at the destination: \"\(newFilePath)\"", level: .error)
        // TODO: more appropriate message
        self.sendErrorAlert(key: "config.cannot_create", args: ["config"])
      } else {
        // - Move file on disk
        do {
          Logger.log("Attempting to move InputConf file \"\(oldFilePath)\" to \"\(newFilePath)\"")
          try FileManager.default.moveItem(atPath: oldFilePath, toPath: newFilePath)
        } catch let error {
          Logger.log("Failed to rename file: \(error)", level: .error)
          // TODO: more appropriate message
          self.sendErrorAlert(key: "config.cannot_create", args: ["config"])
        }
      }
    }
  }

  // Performs removal of files on disk. Throws exception to indicate failure; otherwise success is assumed even if empty dict returned.
  // Returns a copy of each removed files' contents which must be stored for later undo
  private func removeConfFiles(confNamesToRemove: Set<String>) -> [String:InputConfFile] {

    // Cache each file's contents in memory before removing it, for potential later use by undo
    var removedFileDict: [String:InputConfFile] = [:]

    for confName in confNamesToRemove {
      // Move file contents out of memory cache and into undo data:
      Logger.log("Removing from cache: \"\(confName)\"", level: .verbose)
      guard let inputConfFile = confFileMemoryCache.removeValue(forKey: confName) else {
        Logger.log("Cannot remove conf file: no entry in cache for \"\(confName)\" (this should never happen)", level: .error)
        self.sendErrorAlert(key: "error_finding_file", args: ["config"])
        continue
      }
      removedFileDict[confName] = inputConfFile
      let filePath = inputConfFile.filePath

      do {
        try FileManager.default.removeItem(atPath: filePath)
      } catch {
        if FileManager.default.fileExists(atPath: filePath) {
          Logger.log("File exists but could not be deleted: \"\(filePath)\"", level: .error)
          let fileName = URL(fileURLWithPath: filePath).lastPathComponent
          self.sendErrorAlert(key: "error_deleting_file", args: [fileName])
        } else {
          Logger.log("Looks like file was already removed: \"\(filePath)\"")
        }
      }
    }

    return removedFileDict
  }

  // Because the content of removed files was first stored in the undo data, restoring them will always succeed.
  // If disk operations fail, we can continue without immediate data loss - just report the error to user first.
  private func restoreRemovedConfFiles(_ confNames: Set<String>, _ filesRemovedByLastAction: [String:InputConfFile]) {
    for (confName, inputConfFile) in filesRemovedByLastAction {
      confFileMemoryCache[confName] = inputConfFile
    }

    for confName in confNames {
      guard let inputConfFile = filesRemovedByLastAction[confName] else {
        Logger.log("Cannot restore deleted conf \"\(confName)\": file content missing from undo data (this should never happen)", level: .error)
        self.sendErrorAlert(key: "config.cannot_create", args: [Utility.buildConfFilePath(for: confName)])
        continue
      }

      Logger.log("Restoring file to cache: \(confName)", level: .verbose)
      confFileMemoryCache[confName] = inputConfFile

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
        Logger.log("Failed to save undeleted file \"\(filePath)\": \(error)", level: .error)
        self.sendErrorAlert(key: "config.cannot_create", args: [filePath])
        continue
      }
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
