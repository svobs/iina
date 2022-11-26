//
//  TableUIChangeBuildera.swift
//  iina
//
//  Created by Matt Svoboda on 11/26/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class TableUIChangeBuilder {
  // Derives the inverse of the given `TableUIChange` (as suitable for an Undo) and returns it.
  static func inverse(from original: TableUIChange, andAdjustAllIndexesBy offset: Int = 0) -> TableUIChange {
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
        Logger.log("Calling inverse() on content change type '\(original.changeType)': was this intentional?", level: .warning)
        inverted = TableUIChange(original.changeType)
    }

    if let toRemove = original.toRemove {
      inverted.toInsert = IndexSet(toRemove.map({ $0 + offset }))
      Logger.log("Inverse: changed removes=\(toRemove.map{$0}) into inserts=\(inverted.toInsert!.map{$0})", level: .verbose)
    }
    if let toInsert = original.toInsert {
      inverted.toRemove = IndexSet(toInsert.map({ $0 + offset }))
      Logger.log("Inverse: changed inserts=\(toInsert.map{$0}) into removes=\(inverted.toRemove!.map{$0})", level: .verbose)
    }
    if let movePairs = original.toMove {
      inverted.toMove = []
      for (fromIndex, toIndex) in movePairs.reversed() {
        let fromIndexNew = toIndex + offset
        let toIndexNew = fromIndex + offset
        inverted.toMove?.append((fromIndexNew, toIndexNew))

        // FIXME: selection isn't correct
        //          if fromIndexNew < toIndexNew {
        //            // If we moved the row from above to below, all rows up to & including its new location get shifted up 1
        //            moveIndexPairs.append((origIndex + moveFromOffset, insertIndex - 1))
        //            newSelectedRows.insert(insertIndex + moveFromOffset - 1)
        //            moveFromOffset -= 1
        //          } else {
        //            moveIndexPairs.append((origIndex, insertIndex + moveToOffset))
        //            newSelectedRows.insert(insertIndex + moveToOffset)
        //            moveToOffset += 1
        //          }

      }
      Logger.log("Inverse: changed movePairs=\(movePairs) into movePairs=\(inverted.toMove!)", level: .verbose)
    }

    if inverted.changeType != .none && inverted.changeType != .reloadAll {
      inverted.newSelectedRows = IndexSet()

      // Select inserted lines
      if let toInsert = inverted.toInsert {
        for insertedIndex in toInsert {
          inverted.newSelectedRows?.insert(insertedIndex)
        }
      }
      if let toMove = inverted.toMove {
        for (_, toIndex) in toMove {
          inverted.newSelectedRows?.insert(toIndex)
        }
      }
      Logger.log("Inverse: selectedRows=\(inverted.newSelectedRows!.map({$0}))", level: .verbose)
    }
    applyExtraSelectionRules(to: inverted)

    return inverted
  }

  // MARK: Diff

  /*
   Creates a new `TableUIChange` and populates its `toRemove, `toInsert`, `toMove`, and `newSelectedRows` fields
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
  static func buildDiff<R>(oldRows: Array<R>, newRows: Array<R>, isUndoRedo: Bool = false,
                           completionHandler: TableUIChange.CompletionHandler? = nil) -> TableUIChange where R:Hashable {
    guard #available(macOS 10.15, *) else {
      Logger.log("Animated table diff not available in MacOS versions below 10.15. Falling back to ReloadAll")
      return TableUIChange(.reloadAll, completionHandler: completionHandler)
    }

    let diff = TableUIChange(.wholeTableDiff, completionHandler: completionHandler)
    diff.toRemove = IndexSet()
    diff.toInsert = IndexSet()
    diff.toMove = []

    // Remember, AppKit expects the order of operations to be: 1. Delete, 2. Insert, 3. Move

    let steps = newRows.difference(from: oldRows).steps
    Logger.log("Computing table diff: found \(steps.count) differences between \(oldRows.count) old & \(newRows.count) new rows")
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

    if isUndoRedo {  // Special styling for undo & redo
      if !diff.hasMove && !diff.hasRemove && diff.hasInsert {
        // If lines were added with no other changes, highlight them.
        diff.newSelectedRows = IndexSet()
        // Only inserts: select added lines
        if let toInsert = diff.toInsert {
          for insertedIndex in toInsert {
            diff.newSelectedRows?.insert(insertedIndex)
          }
        }
      }
    }
    applyExtraSelectionRules(to: diff)

    return diff
  }

  static private func applyExtraSelectionRules(to tableUIChange: TableUIChange) {
    if TableUIChange.selectNextRowAfterDelete && !tableUIChange.hasMove && !tableUIChange.hasInsert && tableUIChange.hasRemove {
      // After selected rows are deleted, keep a selection on the table by selecting the next row
      if let toRemove = tableUIChange.toRemove, let lastRemoveIndex = toRemove.last {
        let newSelectionIndex: Int = lastRemoveIndex - toRemove.count + 1
        if newSelectionIndex < 0 {
          Logger.log("selectNextRowAfterDelete: new selection index is less than zero! Discarding", level: .error)
        } else {
          tableUIChange.newSelectedRows = IndexSet(integer: newSelectionIndex)
        }
      }
    }
  }
}
