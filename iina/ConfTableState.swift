//
//  InputConfPrefStore.swift
//  iina
//
//  Created by Matt Svoboda on 2022.07.04.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/*
 Provides a snapshot for the user's list of user input conf files and current selection.
 Used as a data store for the User Conf NSTableView, with CRUD operations and support for setting up
 animations, but instances of it are immutable. A new instance is created by ConfTableStateManager each
 time there is a change. Callers should not save references to instances of this class but instead should
 refer to ConfTableState.current each time for an up-to-date version.
 Tries to be model-focused and decoupled from UI code so that everything is cleaner.
 */
struct ConfTableState {
  static var current: ConfTableState = ConfTableStateManager.initialState()
  static let manager: ConfTableStateManager = ConfTableStateManager()

  // MARK: Actual data

  let userConfDict: [String: String]

  let selectedConfName: String

  // MARK: Derived data

  // Looks up the selected conf, then searches for it first in the user confs, then the default confs,
  // then if still not found, returns nil
  var selectedConfFilePath: String? {
    let selectedConf = selectedConfName

    if let filePath = userConfDict[selectedConf] {
      Logger.log("Found file path for user conf '\(selectedConf)': \"\(filePath)\"", level: .verbose)
      if URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent != selectedConf {
        Logger.log("Conf's name '\(selectedConf)' does not match its filename: \"\(filePath)\"", level: .warning)
      }
      return filePath
    }
    if let filePath = AppData.defaultConfs[selectedConf] {
      Logger.log("Found file path for default conf '\(selectedConf)': \"\(filePath)\"", level: .verbose)
      return filePath
    }
    Logger.log("Cannot find file path for conf: '\(selectedConf)'", level: .error)
    return nil
  }

  /*
   Contains names of all user confs, which are also the identifiers in the UI table.
   */
  let confTableRows: [String]

  // When true, a blank "fake" row has been created which doesn't map to anything, and the normal
  // rules of the table are bent a little bit to accomodate it, until the user finishes naming it.
  // The row will also be selected, but `selectedConfName` should not change until the user submits
  let isAddingNewConfInline: Bool

  init(userConfDict: [String: String], selectedConfName: String, isAddingNewConfInline: Bool) {
    self.userConfDict = userConfDict
    self.selectedConfName = selectedConfName
    self.isAddingNewConfInline = isAddingNewConfInline
    self.confTableRows = ConfTableState.buildConfTableRows(from: self.userConfDict, isAddingNewConfInline: isAddingNewConfInline)
  }

  var isSelectedConfReadOnly: Bool {
    return isDefaultConf(selectedConfName)
  }

  func isDefaultConf(_ confName: String) -> Bool {
    return AppData.defaultConfs[confName] != nil
  }

  // MARK: Conf CRUD

  func getFilePath(forConf conf: String) -> String? {
    if let dv = AppData.defaultConfs[conf] {
      return dv
    }
    return userConfDict[conf]
  }

  // Returns the name of the user conf with the given path, or nil if no conf matches
  func getUserConfName(forFilePath filePath: String) -> String? {
    for (userConfName, userFilePath) in userConfDict {
      if userFilePath == filePath {
        return userConfName
      }
    }
    return nil
  }

  // Avoids hard program crash if index is invalid (which would happen for array dereference)
  func getConfName(at index: Int) -> String? {
    guard index >= 0 && index < confTableRows.count else {
      return nil
    }
    return confTableRows[index]
  }

  func changeSelectedConfToDefault() {
    Logger.log("Changing selected conf to default", level: .verbose)
    changeSelectedConf(0)  // using this call will avoid an infinite loop if the default conf cannot be loaded
  }

  func changeSelectedConf(_ newIndex: Int) {
    Logger.log("Changing conf selection, newIndex=\(newIndex)", level: .verbose)
    guard let confNameNew = getConfName(at: newIndex) else {
      Logger.log("Cannot change conf selection: invalid index: \(newIndex)", level: .error)
      return
    }
    if isAddingNewConfInline {
      if confNameNew == "" {
        return
      }
    }
    changeSelectedConf(confNameNew)
  }

  // This is the only method other than ConfTableState.manager.doAction() which actually changes the real preference data
  func changeSelectedConf(_ confNameNew: String) {
    guard !confNameNew.equalsIgnoreCase(self.selectedConfName) else {
      return
    }
    guard confTableRows.contains(confNameNew) else {
      Logger.log("Could not change selected conf to '\(confNameNew)' (not found in table); falling back to default conf", level: .error)
      changeSelectedConfToDefault()
      return
    }

    guard getFilePath(forConf: confNameNew) != nil else {
      Logger.log("Could not change selected conf to '\(confNameNew)' (no entry in prefs); falling back to default conf", level: .error)
      changeSelectedConfToDefault()
      return
    }

    Logger.log("Changing selected conf to: \"\(confNameNew)\"", level: .verbose)

    ConfTableState.manager.doAction(selectedConfNameNew: confNameNew)
  }

  // Adds (or updates) conf file with the given name into the user confs list preference, and sets it as the selected conf.
  // Posts update notification
  func addUserConf(confName: String, filePath: String, completionHandler: TableChange.CompletionHandler? = nil) {
    Logger.log("Adding user conf: \"\(confName)\" (filePath: \(filePath))")
    var userConfDictUpdated = userConfDict
    userConfDictUpdated[confName] = filePath
    ConfTableState.manager.doAction(userConfDictUpdated, selectedConfNameNew: confName, completionHandler: completionHandler)
  }

  func addNewUserConfInline(completionHandler: TableChange.CompletionHandler? = nil) {
    if isAddingNewConfInline {
      Logger.log("Already adding new user conf inline; will reselect it")
    } else {
      Logger.log("Adding blank row for naming new user conf")
    }
    ConfTableState.manager.doAction(isAddingNewConfInline: true, completionHandler: completionHandler)
  }

  func completeInlineAdd(confName: String, filePath: String,
                         completionHandler: TableChange.CompletionHandler? = nil) {
    guard isAddingNewConfInline else {
      Logger.log("completeInlineAdd() called but isAddingNewConfInline is false!", level: .error)
      return
    }

    Logger.log("Completing inline add of user conf: \"\(confName)\" (filePath: \(filePath))")
    var userConfDictUpdated = userConfDict
    userConfDictUpdated[confName] = filePath
    ConfTableState.manager.doAction(userConfDictUpdated, selectedConfNameNew: confName,
                                    isAddingNewConfInline: false, completionHandler: completionHandler)
  }

  func cancelInlineAdd(selectedConfNew: String? = nil) {
    guard isAddingNewConfInline else {
      Logger.log("cancelInlineAdd() called but isAddingNewConfInline is false!", level: .error)
      return
    }
    Logger.log("Cancelling inline add", level: .verbose)
    ConfTableState.manager.doAction(selectedConfNameNew: selectedConfNew, isAddingNewConfInline: false)
  }

  func addUserConfs(_ userConfsToAdd: [String: String]) {
    Logger.log("Adding user confs: \(userConfsToAdd)")
    guard let firstConf = userConfsToAdd.first else {
      return
    }
    var selectedConfNew = firstConf.key

    var userConfDictUpdated = userConfDict
    for (name, filePath) in userConfsToAdd {
      userConfDictUpdated[name] = filePath
      // We can only select one, even if multiple rows added.
      // Select the added conf with the last name in lowercase alphabetical order
      if selectedConfNew.localizedCompare(name) == .orderedAscending {
        selectedConfNew = name
      }
    }
    ConfTableState.manager.doAction(userConfDictUpdated, selectedConfNameNew: selectedConfNew)
  }

  func removeConf(_ confName: String) {
    let isCurrentConf: Bool = confName == selectedConfName
    Logger.log("Removing conf: \"\(confName)\" (isCurrentConf: \(isCurrentConf))")

    var selectedConfNameNew = selectedConfName

    if isCurrentConf {
      guard let confIndex = confTableRows.firstIndex(of: confName) else {
        Logger.log("Cannot find \"\(confName)\" in table!", level: .error)
        return
      }
      // Are we the last entry? If so, after deletion the next entry up should be selected. If not, select the next one down
      selectedConfNameNew = confTableRows[(confIndex == confTableRows.count - 1) ? confIndex - 1 : confIndex + 1]
    }

    var userConfDictUpdated = userConfDict
    guard userConfDictUpdated.removeValue(forKey: confName) != nil else {
      Logger.log("Cannot remove conf \"\(confName)\": it is not a user conf!", level: .error)
      return
    }
    ConfTableState.manager.doAction(userConfDictUpdated, selectedConfNameNew: selectedConfNameNew)
  }

  func renameSelectedConf(newName: String) -> Bool {
    var userConfDictUpdated = userConfDict
    Logger.log("Renaming conf in prefs: \"\(selectedConfName)\" -> \"\(newName)\"")
    guard !selectedConfName.equalsIgnoreCase(newName) else {
      Logger.log("Skipping rename: '\(selectedConfName)' and '\(newName)' are the same", level: .error)
      return false
    }

    guard userConfDictUpdated[newName] == nil else {
      Logger.log("Cannot rename selected conf: a conf already exists named: \"\(newName)\"", level: .error)
      return false
    }

    guard userConfDictUpdated.removeValue(forKey: selectedConfName) != nil else {
      Logger.log("Cannot rename selected conf \"\(selectedConfName)\": it is not a user conf!", level: .error)
      return false
    }

    let newFilePath = Utility.buildConfFilePath(for: newName)
    userConfDictUpdated[newName] = newFilePath

    ConfTableState.manager.doAction(userConfDictUpdated, selectedConfNameNew: newName)
    return true
  }

  private func doAction(_ userConfDictNew: [String:String]? = nil, selectedConfNameNew: String? = nil,
                        isAddingNewConfInline: Bool = false, completionHandler: TableChange.CompletionHandler? = nil) {
    ConfTableState.manager.doAction(userConfDictNew, selectedConfNameNew: selectedConfNameNew, isAddingNewConfInline: isAddingNewConfInline, completionHandler: completionHandler)
  }
  // Rebuilds & re-sorts the table names. Must not change the actual state of any member vars
  static private func buildConfTableRows(from userConfDict: [String: String],
                                         isAddingNewConfInline: Bool) -> [String] {
    var confTableRows: [String] = []

    // - default confs:
    confTableRows.append(contentsOf: AppData.defaultConfNamesSorted)

    // - user: explicitly sort (ignoring case)
    var userConfNameList: [String] = []
    userConfDict.forEach {
      userConfNameList.append($0.key)
    }
    userConfNameList.sort{$0.localizedCompare($1) == .orderedAscending}

    confTableRows.append(contentsOf: userConfNameList)

    if isAddingNewConfInline {
      // Add blank row to be edited to the end
      confTableRows.append("")
    }

    return confTableRows
  }

}
