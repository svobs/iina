//
//  ActiveBindingTableStore.swift
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
 This class is downstream from `AppActiveBindings.current` and should be notified of any changes to it.
 */
class ActiveBindingTableStore {

  // MARK: State

  // The unfiltered list of table rows
  private var bindingRowsAll: [ActiveBinding] = []

  // The table rows currently displayed, which will change depending on the current filterString
  private var bindingRowsFlltered: [ActiveBinding] = []

  // Should be kept current with the value which the user enters in the search box:
  private var filterString: String = ""

  var selectedRowIndexes = IndexSet()

  // MARK: Bindings Table CRUD

  func getBindingRowCount() -> Int {
    return bindingRowsFlltered.count
  }

  // Avoids hard program crash if index is invalid (which would happen for array dereference)
  func getBindingRow(at index: Int) -> ActiveBinding? {
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
        if let unfilteredIndex = translateFilteredIndexToUnfilteredIndex(requestedIndex) {
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
    var beforeInsert: [ActiveBinding] = []
    var afterInsert: [ActiveBinding] = []
    var movedRows: [ActiveBinding] = []
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

    let tableChange = TableChangeByRowIndex(.moveRows)
    Logger.log("MovePairs: \(moveIndexPairs)")
    tableChange.toMove = moveIndexPairs
    tableChange.newSelectedRows = newSelectedRows

    saveAndApplyBindingsStateUpdates(bindingRowsAllUpdated, tableChange)
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

    let tableChange = TableChangeByRowIndex(.addRows)
    tableChange.toInsert = IndexSet(insertIndex..<(insertIndex+bindingList.count))
    tableChange.newSelectedRows = tableChange.toInsert!

    var bindingRowsAllUpdated = bindingRowsAll
    for binding in bindingList.reversed() {
      bindingRowsAllUpdated.insert(ActiveBinding(binding, origin: .confFile, srcSectionName: DefaultInputSection.NAME, isMenuItem: false, isEnabled: true), at: insertIndex)
    }

    saveAndApplyBindingsStateUpdates(bindingRowsAllUpdated, tableChange)
    return insertIndex
  }

  // Returns the index at which it was ultimately inserted
  func insertNewBinding(relativeTo index: Int, isAfterNotAt: Bool = false, _ binding: KeyMapping) -> Int {
    return insertNewBindings(relativeTo: index, isAfterNotAt: isAfterNotAt, [binding])
  }

  // Finds the index into bindingRowsAll corresponding to the row with the same bindingID as the row with filteredIndex into bindingRowsFlltered.
  private func translateFilteredIndexToUnfilteredIndex(_ filteredIndex: Int) -> Int? {
    guard filteredIndex >= 0 else {
      return nil
    }
    if filteredIndex == bindingRowsFlltered.count {
      let filteredRowAtIndex = bindingRowsFlltered[filteredIndex - 1]

      guard let unfilteredIndex = findUnfilteredIndexOfActiveBinding(filteredRowAtIndex) else {
        return nil
      }
      return unfilteredIndex + 1
    }
    let filteredRowAtIndex = bindingRowsFlltered[filteredIndex]
    return findUnfilteredIndexOfActiveBinding(filteredRowAtIndex)
  }

  private func findUnfilteredIndexOfActiveBinding(_ row: ActiveBinding) -> Int? {
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

  static private func getBindingIDs(from rows: [ActiveBinding]) -> Set<Int> {
    return rows.reduce(into: Set<Int>(), { (ids, row) in
      if let bindingID = row.keyMapping.bindingID {
        ids.insert(bindingID)
      }
    })
  }

  static private func getHashes(from rows: [ActiveBinding]) -> [String] {
    // Just use the content itself - should be shorter than an MD5 in most cases
    return rows.map({ $0.keyMapping.confFileFormat })
  }

  private func resolveBindingIDsFromIndexes(_ rowIndexes: IndexSet, excluding isExcluded: ((ActiveBinding) -> Bool)? = nil) -> Set<Int> {
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
  static private func resolveIndexesFromBindingIDs(_ bindingIDs: Set<Int>, in rows: [ActiveBinding]) -> IndexSet {
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

  func removeBindings(at indexesToRemove: IndexSet) {
    Logger.log("Removing bindings (\(indexesToRemove))", level: .verbose)

    // If there is an active filter, the indexes reflect filtered rows.
    // Let's get the underlying IDs of the removed rows so that we can reliably update the unfiltered list of bindings.
    let idsToRemove = resolveBindingIDsFromIndexes(indexesToRemove, excluding: { !$0.isEditableByUser })

    if idsToRemove.isEmpty {
      Logger.log("Aborting remove operation: none of the rows can be modified")
      return
    }

    var remainingRowsUnfiltered: [ActiveBinding] = []
    for row in bindingRowsAll {
      if let id = row.keyMapping.bindingID, idsToRemove.contains(id) {
      } else {
        // be sure to include rows which do not have IDs
        remainingRowsUnfiltered.append(row)
      }
    }

    let tableChange = TableChangeByRowIndex(.removeRows)
    tableChange.toRemove = indexesToRemove

    saveAndApplyBindingsStateUpdates(remainingRowsUnfiltered, tableChange)
  }

  func removeBindings(withIDs idsToRemove: [Int]) {
    Logger.log("Removing bindings with IDs (\(idsToRemove))", level: .verbose)

    // If there is an active filter, the indexes reflect filtered rows.
    // Let's get the underlying IDs of the removed rows so that we can reliably update the unfiltered list of bindings.
    var remainingRowsUnfiltered: [ActiveBinding] = []
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

    saveAndApplyBindingsStateUpdates(remainingRowsUnfiltered, tableChange)
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
    saveAndApplyBindingsStateUpdates(bindingRowsAll, tableChange)
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
    appActiveBindingsDidChange(bindingRowsAll)
  }

  private func updateFilteredBindings() {
    if isFiltered() {
      bindingRowsFlltered = bindingRowsAll.filter {
        $0.keyMapping.rawKey.localizedStandardContains(filterString) || $0.keyMapping.rawAction.localizedStandardContains(filterString)
      }
    } else {
      bindingRowsFlltered = bindingRowsAll
    }
  }

  /*
   Must execute sequentially:
   1. Save conf file, get updated default section rows
   2. Send updated default section bindings to ActiveBindingController. It will recalculate all bindings and re-bind appropriately, then
      returns the updated set of all bindings to us.
   3. Update this class's unfiltered list of bindings, and recalculate filtered list
   4. Push update to the Key Bindings table in the UI so it can be animated.
   */
  private func saveAndApplyBindingsStateUpdates(_ bindingRowsAllNew: [ActiveBinding], _ tableChange: TableChangeByRowIndex) {
    // Save to file
    let defaultSectionBindings = bindingRowsAllNew.filter({ $0.origin == .confFile }).map({ $0.keyMapping })
    let inputConfigFileHandler = (NSApp.delegate as! AppDelegate).inputConfigFileHandler
    guard let defaultSectionBindings = inputConfigFileHandler.saveBindingsToCurrentConfigFile(defaultSectionBindings) else {
      return
    }

    applyDefaultSectionUpdates(defaultSectionBindings, tableChange)
  }

  /*
   Send to ActiveBindingController to ingest. It will return the updated list of all rows.
   Note: we rely on the assumption that we know which rows will be added & removed, and that information is contained in `tableChange`.
   This is needed so that animations can work. But ActiveBindingController builds the actual row data,
   and the two must match or else visual bugs will result.
   */
  func applyDefaultSectionUpdates(_ defaultSectionBindings: [KeyMapping], _ tableChange: TableChangeByRowIndex) {
    InputSectionStack.replaceDefaultSectionBindings(defaultSectionBindings)

    DispatchQueue.main.async {
      let bindingRowsAllNew = PlayerInputConfig.rebuildAppBindings(thenNotifyPrefsUI: false).bindingCandidateList
      guard bindingRowsAllNew.count >= defaultSectionBindings.count else {
        Logger.log("Something went wrong: output binding count (\(bindingRowsAllNew.count)) is less than input bindings count (\(defaultSectionBindings.count))", level: .error)
        return
      }

      self.applyBindingTableChanges(bindingRowsAllNew, tableChange)
    }
  }

  /*
  - Update this class's unfiltered list of bindings, and recalculate filtered list
  - Push update to the Key Bindings table in the UI so it can be animated.
  Expected to be run on the main thread.
  */
  private func applyBindingTableChanges(_ bindingRowsAllNew: [ActiveBinding], _ tableChange: TableChangeByRowIndex) {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))

    let tableChangeImproved: TableChangeByRowIndex = (tableChange.changeType == .reloadAll ? buildBetterReloadAll(bindingRowsAllNew) : tableChange)

    bindingRowsAll = bindingRowsAllNew
    updateFilteredBindings()

    // Notify Key Bindings table of update:
    let notification = Notification(name: .iinaKeyBindingsTableShouldUpdate, object: tableChangeImproved)
    Logger.log("Posting '\(notification.name.rawValue)' notification with changeType \(tableChangeImproved.changeType)", level: .verbose)
    NotificationCenter.default.post(notification)
  }

  private func buildBetterReloadAll(_ bindingRowsAllNew: [ActiveBinding]) -> TableChangeByRowIndex {

    // FIXME: calculate diff, use animation

    let tableChange = TableChangeByRowIndex(.custom)

    let hashesBefore: [String] = ActiveBindingTableStore.getHashes(from: bindingRowsAll)
    let hashesAfter: [String] = ActiveBindingTableStore.getHashes(from: bindingRowsAllNew)

    // Maintain selection across reloads by comparing hashes
    let hashesSelectedBefore: Set<String> = selectedRowIndexes.reduce(into: Set<String>(), { (hashes, index) in
      if index < hashesBefore.count {
        hashes.insert(hashesBefore[index])
      }
    })



//    let newSelectedRowIndexes = ActiveBindingTableStore.resolveIndexesFromHashes(hashesSelected, in: bindingRowsAllNew)
//    tableChange.newSelectedRows = newSelectedRowIndexes
//    Logger.log("Bindings table update: translated \(selectedRowIndexes.count)/\(bindingRowsAll.count) selections to \(newSelectedRowIndexes.count)/\(bindingRowsAllNew.count)")

    tableChange.customFunction = { tableView in

    }

    return tableChange
  }

  // Callback for when Plugin menu bindings, active player bindings, or filtered bindings have changed.
  // Expected to be run on the main thread.
  func appActiveBindingsDidChange(_ bindingRowsAllNew: [ActiveBinding]) {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))

    self.applyBindingTableChanges(bindingRowsAllNew, buildBetterReloadAll(bindingRowsAllNew))
  }
}
