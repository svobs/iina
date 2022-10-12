//
//  InputBindingTableStore.swift
//  iina
//
//  Created by Matt Svoboda on 9/20/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/*
 Encapsulates the user's list of user input config files via stored preferences.
 Provides create/remove/update/delete operations on the table, and also completely handles filtering,  but is decoupled from UI code so that everything is cleaner.
 Not thread-safe at present!
 Should not contain any API calls to UI code. Other classes should call this class's public methods to get & update data.
 This class is downstream from `AppInputConfig.current` and should be notified of any changes to it.
 */
class InputBindingTableStore {

  // MARK: State

  // The current state of the AppInputConfig on which the state of this table is based.
  // While in almost all cases this should be identical to AppInputConfig.current, it is way simpler and more performant
  // to allow some tiny amount of drift. We treat each AppInputConfig object as a read-only version of the application state,
  // and each new AppInputConfig is an atomic update which replaces the previously received one via asynchronous updates.
  private var appInputConfig = AppInputConfig.current

  // The current unfiltered list of table rows
  private var bindingRowsAll: [InputBinding] {
    appInputConfig.bindingCandidateList
  }

  // The table rows currently displayed, which will change depending on the current filterString
  private var bindingRowsFiltered: [InputBinding] = []

  // Should be kept current with the value which the user enters in the search box:
  private var filterString: String = ""

  // MARK: Bindings Table CRUD

  var bindingRowCount: Int {
    return bindingRowsFiltered.count
  }

  // Avoids hard program crash if index is invalid (which would happen for array dereference)
  func getBindingRow(at index: Int) -> InputBinding? {
    guard index >= 0 && index < bindingRowsFiltered.count else {
      return nil
    }
    return bindingRowsFiltered[index]
  }

  // TOOD: clean up this API at some point so that it takes [InputBinding] instead of [KeyMapping] like the others
  func moveBindings(_ bindingList: [KeyMapping], to index: Int, isAfterNotAt: Bool = false,
                    afterComplete: TableChange.CompletionHandler? = nil) -> Int {
    let insertIndex = getClosestValidInsertIndex(from: index, isAfterNotAt: isAfterNotAt)
    Logger.log("Movimg \(bindingList.count) bindings \(isAfterNotAt ? "after" : "to") to filtered index \(index), which equates to insert at unfiltered index \(insertIndex)", level: .verbose)

    if isFiltered() {
      clearFilter()
    }

    let movedBindingIDs = Set(bindingList.map { $0.bindingID! })

    // Divide all the rows into 3 groups: before + after the insert, + the insert itself.
    // Since each row will be moved in order from top to bottom, it's fairly easy to calculate where each row will go
    var beforeInsert: [InputBinding] = []
    var afterInsert: [InputBinding] = []
    var movedRows: [InputBinding] = []
    var moveIndexPairs: [(Int, Int)] = []
    var newSelectedRows = IndexSet()
    var moveFromOffset = 0
    var moveToOffset = 0

    // Drag & Drop reorder algorithm: https://stackoverflow.com/questions/2121907/drag-drop-reorder-rows-on-nstableview
    for (origIndex, row) in bindingRowsAll.enumerated() {
      if let bindingID = row.keyMapping.bindingID, movedBindingIDs.contains(bindingID) {
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

    let tableChange = TableChangeByRowIndex(.moveRows, completionHandler: afterComplete)
    Logger.log("MovePairs: \(moveIndexPairs)", level: .verbose)
    tableChange.toMove = moveIndexPairs
    tableChange.newSelectedRows = newSelectedRows

    saveAndPushDefaultSectionChange(bindingRowsAllUpdated, tableChange)
    return insertIndex
  }

  // TOOD: clean up this API at some point so that it takes [InputBinding] instead of [KeyMapping] like the others
  func insertNewBindings(relativeTo index: Int, isAfterNotAt: Bool = false, _ bindingList: [KeyMapping],
                         afterComplete: TableChange.CompletionHandler? = nil) {
    let insertIndex = getClosestValidInsertIndex(from: index, isAfterNotAt: isAfterNotAt)
    Logger.log("Inserting \(bindingList.count) bindings \(isAfterNotAt ? "after" : "to") unfiltered row index \(index) -> insert at \(insertIndex)", level: .verbose)

    if isFiltered() {
      // If a filter is active, disable it. Otherwise the new row may be hidden by the filter, which might confuse the user.
      // This will cause the UI to reload the table. We will do the insert as a separate step, because a "reload" is a sledgehammer which
      // doesn't support animation and also blows away selections and editors.
      clearFilter()
    }

    let tableChange = TableChangeByRowIndex(.addRows, completionHandler: afterComplete)
    let toInsert = IndexSet(insertIndex..<(insertIndex+bindingList.count))
    tableChange.toInsert = toInsert
    tableChange.newSelectedRows = toInsert

    var bindingRowsAllNew = bindingRowsAll
    for binding in bindingList.reversed() {
      // We can get away with making these assumptions about InputBinding fields, because only the "default" section can be modified by the user
      bindingRowsAllNew.insert(InputBinding(binding, origin: .confFile, srcSectionName: DefaultInputSection.NAME), at: insertIndex)
    }

    saveAndPushDefaultSectionChange(bindingRowsAllNew, tableChange)
  }

  // Returns the index at which it was ultimately inserted
  func insertNewBinding(relativeTo index: Int, isAfterNotAt: Bool = false, _ binding: KeyMapping,
                        afterComplete: TableChange.CompletionHandler? = nil) {
    insertNewBindings(relativeTo: index, isAfterNotAt: isAfterNotAt, [binding], afterComplete: afterComplete)
  }

  func removeBindings(at indexesToRemove: IndexSet) {
    Logger.log("Removing bindings (\(indexesToRemove))", level: .verbose)

    // If there is an active filter, the indexes reflect filtered rows.
    // Let's get the underlying IDs of the removed rows so that we can reliably update the unfiltered list of bindings.
    let idsToRemove = resolveBindingIDs(from: indexesToRemove, excluding: { !$0.isEditableByUser })

    if idsToRemove.isEmpty {
      Logger.log("Aborting remove operation: none of the rows can be modified")
      return
    }

    var remainingRowsUnfiltered: [InputBinding] = []
    for row in bindingRowsAll {
      if let id = row.keyMapping.bindingID, idsToRemove.contains(id) {
      } else {
        // be sure to include rows which do not have IDs
        remainingRowsUnfiltered.append(row)
      }
    }

    let tableChange = TableChangeByRowIndex(.removeRows)
    tableChange.toRemove = indexesToRemove

    saveAndPushDefaultSectionChange(remainingRowsUnfiltered, tableChange)
  }

  func removeBindings(withIDs idsToRemove: [Int]) {
    Logger.log("Removing bindings with IDs (\(idsToRemove))", level: .verbose)

    // If there is an active filter, the indexes reflect filtered rows.
    // Let's get the underlying IDs of the removed rows so that we can reliably update the unfiltered list of bindings.
    var remainingRowsUnfiltered: [InputBinding] = []
    var indexesToRemove = IndexSet()
    for (rowIndex, row) in bindingRowsAll.enumerated() {
      if let id = row.keyMapping.bindingID {
        // Non-editable rows probably do not have IDs, but check editable status to be sure
        if idsToRemove.contains(id) && row.isEditableByUser {
          indexesToRemove.insert(rowIndex)
          continue
        }
      }
      // Be sure to include rows which do not have IDs
      remainingRowsUnfiltered.append(row)
    }

    let tableChange = TableChangeByRowIndex(.removeRows)
    tableChange.toRemove = indexesToRemove

    Logger.log("Of \(idsToRemove.count) requested, (\(indexesToRemove.count) bindings will actually be removed", level: .verbose)
    saveAndPushDefaultSectionChange(remainingRowsUnfiltered, tableChange)
  }

  func updateBinding(at index: Int, to binding: KeyMapping) {
    Logger.log("Updating binding at index \(index) to: \(binding)", level: .verbose)

    guard let existingRow = getBindingRow(at: index), existingRow.isEditableByUser else {
      Logger.log("Cannot update binding at index \(index); aborting", level: .error)
      return
    }

    existingRow.keyMapping = binding

    let tableChange = TableChangeByRowIndex(.updateRows)

    tableChange.toUpdate = IndexSet(integer: index)

    var indexToUpdate: Int = index

    // Is a filter active?
    if isFiltered() {
      // The affected row will change index after the reload. Track it down before clearing the filter.
      if let unfilteredIndex = translateFilteredIndexToUnfilteredIndex(index) {
        indexToUpdate = unfilteredIndex
      }

      // Disable it. Otherwise the row update may then cause the row to be filtered out, which might confuse the user.
      // This will also trigger a full table reload, which will update our row for us, but we will still need to save the update to file.
      clearFilter()
    }

    tableChange.newSelectedRows = IndexSet(integer: indexToUpdate)
    saveAndPushDefaultSectionChange(bindingRowsAll, tableChange)
  }

  // MARK: Various support functions

  func isEditEnabledForBindingRow(_ rowIndex: Int) -> Bool {
    guard let row = self.getBindingRow(at: rowIndex) else {
      return false
    }
    return row.origin == .confFile
  }

  func getClosestValidInsertIndex(from requestedIndex: Int, isAfterNotAt: Bool = false) -> Int {
    var insertIndex: Int
    if requestedIndex < 0 {
      // snap to very beginning
      insertIndex = 0
    } else if requestedIndex >= bindingRowsAll.count {
      // snap to very end
      insertIndex = bindingRowsAll.count
    } else {
      insertIndex = requestedIndex  // default to requested index
    }

    // If there is an active filter, convert the filtered index to unfiltered index
    if isFiltered(), let unfilteredIndex = translateFilteredIndexToUnfilteredIndex(requestedIndex) {
      insertIndex = unfilteredIndex
    }

    // Adjust for insert cursor
    if isAfterNotAt {
      insertIndex = min(insertIndex + 1, bindingRowsAll.count)
    }

    // The "default" section is the only section which can be edited or changed.
    // If the insert cursor is outside the default section, then snap it to the nearest valid index.
    let ai = self.appInputConfig
    if insertIndex < ai.defaultSectionStartIndex {
      Logger.log("Insert index (\(insertIndex), origReq=\(requestedIndex)) is before the default section (\(ai.defaultSectionStartIndex) - \(ai.defaultSectionEndIndex)). Snapping it to index: \(ai.defaultSectionStartIndex)", level: .verbose)
      return ai.defaultSectionStartIndex
    }
    if insertIndex > ai.defaultSectionEndIndex {
      Logger.log("Insert index (\(insertIndex), origReq=\(requestedIndex)) is after the default section (\(ai.defaultSectionStartIndex) - \(ai.defaultSectionEndIndex)). Snapping it to index: \(ai.defaultSectionEndIndex)", level: .verbose)
      return ai.defaultSectionEndIndex
    }

    Logger.log("Returning insertIndex: \(insertIndex) from requestedIndex: \(requestedIndex)", level: .verbose)
    return insertIndex
  }

  // Finds the index into bindingRowsAll corresponding to the row with the same bindingID as the row with filteredIndex into bindingRowsFiltered.
  private func translateFilteredIndexToUnfilteredIndex(_ filteredIndex: Int) -> Int? {
    guard filteredIndex >= 0 else {
      return nil
    }
    if filteredIndex == bindingRowsFiltered.count {
      let filteredRowAtIndex = bindingRowsFiltered[filteredIndex - 1]

      guard let unfilteredIndex = findUnfilteredIndexOfInputBinding(filteredRowAtIndex) else {
        return nil
      }
      return unfilteredIndex + 1
    }
    let filteredRowAtIndex = bindingRowsFiltered[filteredIndex]
    return findUnfilteredIndexOfInputBinding(filteredRowAtIndex)
  }

  private func findUnfilteredIndexOfInputBinding(_ row: InputBinding) -> Int? {
    if let bindingID = row.keyMapping.bindingID {
      for (unfilteredIndex, unfilteredRow) in bindingRowsAll.enumerated() {
        if unfilteredRow.keyMapping.bindingID == bindingID {
          Logger.log("Found matching bindingID \(bindingID) at unfiltered row index \(unfilteredIndex)", level: .verbose)
          return unfilteredIndex
        }
      }
    }
    Logger.log("Failed to find unfiltered row index for: \(row)", level: .error)
    return nil
  }

  static private func resolveBindingIDs(from rows: [InputBinding]) -> Set<Int> {
    return rows.reduce(into: Set<Int>(), { (ids, row) in
      if let bindingID = row.keyMapping.bindingID {
        ids.insert(bindingID)
      }
    })
  }

  private func resolveBindingIDs(from rowIndexes: IndexSet, excluding isExcluded: ((InputBinding) -> Bool)? = nil) -> Set<Int> {
    var idSet = Set<Int>()
    for rowIndex in rowIndexes {
      if let row = getBindingRow(at: rowIndex) {
        if let id = row.keyMapping.bindingID {
          if let isExcluded = isExcluded, isExcluded(row) {
          } else {
            idSet.insert(id)
          }
        } else {
          Logger.log("Cannot resolve row at index \(rowIndex): binding has no ID!", level: .error)
        }
      }
    }
    return idSet
  }

  // Inverse of previous function
  static private func resolveIndexesFromBindingIDs(_ bindingIDs: Set<Int>, in rows: [InputBinding]) -> IndexSet {
    var indexSet = IndexSet()
    for targetID in bindingIDs {
      for (rowIndex, row) in rows.enumerated() {
        guard let rowID = row.keyMapping.bindingID else {
          Logger.log("Cannot resolve row at index \(rowIndex): binding has no ID!", level: .error)
          continue
        }
        if rowID == targetID {
          indexSet.insert(rowIndex)
        }
      }
    }
    return indexSet
  }

  // MARK: Filtering

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
    appInputConfigDidChange(appInputConfig)
  }

  private func updateFilteredBindings() {
    bindingRowsFiltered = InputBindingTableStore.filter(bindingRowsAll: bindingRowsAll, by: filterString)
  }

  private static func filter(bindingRowsAll: [InputBinding], by filterString: String) -> [InputBinding] {
    if filterString.isEmpty {
      return bindingRowsAll
    }
    return bindingRowsAll.filter {
      return $0.getKeyColumnDisplay(raw: true).localizedStandardContains(filterString)
        || $0.getActionColumnDisplay(raw: true).localizedStandardContains(filterString)
    }
  }

  // MARK: TableChange push & receive with other components

  /*
   Must execute sequentially:
   1. Save conf file, get updated default section rows
   2. Send updated default section bindings to InputBindingController. It will recalculate all bindings and re-bind appropriately, then
      returns the updated set of all bindings to us.
   3. Update this class's unfiltered list of bindings, and recalculate filtered list
   4. Push update to the Key Bindings table in the UI so it can be animated.
   */
  private func saveAndPushDefaultSectionChange(_ bindingRowsAllNew: [InputBinding], _ tableChange: TableChangeByRowIndex) {
    // Save to file. Note that all non-"default" rows in this list will be ignored, so there is no chance of corrupting a different section,
    // or of writing another section's bindings to the "default" section.
    let defaultSectionMappings = bindingRowsAllNew.filter({ $0.origin == .confFile }).map({ $0.keyMapping })
    let inputConfigFileHandler = (NSApp.delegate as! AppDelegate).inputConfigFileHandler
    guard let defaultSectionBindings = inputConfigFileHandler.saveBindingsToCurrentConfigFile(defaultSectionMappings) else {
      return
    }

    pushDefaultSectionChange(defaultSectionBindings, tableChange)
  }

  /*
   Send to InputBindingController to ingest. It will return the updated list of all rows.
   Note: we rely on the assumption that we know which rows will be added & removed, and that information is contained in `tableChange`.
   This is needed so that animations can work. But InputBindingController builds the actual row data,
   and the two must match or else visual bugs will result.
   */
  func pushDefaultSectionChange(_ defaultSectionBindings: [KeyMapping], _ tableChange: TableChangeByRowIndex? = nil) {
    InputSectionStack.replaceDefaultSectionBindings(defaultSectionBindings)

    DispatchQueue.main.async {
      let appInputConfigNew = AppInputConfig.rebuildCurrent(thenNotifyPrefsUI: false)
      guard appInputConfigNew.bindingCandidateList.count >= defaultSectionBindings.count else {
        Logger.log("Something went wrong: output binding count (\(appInputConfigNew.bindingCandidateList.count)) is less than input bindings count (\(defaultSectionBindings.count))", level: .error)
        return
      }

      self.appInputConfigDidChange(appInputConfigNew, tableChange)
    }
  }

  /*
   Does the following sequentially:
   - Update this class's unfiltered list of bindings, and recalculate filtered list
   - Push update to the Key Bindings table in the UI so it can be animated.
   Expected to be run on the main thread.
  */
  func appInputConfigDidChange(_ appInputConfigNew: AppInputConfig, _ tableChange: TableChangeByRowIndex? = nil) {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))

    // A table change animation can be calculated if not provided, which should be sufficient in most cases:
    let ultimateTableChange = tableChange ?? buildTableDiff(appInputConfigNew)

    self.appInputConfig = appInputConfigNew
    updateFilteredBindings()

    // Any change made could conceivably change other rows in the table. It's inexpensive to just reload all of them:
    ultimateTableChange.reloadAllExistingRows = true

    // Notify Key Bindings table of update:
    let notification = Notification(name: .iinaKeyBindingsTableShouldUpdate, object: ultimateTableChange)
    Logger.log("Posting '\(notification.name.rawValue)' notification with changeType \(ultimateTableChange.changeType)", level: .verbose)
    NotificationCenter.default.post(notification)
  }

  private func buildTableDiff(_ appInputConfigNew: AppInputConfig) -> TableChangeByRowIndex {
    let bindingRowsAllNew = appInputConfigNew.bindingCandidateList
    // Remember, the displayed table contents must reflect the *filtered* state.
    let bindingRowsAllNewFiltered = InputBindingTableStore.filter(bindingRowsAll: bindingRowsAllNew, by: filterString)
    return TableChangeByRowIndex.buildDiff(oldRows: bindingRowsFiltered, newRows: bindingRowsAllNewFiltered)
  }
}
