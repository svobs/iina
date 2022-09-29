//
//  ActiveBindingStore.swift
//  iina
//
//  Created by Matt Svoboda on 9/20/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Data store which serves as the single source of truth for the Key Bindings table in the Preferences UI.
// Encapsulates the logic for create/remove/update/delete operations on the table, and also completely handles filtering.
// Should not contain any API calls to UI code. Other classes should call this class's public methods to get & update data.
// This class must stay in sync with the ActiveBindingController, which handles the assembly of the rows.
class ActiveBindingStore {

  // MARK: State

  // The unfiltered list of table rows
  private var bindingRowsAll: [ActiveBinding] = []

  // The table rows currently displayed, which will change depending on the current filterString
  private var bindingRowsFlltered: [ActiveBinding] = []

  // Should be kept current with the value which the user enters in the search box:
  private var filterString: String = ""

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
      if let bindingID = row.mpvBinding.bindingID, movedBindingIDs.contains(bindingID) {
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
      bindingRowsAllUpdated.insert(ActiveBinding(binding, origin: .confFile, srcSectionName: DefaultInputSection.NAME, isMenuItem: false, isEnabled: true), at: insertIndex)
    }

    saveAndApplyBindingsStateUpdates(bindingRowsAllUpdated, tableUpdate)
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
    if let bindingID = row.mpvBinding.bindingID {
      for (unfilteredIndex, unfilteredRow) in bindingRowsAll.enumerated() {
        if unfilteredRow.mpvBinding.bindingID == bindingID {
          Logger.log("Found matching bindingID \(bindingID) at unfiltered row index \(unfilteredIndex)", level: .verbose)
          return unfilteredIndex
        }
      }
    }
    Logger.log("Failed to find unfiltered row index for: \(row)", level: .error)
    return nil
  }

  private func resolveBindingIDsFromIndexes(_ indexes: IndexSet, excluding isExcluded: ((ActiveBinding) -> Bool)?) -> Set<Int> {
    var idSet = Set<Int>()
    for index in indexes {
      if let row = getBindingRow(at: index) {
        if let id = row.mpvBinding.bindingID {
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

    var remainingRowsUnfiltered: [ActiveBinding] = []
    for row in bindingRowsAll {
      if let id = row.mpvBinding.bindingID, idsToRemove.contains(id) {
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
    var remainingRowsUnfiltered: [ActiveBinding] = []
    var indexesToRemove = IndexSet()
    for (rowIndex, row) in bindingRowsAll.enumerated() {
      if let id = row.mpvBinding.bindingID {
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

    existingRow.mpvBinding = binding

    let tableUpdate = TableUpdateByRowIndex(.updateRows)

    tableUpdate.toUpdate = IndexSet(integer: index)

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
        $0.mpvBinding.rawKey.localizedStandardContains(filterString) || $0.mpvBinding.rawAction.localizedStandardContains(filterString)
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
   3. Update the list of all bindings here.
   4. Push update to the Key Bindings table in the UI so it can be animated.
   */
  private func saveAndApplyBindingsStateUpdates(_ bindingRowsAllNew: [ActiveBinding], _ tableUpdate: TableUpdateByRowIndex) {
    // Save to file
    let defaultSectionBindings = bindingRowsAllNew.filter({ $0.origin == .confFile }).map({ $0.mpvBinding })
    let inputConfigStore = (NSApp.delegate as! AppDelegate).inputConfigStore
    guard let defaultSectionBindings = inputConfigStore.saveBindingsToCurrentConfigFile(defaultSectionBindings) else {
      return
    }

    applyDefaultSectionUpdates(defaultSectionBindings, tableUpdate)
  }

  /*
   Send to ActiveBindingController to ingest. It will return the updated list of all rows.
   Note: we rely on the assumption that we know which rows will be added & removed, and that information is contained in `tableUpdate`.
   This is needed so that animations can work. But ActiveBindingController builds the actual row data,
   and the two must match or else visual bugs will result.
   */
  func applyDefaultSectionUpdates(_ defaultSectionBindings: [KeyMapping], _ tableUpdate: TableUpdateByRowIndex) {
    PlayerInputConfig.replaceDefaultSectionBindings(defaultSectionBindings, onCompletion: { bindingRowsAllNew in

      guard bindingRowsAllNew.count >= defaultSectionBindings.count else {
        Logger.log("Something went wrong: output binding count (\(bindingRowsAllNew.count)) is less than input bindings count (\(defaultSectionBindings.count))", level: .error)
        return
      }

      self.applyBindingTableUpdates(bindingRowsAllNew, tableUpdate)
    })
  }

  /*
  - Update the list of all bindings here.
  - Push update to the Key Bindings table in the UI so it can be animated.
  */
  private func applyBindingTableUpdates(_ bindingRowsAllNew: [ActiveBinding], _ tableUpdate: TableUpdateByRowIndex) {
    bindingRowsAll = bindingRowsAllNew
    updateFilteredBindings()

    // Notify Key Bindings table of update:
    let notification = Notification(name: .iinaKeyBindingsTableShouldUpdate, object: tableUpdate)
    Logger.log("Posting '\(notification.name.rawValue)' notification with changeType \(tableUpdate.changeType)", level: .verbose)
    NotificationCenter.default.post(notification)
  }

  // Callback for when Plugin menu bindings or active player bindings have changed
  func appActiveBindingsDidChange(_ activeBindingList: [ActiveBinding]) {
    // FIXME: calculate diff, use animation
    let tableUpdate = TableUpdateByRowIndex(.reloadAll)

    applyBindingTableUpdates(activeBindingList, tableUpdate)
  }
}
