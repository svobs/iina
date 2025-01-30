//
//  TableUIChangeBuilder.swift
//  iina
//
//  Created by Matt Svoboda on 11/26/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class TableUIChangeBuilder {
  // Derives the inverse of the given `TableUIChange` (as suitable for an Undo) and returns it.
  func inverted(from original: TableUIChange, andAdjustAllIndexesBy offset: Int = 0,
                selectNextRowAfterDelete: Bool) -> TableUIChange {
    let inverted: TableUIChange

    switch original.changeType {

    case .removeRows:
      inverted = TableUIChange(.insertRows)

    case .insertRows:
      inverted = TableUIChange(.removeRows)

    case .moveRows:
      inverted = TableUIChange(.moveRows)

    case .updateRows:
      inverted = TableUIChange(.updateRows)

    case .none, .reloadAll, .wholeTableDiff:
      // Will not cause a failure. But can't think of a reason to ever invert these types
      Logger.log("Calling inverted() on content change type '\(original.changeType)': was this intentional?", level: .warning)
      inverted = TableUIChange(original.changeType)
    }

    if inverted.changeType != .none && inverted.changeType != .reloadAll {
      inverted.newSelectedRowIndexes = IndexSet()
    }

    if let removed = original.toRemove {
      inverted.toInsert = IndexSet(removed.map({ $0 + offset }))
      // Add inserted lines to selection
      for insertIndex in inverted.toInsert! {
        inverted.newSelectedRowIndexes?.insert(insertIndex)
      }
      Logger.log("Invert: changed removes=\(removed.map{$0}) into inserts=\(inverted.toInsert!.map{$0})", level: .verbose)
    }
    if let toInsert = original.toInsert {
      inverted.toRemove = IndexSet(toInsert.map({ $0 + offset }))
      Logger.log("Invert: changed inserts=\(toInsert.map{$0}) into removes=\(inverted.toRemove!.map{$0})", level: .verbose)
    }
    if let toUpdate = original.toUpdate {
      inverted.toUpdate = IndexSet(toUpdate.map({ $0 + offset }))
      Logger.log("Invert: changed updates=\(toUpdate.map{$0}) into updates=\(inverted.toUpdate!.map{$0})", level: .verbose)
      // Add updated lines to selection
      for updateIndex in inverted.toUpdate! {
        inverted.newSelectedRowIndexes?.insert(updateIndex)
      }
    }
    if let movePairsOrig = original.toMove {
      var movePairsInverted: [(Int, Int)] = []

      for (fromIndex, toIndex) in movePairsOrig {
        let fromIndexNew = toIndex + offset
        let toIndexNew = fromIndex + offset
        movePairsInverted.append((fromIndexNew, toIndexNew))
      }

      inverted.toMove = movePairsInverted.reversed()  // Need to reverse order for proper animation

      // Preserve selection if possible:
      if let origBeginningSelection = original.oldSelectedRowIndexes,
         let origEndingSelection = original.newSelectedRowIndexes, inverted.changeType == .moveRows {
        inverted.newSelectedRowIndexes = origBeginningSelection
        inverted.oldSelectedRowIndexes = origEndingSelection
        Logger.log("Invert: changed movePairs from \(movePairsOrig) to \(inverted.toMove!.map{$0}); changed selection from \(origEndingSelection.map{$0}) to \(origBeginningSelection.map{$0})", level: .verbose)
      }
    }

    // Select next row after delete event (maybe):
    applyExtraSelectionRules(to: inverted, selectNextRowAfterDelete: selectNextRowAfterDelete)

    return inverted
  }

  // MARK: Diff

  /**
   Creates a new `TableUIChange` and populates its `toRemove, `toInsert`, and `toMove` fields
   based on a diffing algorithm similar to Git's.

   Note for tables containing non-unique rows:
   If changes were made to row(s) which not unique in the table, the diffing algorithm can't reliably
   identify which of the duplicates changed and which didn't, and may pick the wrong ones.
   Assuming the positions of shared rows are fungible, this isn't exactly wrong but may be visually
   inconvenient for things like undo. Where possible, this should be avoided in favor of explicit information.

   Solution shared by Giles Hammond:
   https://stackoverflow.com/a/63281265/1347529S
   Further reference:
   https://swiftrocks.com/how-collection-diffing-works-internally-in-swift
   */
  func buildDiff<R>(oldRows: Array<R>, newRows: Array<R>, completionHandler:
                    TableUIChange.CompletionHandler? = nil, overrideSingleRowMove: Bool = true) -> TableUIChange where R:Hashable {

    let diff = TableUIChange(.wholeTableDiff, completionHandler: completionHandler)
    diff.toRemove = IndexSet()
    diff.toInsert = IndexSet()
    diff.toUpdate = IndexSet()
    diff.toMove = []

    // Remember, AppKit expects the order of operations to be: 1. Delete, 2. Insert, 3. Move

    let steps = newRows.difference(from: oldRows).steps
    Logger.log("Computing TableUIChange from diff: found \(steps.count) differences between \(oldRows.count) old & \(newRows.count) new rows")

    // If overrideSingleRowMove==true, override default behavior for single row: treat del + ins as move.
    // This results in a more pleasant animation in cases such as when an inline edit is finished.
    if overrideSingleRowMove && steps.count == 2 {
      switch steps[0] {
      case let .remove(_, indexToRemove):
        switch steps[1] {
        case let .insert(_, indexToInsert):
          if indexToRemove == indexToInsert {
            diff.toUpdate = IndexSet(integer: indexToInsert)
            Logger.log("Overrode TableUIChange from diff: changed 1 rm + 1 add into 1 update: \(indexToInsert)", level: .verbose)
            return diff
          }
          diff.toMove?.append((indexToRemove, indexToInsert))
          Logger.log("Overrode TableUIChange from diff: changed 1 rm + 1 add into 1 move: from \(indexToRemove) to \(indexToInsert)", level: .verbose)
          return diff
        default: break
        }
      default: break
      }
    }

    for step in steps {
      switch step {
      case let .remove(_, index):
        // If toOffset != nil, it signifies a MOVE from fromOffset -> toOffset. But the offset must be adjusted for removes!
        diff.toRemove?.insert(index)
      case let .insert(_, index):
        diff.toInsert?.insert(index)
      case let .move(_, from, to):
        diff.toMove?.append((from, to))
      }
    }

    return diff
  }

  private func applyExtraSelectionRules(to tableUIChange: TableUIChange, selectNextRowAfterDelete: Bool) {
    if selectNextRowAfterDelete && !tableUIChange.hasMove && !tableUIChange.hasInsert && tableUIChange.hasRemove {
      // After selected rows are deleted, keep a selection on the table by selecting the next row
      if let toRemove = tableUIChange.toRemove, let lastRemoveIndex = toRemove.last {
        let newSelectionIndex: Int = lastRemoveIndex - toRemove.count + 1
        if newSelectionIndex < 0 {
          Logger.log("selectNextRowAfterDelete: new selection index is less than zero! Discarding", level: .error)
        } else {
          tableUIChange.newSelectedRowIndexes = IndexSet(integer: newSelectionIndex)
          Logger.log("TableUIChange: selecting next index after removed rows: \(newSelectionIndex)", level: .verbose)
        }
      }
    }
  }

  /// Do not use this moving forward. Use the equivalent `EditableTableView` method.
  func buildInsert<T>(of itemsToInsert: [T], at insertIndex: Int, in allCurrentItems: [T],
                      completionHandler: TableUIChange.CompletionHandler? = nil) -> (TableUIChange, [T]) {
    let tableUIChange = TableUIChange(.insertRows, completionHandler: completionHandler)
    let toInsert = IndexSet(insertIndex..<(insertIndex+itemsToInsert.count))
    tableUIChange.toInsert = toInsert
    tableUIChange.newSelectedRowIndexes = toInsert

    var allItemsNew = allCurrentItems
    allItemsNew.insert(contentsOf: itemsToInsert, at: insertIndex)

    return (tableUIChange, allItemsNew)
  }

  /// Do not use this moving forward. Use the equivalent `EditableTableView` method.
  func buildRemove<T>(_ indexesToRemove: IndexSet,
                      in allCurrentRows: [T],
                      selectNextRowAfterDelete: Bool,
                      completionHandler: TableUIChange.CompletionHandler? = nil) -> (TableUIChange, [T]) {
    let tableUIChange = TableUIChange(.removeRows, completionHandler: completionHandler)
    tableUIChange.toRemove = indexesToRemove

    var remainingRows: [T] = []
    var lastRemovedIndex = 0
    for (rowIndex, row) in allCurrentRows.enumerated() {
      if indexesToRemove.contains(rowIndex) {
        lastRemovedIndex = rowIndex
      } else {
        remainingRows.append(row)
      }
    }

    if selectNextRowAfterDelete {
      // After removal, select the single row after the last one removed:
      let countRemoved = allCurrentRows.count - remainingRows.count
      if countRemoved < allCurrentRows.count {
        let newSelectionIndex: Int = lastRemovedIndex - countRemoved + 1
        tableUIChange.newSelectedRowIndexes = IndexSet(integer: newSelectionIndex)
      }
    }
    return (tableUIChange, remainingRows)
  }

  /// Do not use this moving forward. Use the equivalent `EditableTableView` method.
  func buildMove<T>(_ indexesToMove: IndexSet,
                    to insertIndex: Int,
                    in allCurrentRows: [T],
                    completionHandler: TableUIChange.CompletionHandler? = nil) -> (TableUIChange, [T]) {

    // Divide all the rows into 3 groups: before + after the insert, + the insert itself.
    // Since each row will be moved in order from top to bottom, it's fairly easy to calculate where each row will go
    var beforeInsert: [T] = []
    var afterInsert: [T] = []
    var movedRows: [T] = []
    var moveIndexPairs: [(Int, Int)] = []
    var dstIndexes = IndexSet()
    var moveFromOffset = 0
    var moveToOffset = 0

    // Drag & Drop reorder algorithm: https://stackoverflow.com/questions/2121907/drag-drop-reorder-rows-on-nstableview
    for (origIndex, row) in allCurrentRows.enumerated() {
      if indexesToMove.contains(origIndex) {
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

    let tableUIChange = TableUIChange(.moveRows, completionHandler: completionHandler)
    tableUIChange.toMove = moveIndexPairs
    tableUIChange.newSelectedRowIndexes = dstIndexes

    return (tableUIChange, allRowsUpdated)
  }
}

// MARK: - EditableTableView

extension EditableTableView {
  func buildInsert<T>(of itemsToInsert: [T], at insertIndex: Int, in allCurrentItems: [T],
                      completionHandler: TableUIChange.CompletionHandler? = nil) -> (TableUIChange, [T]) {
    return TableUIChange.builder.buildInsert(of: itemsToInsert, at: insertIndex, in: allCurrentItems,
                                           completionHandler: completionHandler)
  }
  func buildRemove<T>(_ indexesToRemove: IndexSet, in allCurrentRows: [T],
                      completionHandler: TableUIChange.CompletionHandler? = nil) -> (TableUIChange, [T]) {
    return TableUIChange.builder.buildRemove(indexesToRemove, in: allCurrentRows,
                                           selectNextRowAfterDelete: selectNextRowAfterDelete,
                                           completionHandler: completionHandler)
  }
  func buildMove<T>(_ indexesToMove: IndexSet,
                    to insertIndex: Int,
                    in allCurrentRows: [T],
                    completionHandler: TableUIChange.CompletionHandler? = nil) -> (TableUIChange, [T]) {
    return TableUIChange.builder.buildMove(indexesToMove, to: insertIndex, in: allCurrentRows,
                                         completionHandler: completionHandler)
  }
}
