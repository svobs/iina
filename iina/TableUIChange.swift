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

  var newSelectedRowIndexes: IndexSet? = nil

  // MARK: Optional vars

  // Provide this to restore old selection when calculating the inverse of this change (when doing an undo of "move").
  // TODO: (optimization) figure out how to calculate this from `toMove` instead of storing this
  var oldSelectedRowIndexes: IndexSet? = nil

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
          Logger.log("Calling completion handler", level: .verbose)
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

    if let newSelectedRowIndexes = self.newSelectedRowIndexes {
      // NSTableView already updates previous selection indexes if added/removed rows cause them to move.
      // To select added rows, will need an explicit call here.
      tableView.selectApprovedRowIndexes(newSelectedRowIndexes)
    }

    if reloadAllExistingRows && self.changeType != .reloadAll {
      tableView.reloadExistingRows()
    }

    if let newSelectedRowIndexes = self.newSelectedRowIndexes, let firstSelectedRow = newSelectedRowIndexes.first, scrollToFirstSelectedRow {
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
}
