//
//  TableChange.swift
//  iina
//
//  Created by Matt Svoboda on 9/29/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/*
 Object which contains all the information needed for an `EditableTableView` to transition
 from {State_N} to {State_N+1} (or at least how that should appear to the user), and to animate that change when executed.

 In order to facilitate table animations, and to get around some AppKit limitations such as the tendency
 for it to lose track of the row selection, much work is needed to keep track of state. The subclasses of this object
 attempt to automate as much of this as possible and hopefully end up with something which can reduce the effort needed
 in the future.
 */
class TableChange {
  enum ChangeType {
    case selectionChangeOnly
    case addRows
    case removeRows
    case moveRows
    case renameAndMoveOneRow
    case updateRows
    // Due to AppKit limitations (removes selection, disables animations, seems to send extra events)
    // use this only when absolutely needed:
    case reloadAll
    // Can have any number of adds, removes, moves, and updates:
    case wholeTableDiff
  }

  let changeType: ChangeType

  var newSelectedRows: IndexSet? = nil

  fileprivate init(_ changeType: ChangeType) {
    self.changeType = changeType
  }

  func execute(on tableView: EditableTableView) {}
}

// To describe the changes, relies on each row of the table being a simple String.
class TableChangeByStringElement: TableChange {
  var oldRows: [String] = []
  var newRows: [String]? = nil

  override init(_ changeType: ChangeType) {
    super.init(changeType)
  }

  /*
   Attempts to be a generic mechanism for updating the table's contents with an animation and
   avoiding unnecessary calls to listeners such as tableViewSelectionDidChange()
   */
  override func execute(on tableView: EditableTableView) {
    // encapsulate animation transaction in this function
    tableView.beginUpdates()
    defer {
      tableView.endUpdates()
    }

    switch self.changeType {
      case .selectionChangeOnly:
        fallthrough
      case .renameAndMoveOneRow:
        renameAndMoveOneRow(tableView)
      case .addRows:
        addRows(tableView)
      case .removeRows:
        removeRows(tableView)
      case .updateRows:
        // Just redraw all of them. This is a very inexpensive operation
        tableView.reloadExistingRows()
      case .moveRows:
        Logger.fatal("Not yet supported: moveRows for TableChangeByStringElement")
      case .reloadAll:
        // Try not to use this much, if at all
        Logger.log("TableChangeByStringElement: ReloadAll", level: .verbose)
        tableView.reloadData()
      case .wholeTableDiff:
        Logger.fatal("Not yet supported: wholeTableDiff for TableChangeByStringElement")
    }

    if let newSelectedRows = self.newSelectedRows {
      // NSTableView already updates previous selection indexes if added/removed rows cause them to move.
      // To select added rows, will need an explicit call here even if oldSelection and newSelection are the same.
      Logger.log("Updating table selection to indexes: \(newSelectedRows.reduce("[", { "\($0) \($1)"  })) ]", level: .verbose)
      tableView.selectRowIndexes(newSelectedRows, byExtendingSelection: false)
    }
  }

  private func renameAndMoveOneRow(_ tableView: EditableTableView) {
    guard let newRowsArray = self.newRows else {
      return
    }
    guard newRowsArray.count == self.oldRows.count else {
      return
    }
    var oldRowsSet = Set(self.oldRows)
    let oldSet = oldRowsSet.subtracting(newRowsArray)
    guard oldSet.count == 1 else {
      return
    }
    guard let oldName = oldSet.first else {
      return
    }
    oldRowsSet.remove(oldName)
    let newSet = oldRowsSet.symmetricDifference(newRowsArray)
    guard newSet.count == 1 else {
      return
    }
    guard let newName = newSet.first else {
      return
    }

    guard let oldIndex = self.oldRows.firstIndex(of: oldName) else {
      return
    }
    guard let newIndex = newRowsArray.firstIndex(of: newName) else {
      return
    }

    Logger.log("Moving row from index \(oldIndex) to index \(newIndex)", level: .verbose)
    tableView.moveRow(at: oldIndex, to: newIndex)
  }

  private func addRows(_ tableView: EditableTableView) {
    guard let newRowsArray = self.newRows else {
      return
    }
    var addedRowsSet = Set(newRowsArray)
    assert (addedRowsSet.count == newRowsArray.count)
    addedRowsSet.subtract(self.oldRows)
    Logger.log("Set of rows to add = \(addedRowsSet)", level: .verbose)

    // Find start indexes of each span of added rows
    var tableIndex = 0
    var indexesOfInserts = IndexSet()
    for newRow in newRowsArray {
      if addedRowsSet.contains(newRow) {
        indexesOfInserts.insert(tableIndex)
      }
      tableIndex += 1
    }
    guard !indexesOfInserts.isEmpty else {
      Logger.log("TableChangeByStringElement: \(newRowsArray.count) adds but no inserts!", level: .error)
      return
    }
    Logger.log("Inserting \(indexesOfInserts.count) indexes into table")
    tableView.insertRows(at: indexesOfInserts, withAnimation: tableView.rowAnimation)
  }

  private func removeRows(_ tableView: EditableTableView) {
    guard let newRowsArray = self.newRows else {
      return
    }
    var removedRowsSet = Set(self.oldRows)
    assert (removedRowsSet.count == self.oldRows.count)
    removedRowsSet.subtract(newRowsArray)

    var indexesOfRemoves = IndexSet()
    for (oldRowIndex, oldRow) in self.oldRows.enumerated() {
      if removedRowsSet.contains(oldRow) {
        indexesOfRemoves.insert(oldRowIndex)
      }
    }
    Logger.log("Removing rows from table (IDs: \(removedRowsSet); \(indexesOfRemoves.count) indexes)", level: .verbose)
    tableView.removeRows(at: indexesOfRemoves, withAnimation: tableView.rowAnimation)
  }
}

// Uses IndexSets of integer-based row indexes to describe the changes
class TableChangeByRowIndex: TableChange {
  var toInsert: IndexSet? = nil
  var toRemove: IndexSet? = nil
  var toUpdate: IndexSet? = nil
  // Used by ChangeType.moveRows. Ordered list of pairs of (fromIndex, toIndex)
  var toMove: [(Int, Int)]? = nil

  override init(_ changeType: ChangeType) {
    super.init(changeType)
  }

  override func execute(on tableView: EditableTableView) {
    tableView.beginUpdates()
    defer {
      tableView.endUpdates()
    }

    switch changeType {
      case .selectionChangeOnly:
        fallthrough
      case .renameAndMoveOneRow:
        Logger.fatal("Not yet supported: renameAndMoveOneRow for TableChangeByRowIndex")
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
        Logger.log("TableChangeByRowIndex: ReloadAll", level: .verbose)
        tableView.reloadData()
      case .wholeTableDiff:
        Logger.log("TableChangeByRowIndex: executing diff", level: .verbose)
        if let toRemove = self.toRemove,
           let toInsert = self.toInsert,
           let movePairs = self.toMove {
          // Remember, AppKit expects the order of operations to be: 1. Delete, 2. Insert, 3. Move
          Logger.log("TableChangeByRowIndex: diff: removing \(toRemove.count), adding \(toInsert.count), and moving \(movePairs.count) rows", level: .verbose)
          tableView.removeRows(at: toRemove, withAnimation: tableView.rowAnimation)
          tableView.insertRows(at: toInsert, withAnimation: tableView.rowAnimation)
          for (oldIndex, newIndex) in movePairs {
            Logger.log("Diff: moving row: \(oldIndex) -> \(newIndex)", level: .verbose)
            tableView.moveRow(at: oldIndex, to: newIndex)
          }
        }
    }

    if let newSelectedRows = self.newSelectedRows {
      // NSTableView already updates previous selection indexes if added/removed rows cause them to move.
      // To select added rows, will need an explicit call here even if oldSelection and newSelection are the same.
      Logger.log("Updating table selection to indexes: \(newSelectedRows.reduce("[", { "\($0) \($1)"  })) ]", level: .verbose)
      tableView.selectRowIndexes(newSelectedRows, byExtendingSelection: false)
      // Make sure the table gets focus:
      tableView.window!.makeFirstResponder(tableView)
    }
  }

  static func buildDiff<R>(oldRows: Array<R>, newRows: Array<R>) -> TableChangeByRowIndex where R:Hashable {
    guard #available(macOS 10.15, *) else {
      Logger.log("Animated table diff not available in MacOS versions below 10.15. Falling back to ReloadAll")
      return TableChangeByRowIndex(.reloadAll)
    }

    let tableChange = TableChangeByRowIndex(.wholeTableDiff)
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
    Logger.log("Building table diff: found \(steps.count) differences between \(oldRows.count) old & \(newRows.count) new rows")
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
