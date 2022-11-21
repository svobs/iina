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

  private var observers: [NSObjectProtocol] = []

  override init() {
    super.init()
    Logger.log("ConfTableStateManager init", level: .verbose)

    // This will notify that a pref has changed, even if it was changed by another instance of IINA:
    for key in [Preference.Key.currentInputConfigName, Preference.Key.inputConfigs] {
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }

    observers.append(NotificationCenter.default.addObserver(forName: .iinaSelectedConfFileNeedsLoad, object: nil, queue: .main, using: self.loadCurrentConfFileWasRequested))
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

  fileprivate struct UndoData {
    var userConfDict: [String:String]?
    var selectedConfName: String?
    var filesRemovedByLastAction: [String:String]?
  }
  fileprivate enum UpdateFilesError: Error {
    case errorOccurred
  }

  func doAction(_ userConfDictNew: [String:String]? = nil, selectedConfNameNew: String? = nil,
                enterSpecialState specialState: ConfTableState.SpecialState = .none,
                completionHandler: TableChange.CompletionHandler? = nil) {

    let doData = UndoData(userConfDict: userConfDictNew, selectedConfName: selectedConfNameNew)
    self.doAction(doData, enterSpecialState: specialState, completionHandler: completionHandler)
  }

  // May be called for do, undo, or redo
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

        Logger.log("Registering for undo: \"\(undoActionName)\" (removed: \(oldData.filesRemovedByLastAction?.keys.count ?? 0))", level: .verbose)
        undoManager.registerUndo(withTarget: self, handler: { manager in
          Logger.log("Undoing or redoing action \"\(undoActionName)\"", level: .verbose)

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
    let userConfigsNew = Set(userConfDictNew.keys)
    let userConfigsOld = Set(oldData.userConfDict!.keys)

    let added = userConfigsNew.subtracting(userConfigsOld)
    let removed = userConfigsOld.subtracting(userConfigsNew)
    if let oldName = removed.first, let newName = added.first {
      // File renamed/moved
      actionName = "Rename Config"

      if added.count != 1 || removed.count != 1 {
        // This shouldn't be possible. Make sure we catch it if it is
        Logger.fatal("Can't rename more than 1 InputConfig file at a time! (Added: \(added); Removed: \(removed))")
      }

      let oldFilePath = Utility.buildConfFilePath(for: oldName)
      let newFilePath = Utility.buildConfFilePath(for: newName)

      let oldExists = FileManager.default.fileExists(atPath: oldFilePath)
      let newExists = FileManager.default.fileExists(atPath: newFilePath)

      if !oldExists && newExists {
        Logger.log("Looks like file has already moved: \"\(oldFilePath)\"")
      } else {
        if !oldExists {
          Logger.log("Can't rename config: could not find file: \"\(oldFilePath)\"", level: .error)
          self.sendErrorAlert(key: "error_finding_file", args: ["config"])
          throw UpdateFilesError.errorOccurred
        } else if newExists {
          Logger.log("Can't rename config: a file already exists at the destination: \"\(newFilePath)\"", level: .error)
          // TODO: more appropriate message
          self.sendErrorAlert(key: "config.cannot_create", args: ["config"])
          throw UpdateFilesError.errorOccurred
        }

        // - Move file on disk
        do {
          Logger.log("Attempting to move InputConf file \"\(oldFilePath)\" to \"\(newFilePath)\"")
          try FileManager.default.moveItem(atPath: oldFilePath, toPath: newFilePath)
        } catch let error {
          Logger.log("Failed to rename file: \(error)", level: .error)
          // TODO: more appropriate message
          self.sendErrorAlert(key: "config.cannot_create", args: ["config"])
          throw UpdateFilesError.errorOccurred
        }
      }

    } else if removed.count > 0 {
      // File(s) removed (This can be more than one if we're undoing a multi-file import)
      actionName = Utility.format(.config, removed.count, .delete)

      oldData.filesRemovedByLastAction = [:]
      for confName in removed {
        let confFilePath = Utility.buildConfFilePath(for: confName)

        // Save file contents in memory before removing it. Do not remove a file if it can't be read
        do {
          oldData.filesRemovedByLastAction![confName] = try String(contentsOf: URL(fileURLWithPath: confFilePath))
        } catch {
          Logger.log("Failed to read file before removal: \"\(confFilePath)\": \(error)", level: .error)
          self.sendErrorAlert(key: "keybinding_config.error", args: [confFilePath])

          if FileManager.default.fileExists(atPath: confFilePath) {
            Logger.log("File exists but cannot be read; aborting delete", level: .error)
            throw UpdateFilesError.errorOccurred
          } else {
            Logger.log("Looks like file was already removed: \"\(confFilePath)\"")
          }
          continue
        }

        do {
          try FileManager.default.removeItem(atPath: confFilePath)
        } catch {
          let fileName = URL(fileURLWithPath: confFilePath).lastPathComponent
          let alertInfo = Utility.AlertInfo(key: "error_deleting_file", args: [fileName])
          NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
          // try to recover, and fall through
          oldData.filesRemovedByLastAction!.removeValue(forKey: confName)
        }
      }

    } else if added.count > 0 {
      // Files(s) duplicated, created, or imported.
      // Too many different cases and fancy logic: let the UI controller handle the file stuff...
      // UNLESS we are in an undo (if `removedFilesForUndo` != nil): then this class must restore deleted files
      actionName = Utility.format(.config, added.count, .add)

      if let filesRemovedByLastAction = newData.filesRemovedByLastAction {
        for confName in added {
          let confFilePath = Utility.buildConfFilePath(for: confName)
          guard let fileContent = filesRemovedByLastAction[confName] else {
            // Should never happen
            Logger.log("Cannot restore deleted file: file content is missing! (config name: \(confName)", level: .error)
            self.sendErrorAlert(key: "config.cannot_create", args: [confFilePath])
            continue
          }
          do {
            if FileManager.default.fileExists(atPath: confFilePath) {
              Logger.log("Cannot restore deleted file: file aleady exists: \(confFilePath)", level: .error)
              // TODO: more appropriate message
              self.sendErrorAlert(key: "config.cannot_create", args: [confFilePath])
              continue
            }
            try fileContent.write(toFile: confFilePath, atomically: true, encoding: .utf8)
          } catch {
            Logger.log("Failed to restore deleted file \"\(confFilePath)\": \(error)", level: .error)
            self.sendErrorAlert(key: "config.cannot_create", args: [confFilePath])
            continue
          }
        }
      }
    }
    return actionName
  }

  // MARK: Load Conf File

  private func loadCurrentConfFileWasRequested(_ notification: Notification) {
    loadBindingsFromSelectedConfFile()
  }

  // Conf File load. Triggered any time `selectedConfName` is changed
  func loadBindingsFromSelectedConfFile() {
    let currentState = ConfTableState.current
    guard let confFilePath = currentState.selectedConfFilePath else {
      Logger.log("Could not find file for current conf (\"\(currentState.selectedConfName)\"); falling back to default conf", level: .error)
      currentState.fallBackToDefaultConf()
      return
    }

    Logger.log("Loading bindings from conf file: \"\(confFilePath)\"")
    guard let inputConfFile = InputConfFile.loadFile(at: confFilePath, isReadOnly: currentState.isSelectedConfReadOnly) else {
      currentState.fallBackToDefaultConf()
      return
    }

    var userData: [BindingTableStateManager.Key: Any] = [BindingTableStateManager.Key.confFile: inputConfFile]

    if !Preference.bool(for: .animateKeyBindingTableReloadAll) {
      userData[BindingTableStateManager.Key.tableChange] = TableChange(.reloadAll)
    }

    // Send down the pipeline
    let userConfMappingsNew = inputConfFile.parseMappings()
    AppInputConfig.replaceDefaultSectionMappings(with: userConfMappingsNew, attaching: userData)
  }
}
