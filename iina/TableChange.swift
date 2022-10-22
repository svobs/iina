//
//  TableChange.swift
//  iina
//
//  Created by Matt Svoboda on 9/29/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/*
 Each instance of this class should represent an atomic operation on an associated `EditableTableView`, which contains all the
 information needed to transition it from {State_N} to {State_N+1}, where each state refers to a single user action or
 the response to some external update. All of thiis is needed in order to make AppKit animations work.

 In order to facilitate table animations, and to get around some AppKit limitations such as the tendency
 for it to lose track of the row selection, much additional boilerplate is needed to keep track of state.
 This objects attempts to provide as much of this as possible and provide future reusability.
 */
class TableChange {
  typealias CompletionHandler = (TableChange) -> Void

  enum ChangeType {
    case selectionChangeOnly
    case addRows
    case removeRows
    case moveRows
    case updateRows
    // Due to AppKit limitations (removes selection, disables animations, seems to send extra events)
    // use this only when absolutely needed:
    case reloadAll
    // Can have any number of adds, removes, moves, and updates:
    case wholeTableDiff
  }

  let changeType: ChangeType

  var toInsert: IndexSet? = nil
  var toRemove: IndexSet? = nil
  var toUpdate: IndexSet? = nil
  // Used by ChangeType.moveRows. Ordered list of pairs of (fromIndex, toIndex)
  var toMove: [(Int, Int)]? = nil

  var newSelectedRows: IndexSet? = nil

  var scrollToFirstSelectedRow: Bool = false

  // If true, reload all existing rows after executing the primary differences (to cover the case that one of them may have changed)
  var reloadAllExistingRows: Bool = false

  // A method which, if supplied, is called at the end of execute()
  let completionHandler: TableChange.CompletionHandler?

  init(_ changeType: ChangeType, completionHandler: TableChange.CompletionHandler? = nil) {
    self.changeType = changeType
    self.completionHandler = completionHandler
  }

  // Subclasses should override executeStructureUpdates() instead of this
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
    executeStructureUpdates(on: tableView)

    if let newSelectedRows = self.newSelectedRows {
      // NSTableView already updates previous selection indexes if added/removed rows cause them to move.
      // To select added rows, will need an explicit call here.
      Logger.log("Updating table selection to indexes: \(newSelectedRows.map{$0})", level: .verbose)
      tableView.selectRowIndexes(newSelectedRows, byExtendingSelection: false)
    }

    if reloadAllExistingRows && self.changeType != .reloadAll {
      tableView.reloadExistingRows()
    }

    if let newSelectedRows = self.newSelectedRows, let firstSelectedRow = newSelectedRows.first, scrollToFirstSelectedRow {
      tableView.scrollRowToVisible(firstSelectedRow)
    }

    tableView.endUpdates()
  }

  private func executeStructureUpdates(on tableView: EditableTableView) {

    switch changeType {
      case .selectionChangeOnly:
        fallthrough
      case .moveRows:
        if let movePairs = self.toMove {
          for (oldIndex, newIndex) in movePairs {
            tableView.moveRow(at: oldIndex, to: newIndex)
          }
        }
      case .addRows:
        if let indexes = self.toInsert {
          tableView.insertRows(at: indexes, withAnimation: tableView.rowAnimation)
        }
      case .removeRows:
        if let indexes = self.toRemove {
          tableView.removeRows(at: indexes, withAnimation: tableView.rowAnimation)
        }
      case .updateRows:
        // Just redraw all of them. This is a very inexpensive operation, and much easier
        // than chasing down all the possible ways other rows could be updated.
        tableView.reloadExistingRows()
      case .reloadAll:
        // Try not to use this much, if at all
        Logger.log("TableChange: ReloadAll", level: .verbose)
        tableView.reloadData()
      case .wholeTableDiff:
        Logger.log("TableChange: executing diff", level: .verbose)
        if let toRemove = self.toRemove,
           let toInsert = self.toInsert,
           let movePairs = self.toMove {
          // Remember, AppKit expects the order of operations to be: 1. Delete, 2. Insert, 3. Move
          Logger.log("TableChange: diff: removing \(toRemove.count), adding \(toInsert.count), and moving \(movePairs.count) rows", level: .verbose)
          tableView.removeRows(at: toRemove, withAnimation: tableView.rowAnimation)
          tableView.insertRows(at: toInsert, withAnimation: tableView.rowAnimation)
          for (oldIndex, newIndex) in movePairs {
            Logger.log("Diff: moving row: \(oldIndex) -> \(newIndex)", level: .verbose)
            tableView.moveRow(at: oldIndex, to: newIndex)
          }
        }
    }
  }

  static func buildDiff<R>(oldRows: Array<R>, newRows: Array<R>,
                           completionHandler: TableChange.CompletionHandler? = nil) -> TableChange where R:Hashable {
    guard #available(macOS 10.15, *) else {
      Logger.log("Animated table diff not available in MacOS versions below 10.15. Falling back to ReloadAll")
      return TableChange(.reloadAll, completionHandler: completionHandler)
    }

    let tableChange = TableChange(.wholeTableDiff, completionHandler: completionHandler)
    tableChange.toRemove = IndexSet()
    tableChange.toInsert = IndexSet()
    tableChange.toMove = []

    // Remember, AppKit expects the order of operations to be: 1. Delete, 2. Insert, 3. Move

    /*
     Solution shared by Giles Hammond:
     https://stackoverflow.com/a/63281265/1347529S
     Further reference:
     https://swiftrocks.com/how-collection-diffing-works-internally-in-swift
     */
    let steps = newRows.difference(from: oldRows).steps
    Logger.log("Computing table animation: found \(steps.count) differences between \(oldRows.count) old & \(newRows.count) new rows")
    for step in steps {
      switch step {
        case let .remove(_, index):
          // If toOffset != nil, it signifies a MOVE from fromOffset -> toOffset. But the offset must be adjusted for removes!
          tableChange.toRemove?.insert(index)
        case let .insert(_, index):
          tableChange.toInsert?.insert(index)
        case let .move(_, from, to):
          tableChange.toMove?.append((from, to))
      }
    }
    return tableChange
  }
}
