//
//  BindingTableState.swift
//  iina
//
//  Created by Matt Svoboda on 9/20/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/// • Represents a snapshot of the state of tbe Key Bindings table, generated downstream from an instance of `AppInputConfig`.
/// • Like `AppInputConfig`, each instance is read-only and is designed to be rebuilt & replaced each time there is a change,
///   to help ensure the integrity of its data. See `BindingTableStateManager` for all changes.
/// • Provides create/remove/update/delete operations on the table, and also completely handles filtering,  but is decoupled from UI code
///   so that everything is cleaner.
/// • Should not contain any API calls to UI code. Other classes should call this class's public methods to get & update data.
struct BindingTableState {
  static var current: BindingTableState = BindingTableStateManager.initialState()
  static let manager: BindingTableStateManager = BindingTableStateManager()

  init(_ appInputConfig: AppInputConfig, filterString: String, inputConfFile: InputConfFile, showAllBindings: Bool) {
    self.appInputConfig = appInputConfig
    self.inputConfFile = inputConfFile
    self.filterString = filterString
    self.showAllBindings = showAllBindings
    self.filterBimap = BindingTableState.buildFilterBimap(from: appInputConfig, by: filterString, confBindingsOnly: !showAllBindings)
  }

  // MARK: Data

  /// The state of the AppInputConfig on which the state of this table is based.
  /// While in almost all cases this should be identical to `AppInputConfig.current`, it is way simpler and more performant
  /// to allow some tiny amount of drift. We treat each `AppInputConfig` object as a read-only version of the application state,
  /// and each new AppInputConfig is an atomic update which replaces the previously received one via asynchronous updates.
  let appInputConfig: AppInputConfig

  /// The input conf file from where the bindings originated.
  /// This reference is just for convenience in case its metadata is needed; for updates to this data, consult `InputConfFileCache`.
  let inputConfFile: InputConfFile

  /// Should be kept current with the value which the user enters in the search box. Empty string means no filter applied.
  let filterString: String

  /// Whether to include bindings from all sources in the displayed list, or just the conf file bindings.
  let showAllBindings: Bool

  /// The table rows currently displayed, which will change depending on the current `filterString`.
  private let filterBimap: BiDictionary<Int, Int>?

  /// The current *unfiltered* list of table rows
  private var allRows: [InputBinding] {
    appInputConfig.bindingCandidateList
  }

  // MARK: Bindings Table CRUD

  /// The currently displayed list of table rows. Subset of `allRows`; exact number depends on `filterString`
  var displayedRowIndexes: IndexSet {
    if let filterBimap = filterBimap {
      var displayedIndexes = IndexSet()
      for index in filterBimap.keys {
        displayedIndexes.insert(index)
      }
      return displayedIndexes
    }
    return IndexSet(integersIn: 0..<allRows.count)
  }

  /// The currently displayed list of table rows. Subset of `allRows`; exact number depends on `filterString`
  var displayedRows: [InputBinding] {
    if let filterBimap = filterBimap {
      return allRows.enumerated().compactMap({ filterBimap.keys.contains($0.offset) ? $0.element : nil })
    }
    return allRows
  }

  var displayedRowCount: Int {
    if let filterBimap = filterBimap {
      return filterBimap.values.count
    }
    return allRows.count
  }

  /// Avoids hard program crash if index is invalid (which would happen for array dereference)
  func getDisplayedRow(at displayIndex: Int) -> InputBinding? {
    guard displayIndex >= 0 else { return nil }
    let allRowsIndex: Int
    if let filterBimap = filterBimap, let unfilteredIndex = filterBimap[value: displayIndex] {
      allRowsIndex = unfilteredIndex
    } else {
      allRowsIndex = displayIndex
    }
    if allRowsIndex < allRows.count {
      return allRows[allRowsIndex]
    }
    return nil
  }

  func moveBindings(from rowIndexes: IndexSet, to index: Int,
                    afterComplete: TableUIChange.CompletionHandler? = nil) -> Int {

    let insertIndex = getClosestValidInsertIndex(from: index, returnUnfilteredIndex: true)
    Logger.log.verbose("Moving \(rowIndexes.count) bindings to \(isFiltered ? "filtered" : "unfiltered") index \(index), which equates to insert at unfiltered index \(insertIndex)")

    let srcIndexes = ensureUnfilteredIndexes(forRowIndexes: rowIndexes)  // guarantees unfiltered indexes

    // Divide all the rows into 3 groups: before + after the insert, + the insert itself.
    // Since each row will be moved in order from top to bottom, it's fairly easy to calculate where each row will go
    var beforeInsert: [InputBinding] = []
    var afterInsert: [InputBinding] = []
    var movedRows: [InputBinding] = []
    var moveIndexPairs: [(Int, Int)] = []
    var dstIndexes = IndexSet()
    var moveFromOffset = 0
    var moveToOffset = 0

    // Drag & Drop reorder algorithm: https://stackoverflow.com/questions/2121907/drag-drop-reorder-rows-on-nstableview
    for (origIndex, row) in allRows.enumerated() {
      if srcIndexes.contains(origIndex) {
        if origIndex < insertIndex {
          // If we moved the row from above to below, all rows up to & including its new location get shifted up 1
          moveIndexPairs.append((origIndex + moveFromOffset, insertIndex - 1))
          dstIndexes.insert(insertIndex + moveFromOffset - 1)  // new selected index
          moveFromOffset -= 1
        } else {
          moveIndexPairs.append((origIndex, insertIndex + moveToOffset))
          dstIndexes.insert(insertIndex + moveToOffset)  // new selected index
          moveToOffset += 1
        }
        movedRows.append(row)
      } else if origIndex < insertIndex {
        beforeInsert.append(row)
      } else {
        afterInsert.append(row)
      }
    }
    let allRowsUpdated = beforeInsert + movedRows + afterInsert

    let tableUIChange = TableUIChange(.moveRows, completionHandler: afterComplete)
    Logger.log("Generated \(moveIndexPairs.count) movePairs: \(moveIndexPairs); will change selection: \(srcIndexes.map{$0}) → \(dstIndexes.map{$0})", level: .verbose)
    tableUIChange.toMove = moveIndexPairs
    tableUIChange.newSelectedRowIndexes = dstIndexes
    tableUIChange.oldSelectedRowIndexes = srcIndexes  // to help restore selection on undo

    doAction(allRowsUpdated, tableUIChange)
    return insertIndex
  }

  func appendBindingsToUserConfSection(_ mappingList: [KeyMapping]) {
    insertNewBindings(relativeTo: appInputConfig.userConfSectionEndIndex, mappingList)
  }

  func insertNewBindings(relativeTo index: Int, isAfterNotAt: Bool = false, _ mappingList: [KeyMapping],
                         afterComplete: TableUIChange.CompletionHandler? = nil) {
    let insertIndex = getClosestValidInsertIndex(from: index, isAfterNotAt: isAfterNotAt, returnUnfilteredIndex: true)
    Logger.log("Inserting \(mappingList.count) bindings \(isAfterNotAt ? "after" : "into") \(isFiltered ? "filtered" : "unfiltered") rowIndex \(index) → insert at \(insertIndex)", level: .verbose)
    guard canModifyCurrentConf else {
      Logger.log("Aborting: cannot modify current conf!", level: .error)
      return
    }

    var allRowsNew = allRows
    // We can get away with making these assumptions about InputBinding fields, because only the "default" section can be modified by the user
    let insertedRows = mappingList.map{InputBinding($0, origin: .confFile, srcSectionName: SharedInputSection.USER_CONF_SECTION_NAME)}
    allRowsNew.insert(contentsOf: insertedRows, at: insertIndex)

    let tableUIChange = TableUIChange.buildInsertion(at: insertIndex, insertCount: insertedRows.count,
                                                     completionHandler: afterComplete)

    doAction(allRowsNew, tableUIChange)
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
    let indexesToRemove = ensureUnfilteredIndexes(forRowIndexes: indexes, excluding: { !$0.canBeModified })

    if indexesToRemove.isEmpty {
      Logger.log("Aborting remove operation: none of the rows can be modified")
      return
    }

    let (tableUIChange, remainingRowsUnfiltered) = TableUIChange.buildRemove(indexesToRemove, from: allRows)
    tableUIChange.toRemove = indexesToRemove

    doAction(remainingRowsUnfiltered, tableUIChange)
  }

  func updateBinding(at displayIndex: Int, to mapping: KeyMapping) {
    guard canModifyCurrentConf else {
      Logger.log("Aborting updateBinding(): cannot modify current conf!", level: .error)
      return
    }

    guard let existingRow = getDisplayedRow(at: displayIndex), existingRow.canBeModified else {
      Logger.log("Aborting updateBinding(): binding at displayIndex \(displayIndex) is read-only; aborting", level: .error)
      return
    }

    Logger.log("Updating binding at displayIndex \(displayIndex) from \(existingRow.keyMapping) to: \(mapping)", level: .verbose)

    let indexToUpdate: Int
    // The affected row will change index after the reload. Track it down before clearing the filter.
    if let unfilteredIndex = getUnfilteredIndex(fromFiltered: displayIndex) {
      Logger.log("Translated filtered index \(displayIndex) to unfiltered index \(unfilteredIndex)", level: .verbose)
      indexToUpdate = unfilteredIndex
    } else {
      indexToUpdate = displayIndex
    }

    // Must create a clone. If the original binding is modified it will screw up Undo
    var allRowsNew = allRows
    guard indexToUpdate < allRowsNew.count else {
      Logger.log("Index to update (\(indexToUpdate)) is larger than row count (\(allRowsNew.count)); aborting", level: .error)
      return
    }
    let bindingClone = existingRow.shallowClone(keyMapping: mapping)
    allRowsNew[indexToUpdate] = bindingClone

    let tableUIChange = TableUIChange(.updateRows)
    tableUIChange.toUpdate = IndexSet(integer: indexToUpdate)
    tableUIChange.newSelectedRowIndexes = IndexSet(integer: indexToUpdate)

    doAction(allRowsNew, tableUIChange)
  }

  // MARK: Various utility functions

  func isRowModifiable(_ rowIndex: Int) -> Bool {
    self.getDisplayedRow(at: rowIndex)?.canBeModified ?? false
  }

  /// Set `returnUnfilteredIndex` to `true` to always return unfiltered index, never filtered
  func getClosestValidInsertIndex(from requestedIndex: Int, isAfterNotAt: Bool = false, returnUnfilteredIndex: Bool = false) -> Int {
    var insertIndex: Int
    if requestedIndex < 0 {
      // snap to very beginning
      insertIndex = 0
    } else if let filterBimap = filterBimap, requestedIndex > filterBimap.values.count {
      insertIndex = filterBimap.values.count
    } else if requestedIndex > allRows.count {
      // snap to very end
      insertIndex = allRows.count
    } else {
      insertIndex = requestedIndex  // default to requested index
    }

    var didUnfilter = false

    // If there is an active filter, convert the filtered index to unfiltered index
    if let unfilteredIndex = getUnfilteredIndex(fromFiltered: requestedIndex) {
      Logger.log("Translated filtered index \(requestedIndex) to unfiltered index \(unfilteredIndex)", level: .verbose)
      insertIndex = unfilteredIndex
      didUnfilter = true
    }

    // Adjust for insert cursor
    if isAfterNotAt {
      insertIndex = min(insertIndex + 1, allRows.count)
    }

    // The "default" section is the only section which can be edited or changed.
    // If the insert cursor is outside the default section, then snap it to the nearest valid index.
    let ai = self.appInputConfig
    if insertIndex < ai.userConfSectionStartIndex {
      Logger.log("Insert index (\(insertIndex), origReq=\(requestedIndex)) is before the default section (\(ai.userConfSectionStartIndex) - \(ai.userConfSectionEndIndex)). Snapping it to index: \(ai.userConfSectionStartIndex)", level: .verbose)
      return ai.userConfSectionStartIndex
    }
    if insertIndex > ai.userConfSectionEndIndex {
      Logger.log("Insert index (\(insertIndex), origReq=\(requestedIndex)) is after the default section (\(ai.userConfSectionStartIndex) - \(ai.userConfSectionEndIndex)). Snapping it to index: \(ai.userConfSectionEndIndex)", level: .verbose)
      return ai.userConfSectionEndIndex
    }

    if !returnUnfilteredIndex && didUnfilter {
      if let filteredIndex = getFilteredIndex(fromUniltered: insertIndex) {
        Logger.log("Returning filtered insertIndex: \(filteredIndex) from requestedIndex: \(requestedIndex)", level: .verbose)
        return filteredIndex
      }
      let displayedRowIndexes = self.displayedRowIndexes
      if let lastFilteredIndex = displayedRowIndexes.last, insertIndex > lastFilteredIndex {
        Logger.log("Returning index after filtered array: \(displayedRowIndexes.count) from requestedIndex: \(requestedIndex)", level: .verbose)
        return displayedRowIndexes.count
      }
    }

    Logger.log("Returning insertIndex: \(insertIndex) from requestedIndex: \(requestedIndex)", level: .verbose)
    return insertIndex
  }

  // Both params should be calculated based on UNFILTERED rows.
  // Let BindingTableStateManager deal with altering animations with a filter
  private func doAction(_ allRowsNew: [InputBinding], _ tableUIChange: TableUIChange) {
    BindingTableState.manager.doAction(allRowsNew, tableUIChange)
  }

  private var canModifyCurrentConf: Bool {
    return !self.inputConfFile.isReadOnly
  }

  // MARK: Filtering

  private var isFiltered: Bool {
    return !filterString.isEmpty
  }

  func applyFilter(_ searchString: String) {
    Logger.log("Updating Bindings UI filter to \(searchString.quoted)", level: .verbose)
    BindingTableState.manager.applyFilter(newFilterString: searchString)
  }

  // Returns the index into filteredRows corresponding to the given unfiltered index.
  func getFilteredIndex(fromUniltered unfilteredIndex: Int) -> Int? {
    guard unfilteredIndex >= 0 else {
      return nil
    }
    guard let filterBimap = filterBimap else {
      return unfilteredIndex
    }
    if unfilteredIndex == allRows.count {
      // Special case: inserting at end of list
      return filterBimap.values.count
    }
    return filterBimap[key: unfilteredIndex]
  }

  /// Returns the index into allRows corresponding to the given filtered index.
  /// Returns nil if given `filteredIndex` is invalid or there is no active filter
  func getUnfilteredIndex(fromFiltered filteredIndex: Int) -> Int? {
    guard filteredIndex >= 0 else {
      return nil
    }
    guard let filterBimap = filterBimap else {
      return nil
    }
    if filteredIndex == filterBimap.values.count {
      // Special case: inserting at end of list
      return allRows.count
    }
    return filterBimap[value: filteredIndex]
  }

  private func ensureUnfilteredIndexes(forRowIndexes indexes: IndexSet, excluding isExcluded: ((InputBinding) -> Bool)? = nil) -> IndexSet {
    guard let filterBimap = filterBimap else {
      return indexes
    }
    var unfiltered = IndexSet()
    for fi in indexes {
      if let ufi = filterBimap[value: fi] {
        if let isExcluded = isExcluded, isExcluded(allRows[ufi]) {
        } else {
          unfiltered.insert(ufi)
        }
        unfiltered.insert(ufi)
      }
    }
    return unfiltered
  }

  private static func buildFilterBimap(from appInputConfig: AppInputConfig, by filterString: String, 
                                       confBindingsOnly: Bool) -> BiDictionary<Int, Int>? {
    if filterString.isEmpty && !confBindingsOnly {
      return nil
    }

    if filterString.hasPrefix("#key=") {
      // Match all occurrences of normalized key. Useful for finding duplicates
      let key = filterString.dropFirst(5)
      if key.isEmpty {
        return BiDictionary<Int, Int>()  // empty set
      }
      let normalizedMpvKey = KeyCodeHelper.normalizeMpv(String(key))
      return buildFilterBimap(from: appInputConfig.bindingCandidateList, { indexUnfiltered, bindingRow in
        return (!confBindingsOnly || bindingRow.origin == .confFile) && bindingRow.keyMapping.normalizedMpvKey == normalizedMpvKey
      })

    } else if filterString.hasPrefix("#dup") {
      // Find all duplicates (i.e., bindings are not the only in the table with the same key)
      return buildFilterBimap(from: appInputConfig.bindingCandidateList, { indexUnfiltered, bindingRow in
        return appInputConfig.duplicateKeys.contains(bindingRow.keyMapping.normalizedMpvKey)
      })
    }

    // Regular match
    return buildFilterBimap(from: appInputConfig.bindingCandidateList, { indexUnfiltered, bindingRow in
      return (!confBindingsOnly || bindingRow.origin == .confFile) && (filterString.isEmpty
          || bindingRow.getKeyColumnDisplay(raw: true).localizedStandardContains(filterString)
          || bindingRow.getActionColumnDisplay(raw: true).localizedStandardContains(filterString)
          || bindingRow.getActionColumnDisplay(raw: false).localizedStandardContains(filterString))
    })
  }

  private static func buildFilterBimap(from unfilteredRows: [InputBinding], _ isIncluded: (Int, InputBinding) -> Bool) -> BiDictionary<Int, Int>? {
    var biDict = BiDictionary<Int, Int>()

    for (indexUnfiltered, bindingRow) in unfilteredRows.enumerated() {
      if isIncluded(indexUnfiltered, bindingRow) {
        let filteredIndex = biDict.values.count
        biDict[key: indexUnfiltered] = filteredIndex
      }
    }
    return biDict
  }
}
