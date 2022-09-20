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
  // MARK: Static section

  static let CONFIG_FILE_EXTENSION = "conf"

  // Immmutable default configs. These would be best combined into a SortedDictionary
  private static let defaultConfigNamesSorted = ["IINA Default", "mpv Default", "VLC Default", "Movist Default"]
  static let defaultConfigs: [String: String] = [
    "IINA Default": Bundle.main.path(forResource: "iina-default-input", ofType: CONFIG_FILE_EXTENSION, inDirectory: "config")!,
    "mpv Default": Bundle.main.path(forResource: "input", ofType: CONFIG_FILE_EXTENSION, inDirectory: "config")!,
    "VLC Default": Bundle.main.path(forResource: "vlc-default-input", ofType: CONFIG_FILE_EXTENSION, inDirectory: "config")!,
    "Movist Default": Bundle.main.path(forResource: "movist-default-input", ofType: CONFIG_FILE_EXTENSION, inDirectory: "config")!
  ]

  static func computeFilePath(forUserConfigName configName: String) -> String {
    return Utility.userInputConfDirURL.appendingPathComponent(configName + CONFIG_FILE_EXTENSION).path
  }

  // MARK: Non-static section start

  let appActiveBindingController = AppActiveBindingController()

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
        let defaultConfig = InputConfigDataStore.defaultConfigNamesSorted[0]
        Logger.log("Could not get pref: \(Preference.Key.currentInputConfigName.rawValue): will use default (\"\(defaultConfig)\")", level: .warning)
        return defaultConfig
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

  private var currentParsedConfigFile: ParsedInputConfigFile? = nil

  /*
   Contains names of all user configs, which are also the identifiers in the UI table.
   */
  private(set) var configTableRows: [String] = []

  // The unfiltered list of table rows
  private var bindingRowsAll: [ActiveBindingMeta] = []

  // The table rows currently displayed, which will change depending on the current filterString
  private var bindingRowsFlltered: [ActiveBindingMeta] = []

  // Should be kept current with the value which the user enters in the search box:
  private var filterString: String = ""

  private var observers: [NSObjectProtocol] = []

  init() {
    configTableRows = buildConfigTableRows()
    loadBindingsFromCurrentConfigFile()

    observers.append(NotificationCenter.default.addObserver(forName: .iinaAppActiveKeyBindingsChanged, object: nil, queue: .main, using: appActiveBindingsChanged))
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

    Logger.log("Rebuilt Config table rows (current='\(currentConfigName)'): \(configTableRowsNew)", level: .verbose)

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
    NotificationCenter.default.post(Notification(name: .iinaInputConfigTableShouldUpdate, object: configTableUpdate))
  }

  // MARK: Binding CRUD

  func getBindingRowCount() -> Int {
    return bindingRowsFlltered.count
  }

  // Avoids hard program crash if index is invalid (which would happen for array dereference)
  func getBindingRow(at index: Int) -> ActiveBindingMeta? {
    guard index >= 0 && index < bindingRowsFlltered.count else {
      return nil
    }
    return bindingRowsFlltered[index]
  }

  func isEditEnabledForBindingRow(_ rowIndex: Int) -> Bool {
    guard let row = self.getBindingRow(at: rowIndex) else {
      return false
    }
    return row.origin == .confFile
  }

  private func determimeInsertIndex(from requestedIndex: Int, isAfterNotAt: Bool = false) -> Int {
    var insertIndex: Int
    if requestedIndex < 0 {
      // snap to very beginning
      insertIndex = 0
    } else if requestedIndex >= bindingRowsAll.count {
      // snap to very end
      insertIndex = bindingRowsAll.count
    } else {
      if isFiltered() {
        insertIndex = bindingRowsAll.count  // default to end, in case something breaks

        // If there is an active filter, convert the filtered index to unfiltered index
        if let unfilteredIndex = resolveFilteredIndexToUnfilteredIndex(requestedIndex) {
          insertIndex = unfilteredIndex
        }
      } else {
        insertIndex = requestedIndex  // default to requested index
      }
      if isAfterNotAt {
        insertIndex += 1
        if insertIndex >= bindingRowsAll.count {
          insertIndex = bindingRowsAll.count
        }
      }
    }

    return insertIndex
  }

  func moveBindings(_ bindingList: [KeyMapping], to index: Int, isAfterNotAt: Bool = false) -> Int {
    let insertIndex = determimeInsertIndex(from: index, isAfterNotAt: isAfterNotAt)
    Logger.log("Movimg \(bindingList.count) bindings \(isAfterNotAt ? "after" : "to") to filtered index \(index), which equates to insert at unfiltered index \(insertIndex)", level: .verbose)

    if isFiltered() {
      clearFilter()
    }

    let movedBindingIDs = Set(bindingList.map { $0.bindingID! })

    // Divide all the rows into 3 groups: before + after the insert, + the insert itself.
    // Since each row will be moved in order from top to bottom, it's fairly easy to calculate where each row will go
    var beforeInsert: [ActiveBindingMeta] = []
    var afterInsert: [ActiveBindingMeta] = []
    var movedRows: [ActiveBindingMeta] = []
    var moveIndexPairs: [(Int, Int)] = []
    var newSelectedRows = IndexSet()
    var moveFromOffset = 0
    var moveToOffset = 0

    // Drag & Drop reorder algorithm: https://stackoverflow.com/questions/2121907/drag-drop-reorder-rows-on-nstableview
    for (origIndex, row) in bindingRowsAll.enumerated() {
      if let bindingID = row.binding.bindingID, movedBindingIDs.contains(bindingID) {
        if origIndex < insertIndex {
          // If we moved the row from above to below, all rows up to & including its new location get shifted up 1
          moveIndexPairs.append((origIndex + moveFromOffset, insertIndex - 1))
          newSelectedRows.insert(insertIndex + moveFromOffset - 1)
          moveFromOffset -= 1
        } else {
          moveIndexPairs.append((origIndex, insertIndex + moveToOffset))
          newSelectedRows.insert(insertIndex + moveToOffset)
          moveToOffset += 1
        }
        movedRows.append(row)
      } else if origIndex < insertIndex {
        beforeInsert.append(row)
      } else {
        afterInsert.append(row)
      }
    }
    let bindingRowsAllUpdated = beforeInsert + movedRows + afterInsert

    let tableUpdate = TableUpdateByRowIndex(.moveRows)
    Logger.log("MovePairs: \(moveIndexPairs)")
    tableUpdate.toMove = moveIndexPairs
    tableUpdate.newSelectedRows = newSelectedRows

    saveAndApplyBindingsStateUpdates(bindingRowsAllUpdated, tableUpdate)
    return insertIndex
  }

  // Returns the index of the first element which was ultimately inserted
  func insertNewBindings(relativeTo index: Int, isAfterNotAt: Bool = false, _ bindingList: [KeyMapping]) -> Int {
    let insertIndex = determimeInsertIndex(from: index, isAfterNotAt: isAfterNotAt)
    Logger.log("Inserting \(bindingList.count) bindings \(isAfterNotAt ? "after" : "to") unfiltered row index \(index) -> insert at \(insertIndex)", level: .verbose)

    if isFiltered() {
      // If a filter is active, disable it. Otherwise the new row may be hidden by the filter, which might confuse the user.
      // This will cause the UI to reload the table. We will do the insert as a separate step, because a "reload" is a sledgehammer which
      // doesn't support animation and also blows away selections and editors.
      clearFilter()
    }

    let tableUpdate = TableUpdateByRowIndex(.addRows)
    tableUpdate.toInsert = IndexSet(insertIndex..<(insertIndex+bindingList.count))
    tableUpdate.newSelectedRows = tableUpdate.toInsert!

    var bindingRowsAllUpdated = bindingRowsAll
    for binding in bindingList.reversed() {
      bindingRowsAllUpdated.insert(ActiveBindingMeta(binding, origin: .confFile, srcSectionName: MPVInputSection.DEFAULT_SECTION_NAME, isMenuItem: false, isEnabled: true), at: insertIndex)
    }

    saveAndApplyBindingsStateUpdates(bindingRowsAllUpdated, tableUpdate)
    return insertIndex
  }

  // Returns the index at which it was ultimately inserted
  func insertNewBinding(relativeTo index: Int, isAfterNotAt: Bool = false, _ binding: KeyMapping) -> Int {
    return insertNewBindings(relativeTo: index, isAfterNotAt: isAfterNotAt, [binding])
  }

  // Finds the index into bindingRowsAll corresponding to the row with the same bindingID as the row with filteredIndex into bindingRowsFlltered.
  private func resolveFilteredIndexToUnfilteredIndex(_ filteredIndex: Int) -> Int? {
    guard filteredIndex >= 0 else {
      return nil
    }
    if filteredIndex == bindingRowsFlltered.count {
      let filteredRowAtIndex = bindingRowsFlltered[filteredIndex - 1]

      guard let unfilteredIndex = findUnfilteredIndexOfActiveBindingMeta(filteredRowAtIndex) else {
        return nil
      }
      return unfilteredIndex + 1
    }
    let filteredRowAtIndex = bindingRowsFlltered[filteredIndex]
    return findUnfilteredIndexOfActiveBindingMeta(filteredRowAtIndex)
  }

  private func findUnfilteredIndexOfActiveBindingMeta(_ row: ActiveBindingMeta) -> Int? {
    if let bindingID = row.binding.bindingID {
      for (unfilteredIndex, unfilteredRow) in bindingRowsAll.enumerated() {
        if unfilteredRow.binding.bindingID == bindingID {
          Logger.log("Found matching bindingID \(bindingID) at unfiltered row index \(unfilteredIndex)", level: .verbose)
          return unfilteredIndex
        }
      }
    }
    Logger.log("Failed to find unfiltered row index for: \(row)", level: .error)
    return nil
  }

  private func resolveBindingIDsFromIndexes(_ indexes: IndexSet, excluding isExcluded: ((ActiveBindingMeta) -> Bool)?) -> Set<Int> {
    var idSet = Set<Int>()
    for index in indexes {
      if let row = getBindingRow(at: index) {
        if let id = row.binding.bindingID {
          if let isExcluded = isExcluded, isExcluded(row) {
          } else {
            idSet.insert(id)
          }
        } else {
          Logger.log("Cannot remove row at index \(index): binding has no ID!", level: .error)
        }
      }
    }
    return idSet
  }

  func removeBindings(at indexesToRemove: IndexSet) {
    Logger.log("Removing bindings (\(indexesToRemove))", level: .verbose)

    // If there is an active filter, the indexes reflect filtered rows.
    // Let's get the underlying IDs of the removed rows so that we can reliably update the unfiltered list of bindings.
    let idsToRemove = resolveBindingIDsFromIndexes(indexesToRemove, excluding: { !$0.isEditableByUser })

    if idsToRemove.isEmpty {
      Logger.log("Aborting remove operation: none of the rows can be modified")
      return
    }

    var remainingRowsUnfiltered: [ActiveBindingMeta] = []
    for row in bindingRowsAll {
      if let id = row.binding.bindingID, idsToRemove.contains(id) {
      } else {
        // be sure to include rows which do not have IDs
        remainingRowsUnfiltered.append(row)
      }
    }

    let tableUpdate = TableUpdateByRowIndex(.removeRows)
    tableUpdate.toRemove = indexesToRemove

    saveAndApplyBindingsStateUpdates(remainingRowsUnfiltered, tableUpdate)
  }

  func removeBindings(withIDs idsToRemove: [Int]) {
    Logger.log("Removing bindings with IDs (\(idsToRemove))", level: .verbose)

    // If there is an active filter, the indexes reflect filtered rows.
    // Let's get the underlying IDs of the removed rows so that we can reliably update the unfiltered list of bindings.
    var remainingRowsUnfiltered: [ActiveBindingMeta] = []
    var indexesToRemove = IndexSet()
    for (rowIndex, row) in bindingRowsAll.enumerated() {
      if let id = row.binding.bindingID {
        // Non-editable rows probably do not have IDs, but check editable status to be sure
        if idsToRemove.contains(id) && row.isEditableByUser {
          indexesToRemove.insert(rowIndex)
          continue
        }
      }
      // Be sure to include rows which do not have IDs
      remainingRowsUnfiltered.append(row)
    }

    let tableUpdate = TableUpdateByRowIndex(.removeRows)
    tableUpdate.toRemove = indexesToRemove

    saveAndApplyBindingsStateUpdates(remainingRowsUnfiltered, tableUpdate)
  }

  func updateBinding(at index: Int, to binding: KeyMapping) {
    Logger.log("Updating binding at index \(index) to: \(binding)", level: .verbose)

    guard let existingRow = getBindingRow(at: index), existingRow.isEditableByUser else {
      Logger.log("Cannot update binding at index \(index); aborting", level: .error)
      return
    }

    existingRow.binding = binding

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
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingSearchFieldShouldUpdate, object: ""))
  }

  func filterBindings(_ searchString: String) {
    Logger.log("Updating Bindings Table filter: \"\(searchString)\"", level: .verbose)
    self.filterString = searchString
    applyBindingTableUpdates(bindingRowsAll, TableUpdateByRowIndex(.reloadAll))
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

  private func saveAndApplyBindingsStateUpdates(_ bindingRowsAllNew: [ActiveBindingMeta], _ tableUpdate: TableUpdateByRowIndex) {
    guard let defaultSectionBindings = saveBindingsToCurrentConfigFile(bindingRowsAllNew) else {
      return
    }

    applyDefaultSectionUpdates(defaultSectionBindings, tableUpdate)
  }

  private func applyDefaultSectionUpdates(_ defaultSectionBindings: [KeyMapping], _ tableUpdate: TableUpdateByRowIndex) {
    // Send to AppActiveBindingController to ingest. It will return the updated list of rows.
    // Note: we rely on the assumption that we know which rows will be added
    // and removed, and that information is contained in `tableUpdate`.
    // This is needed so that animations can work. But AppActiveBindingController
    // builds the actual row data, and the two must match or else visual bugs will result.
    let bindingRowsAllNew = appActiveBindingController.replaceDefaultSectionBindings(defaultSectionBindings)
    guard bindingRowsAllNew.count >= defaultSectionBindings.count else {
      Logger.log("Something went wrong: output binding count (\(bindingRowsAllNew.count)) is less than input bindings count (\(defaultSectionBindings.count))", level: .error)
      return
    }

    applyBindingTableUpdates(bindingRowsAllNew, tableUpdate)
  }

  // General purpose update
  private func applyBindingTableUpdates(_ bindingRowsAllNew: [ActiveBindingMeta], _ tableUpdate: TableUpdateByRowIndex) {
    bindingRowsAll = bindingRowsAllNew
    updateFilteredBindings()

    // Notify Key Bindings table of update:
    let notification = Notification(name: .iinaKeyBindingsTableShouldUpdate, object: tableUpdate)
    Logger.log("Posting '\(notification.name.rawValue)' notification with changeType \(tableUpdate.changeType)", level: .verbose)
    NotificationCenter.default.post(notification)
  }

  private func saveBindingsToCurrentConfigFile(_ bindingLines: [ActiveBindingMeta]) -> [KeyMapping]? {
    guard let configFilePath = requireCurrentFilePath() else {
      return nil
    }
    let defaultSectionBindings = extractConfFileBindings(bindingLines)
    Logger.log("Saving \(defaultSectionBindings.count) bindings to current config file: \"\(configFilePath)\"", level: .verbose)
    do {
      guard let currentParsedConfig = currentParsedConfigFile else {
        Logger.log("Cannot save bindings updates to file: could not find file in memory!", level: .error)
        return nil
      }
      currentParsedConfig.replaceAllBindings(with: defaultSectionBindings)
      try currentParsedConfig.write(to: configFilePath)
      return currentParsedConfig.parseBindings()  // gets updated line numbers
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
    guard let configContent = ParsedInputConfigFile.loadFile(at: configFilePath) else {
      // on error
      Logger.log("Error loading key bindings from config \"\(self.currentConfigName)\", at path: \"\(configFilePath)\"", level: .error)
      let fileName = URL(fileURLWithPath: configFilePath).lastPathComponent
      let alertInfo = AlertInfo(key: "keybinding_config.error", args: [fileName])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))

      changeCurrentConfigToDefault()
      return
    }
    self.currentParsedConfigFile = configContent

    let defaultSectionBindings = configContent.parseBindings()
    applyDefaultSectionUpdates(defaultSectionBindings, TableUpdateByRowIndex(.reloadAll))
  }

  private func extractConfFileBindings(_ bindingLines: [ActiveBindingMeta]) -> [KeyMapping] {
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

  // Callback for when Plugin menu bindings or active player bindings have changed
  private func appActiveBindingsChanged(_ notification: Notification) {
    guard let bindingRowsAllNew = notification.object as? [ActiveBindingMeta] else {
      Logger.log("Notification.iinaAppActiveKeyBindingsChanged: invalid object: \(type(of: notification.object))", level: .error)
      return
    }
    Logger.log("Got '\(notification.name.rawValue)' notification with \(bindingRowsAllNew.count) bindings", level: .verbose)

    // FIXME: calculate diff, use animation
    let tableUpdate = TableUpdateByRowIndex(.reloadAll)

    applyBindingTableUpdates(bindingRowsAllNew, tableUpdate)
  }
}
