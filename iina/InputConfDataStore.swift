//
//  InputConfPrefStore.swift
//  iina
//
//  Created by Matt Svoboda on 2022.07.04.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/*
 Encapsulates the user's UserConf stored preferences.
 Controls access & restricts updates to support being used as a backing store for an NSTableView.
 Not thread-safe at present!
 */
class InputConfDataStore {

  // Immmutable default configs.
  // TODO: these would be best combined into a SortedDictionary
  private static let defaultConfigNamesSorted = ["IINA Default", "mpv Default", "VLC Default", "Movist Default"]
  static let defaultConfigs: [String: String] = [
    "IINA Default": Bundle.main.path(forResource: "iina-default-input", ofType: "conf", inDirectory: "config")!,
    "mpv Default": Bundle.main.path(forResource: "input", ofType: "conf", inDirectory: "config")!,
    "VLC Default": Bundle.main.path(forResource: "vlc-default-input", ofType: "conf", inDirectory: "config")!,
    "Movist Default": Bundle.main.path(forResource: "movist-default-input", ofType: "conf", inDirectory: "config")!
  ]

  // Actual persisted data #1
  private var userConfigDict: [String: String] {
    get {
      guard let userConfigDict = Preference.dictionary(for: .inputConfigs) as? [String: String] else {
        Logger.fatal("Cannot get pref: \(Preference.Key.inputConfigs.rawValue)!")
      }
      return userConfigDict
    }
  }

  // Actual persisted data #2
  var currentConfName: String {
    get {
      guard let currentConf = Preference.string(for: .currentInputConfigName) else {
        Logger.fatal("Cannot get pref: \(Preference.Key.currentInputConfigName.rawValue)!")
      }
      Logger.log("Returning currentConfName='\(currentConf)'", level: .verbose)
      return currentConf
    }
    // no setter. See: changeCurrentConfig()
  }

  var currentConfFilePath: String? {
    get {
      let currentConf = currentConfName
      if let filePath = InputConfDataStore.defaultConfigs[currentConf] {
        Logger.log("Found file path for default inputConfig '\(currentConf)': \"\(filePath)\"", level: .verbose)
        return filePath
      }
      if let filePath = userConfigDict[currentConf] {
        Logger.log("Found file path for user inputConfig '\(currentConf)': \"\(filePath)\"", level: .verbose)
        if URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent != currentConf {
          Logger.log("InputConfig's name '\(currentConf)' does not match its filename: \"\(filePath)\"", level: .warning)
        }
        return filePath
      }
      Logger.log("Cannot find file path for inputConfig: '\(currentConf)'", level: .error)
      return nil
    }
  }

  /*
   Contains names of all user configs, which are also the identifiers in the UI table.
   */
  private(set) var tableRows: [String] = []

  init() {
    tableRows = buildTableRows()
  }

  func isDefaultConfig(_ configName: String) -> Bool {
    return InputConfDataStore.defaultConfigs[configName] != nil
  }

  func getFilePath(forConfig conf: String) -> String? {
    if let dv = InputConfDataStore.defaultConfigs[conf] {
      return dv
    }
    return userConfigDict[conf]
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

  // Avoids hard program crash if index is invalid
  func getRow(at index: Int) -> String? {
    guard index >= 0 && index < tableRows.count else {
      return nil
    }
    return tableRows[index]
  }

  func changeCurrentConfigToDefault() {
    Logger.log("Changing current config to default", level: .verbose)
    changeCurrentConfig(0)  // using this call will avoid an infinite loop if the default conf cannot be loaded
  }

  func changeCurrentConfig(_ newIndex: Int) {
    Logger.log("Changing current input config, newIndex=\(newIndex)", level: .verbose)
    guard let confName = getRow(at: newIndex) else {
      Logger.log("Cannot change current config: invalid index: \(newIndex)", level: .error)
      return
    }
    changeCurrentConfig(confName)
  }

  // This is the only method other than updateState() which actually changes the real preference data
  func changeCurrentConfig(_ confName: String) {
    guard !confName.equalsIgnoreCase(self.currentConfName) else {
      Logger.log("No need to persist change to current config '\(confName)'; it is already current", level: .verbose)
      return
    }
    guard tableRows.contains(confName) && getFilePath(forConfig: confName) != nil else {
      Logger.log("Could not change current conf to '\(confName)'; falling back to default config", level: .error)
      changeCurrentConfigToDefault()
      return
    }

    Preference.set(confName, for: .currentInputConfigName)

    Logger.log("Current input config changed: '\(self.currentConfName)' -> '\(confName)'")
    NotificationCenter.default.post(Notification(name: .iinaCurrentInputConfChanged))
  }

  // Adds (or updates) config file with the given name into the user configs list preference, and sets it as the current config.
  // Posts update notification
  func addUserConfig(name: String, filePath: String) {
    Logger.log("Adding user config: \"\(name)\" (filePath: \(filePath))")
    var newUserConfigDict = userConfigDict
    newUserConfigDict[name] = filePath
    updateState(newUserConfigDict, currentConfigName: name, .addRows)
  }

  func addUserConfigs(_ userConfigsToAdd: [String: String]) {
    Logger.log("Adding user configs: \"\(userConfigsToAdd))")
    guard let firstConfig = userConfigsToAdd.first else {
      return
    }
    var newCurrentConfig = firstConfig.key

    var newUserConfigDict = userConfigDict
    for (name, filePath) in userConfigsToAdd {
      newUserConfigDict[name] = filePath
      // We can only select one, even if multiple rows added.
      // Select the added config with the last name in lowercase alphabetical order
      if newCurrentConfig.localizedCompare(name) == .orderedAscending {
        newCurrentConfig = name
      }
    }
    updateState(newUserConfigDict, currentConfigName: newCurrentConfig, .addRows)
  }

  @objc
  func removeConfig(_ configName: String) {
    let isCurrentConfig: Bool = configName == currentConfName
    Logger.log("Removing config: \"\(configName)\" (isCurrentConfig: \(isCurrentConfig))")

    var newCurrentConfigName = currentConfName

    if isCurrentConfig {
      guard let configIndex = tableRows.firstIndex(of: configName) else {
        Logger.log("Cannot find '\(configName)' in table!", level: .error)
        return
      }
      // Are we the last entry? If so, after deletion the next entry up should be selected. If not, select the next one down
      newCurrentConfigName = tableRows[(configIndex == tableRows.count - 1) ? configIndex - 1 : configIndex + 1]
    }

    var newUserConfigDict = userConfigDict
    guard newUserConfigDict.removeValue(forKey: configName) != nil else {
      Logger.log("Cannot remove config '\(configName)': it is not a user config!", level: .error)
      return
    }
    updateState(newUserConfigDict, currentConfigName: newCurrentConfigName, .removeRows)
  }

  func renameCurrentConfig(to newName: String) -> Bool {
    var newUserConfigDict = userConfigDict
    Logger.log("Renaming config: \"\(currentConfName)\" -> \"\(newName)\"")
    guard currentConfName.equalsIgnoreCase(newName) else {
      Logger.log("Cannot rename: '\(currentConfName)' and '\(newName)' are the same", level: .error)
      return false
    }

    guard let filePath = currentConfFilePath else {
      Logger.log("Cannot rename current config '\(currentConfName)': no file path!", level: .error)
      return false
    }

    guard newUserConfigDict[newName] == nil else {
      Logger.log("Cannot rename current config: a config already exists named: '\(newName)'", level: .error)
      return false
    }

    guard newUserConfigDict.removeValue(forKey: currentConfName) != nil else {
      Logger.log("Cannot rename current config '\(currentConfName)': it is not a user config!", level: .error)
      return false
    }

    newUserConfigDict[newName] = filePath

    updateState(newUserConfigDict, currentConfigName: newName, .renameAndMoveOneRow)

    return true
  }

  // Replaces the current state with the given params, and fires listeners.
  private func updateState(_ userConfigDict: [String: String], currentConfigName: String, _ changeType: TableStateChange.ChangeType) {
    let tableChanges = TableStateChange(changeType)
    tableChanges.oldRows = tableRows

    let currentConfigChanged = self.currentConfName != currentConfigName

    Logger.log("Saving prefs: currentInputConfigName='\(currentConfigName)', inputConfigs='\(userConfigDict)'", level: .verbose)
    Preference.set(userConfigDict, for: .inputConfigs)
    Preference.set(currentConfigName, for: .currentInputConfigName)
    // refresh
    tableRows = buildTableRows()
    tableChanges.newRows = tableRows
    tableChanges.newSelectionIndex = tableRows.firstIndex(of: currentConfigName)
    NotificationCenter.default.post(Notification(name: .iinaInputConfListChanged, object: tableChanges))
    if currentConfigChanged {
      NotificationCenter.default.post(Notification(name: .iinaCurrentInputConfChanged))
    }
  }


  // Rebuilds & re-sorts the table names. Must not change the actual state of any member vars
  private func buildTableRows() -> [String] {
    var tableRowsNew: [String] = []

    // - default configs:
    tableRowsNew.append(contentsOf: InputConfDataStore.defaultConfigNamesSorted)

    // - user: explicitly sort (ignoring case)
    var userConfigNameList: [String] = []
    userConfigDict.forEach {
      userConfigNameList.append($0.key)
    }
    userConfigNameList.sort{$0.localizedCompare($1) == .orderedAscending}

    tableRowsNew.append(contentsOf: userConfigNameList)

    Logger.log("Rebuilt table rows (currentConfig='\(currentConfName)'): \(tableRowsNew)", level: .verbose)

    return tableRowsNew
  }
}
