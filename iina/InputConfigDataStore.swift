//
//  InputConfPrefStore.swift
//  iina
//
//  Created by Matt Svoboda on 2022.07.04.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class BindingLineItem {
  enum Origin {
    case confFile
    case luaScript
    case iinaPlugin
  }

  var binding: KeyMapping
  var origin: Origin
  var isEnabled: Bool
  var isMenuItem: Bool

  init(_ binding: KeyMapping, origin: Origin, isEnabled: Bool, isMenuItem: Bool) {
    self.binding = binding
    self.origin = origin
    self.isEnabled = isEnabled
    self.isMenuItem = isMenuItem
  }
}

/*
 Encapsulates the user's UserConf stored preferences.
 Controls access & restricts updates to support being used as a backing store for an NSTableView, but does not contain any UI code.
 Not thread-safe at present!
 */
class InputConfigDataStore {
  // MARK: Static section

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

  private static let singletonInstance = InputConfigDataStore()

  static func computeFilePath(forUserConfigName configName: String) -> String {
    return Utility.userInputConfDirURL.appendingPathComponent(configName + CONFIG_FILE_EXTENSION).path
  }

  static func getInstance() -> InputConfigDataStore {
    return InputConfigDataStore.singletonInstance
  }

  // MARK: Non-static section start

  // Actual persisted data #1
  private var userConfigDict: [String: String] {
    get {
      guard let userConfigDict = Preference.dictionary(for: .inputConfigs) as? [String: String] else {
        Logger.fatal("Cannot get pref: \(Preference.Key.inputConfigs.rawValue)!")
      }
      return userConfigDict
    } set {
      Preference.set(newValue, for: .inputConfigs)
    }
  }

  // Actual persisted data #2
  private(set) var currentConfigName: String {
    get {
      guard let currentConfig = Preference.string(for: .currentInputConfigName) else {
        Logger.fatal("Cannot get pref: \(Preference.Key.currentInputConfigName.rawValue)!")
      }
      return currentConfig
    } set {
      Logger.log("Current input config changed: '\(self.currentConfigName)' -> '\(newValue)'")
      Preference.set(newValue, for: .currentInputConfigName)

      loadBindingsFromCurrentConfigFile()
    }
  }

  // Looks up the current config, then searches for it first in the user configs, theb the default configs,
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
      if let filePath = InputConfigDataStore.defaultConfigs[currentConfig] {
        Logger.log("Found file path for default inputConfig '\(currentConfig)': \"\(filePath)\"", level: .verbose)
        return filePath
      }
      Logger.log("Cannot find file path for inputConfig: '\(currentConfig)'", level: .error)
      return nil
    }
  }

  private var currentLoadedConfig: InputConfigFile? = nil

  /*
   Contains names of all user configs, which are also the identifiers in the UI table.
   */
  private(set) var configTableRows: [String] = []

  // The unfiltered list of table rows
  private var bindingRowsAll: [BindingLineItem] = []

  // The table rows currently displayed, which will change depending on the current filterString
  private var bindingRowsFlltered: [BindingLineItem] = []

  // Should be kept current with the value which the user enters in the search box:
  private var filterString: String = ""

  private var observers: [NSObjectProtocol] = []

  init() {
    configTableRows = buildConfigTableRows()
    loadBindingsFromCurrentConfigFile()
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }

  // MARK: Config CRUD

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

    let newFilePath = InputConfigDataStore.computeFilePath(forUserConfigName: newName)
    userConfDictUpdated[newName] = newFilePath

    setConfigTableState(userConfDictUpdated, currentConfigNameNew: newName, .renameAndMoveOneRow)

    return true
  }

  // Rebuilds & re-sorts the table names. Must not change the actual state of any member vars
  private func buildConfigTableRows() -> [String] {
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

  // Replaces the current state with the given params, and fires listeners.
  private func setConfigTableState(_ userConfigDictNew: [String: String]? = nil, currentConfigNameNew: String, _ changeType: TableUpdate.ChangeType) {
    let configTableUpdate = TableUpdateByRowID(changeType)
    configTableUpdate.oldRows = configTableRows

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
      // This will also trigger a file load and
      currentConfigName = currentConfigNameNew
    }

    configTableRows = buildConfigTableRows()
    configTableUpdate.newRows = configTableRows
    if let currentConfigIndex = configTableRows.firstIndex(of: self.currentConfigName) {
      configTableUpdate.newSelectedRows = IndexSet(integer: currentConfigIndex)
    }

    // Finally, fire notification. This covers row selection too
    NotificationCenter.default.post(Notification(name: .iinaInputConfigListDidChange, object: configTableUpdate))
  }

  // MARK: Binding CRUD

  func getBindingRowCount() -> Int {
    return bindingRowsFlltered.count
  }

  // Avoids hard program crash if index is invalid (which would happen for array dereference)
  func getBindingRow(at index: Int) -> BindingLineItem? {
    guard index >= 0 && index < bindingRowsFlltered.count else {
      return nil
    }
    return bindingRowsFlltered[index]
  }

  // Returns the index at which it was ultimately inserted
  func insertNewBinding(relativeTo index: Int, isAfterNotAt: Bool = false, _ binding: KeyMapping) -> Int {
    var insertIndex: Int
    if index < 0 {
      // snap to very beginning
      insertIndex = 0
    } else if index >= bindingRowsFlltered.count {
      // snap to very end
      insertIndex = bindingRowsAll.count
    } else {
      if isFiltered() {
        insertIndex = bindingRowsAll.count  // default to end, in case something breaks

        // If there is an active filter, convert the filtered index to unfiltered index
        if let unfilteredIndex = resolveFilteredIndexToUnfilteredIndex(index) {
          insertIndex = unfilteredIndex
        }
      } else {
        insertIndex = index  // default to requested index
      }
      if isAfterNotAt {
        insertIndex += 1
        if insertIndex >= bindingRowsAll.count {
          insertIndex = bindingRowsAll.count
        }
      }
    }
    Logger.log("Inserting new binding at unfiltered row index \(insertIndex): \(binding)", level: .verbose)


    if isFiltered() {
      // If a filter is active, disable it. Otherwise the new row may be hidden by the filter, which might confuse the user.
      // This will cause the UI to reload the table. We will do the insert as a separate step, because a "reload" is a sledgehammer which
      // doesn't support animation and also blows away selections and editors.
      clearFilter()
    }

    let tableUpdateInsert = TableUpdateByRowIndex(.addRows)
    tableUpdateInsert.toInsert = IndexSet(integer: insertIndex)
    tableUpdateInsert.newSelectedRows = tableUpdateInsert.toInsert!

    var updatedTRs = bindingRowsAll
    updatedTRs.insert(BindingLineItem(binding, origin: .confFile, isEnabled: true, isMenuItem: false), at: insertIndex)

    saveAndApplyBindingsStateUpdates(updatedTRs, tableUpdateInsert)
    return insertIndex
  }

  // Finds the index into bindingRowsAll corresponding to the row with the same bindingID as the row with filteredIndex into bindingRowsFlltered.
  private func resolveFilteredIndexToUnfilteredIndex(_ filteredIndex: Int) -> Int? {
    guard filteredIndex >= 0 || filteredIndex < bindingRowsFlltered.count else {
      return nil
    }
    let bindingAtIndex = bindingRowsFlltered[filteredIndex]
    if let bindingID = bindingAtIndex.binding.bindingID {
      for (unfilteredIndex, row) in bindingRowsAll.enumerated() {
        if row.binding.bindingID == bindingID {
          Logger.log("Found matching bindingID \(bindingID) at unfiltered row index \(unfilteredIndex)", level: .verbose)
          return unfilteredIndex
        }
      }
    }
    return nil
  }

  private func reoolveBindingIDsFromIndexes(_ indexes: IndexSet) -> Set<Int> {
    var idSet = Set<Int>()
    for index in indexes {
      if let row = getBindingRow(at: index) {
        if let id = row.binding.bindingID {
          idSet.insert(id)
        } else {
          Logger.log("Cannot remove row at index \(index): binding has no ID!", level: .error)
        }
      }
    }
    return idSet
  }

  func removeBindings(at indexes: IndexSet) {
    Logger.log("Removing bindings (\(indexes))", level: .verbose)

    // If there is an active filter, the indexes reflect filtered rows.
    // Let's get the underlying IDs of the removed rows so that we can reliably update the unfiltered list of bindings.
    let idsToRemove = reoolveBindingIDsFromIndexes(indexes)

    var remainingRowsUnfiltered: [BindingLineItem] = []
    for row in bindingRowsAll {
      if let id = row.binding.bindingID, !idsToRemove.contains(id) {
        remainingRowsUnfiltered.append(row)
      }
    }

    let tableUpdate = TableUpdateByRowIndex(.removeRows)
    tableUpdate.toRemove = indexes

    saveAndApplyBindingsStateUpdates(remainingRowsUnfiltered, tableUpdate)
  }

  func updateBinding(at index: Int, to binding: KeyMapping) {
    Logger.log("Updating binding at index \(index) to: \(binding)", level: .verbose)

    if let existingRow = getBindingRow(at: index) {
      existingRow.binding = binding
    }

    let tableUpdate = TableUpdateByRowIndex(.updateRows)

    tableUpdate.toUpdate = IndexSet(integer: index)

    var indexToUpdate: Int = index

    // Is a filter active?
    if isFiltered() {
      // The affected row will change index after the reload. Track it down before clearing the filter.
      if let unfilteredIndex = resolveFilteredIndexToUnfilteredIndex(index) {
        indexToUpdate = unfilteredIndex
      }

      // Disable it. Otherwise the row update may then cause the row to be filtered out, which might confuse the user.
      // This will also trigger a full table reload, which will update our row for us, but we will still need to save the update to file.
      clearFilter()
    }

    tableUpdate.newSelectedRows = IndexSet(integer: indexToUpdate)
    saveAndApplyBindingsStateUpdates(bindingRowsAll, tableUpdate)
  }

  private func isFiltered() -> Bool {
    return !filterString.isEmpty
  }

  private func clearFilter() {
    filterBindings("")
    // Tell search field to clear itself:
    NotificationCenter.default.post(Notification(name: .iinaUpdateKeyBindingSearchField, object: ""))
  }

  func filterBindings(_ searchString: String) {
    Logger.log("Updating Bindings Table filter: \"\(searchString)\"", level: .verbose)
    self.filterString = searchString
    updateFilteredBindings()
    NotificationCenter.default.post(Notification(name: .iinaCurrentBindingsDidChange, object: TableUpdateByRowIndex(.reloadAll)))
    // TODO: add code to maintain selection across reloads
  }

  private func updateFilteredBindings() {
    if isFiltered() {
      bindingRowsFlltered = bindingRowsAll.filter {
        $0.binding.rawKey.localizedStandardContains(filterString) || $0.binding.rawAction.localizedStandardContains(filterString)
      }
    } else {
      bindingRowsFlltered = bindingRowsAll
    }
  }

  private func saveAndApplyBindingsStateUpdates(_ bindingRowsAllNew: [BindingLineItem], _ tableUpdate: TableUpdateByRowIndex) {
    guard let configFileBindings = saveBindingsToCurrentConfigFile(bindingRowsAllNew) else {
      return
    }

    applyBindingsStateUpdates(configFileBindings, tableUpdate)
  }

  private func applyBindingsStateUpdates(_ configFileBindings: [KeyMapping], _ tableUpdate: TableUpdateByRowIndex) {
    // Send to PlayerInputController to ingest. It wil return the metadata we need
    let sharedPlayerBindings = PlayerInputController.applySharedBindingsFromInputConfFile(configFileBindings)
    assert(sharedPlayerBindings.count >= configFileBindings.count, "Something went wrong!")

    // TODO: add dropdown to UI: Preferences > Key Bindings to choose display for a single player vs shared
    bindingRowsAll = sharedPlayerBindings
    updateFilteredBindings()

    // Notify Key Bindings table of update:
    NotificationCenter.default.post(Notification(name: .iinaCurrentBindingsDidChange, object: tableUpdate))
  }

  private func saveBindingsToCurrentConfigFile(_ bindingLines: [BindingLineItem]) -> [KeyMapping]? {
    guard let configFilePath = requireCurrentFilePath() else {
      return nil
    }
    let configFileBindings = extractConfFileBindings(bindingLines)
    Logger.log("Saving \(configFileBindings.count) bindings to current config file: \"\(configFilePath)\"", level: .verbose)
    do {
      guard let currentConfig = currentLoadedConfig else {
        Logger.log("Cannot save bindings updates to file: could not find file in memory!", level: .error)
        return nil
      }
      currentConfig.replaceAllBindings(with: configFileBindings)
      try currentConfig.write(to: configFilePath)
      return currentConfig.parseBindings()  // gets updated line numbers
    } catch {
      Logger.log("Failed to save bindings updates to file: \(error)", level: .error)
      let alertInfo = AlertInfo(key: "config.cannot_write", args: [configFilePath])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
    }
    return nil
  }

  // Triggered any time `currentConfigName` is changed
  public func loadBindingsFromCurrentConfigFile() {
    guard let configFilePath = currentConfigFilePath else {
      Logger.log("Could not find file for current config (\"\(self.currentConfigName)\"); falling back to default config", level: .error)
      changeCurrentConfigToDefault()
      return
    }
    Logger.log("Loading key bindings config from \"\(configFilePath)\"")
    guard let configContent = InputConfigFile.loadFile(at: configFilePath) else {
      // on error
      Logger.log("Error loading key bindings from config \"\(self.currentConfigName)\", at path: \"\(configFilePath)\"", level: .error)
      let fileName = URL(fileURLWithPath: configFilePath).lastPathComponent
      let alertInfo = AlertInfo(key: "keybinding_config.error", args: [fileName])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))

      changeCurrentConfigToDefault()
      return
    }
    self.currentLoadedConfig = configContent

    let configFileBindings = configContent.parseBindings()
    applyBindingsStateUpdates(configFileBindings, TableUpdateByRowIndex(.reloadAll))
  }

  private func extractConfFileBindings(_ bindingLines: [BindingLineItem]) -> [KeyMapping] {
    return bindingLines.filter({ $0.origin == .confFile }).map({ $0.binding })
  }

  private func requireCurrentFilePath() -> String? {
    if let filePath = currentConfigFilePath {
      return filePath
    }
    let alertInfo = AlertInfo(key: "error_finding_file", args: ["config"])
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
    return nil
  }
}
