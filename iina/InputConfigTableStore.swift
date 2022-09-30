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
class InputConfigTableStore {
  // MARK: Non-static section start

  private var currentParsedConfigFile: InputConfigFileData? = nil

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
      Logger.log("Current input config changed: '\(self.currentConfigName)' -> '\(newValue)'")
      Preference.set(newValue, for: .currentInputConfigName)

      self.loadBindingsFromCurrentConfigFile()
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

  init() {
    configTableRows = buildConfigTableRows()
  }

  // MARK: Config CRUD

  func isEditEnabledForCurrentConfig() -> Bool {
    return !isDefaultConfig(currentConfigName)
  }

  func isDefaultConfig(_ configName: String) -> Bool {
    return AppData.defaultConfigs[configName] != nil
  }

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
    changeCurrentConfig(configNameNew)
  }

  // This is the only method other than setConfigTableState() which actually changes the real preference data
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

    setConfigTableState(currentConfigNameNew: configNameNew, .selectionChangeOnly)
  }

  // Adds (or updates) config file with the given name into the user configs list preference, and sets it as the current config.
  // Posts update notification
  func addUserConfig(name: String, filePath: String) {
    Logger.log("Adding user config: \"\(name)\" (filePath: \(filePath))")
    var userConfDictUpdated = userConfigDict
    userConfDictUpdated[name] = filePath
    setConfigTableState(userConfDictUpdated, currentConfigNameNew: name, .addRows)
  }

  func addUserConfigs(_ userConfigsToAdd: [String: String]) {
    Logger.log("Adding user configs: \"\(userConfigsToAdd))")
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
    setConfigTableState(userConfDictUpdated, currentConfigNameNew: newCurrentConfig, .addRows)
  }

  @objc
  func removeConfig(_ configName: String) {
    let isCurrentConfig: Bool = configName == currentConfigName
    Logger.log("Removing config: \"\(configName)\" (isCurrentConfig: \(isCurrentConfig))")

    var newCurrentConfName = currentConfigName

    if isCurrentConfig {
      guard let configIndex = configTableRows.firstIndex(of: configName) else {
        Logger.log("Cannot find '\(configName)' in table!", level: .error)
        return
      }
      // Are we the last entry? If so, after deletion the next entry up should be selected. If not, select the next one down
      newCurrentConfName = configTableRows[(configIndex == configTableRows.count - 1) ? configIndex - 1 : configIndex + 1]
    }

    var userConfDictUpdated = userConfigDict
    guard userConfDictUpdated.removeValue(forKey: configName) != nil else {
      Logger.log("Cannot remove config '\(configName)': it is not a user config!", level: .error)
      return
    }
    setConfigTableState(userConfDictUpdated, currentConfigNameNew: newCurrentConfName, .removeRows)
  }

  func renameCurrentConfig(newName: String) -> Bool {
    var userConfDictUpdated = userConfigDict
    Logger.log("Renaming config in prefs: \"\(currentConfigName)\" -> \"\(newName)\"")
    guard !currentConfigName.equalsIgnoreCase(newName) else {
      Logger.log("Skipping rename: '\(currentConfigName)' and '\(newName)' are the same", level: .error)
      return false
    }

    guard userConfDictUpdated[newName] == nil else {
      Logger.log("Cannot rename current config: a config already exists named: '\(newName)'", level: .error)
      return false
    }

    guard userConfDictUpdated.removeValue(forKey: currentConfigName) != nil else {
      Logger.log("Cannot rename current config '\(currentConfigName)': it is not a user config!", level: .error)
      return false
    }

    let newFilePath = Utility.buildConfigFilePath(for: newName)
    userConfDictUpdated[newName] = newFilePath

    setConfigTableState(userConfDictUpdated, currentConfigNameNew: newName, .renameAndMoveOneRow)

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

    Logger.log("Rebuilt Config table rows (current='\(currentConfigName)'): \(configTableRowsNew)", level: .verbose)

    return configTableRowsNew
  }

  // Replaces the current state with the given params, and fires listeners.
  private func setConfigTableState(_ userConfigDictNew: [String: String]? = nil, currentConfigNameNew: String, _ changeType: TableChange.ChangeType) {
    let configTableChange = TableChangeByStringElement(changeType)
    configTableChange.oldRows = configTableRows

    let currentConfigNameChanged = !self.currentConfigName.equalsIgnoreCase(currentConfigNameNew)

    if let userConfigDictNew = userConfigDictNew {
      Logger.log("Saving prefs: currentInputConfigName='\(currentConfigNameNew)', inputConfigs='\(userConfigDictNew)'", level: .verbose)
      guard userConfigDictNew[currentConfigNameNew] != nil else {
        Logger.log("Cannot update: '\(userConfigDictNew)' not found in supplied config dict (\(userConfigDictNew))", level: .error)
        return
      }
      self.userConfigDict = userConfigDictNew
    }

    if currentConfigNameChanged {
      // Keep in mind that if a failure happens this may end up changing currentConfigName to a different value than what goes in here.
      // This will also trigger a file load a Key Bindings Table update
      currentConfigName = currentConfigNameNew
    }

    configTableRows = buildConfigTableRows()
    configTableChange.newRows = configTableRows
    if let currentConfigIndex = configTableRows.firstIndex(of: self.currentConfigName) {
      configTableChange.newSelectedRows = IndexSet(integer: currentConfigIndex)
    }

    // Finally, fire notification. This covers row selection too
    NotificationCenter.default.post(Notification(name: .iinaInputConfigTableShouldUpdate, object: configTableChange))
  }

  // MARK: Input Config File serialize/deserialize

  // Input Config File: Load
  // Triggered any time `currentConfigName` is changed
  public func loadBindingsFromCurrentConfigFile() {
    guard let configFilePath = currentConfigFilePath else {
      Logger.log("Could not find file for current config (\"\(self.currentConfigName)\"); falling back to default config", level: .error)
      self.changeCurrentConfigToDefault()
      return
    }
    Logger.log("Loading key bindings config from \"\(configFilePath)\"")
    guard let inputConfigFile = InputConfigFileData.loadFile(at: configFilePath) else {
      // on error
      Logger.log("Error loading key bindings from config \"\(self.currentConfigName)\", at path: \"\(configFilePath)\"", level: .error)
      let fileName = URL(fileURLWithPath: configFilePath).lastPathComponent
      let alertInfo = AlertInfo(key: "keybinding_config.error", args: [fileName])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))

      self.changeCurrentConfigToDefault()
      return
    }
    self.currentParsedConfigFile = inputConfigFile

    let defaultSectionBindings = inputConfigFile.parseBindings()
    (NSApp.delegate as! AppDelegate).bindingTableStore.applyDefaultSectionUpdates(defaultSectionBindings, TableChangeByRowIndex(.reloadAll))
  }

  // Input Config File: Save
  public func saveBindingsToCurrentConfigFile(_ defaultSectionBindings: [KeyMapping]) -> [KeyMapping]? {
    guard let configFilePath = self.currentConfigFilePath else {
      let alertInfo = AlertInfo(key: "error_finding_file", args: ["config"])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
      return nil
    }
    Logger.log("Saving \(defaultSectionBindings.count) bindings to current config file: \"\(configFilePath)\"", level: .verbose)
    do {
      guard let currentParsedConfig = self.currentParsedConfigFile else {
        Logger.log("Cannot save bindings updates to file: could not find file in memory!", level: .error)
        return nil
      }
      currentParsedConfig.replaceAllBindings(with: defaultSectionBindings)
      try currentParsedConfig.writeFile(to: configFilePath)
      return currentParsedConfig.parseBindings()  // gets updated line numbers
    } catch {
      Logger.log("Failed to save bindings updates to file: \(error)", level: .error)
      let alertInfo = AlertInfo(key: "config.cannot_write", args: [configFilePath])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
    }
    return nil
  }

}
