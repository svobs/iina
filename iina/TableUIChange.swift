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

  var toRemove: IndexSet? = nil
  var toInsert: IndexSet? = nil
  var toUpdate: IndexSet? = nil
  // Used by ContentChangeType.moveRows. Ordered list of pairs of (fromIndex, toIndex)
  var toMove: [(Int, Int)]? = nil

  // NSTableView already updates previous selection indexes if added/removed rows cause them to move.
  // To select added rows, or select next index after remove, etc, will need an explicit call to update selection afterwards.
  // Will not call to update selection if this is nil.
  var newSelectedRowIndexes: IndexSet? = nil

  // MARK: Optional vars

  // Provide this to restore old selection when calculating the inverse of this change (when doing an undo of "move").
  // TODO: (optimization) figure out how to calculate this from `toMove` instead of storing this
  var oldSelectedRowIndexes: IndexSet? = nil

  // Optional animations
  var flashBefore: IndexSet? = nil
  var flashAfter: IndexSet? = nil

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
    // 1. "Before" animations (if provided)
    NSAnimationContext.runAnimationGroup({ (contextBefore) in
      if let flashBefore = self.flashBefore, !flashBefore.isEmpty {
        self.animateFlash(forIndexes: flashBefore, in: tableView, contextBefore)
      }

    }, completionHandler: {

      // 2. Perform row update animations
      NSAnimationContext.runAnimationGroup({contextDuring in
        self.executeInAnimationGroup(tableView, contextDuring)

      }, completionHandler: {

        // 3. "After" animations (if provided)
        NSAnimationContext.runAnimationGroup({contextAfter in
          if let flashAfter = self.flashAfter, !flashAfter.isEmpty {
            self.animateFlash(forIndexes: flashAfter, in: tableView, contextAfter)
          }
        }, completionHandler: {

          // 4. `completionHandler` (if provided):
          // Put things like "inline editing after adding a row" here, so
          // it will wait until after the animations are complete. Doing so
          // avoids issues such as unexpected notifications being fired from animations
          if let completionHandler = self.completionHandler {
            DispatchQueue.main.async {
              Logger.log("TableUIChange: calling completion handler", level: .verbose)
              completionHandler(self)
            }
          }
        })
      })
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

    executeRowUpdates(on: tableView)

    tableView.endUpdates()
  }

  private func executeRowUpdates(on tableView: EditableTableView) {
    let insertAnimation = AccessibilityPreferences.motionReductionEnabled ? [] : (self.rowInsertAnimation ?? tableView.rowInsertAnimation)
    let removeAnimation = AccessibilityPreferences.motionReductionEnabled ? [] : (self.rowRemoveAnimation ?? tableView.rowRemoveAnimation)

    Logger.log("Executing TableUIChange type \"\(self.changeType)\": \(self.toRemove?.count ?? 0) removes, \(self.toInsert?.count ?? 0) inserts, \(self.toMove?.count ?? 0), moves, \(self.toUpdate?.count ?? 0) updates; reloadExisting: \(self.reloadAllExistingRows), hasNewSelection: \(self.newSelectedRowIndexes != nil)", level: .verbose)

    // track this so we don't do it more than once (it fires the selectionChangedListener every time)
    var wantsReloadOfExistingRows = false
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
            Logger.log("Moving row \(oldIndex) -> \(newIndex)", level: .verbose)
            tableView.moveRow(at: oldIndex, to: newIndex)
          }
        }

      case .updateRows:
        // Just schedule a reload for all of them. This is a very inexpensive operation, and much easier
        // than chasing down all the possible ways other rows could be updated.
        wantsReloadOfExistingRows = true

      case .none:
        break

      case .reloadAll:
        // Try not to use this much, if at all
        Logger.log("Executing TableUIChange: ReloadAll", level: .verbose)
        tableView.reloadData()
        wantsReloadOfExistingRows = false

      case .wholeTableDiff:
        if let toRemove = self.toRemove,
           let toInsert = self.toInsert,
           let movePairs = self.toMove {
          guard !toRemove.isEmpty || !toInsert.isEmpty || !movePairs.isEmpty else {
            Logger.log("Executing changes from diff: no rows changed", level: .verbose)
            break
          }
          // Remember, AppKit expects the order of operations to be: 1. Delete, 2. Insert, 3. Move
          tableView.removeRows(at: toRemove, withAnimation: removeAnimation)
          tableView.insertRows(at: toInsert, withAnimation: insertAnimation)
          for (oldIndex, newIndex) in movePairs {
            Logger.log("Executing changes from diff: moving row: \(oldIndex) -> \(newIndex)", level: .verbose)
            tableView.moveRow(at: oldIndex, to: newIndex)
          }
        }
    }

    if wantsReloadOfExistingRows {
      // Also uses `newSelectedRowIndexes`, if it is not nil:
      tableView.reloadExistingRows(reselectRowsAfter: true, usingNewSelection: self.newSelectedRowIndexes)
    } else if let newSelectedRowIndexes = self.newSelectedRowIndexes {
      tableView.selectApprovedRowIndexes(newSelectedRowIndexes)
    }

    if let newSelectedRowIndexes = self.newSelectedRowIndexes, let firstSelectedRow = newSelectedRowIndexes.first, scrollToFirstSelectedRow {
      tableView.scrollRowToVisible(firstSelectedRow)
    }
  }

  // Set up a flash animation to make it clear which rows were updated or removed.
  // Don't need to worry about moves & inserts, because those will be highlighted
  func setUpFlashForChangedRows() {
    flashBefore = IndexSet()
    if let toRemove = self.toRemove {
      for index in toRemove {
        flashBefore?.insert(index)
      }
    }

    flashAfter = IndexSet()
    if let toUpdate = self.toUpdate {
      for index in toUpdate {
        flashAfter?.insert(index)
      }
    }
  }

  private func animateFlash(forIndexes indexes: IndexSet, in tableView: NSTableView, _ context: NSAnimationContext) {
    context.duration = 0.2
    tableView.beginUpdates()
    Logger.log("Flashing rows: \(indexes.map({$0}))", level: .verbose)
    for index in indexes {
      if let rowView = tableView.rowView(atRow: index, makeIfNecessary: false) {
        let animation = CAKeyframeAnimation()
        animation.keyPath = "backgroundColor"
        animation.values = [NSColor.textBackgroundColor.cgColor,
                            NSColor.controlTextColor.cgColor,
                            NSColor.textBackgroundColor.cgColor]
        animation.keyTimes = [0, 0.25, 1]
        animation.duration = context.duration
        rowView.layer?.add(animation, forKey: "bgFlash")
      }
    }
    tableView.endUpdates()
  }

  func shallowClone() -> TableUIChange {
    let clone = TableUIChange(self.changeType, completionHandler: self.completionHandler)
    clone.toRemove = self.toRemove
    clone.toInsert = self.toInsert
    clone.toMove = self.toMove
    clone.toUpdate = self.toUpdate
    clone.newSelectedRowIndexes = self.newSelectedRowIndexes
    clone.oldSelectedRowIndexes = self.oldSelectedRowIndexes
    clone.rowInsertAnimation = self.rowInsertAnimation
    clone.rowRemoveAnimation = self.rowRemoveAnimation
    clone.reloadAllExistingRows = self.reloadAllExistingRows
    clone.scrollToFirstSelectedRow = self.scrollToFirstSelectedRow

    return clone
  }
}
