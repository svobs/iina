//
//  InputConfPrefStore.swift
//  iina
//
//  Created by Matt Svoboda on 2022.07.04.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/*
 Encapsulates the user's list of user input config files via stored preferences.
 Used as a data store for an NSTableView with CRUD operations and support for setting up
 animations, but is decoupled from UI code so that everything is cleaner.
 Not thread-safe at present!
 */
class InputConfigStore {

  // Actual persisted data #1
  private var userConfigDict: [String: String] {
    get {
      guard let userConfigDict = Preference.dictionary(for: .inputConfigs) else {
        return [:]
      }
      guard let userConfigStringDict = userConfigDict as? [String: String] else {
        Logger.fatal("Unexpected type for pref: \(Preference.Key.inputConfigs.rawValue): \(type(of: userConfigDict))")
      }
      return userConfigStringDict
    } set {
      Preference.set(newValue, for: .inputConfigs)
    }
  }

  // Actual persisted data #2
  private(set) var currentConfigName: String {
    get {
      guard let currentConfig = Preference.string(for: .currentInputConfigName) else {
        let defaultConfig = AppData.defaultConfigNamesSorted[0]
        Logger.log("Could not get pref: \(Preference.Key.currentInputConfigName.rawValue): will use default (\"\(defaultConfig)\")", level: .warning)
        return defaultConfig
      }
      return currentConfig
    } set {
      guard !currentConfigName.equalsIgnoreCase(newValue) else {
        return
      }
      Logger.log("Current input config changed: '\(currentConfigName)' -> '\(newValue)'")
      Preference.set(newValue, for: .currentInputConfigName)

      loadBindingsFromCurrentConfigFile()
    }
  }

  // Looks up the current config, then searches for it first in the user configs, then the default configs,
  // then if still not found, returns nil
  var currentConfigFilePath: String? {
    get {
      let currentConfig = currentConfigName

      if let filePath = userConfigDict[currentConfig] {
        Logger.log("Found file path for user inputConfig '\(currentConfig)': \"\(filePath)\"", level: .verbose)
        if URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent != currentConfig {
          Logger.log("InputConfig's name '\(currentConfig)' does not match its filename: \"\(filePath)\"", level: .warning)
        }
        return filePath
      }
      if let filePath = AppData.defaultConfigs[currentConfig] {
        Logger.log("Found file path for default inputConfig '\(currentConfig)': \"\(filePath)\"", level: .verbose)
        return filePath
      }
      Logger.log("Cannot find file path for inputConfig: '\(currentConfig)'", level: .error)
      return nil
    }
  }

  /*
   Contains names of all user configs, which are also the identifiers in the UI table.
   */
  private(set) var configTableRows: [String] = []

  // When true, a blank "fake" row has been created which doesn't map to anything, and the normal
  // rules of the table are bent a little bit to accomodate it, until the user finishes naming it.
  // The row will also be selected, but `currentConfigName` should not change until the user submits
  private(set) var isAddingNewConfigInline: Bool = false

  init() {
    configTableRows = buildConfigTableRows()
  }

  var isCurrentConfigReadOnly: Bool {
    return isDefaultConfig(currentConfigName)
  }

  func isDefaultConfig(_ configName: String) -> Bool {
    return AppData.defaultConfigs[configName] != nil
  }

  // MARK: Config CRUD

  func getFilePath(forConfig config: String) -> String? {
    if let dv = AppData.defaultConfigs[config] {
      return dv
    }
    return userConfigDict[config]
  }

  // Returns the name of the user config with the given path, or nil if no config matches
  func getUserConfigName(forFilePath filePath: String) -> String? {
    for (userConfigName, userFilePath) in userConfigDict {
      if userFilePath == filePath {
        return userConfigName
      }
    }
    return nil
  }

  // Avoids hard program crash if index is invalid (which would happen for array dereference)
  func getConfigRow(at index: Int) -> String? {
    guard index >= 0 && index < configTableRows.count else {
      return nil
    }
    return configTableRows[index]
  }

  func changeCurrentConfigToDefault() {
    Logger.log("Changing current config to default", level: .verbose)
    changeCurrentConfig(0)  // using this call will avoid an infinite loop if the default config cannot be loaded
  }

  func changeCurrentConfig(_ newIndex: Int) {
    Logger.log("Changing current input config, newIndex=\(newIndex)", level: .verbose)
    guard let configNameNew = getConfigRow(at: newIndex) else {
      Logger.log("Cannot change current config: invalid index: \(newIndex)", level: .error)
      return
    }
    if isAddingNewConfigInline {
      if configNameNew == "" {
        return
      } else {
        cancelInlineAdd(newCurrentConfig: configNameNew)
        return
      }
    }
    changeCurrentConfig(configNameNew)
  }

  // This is the only method other than applyConfigTableChange() which actually changes the real preference data
  func changeCurrentConfig(_ configNameNew: String) {
    guard !configNameNew.equalsIgnoreCase(self.currentConfigName) else {
      Logger.log("No need to persist change to current config '\(configNameNew)'; it is already current", level: .verbose)
      return
    }
    guard configTableRows.contains(configNameNew) else {
      Logger.log("Could not change current config to '\(configNameNew)' (not found in table); falling back to default config", level: .error)
      changeCurrentConfigToDefault()
      return
    }

    guard getFilePath(forConfig: configNameNew) != nil else {
      Logger.log("Could not change current config to '\(configNameNew)' (no entry in prefs); falling back to default config", level: .error)
      changeCurrentConfigToDefault()
      return
    }

    Logger.log("Changing current config to: \"\(configNameNew)\"", level: .verbose)

    applyConfigTableChange(currentConfigNameNew: configNameNew)
  }

  // Adds (or updates) config file with the given name into the user configs list preference, and sets it as the current config.
  // Posts update notification
  func addUserConfig(configName: String, filePath: String, completionHandler: TableChange.CompletionHandler? = nil) {
    Logger.log("Adding user config: \"\(configName)\" (filePath: \(filePath))")
    var userConfDictUpdated = userConfigDict
    userConfDictUpdated[configName] = filePath
    applyConfigTableChange(userConfDictUpdated, currentConfigNameNew: configName, completionHandler: completionHandler)
  }

  func addNewUserConfigInline(completionHandler: TableChange.CompletionHandler? = nil) {
    if isAddingNewConfigInline {
      Logger.log("Already adding new user config inline; will reselect it")
    } else {
      Logger.log("Adding blank row for naming new user config")
    }
    isAddingNewConfigInline = true
    applyConfigTableChange(currentConfigNameNew: currentConfigName, completionHandler: completionHandler)
  }

  func completeInlineAdd(configName: String, filePath: String,
                         completionHandler: TableChange.CompletionHandler? = nil) {
    guard isAddingNewConfigInline else {
      Logger.log("completeInlineAdd() called but isAddingNewConfigInline is false!", level: .error)
      return
    }
    isAddingNewConfigInline = false

    Logger.log("Completing inline add of user config: \"\(configName)\" (filePath: \(filePath))")
    var userConfDictUpdated = userConfigDict
    userConfDictUpdated[configName] = filePath
    applyConfigTableChange(userConfDictUpdated, currentConfigNameNew: configName,
                           completionHandler: completionHandler)
  }

  func cancelInlineAdd(newCurrentConfig: String? = nil) {
    guard isAddingNewConfigInline else {
      Logger.log("cancelInlineAdd() called but isAddingNewConfigInline is false!", level: .error)
      return
    }
    isAddingNewConfigInline = false
    Logger.log("Cancelling inline add", level: .verbose)
    applyConfigTableChange(currentConfigNameNew: newCurrentConfig ?? currentConfigName)
  }

  func addUserConfigs(_ userConfigsToAdd: [String: String]) {
    Logger.log("Adding user configs: \(userConfigsToAdd)")
    guard let firstConfig = userConfigsToAdd.first else {
      return
    }
    var newCurrentConfig = firstConfig.key

    var userConfDictUpdated = userConfigDict
    for (name, filePath) in userConfigsToAdd {
      userConfDictUpdated[name] = filePath
      // We can only select one, even if multiple rows added.
      // Select the added config with the last name in lowercase alphabetical order
      if newCurrentConfig.localizedCompare(name) == .orderedAscending {
        newCurrentConfig = name
      }
    }
    applyConfigTableChange(userConfDictUpdated, currentConfigNameNew: newCurrentConfig)
  }

  func removeConfig(_ configName: String) {
    let isCurrentConfig: Bool = configName == currentConfigName
    Logger.log("Removing config: \"\(configName)\" (isCurrentConfig: \(isCurrentConfig))")

    var newCurrentConfName = currentConfigName

    if isCurrentConfig {
      guard let configIndex = configTableRows.firstIndex(of: configName) else {
        Logger.log("Cannot find \"\(configName)\" in table!", level: .error)
        return
      }
      // Are we the last entry? If so, after deletion the next entry up should be selected. If not, select the next one down
      newCurrentConfName = configTableRows[(configIndex == configTableRows.count - 1) ? configIndex - 1 : configIndex + 1]
    }

    var userConfDictUpdated = userConfigDict
    guard userConfDictUpdated.removeValue(forKey: configName) != nil else {
      Logger.log("Cannot remove config \"\(configName)\": it is not a user config!", level: .error)
      return
    }
    applyConfigTableChange(userConfDictUpdated, currentConfigNameNew: newCurrentConfName)
  }

  func renameCurrentConfig(newName: String) -> Bool {
    var userConfDictUpdated = userConfigDict
    Logger.log("Renaming config in prefs: \"\(currentConfigName)\" -> \"\(newName)\"")
    guard !currentConfigName.equalsIgnoreCase(newName) else {
      Logger.log("Skipping rename: '\(currentConfigName)' and '\(newName)' are the same", level: .error)
      return false
    }

    guard userConfDictUpdated[newName] == nil else {
      Logger.log("Cannot rename current config: a config already exists named: \"\(newName)\"", level: .error)
      return false
    }

    guard userConfDictUpdated.removeValue(forKey: currentConfigName) != nil else {
      Logger.log("Cannot rename current config \"\(currentConfigName)\": it is not a user config!", level: .error)
      return false
    }

    let newFilePath = Utility.buildConfigFilePath(for: newName)
    userConfDictUpdated[newName] = newFilePath

    applyConfigTableChange(userConfDictUpdated, currentConfigNameNew: newName)

    return true
  }

  // Rebuilds & re-sorts the table names. Must not change the actual state of any member vars
  private func buildConfigTableRows() -> [String] {
    var configTableRowsNew: [String] = []

    // - default configs:
    configTableRowsNew.append(contentsOf: AppData.defaultConfigNamesSorted)

    // - user: explicitly sort (ignoring case)
    var userConfigNameList: [String] = []
    userConfigDict.forEach {
      userConfigNameList.append($0.key)
    }
    userConfigNameList.sort{$0.localizedCompare($1) == .orderedAscending}

    configTableRowsNew.append(contentsOf: userConfigNameList)

    Logger.log("Rebuilt Config table rows (current=\"\(currentConfigName)\"): \(configTableRowsNew)", level: .verbose)

    return configTableRowsNew
  }

  // Replaces the current state with the given params, and fires listeners.
  private func applyConfigTableChange(_ userConfigDictNew: [String: String]? = nil, currentConfigNameNew: String,
                                      completionHandler: TableChange.CompletionHandler? = nil) {

    if let userConfigDictNew = userConfigDictNew {
      Logger.log("Saving prefs: currentInputConfigName=\"\(currentConfigNameNew)\", inputConfigs=\(userConfigDictNew)", level: .verbose)
      guard userConfigDictNew[currentConfigNameNew] != nil else {
        Logger.log("Cannot update: \"\(currentConfigNameNew)\" not found in supplied config dict (\(userConfigDictNew))", level: .error)
        return
      }
      self.userConfigDict = userConfigDictNew
    }

    currentConfigName = currentConfigNameNew

    let oldRows = configTableRows
    var newRows = buildConfigTableRows()
    if isAddingNewConfigInline {
      // Add blank row to be edited to the end
      newRows.append("")
    }

    let configTableChange = TableChange.buildDiff(oldRows: oldRows, newRows: newRows, completionHandler: completionHandler)
    configTableChange.scrollToFirstSelectedRow = true

    configTableRows = newRows

    if isAddingNewConfigInline { // special case: creating an all-new config
      // Select the new blank row, which will be the last one:
      configTableChange.newSelectedRows = IndexSet(integer: configTableRows.count - 1)
    } else {
      // Always keep the current config selected
      if let currentConfigIndex = configTableRows.firstIndex(of: self.currentConfigName) {
        configTableChange.newSelectedRows = IndexSet(integer: currentConfigIndex)
      }
    }

    // Finally, fire notification. This covers row selection too
    NotificationCenter.default.post(Notification(name: .iinaInputConfigTableShouldUpdate, object: configTableChange))
  }

  // MARK: Config File Load
  // Triggered any time `currentConfigName` is changed
  public func loadBindingsFromCurrentConfigFile() {
    guard let configFilePath = currentConfigFilePath else {
      Logger.log("Could not find file for current config (\"\(currentConfigName)\"); falling back to default config", level: .error)
      changeCurrentConfigToDefault()
      return
    }
    Logger.log("Loading bindings config from \"\(configFilePath)\"")
    guard let inputConfigFile = InputConfigFile.loadFile(at: configFilePath, isReadOnly: isCurrentConfigReadOnly) else {
      changeCurrentConfigToDefault()
      return
    }

    AppInputConfig.inputBindingStore.currenConfigFileDidChange(inputConfigFile)
  }
}
