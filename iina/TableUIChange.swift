//
//  TableUIChange.swift
//  iina
//
//  Created by Matt Svoboda on 9/29/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/*
 Each instance of this class:
 * Represents an atomic state change to the UI of an associated `EditableTableView`
 * Contains all the metadata (though not the actual data) needed to transition it from {State_N} to {State_N+1}, where each state refers to a single user action or the response to some external update. All of thiis is needed in order to make AppKit animations work.

 In order to facilitate table animations, and to get around some AppKit limitations such as the tendency
 for it to lose track of the row selection, much additional boilerplate is needed to keep track of state.
 This objects attempts to provide as much of this as possible and provide future reusability.
 */
class TableUIChange {
  // MARK: Static definitions

  typealias CompletionHandler = (TableUIChange) -> Void

  // After removal of rows, select the next single row after the last one removed:
  static let selectNextRowAfterDelete = true

  enum ContentChangeType {
    case removeRows

    case insertRows

    case moveRows

    case updateRows

    // No changes to content, but can specify changes to metadata (selection change, completionHandler, ...)
    case none

    // Due to AppKit limitations (removes selection, disables animations, seems to send extra events)
    // use this only when absolutely needed:
    case reloadAll

    // Can have any number of inserts, removes, moves, and updates:
    case wholeTableDiff
  }

  // MARK: Instance Vars

  // Required
  let changeType: ContentChangeType

  var toInsert: IndexSet? = nil
  var toRemove: IndexSet? = nil
  var toUpdate: IndexSet? = nil
  // Used by ContentChangeType.moveRows. Ordered list of pairs of (fromIndex, toIndex)
  var toMove: [(Int, Int)]? = nil

  var newSelectedRows: IndexSet? = nil

  // MARK: Additoional options

  // Animation overrides. Leave nil to use the value from the table
  var rowInsertAnimation: NSTableView.AnimationOptions? = nil
  var rowRemoveAnimation: NSTableView.AnimationOptions? = nil

  // If true, reload all existing rows after executing the primary differences (to cover the case that one of them may have changed)
  var reloadAllExistingRows: Bool = false

  // If true, and only if there are selected row(s), scroll the table so that the first selected row is
  // visible to the user. Does this after `reloadAllExistingRows` but before `completionHandler`.
  var scrollToFirstSelectedRow: Bool = false

  // A method which, if supplied, is called at the end of execute()
  let completionHandler: TableUIChange.CompletionHandler?

  var hasRemove: Bool {
    if let toRemove = self.toRemove {
      return !toRemove.isEmpty
    }
    return false
  }

  var hasInsert: Bool {
    if let toInsert = self.toInsert {
      return !toInsert.isEmpty
    }
    return false
  }

  var hasMove: Bool {
    if let toMove = self.toMove {
      return !toMove.isEmpty
    }
    return false
  }

  init(_ changeType: ContentChangeType, completionHandler: TableUIChange.CompletionHandler? = nil) {
    self.changeType = changeType
    self.completionHandler = completionHandler
  }

  // MARK: Execute

  // Subclasses should override executeContentUpdates() instead of this
  func execute(on tableView: EditableTableView) {
    NSAnimationContext.runAnimationGroup({context in
      self.executeInAnimationGroup(tableView, context)
    }, completionHandler: {
      // Put things like "inline editing after adding a row" here, so
      // it will wait until after the animations are complete. Doing so
      // avoids issues such as unexpected notifications being fired from animations
      if let completionHandler = self.completionHandler {
        DispatchQueue.main.async {
          Logger.log("Executing completion handler", level: .verbose)
          completionHandler(self)
        }
      }
    })
  }

  private func executeInAnimationGroup(_ tableView: EditableTableView, _ context: NSAnimationContext) {
    // Encapsulate all animations in this function inside a transaction.
    tableView.beginUpdates()
    if AccessibilityPreferences.motionReductionEnabled {
      Logger.log("Motion reduction is enabled: nulling out animation", level: .verbose)
      context.duration = 0.0
      context.allowsImplicitAnimation = false
    }
    executeContentUpdates(on: tableView)

    if let newSelectedRows = self.newSelectedRows {
      // NSTableView already updates previous selection indexes if added/removed rows cause them to move.
      // To select added rows, will need an explicit call here.
      tableView.selectApprovedRowIndexes(newSelectedRows)
    }

    if reloadAllExistingRows && self.changeType != .reloadAll {
      tableView.reloadExistingRows()
    }

    if let newSelectedRows = self.newSelectedRows, let firstSelectedRow = newSelectedRows.first, scrollToFirstSelectedRow {
      tableView.scrollRowToVisible(firstSelectedRow)
    }

    tableView.endUpdates()
  }

  private func executeContentUpdates(on tableView: EditableTableView) {
    let insertAnimation = AccessibilityPreferences.motionReductionEnabled ? [] : (self.rowInsertAnimation ?? tableView.rowInsertAnimation)
    let removeAnimation = AccessibilityPreferences.motionReductionEnabled ? [] : (self.rowRemoveAnimation ?? tableView.rowRemoveAnimation)

    switch changeType {

      case .removeRows:
        if let indexes = self.toRemove {
          tableView.removeRows(at: indexes, withAnimation: removeAnimation)
        }

      case .insertRows:
        if let indexes = self.toInsert {
          tableView.insertRows(at: indexes, withAnimation: insertAnimation)
        }

      case .moveRows:
        if let movePairs = self.toMove {
          for (oldIndex, newIndex) in movePairs {
            tableView.moveRow(at: oldIndex, to: newIndex)
          }
        }

      case .updateRows:
        // Just redraw all of them. This is a very inexpensive operation, and much easier
        // than chasing down all the possible ways other rows could be updated.
        tableView.reloadExistingRows()

      case .none:
        fallthrough

      case .reloadAll:
        // Try not to use this much, if at all
        Logger.log("TableUIChange: ReloadAll", level: .verbose)
        tableView.reloadData()

      case .wholeTableDiff:
        if let toRemove = self.toRemove,
           let toInsert = self.toInsert,
           let movePairs = self.toMove {
          guard !toRemove.isEmpty || !toInsert.isEmpty || !movePairs.isEmpty else {
            // Remember, AppKit expects the order of operations to be: 1. Delete, 2. Insert, 3. Move
            Logger.log("TableUIChange from diff: no rows changed", level: .verbose)
            break
          }
          // Remember, AppKit expects the order of operations to be: 1. Delete, 2. Insert, 3. Move
          Logger.log("TableUIChange from diff: removing \(toRemove.count), adding \(toInsert.count), and moving \(movePairs.count) rows", level: .verbose)
          tableView.removeRows(at: toRemove, withAnimation: removeAnimation)
          tableView.insertRows(at: toInsert, withAnimation: insertAnimation)
          for (oldIndex, newIndex) in movePairs {
            Logger.log("Diff: moving row: \(oldIndex) -> \(newIndex)", level: .verbose)
            tableView.moveRow(at: oldIndex, to: newIndex)
          }
        }
    }
  }

  // Derives the inverse of this `TableUIChange` (as suitable for an Undo) and returns it.
  func inverse(andAdjustAllIndexesBy offset: Int = 0) -> TableUIChange {
    let inverted: TableUIChange

    switch changeType {

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
        Logger.log("Calling inverse() on content change type '\(changeType)': was this intentional?", level: .warning)
        inverted = TableUIChange(changeType)
    }

    if let toRemove = self.toRemove {
      inverted.toInsert = IndexSet(toRemove.map({ $0 + offset }))
      Logger.log("Inverse: changed removes=\(toRemove.map{$0}) into inserts=\(inverted.toInsert!.map{$0})", level: .verbose)
    }
    if let toInsert = self.toInsert {
      inverted.toRemove = IndexSet(toInsert.map({ $0 + offset }))
      Logger.log("Inverse: changed inserts=\(toInsert.map{$0}) into removes=\(inverted.toRemove!.map{$0})", level: .verbose)
    }
    if let movePairs = self.toMove {
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
    inverted.applyExtraSelectionRules()

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

    let tableUIChange = TableUIChange(.wholeTableDiff, completionHandler: completionHandler)
    tableUIChange.toRemove = IndexSet()
    tableUIChange.toInsert = IndexSet()
    tableUIChange.toMove = []

    // Remember, AppKit expects the order of operations to be: 1. Delete, 2. Insert, 3. Move

    let steps = newRows.difference(from: oldRows).steps
    Logger.log("Computing table diff: found \(steps.count) differences between \(oldRows.count) old & \(newRows.count) new rows")
    for step in steps {
      switch step {
        case let .remove(_, index):
          // If toOffset != nil, it signifies a MOVE from fromOffset -> toOffset. But the offset must be adjusted for removes!
          tableUIChange.toRemove?.insert(index)
        case let .insert(_, index):
          tableUIChange.toInsert?.insert(index)
        case let .move(_, from, to):
          tableUIChange.toMove?.append((from, to))
      }
    }

    if isUndoRedo {  // Special styling for undo & redo
      if !tableUIChange.hasMove && !tableUIChange.hasRemove && tableUIChange.hasInsert {
        // If lines were added with no other changes, highlight them.
        tableUIChange.newSelectedRows = IndexSet()
        // Only inserts: select added lines
        if let toInsert = tableUIChange.toInsert {
          for insertedIndex in toInsert {
            tableUIChange.newSelectedRows?.insert(insertedIndex)
          }
        }
      }
    }
    tableUIChange.applyExtraSelectionRules()

    return tableUIChange
  }

  private func applyExtraSelectionRules() {
    if TableUIChange.selectNextRowAfterDelete && !self.hasMove && !self.hasInsert && self.hasRemove {
      // After selected rows are deleted, keep a selection on the table by selecting the next row
      if let toRemove = self.toRemove, let lastRemoveIndex = toRemove.last {
        let newSelectionIndex: Int = lastRemoveIndex - toRemove.count + 1
        if newSelectionIndex < 0 {
          Logger.log("selectNextRowAfterDelete: new selection index is less than zero! Discarding", level: .error)
        } else {
          self.newSelectedRows = IndexSet(integer: newSelectionIndex)
        }
      }
    }
  }
}
