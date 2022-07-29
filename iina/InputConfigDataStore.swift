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
 Controls access & restricts updates to support being used as a backing store for an NSTableView, but does not contain any UI code.
 Not thread-safe at present!
 */
class InputConfigDataStore {
  static let CONFIG_FILE_EXTENSION = "conf"

  // Immmutable default configs.
  // TODO: these would be best combined into a SortedDictionary
  private static let defaultConfigNamesSorted = ["IINA Default", "mpv Default", "VLC Default", "Movist Default"]
  static let defaultConfigs: [String: String] = [
    "IINA Default": Bundle.main.path(forResource: "iina-default-input", ofType: CONFIG_FILE_EXTENSION, inDirectory: "config")!,
    "mpv Default": Bundle.main.path(forResource: "input", ofType: CONFIG_FILE_EXTENSION, inDirectory: "config")!,
    "VLC Default": Bundle.main.path(forResource: "vlc-default-input", ofType: CONFIG_FILE_EXTENSION, inDirectory: "config")!,
    "Movist Default": Bundle.main.path(forResource: "movist-default-input", ofType: CONFIG_FILE_EXTENSION, inDirectory: "config")!
  ]

  static func computeFilePath(forUserConfigName configName: String) -> String {
    return Utility.userInputConfDirURL.appendingPathComponent(configName + ".config").path
  }

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
  var currentConfigName: String {
    get {
      guard let currentConfig = Preference.string(for: .currentInputConfigName) else {
        Logger.fatal("Cannot get pref: \(Preference.Key.currentInputConfigName.rawValue)!")
      }
      Logger.log("Returning currentConfigName='\(currentConfig)'", level: .verbose)
      return currentConfig
    }
    // no setter. See: changeCurrentConfig()
  }

  var currentConfigFilePath: String? {
    get {
      let currentConfig = currentConfigName
      if let filePath = InputConfigDataStore.defaultConfigs[currentConfig] {
        Logger.log("Found file path for default inputConfig '\(currentConfig)': \"\(filePath)\"", level: .verbose)
        return filePath
      }
      if let filePath = userConfigDict[currentConfig] {
        Logger.log("Found file path for user inputConfig '\(currentConfig)': \"\(filePath)\"", level: .verbose)
        if URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent != currentConfig {
          Logger.log("InputConfig's name '\(currentConfig)' does not match its filename: \"\(filePath)\"", level: .warning)
        }
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

  private(set) var bindingTableRows: [KeyMapping] = []

  private var observers: [NSObjectProtocol] = []

  init() {
    configTableRows = buildCofigTableRows()
    loadBindingsForCurrentConfig()

    observers.append(NotificationCenter.default.addObserver(forName: .iinaKeyBindingChanged, object: nil, queue: .main, using: saveToCurrentConfigFile))
    observers.append(NotificationCenter.default.addObserver(forName: .iinaGlobalKeyBindingsChanged, object: nil, queue: .main, using: onNewGlobalBindingsSet))
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }

  func isEditEnabledForCurrentConfig() -> Bool {
    return !isDefaultConfig(currentConfigName)
  }

  func isDefaultConfig(_ configName: String) -> Bool {
    return InputConfigDataStore.defaultConfigs[configName] != nil
  }

  func getFilePath(forConfig config: String) -> String? {
    if let dv = InputConfigDataStore.defaultConfigs[config] {
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

  // Avoids hard program crash if index is invalid (which would happen for array dereference)
  func getBindingRow(at index: Int) -> KeyMapping? {
    guard index >= 0 && index < bindingTableRows.count else {
      return nil
    }
    return bindingTableRows[index]
  }

  func changeCurrentConfigToDefault() {
    Logger.log("Changing current config to default", level: .verbose)
    changeCurrentConfig(0)  // using this call will avoid an infinite loop if the default config cannot be loaded
  }

  func changeCurrentConfig(_ newIndex: Int) {
    Logger.log("Changing current input config, newIndex=\(newIndex)", level: .verbose)
    guard let configName = getConfigRow(at: newIndex) else {
      Logger.log("Cannot change current config: invalid index: \(newIndex)", level: .error)
      return
    }
    changeCurrentConfig(configName)
  }

  // This is the only method other than updateState() which actually changes the real preference data
  func changeCurrentConfig(_ configName: String) {
    guard !configName.equalsIgnoreCase(self.currentConfigName) else {
      Logger.log("No need to persist change to current config '\(configName)'; it is already current", level: .verbose)
      return
    }
    guard configTableRows.contains(configName) else {
      Logger.log("Could not change current config to '\(configName)' (not found in table); falling back to default config", level: .error)
      changeCurrentConfigToDefault()
      return
    }

    guard let filePath = getFilePath(forConfig: configName) else {
      Logger.log("Could not change current config to '\(configName)' (no entry in prefs); falling back to default config", level: .error)
      changeCurrentConfigToDefault()
      return
    }

    updateCurrentConfigState(configName: configName, confFilePath: filePath)

    Logger.log("Current input config changed: '\(self.currentConfigName)' -> '\(configName)'")
    NotificationCenter.default.post(Notification(name: .iinaCurrentInputConfigChanged))
  }

  // Adds (or updates) config file with the given name into the user configs list preference, and sets it as the current config.
  // Posts update notification
  func addUserConfig(name: String, filePath: String) {
    Logger.log("Adding user config: \"\(name)\" (filePath: \(filePath))")
    var userConfDictUpdated = userConfigDict
    userConfDictUpdated[name] = filePath
    updateState(userConfDictUpdated, currentConfigNameUpdated: name, .addRows)
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
    updateState(userConfDictUpdated, currentConfigNameUpdated: newCurrentConfig, .addRows)
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
    updateState(userConfDictUpdated, currentConfigNameUpdated: newCurrentConfName, .removeRows)
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

    let newFilePath = InputConfigDataStore.computeFilePath(forUserConfigName: newName)
    userConfDictUpdated[newName] = newFilePath

    updateState(userConfDictUpdated, currentConfigNameUpdated: newName, .renameAndMoveOneRow)

    return true
  }

  // Replaces the current state with the given params, and fires listeners.
  private func updateState(_ userConfigDict: [String: String], currentConfigNameUpdated: String, _ changeType: TableStateChange.ChangeType) {
    let configTableChanges = TableStateChange(changeType)
    configTableChanges.oldRows = configTableRows

    let currentConfigChanged = self.currentConfigName != currentConfigNameUpdated

    Logger.log("Saving prefs: currentInputConfigName='\(currentConfigNameUpdated)', inputConfigs='\(userConfigDict)'", level: .verbose)
    guard let confFilePath = userConfigDict[currentConfigNameUpdated] else {
      Logger.log("Cannot update: '\(currentConfigNameUpdated)' not found in supplied config dict (\(userConfigDict))", level: .error)
      return
    }
    Preference.set(userConfigDict, for: .inputConfigs)
    // Keep in mind that if a failure happens this may end up changing currentConfigName to a different value than what goes in here:
    updateCurrentConfigState(configName: currentConfigNameUpdated, confFilePath: confFilePath)

    // refresh
    configTableRows = buildCofigTableRows()
    configTableChanges.newRows = configTableRows
    configTableChanges.newSelectionIndex = configTableRows.firstIndex(of: self.currentConfigName)

    // finally, fire listeners
    NotificationCenter.default.post(Notification(name: .iinaInputConfigListChanged, object: configTableChanges))
    if currentConfigChanged {
      NotificationCenter.default.post(Notification(name: .iinaCurrentInputConfigChanged))
    }
  }

  func addBinding(_ row: Int, _ binding: KeyMapping) {
    // TODO

    NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
  }

  func removeBindings(at indexes: IndexSet) {
    // TODO

    NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
  }

  private func updateCurrentConfigState(configName: String, confFilePath: String) {
    Preference.set(configName, for: .currentInputConfigName)

    loadBindingsForCurrentConfig()

    setKeybindingsForPlayerCore(bindingTableRows)
  }

  private func loadBindingsForCurrentConfig() {
    guard let configFilePath = currentConfigFilePath else {
      Logger.log("loadConfigFile(): could not find current config file; falling back to default config", level: .error)
      changeCurrentConfigToDefault()
      return
    }
    Logger.log("Loading key bindings config from \"\(configFilePath)\"")
    guard let keyBindingList = KeyMapping.parseInputConf(at: configFilePath) else {
      // on error
      Logger.log("Error loading key bindings config from \"\(configFilePath)\"", level: .error)
      let fileName = URL(fileURLWithPath: configFilePath).lastPathComponent
      let alertInfo = AlertInfo(key: "keybinding_config.error", args: [fileName])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))

      changeCurrentConfigToDefault()
      return
    }

    bindingTableRows = keyBindingList
  }

  // Rebuilds & re-sorts the table names. Must not change the actual state of any member vars
  private func buildCofigTableRows() -> [String] {
    var configTableRowsNew: [String] = []

    // - default configs:
    configTableRowsNew.append(contentsOf: InputConfigDataStore.defaultConfigNamesSorted)

    // - user: explicitly sort (ignoring case)
    var userConfigNameList: [String] = []
    userConfigDict.forEach {
      userConfigNameList.append($0.key)
    }
    userConfigNameList.sort{$0.localizedCompare($1) == .orderedAscending}

    configTableRowsNew.append(contentsOf: userConfigNameList)

    Logger.log("Rebuilt table rows (currentConfig='\(currentConfigName)'): \(configTableRowsNew)", level: .verbose)

    return configTableRowsNew
  }


  private func saveToCurrentConfigFile(_ notification: Notification) {
    guard let configFilePath = requireCurrentFilePath() else {
      return
    }
    let keyBindingList = bindingTableRows
    setKeybindingsForPlayerCore(keyBindingList)
    do {
      try KeyMapping.generateInputConf(from: keyBindingList).write(toFile: configFilePath, atomically: true, encoding: .utf8)
    } catch {
      let alertInfo = AlertInfo(key: "config.cannot_write", args: [configFilePath])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
    }
  }

  private func requireCurrentFilePath() -> String? {
    if let filePath = currentConfigFilePath {
      return filePath
    }
    let alertInfo = AlertInfo(key: "error_finding_file", args: ["config"])
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
    return nil
  }

  private func setKeybindingsForPlayerCore(_ keyBindingList: [KeyMapping]) {
    PlayerCore.setKeyBindings(keyBindingList)
  }

  private func onNewGlobalBindingsSet(_ notification: Notification) {
    guard let globalDefaultBindings = notification.object as? [KeyMapping] else {
      Logger.log("onGlobalKeyBindingsChanged(): invalid object: \(type(of: notification.object))", level: .error)
      return
    }
    // TODO: use this to populate row metadata
  }
}
