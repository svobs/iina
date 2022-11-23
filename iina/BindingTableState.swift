//
//  BindingTableState.swift
//  iina
//
//  Created by Matt Svoboda on 9/20/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/*
 Represents a snapshot of the state of tbe Key Bindings table, closely tied to an instance of `AppInputConfig.
 Like `AppInputConfig`, each instance is read-only and is designed to be rebuilt & replaced each time there is a change,
 to help ensure the integrity of its data. See `BindingTableStateManager` for all changes.
 Provides create/remove/update/delete operations on the table, and also completely handles filtering,  but is decoupled from UI code so that everything is cleaner.
 Should not contain any API calls to UI code. Other classes should call this class's public methods to get & update data.
 This class is downstream from `AppInputConfig.current`
 */
struct BindingTableState {
  static var current = BindingTableState(AppInputConfig.current, filterString: "", inputConfFile: nil)
  static let manager: BindingTableStateManager = BindingTableStateManager()

  init(_ appInputConfig: AppInputConfig, filterString: String, inputConfFile: InputConfFile?) {
    self.appInputConfig = appInputConfig
    self.inputConfFile = inputConfFile
    self.filterString = filterString
    self.filterBimap = BindingTableState.buildFilterBimap(from: appInputConfig.bindingCandidateList, by: filterString)
  }

  // MARK: Data

  // The state of the AppInputConfig on which the state of this table is based.
  // While in almost all cases this should be identical to AppInputConfig.current, it is way simpler and more performant
  // to allow some tiny amount of drift. We treat each AppInputConfig object as a read-only version of the application state,
  // and each new AppInputConfig is an atomic update which replaces the previously received one via asynchronous updates.
  let appInputConfig: AppInputConfig

  // The source user conf file
  let inputConfFile: InputConfFile?

  // Should be kept current with the value which the user enters in the search box:
  let filterString: String

  // The table rows currently displayed, which will change depending on the current filterString
  private let filterBimap: BiDictionary<Int, Int>?

  // The current unfiltered list of table rows
  private var bindingRowsAll: [InputBinding] {
    appInputConfig.bindingCandidateList
  }

  // MARK: Bindings Table CRUD

  var bindingRowCount: Int {
    if let filterBimap = filterBimap {
      return filterBimap.values.count
    }
    return bindingRowsAll.count
  }

  // Avoids hard program crash if index is invalid (which would happen for array dereference)
  func getDisplayedRow(at index: Int) -> InputBinding? {
    guard index >= 0 else { return nil }
    if let filterBimap = filterBimap {
      if let unfilteredIndex = filterBimap[value: index] {
        return bindingRowsAll[unfilteredIndex]
      }
    } else if  index < bindingRowsAll.count {
      return bindingRowsAll[index]
    }
    return nil
  }

  func moveBindings(at rowIndexes: IndexSet, to index: Int, isAfterNotAt: Bool = false,
                    afterComplete: TableUIChange.CompletionHandler? = nil) -> Int {
    let insertIndex = getClosestValidInsertIndex(from: index, isAfterNotAt: isAfterNotAt)
    Logger.log("Movimg \(rowIndexes.count) bindings \(isAfterNotAt ? "after" : "to") to filtered index \(index), which equates to insert at unfiltered index \(insertIndex)", level: .verbose)

    let unfilteredIndexes = getUnfilteredIndexes(fromFiltered: rowIndexes)

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
      if unfilteredIndexes.contains(origIndex) {
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

    let tableUIChange = TableUIChange(.moveRows, completionHandler: afterComplete)
    Logger.log("MovePairs: \(moveIndexPairs)", level: .verbose)
    tableUIChange.toMove = moveIndexPairs
    tableUIChange.newSelectedRows = newSelectedRows

    doAction(bindingRowsAllUpdated, tableUIChange)
    return insertIndex
  }

  func appendBindingsToDefaultSection(_ mappingList: [KeyMapping]) {
    insertNewBindings(relativeTo: appInputConfig.defaultSectionEndIndex, mappingList)
  }

  func insertNewBindings(relativeTo index: Int, isAfterNotAt: Bool = false, _ mappingList: [KeyMapping],
                         afterComplete: TableUIChange.CompletionHandler? = nil) {
    let insertIndex = getClosestValidInsertIndex(from: index, isAfterNotAt: isAfterNotAt)
    Logger.log("Inserting \(mappingList.count) bindings \(isAfterNotAt ? "after" : "into") unfiltered row index \(index) -> insert at \(insertIndex)", level: .verbose)
    guard canModifyCurrentConf else {
      Logger.log("Aborting: cannot modify current conf!", level: .error)
      return
    }

    let tableUIChange = TableUIChange(.addRows, completionHandler: afterComplete)
    let toInsert = IndexSet(insertIndex..<(insertIndex+mappingList.count))
    tableUIChange.toInsert = toInsert
    tableUIChange.newSelectedRows = toInsert

    var bindingRowsAllNew = bindingRowsAll
    for mapping in mappingList.reversed() {
      // We can get away with making these assumptions about InputBinding fields, because only the "default" section can be modified by the user
      bindingRowsAllNew.insert(InputBinding(mapping, origin: .confFile, srcSectionName: SharedInputSection.DEFAULT_SECTION_NAME), at: insertIndex)
    }

    doAction(bindingRowsAllNew, tableUIChange)
  }

  // Returns the index at which it was ultimately inserted
  func insertNewBinding(relativeTo index: Int, isAfterNotAt: Bool = false, _ mapping: KeyMapping,
                        afterComplete: TableUIChange.CompletionHandler? = nil) {
    insertNewBindings(relativeTo: index, isAfterNotAt: isAfterNotAt, [mapping], afterComplete: afterComplete)
  }

  func removeBindings(at indexes: IndexSet) {
    Logger.log("Removing bindings (\(indexes.map{$0}))", level: .verbose)
    guard canModifyCurrentConf else {
      Logger.log("Aborting: cannot modify current conf!", level: .error)
      return
    }

    // If there is an active filter, the indexes reflect filtered rows.
    // Need to submit changes for unfiltered operations
    let indexesToRemove = getUnfilteredIndexes(fromFiltered: indexes, excluding: { !$0.canBeModified })

    if indexesToRemove.isEmpty {
      Logger.log("Aborting remove operation: none of the rows can be modified")
      return
    }

    var remainingRowsUnfiltered: [InputBinding] = []
    var lastRemovedIndex = 0
    for (rowIndex, row) in bindingRowsAll.enumerated() {
      if indexesToRemove.contains(rowIndex) {
        lastRemovedIndex = rowIndex
      } else {
        remainingRowsUnfiltered.append(row)
      }
    }
    let tableUIChange = TableUIChange(.removeRows)
    tableUIChange.toRemove = indexesToRemove

    if TableUIChange.selectNextRowAfterDelete {
      // After removal, select the single row after the last one removed:
      let countRemoved = bindingRowsAll.count - remainingRowsUnfiltered.count
      if countRemoved < bindingRowsAll.count {
        let newSelectionIndex: Int = lastRemovedIndex - countRemoved + 1
        tableUIChange.newSelectedRows = IndexSet(integer: newSelectionIndex)
      }
    }

    doAction(remainingRowsUnfiltered, tableUIChange)
  }

  func updateBinding(at index: Int, to mapping: KeyMapping) {
    Logger.log("Updating binding at index \(index) to: \(mapping)", level: .verbose)
    guard canModifyCurrentConf else {
      Logger.log("Aborting: cannot modify current conf!", level: .error)
      return
    }

    guard let existingRow = getDisplayedRow(at: index), existingRow.canBeModified else {
      Logger.log("Cannot update binding at index \(index); aborting", level: .error)
      return
    }

    existingRow.keyMapping = mapping

    let tableUIChange = TableUIChange(.updateRows)

    tableUIChange.toUpdate = IndexSet(integer: index)

    var indexToUpdate: Int = index

    // The affected row will change index after the reload. Track it down before clearing the filter.
    if let unfilteredIndex = getFilteredIndex(fromUnfiltered: index) {
      indexToUpdate = unfilteredIndex
    }

    tableUIChange.newSelectedRows = IndexSet(integer: indexToUpdate)
    doAction(bindingRowsAll, tableUIChange)
  }

  // MARK: Various utility functions

  func isEditEnabledForBindingRow(_ rowIndex: Int) -> Bool {
    self.getDisplayedRow(at: rowIndex)?.canBeModified ?? false
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
    if let unfilteredIndex = getFilteredIndex(fromUnfiltered: requestedIndex) {
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

  // Both params should be calculated based on UNFILTERED rows.
  // Let BindingTableStateManager deal with altering animations with a filter
  private func doAction(_ bindingRowsAllNew: [InputBinding], _ tableUIChange: TableUIChange) {
    let defaultSectionNew = bindingRowsAllNew.filter({ $0.origin == .confFile }).map({ $0.keyMapping })
    BindingTableState.manager.doAction(defaultSectionNew, tableUIChange)
  }

  private var canModifyCurrentConf: Bool {
    if let currentConfigFile = self.inputConfFile, !currentConfigFile.isReadOnly {
      return true
    }
    return false
  }

  // MARK: Filtering

  private var isFiltered: Bool {
    return !filterString.isEmpty
  }

  func applyFilter(_ searchString: String) {
    Logger.log("Updating Bindings UI filter to \"\(searchString)\"", level: .verbose)
    BindingTableState.manager.applyFilter(newFilterString: searchString)
  }

  var bindingRowsFiltered: [InputBinding] {
    if let filterBimap = filterBimap {
      return bindingRowsAll.enumerated().compactMap({ filterBimap.keys.contains($0.offset) ? $0.element : nil })
    }
    return bindingRowsAll
  }

  // Returns the index into bindingRowsAll corresponding to the given filtered index.
  private func getFilteredIndex(fromUnfiltered index: Int) -> Int? {
    guard index >= 0 else {
      return nil
    }
    guard isFiltered else {
      return index
    }
    return filterBimap?[value: index]
  }

  private func getUnfilteredIndexes(fromFiltered indexes: IndexSet, excluding isExcluded: ((InputBinding) -> Bool)? = nil) -> IndexSet {
    guard let filterBimap = filterBimap else {
      return indexes
    }
    var unfiltered = IndexSet()
    for fi in indexes {
      if let ufi = filterBimap[value: fi] {
        if let isExcluded = isExcluded, isExcluded(bindingRowsAll[ufi]) {
        } else {
          unfiltered.insert(ufi)
        }
        unfiltered.insert(ufi)
      }
    }
    return unfiltered
  }

  private static func buildFilterBimap(from unfilteredRows: [InputBinding], by filterString: String) -> BiDictionary<Int, Int>? {
    if filterString.isEmpty {
      return nil
    }

    var biDict = BiDictionary<Int, Int>()

    for (indexUnfiltered, bindingRow) in unfilteredRows.enumerated() {
      if matches(bindingRow, filterString) {
        biDict[key: indexUnfiltered] = biDict.values.count
      }
    }

    return biDict
  }

  private static func matches(_ binding: InputBinding, _ filterString: String) -> Bool {
    return binding.getKeyColumnDisplay(raw: true).localizedStandardContains(filterString)
    || binding.getActionColumnDisplay(raw: true).localizedStandardContains(filterString)
  }
}
